#!/usr/bin/env bash
# Usage: scripts/check-reach-around-drift.sh [--offline] [--timeout SECS]
#            [--tokens FILE] [--ra-tokens FILE --ra-lock FILE]
#
# Two-way drift check for the shared design tokens (docs/token-drift.md).
# This repo's brand/tokens.json is the source of truth. Reach Around vendors a
# copy (vendor/brand/tokens.json) pinned by vendor/brand/tokens.lock.json. This
# compares the two and reports token keys added, removed and changed on the
# Reach Around side, plus the blog commit that side is pinned to.
#
# By default the head commit of Reach Around's default branch is resolved first
# (GitHub REST commits API), then both files are read at that one commit through
# the contents API (public repo, no token), so a push between requests cannot
# pair a new tokens.json with an old lock. The commit used is printed. Each
# request is bounded by --timeout (a positive integer, default 20 s). --ra-tokens and --ra-lock read local files instead
# (the tests use this; no network). --offline skips the check with a message and
# exit 0, so CI never flakes on a network error. A fetch failure without
# --offline exits 3, never 0.
#
# Exit codes: 0 no drift (or skipped offline), 1 drift, 2 usage, 3 fetch or parse error.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
api="${RA_DRIFT_API:-https://api.github.com/repos/ChiefGyk3D/Reach-Around}"
timeout=20
offline=0
tokens="$root/brand/tokens.json"
ra_tokens=""
ra_lock=""

usage() {
    echo "usage: check-reach-around-drift.sh [--offline] [--timeout SECS] [--tokens FILE] [--ra-tokens FILE --ra-lock FILE]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --offline) offline=1 ;;
        --timeout)
            [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || usage
            timeout="$2"
            shift
            ;;
        --tokens)
            [[ $# -ge 2 ]] || usage
            tokens="$2"
            shift
            ;;
        --ra-tokens)
            [[ $# -ge 2 ]] || usage
            ra_tokens="$2"
            shift
            ;;
        --ra-lock)
            [[ $# -ge 2 ]] || usage
            ra_lock="$2"
            shift
            ;;
        *) usage ;;
    esac
    shift
done
[[ -n "$ra_tokens" && -z "$ra_lock" ]] || [[ -z "$ra_tokens" && -n "$ra_lock" ]] && usage

if [[ $offline -eq 1 ]]; then
    echo "skip: --offline given, Reach Around drift not checked"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ -z "$ra_tokens" ]]; then
    ra_tokens="$work/tokens.json"
    ra_lock="$work/tokens.lock.json"
    fetch() { # fetch <accept-type> <url> <out>
        curl -fsSL --max-time "$timeout" --retry 1 \
            -H "Accept: $1" -o "$3" "$2" 2>"$work/curl.err"
    }
    ra_sha=""
    if fetch application/vnd.github.sha "$api/commits/main" "$work/sha.txt"; then
        ra_sha="$(tr -d '[:space:]' <"$work/sha.txt")"
    fi
    if [[ ! "$ra_sha" =~ ^[0-9a-f]{40}$ ]]; then
        echo "error: could not resolve Reach Around's head commit ($(tr '\n' ' ' <"$work/curl.err"))" >&2
        echo "       rerun with --offline to skip this check" >&2
        exit 3
    fi
    echo "Reach Around commit checked: $ra_sha"
    if ! fetch application/vnd.github.raw+json "$api/contents/vendor/brand/tokens.json?ref=$ra_sha" "$ra_tokens" ||
        ! fetch application/vnd.github.raw+json "$api/contents/vendor/brand/tokens.lock.json?ref=$ra_sha" "$ra_lock"; then
        echo "error: could not fetch Reach Around's vendored tokens ($(tr '\n' ' ' <"$work/curl.err"))" >&2
        echo "       rerun with --offline to skip this check" >&2
        exit 3
    fi
fi

python3 -I - "$tokens" "$ra_tokens" "$ra_lock" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path


def flatten(doc):
    out = {"version": json.dumps(doc.get("version"))}
    for face in doc.get("fontFace", []):
        out["fontFace:%s" % face.get("family")] = json.dumps(face, sort_keys=True)
    for group in doc.get("groups", []):
        for name, value in group.get("tokens", {}).items():
            out["token:%s" % name] = json.dumps(value)
    return out


try:
    ours_path, theirs_path, lock_path = (Path(p) for p in sys.argv[1:4])
    ours = flatten(json.loads(ours_path.read_text(encoding="utf-8")))
    theirs_raw = theirs_path.read_bytes()
    theirs = flatten(json.loads(theirs_raw))
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    commit = lock["source"]["commit"]
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("lock source.commit must be 40 lowercase hex characters")
    pin = lock["sha256"]
    if not isinstance(pin, str):
        raise ValueError("lock sha256 must be a string")
except (OSError, ValueError, AttributeError, TypeError, KeyError) as exc:
    print("error: cannot read or parse tokens: %s" % exc, file=sys.stderr)
    sys.exit(3)

print("Reach Around is pinned to blog commit %s" % commit)
drift = False
actual = hashlib.sha256(theirs_raw).hexdigest()
if actual != pin:
    drift = True
    print("DRIFT Reach Around's own pin is stale: lock says %s, file is %s" % (pin, actual))
added = sorted(set(theirs) - set(ours))
removed = sorted(set(ours) - set(theirs))
changed = sorted(k for k in set(ours) & set(theirs) if ours[k] != theirs[k])
for label, keys in (("added", added), ("removed", removed), ("changed", changed)):
    for key in keys:
        drift = True
        if label == "changed":
            print("DRIFT changed %s: blog %s, Reach Around %s" % (key, ours[key], theirs[key]))
        elif label == "added":
            print("DRIFT added on Reach Around (not in blog): %s = %s" % (key, theirs[key]))
        else:
            print("DRIFT removed on Reach Around (in blog only): %s = %s" % (key, ours[key]))
if drift:
    print("drift: see docs/token-drift.md to re-vendor or to propose the change here")
    sys.exit(1)
print("ok   Reach Around's vendored tokens match brand/tokens.json")
PY
