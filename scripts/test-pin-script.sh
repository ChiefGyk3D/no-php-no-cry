#!/usr/bin/env bash
# Test for scripts/pin-script.sh: it writes the one-line hash file of a pinned
# script (copy.js or search.js, each with its own <name>.sha256), --check agrees
# with it, and a changed or missing script or hash file fails. A script that is
# not on the allowlist is refused.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pin="$root/scripts/pin-script.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/pin-script.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
check() {
    # check <name> <wanted rc> <command...>
    local name="$1" want="$2" rc=0
    shift 2
    "$@" >"$work/out" 2>&1 || rc=$?
    if [[ $rc -eq $want ]]; then
        echo "ok: $name"
    else
        echo "FAIL: $name (rc=$rc, wanted $want)"
        cat "$work/out"
        failures=$((failures + 1))
    fi
}

printf 'document.documentElement.dataset.copy="dark"\n' >"$work/copy.js"
hashfile="$work/copy.js.sha256"
export SCRIPT_HASH_DIR="$work"

check "pin writes the hash file" 0 "$pin" "$work/copy.js"
want="$(sha256sum "$work/copy.js" | cut -d' ' -f1)  copy.js"
if [[ "$(cat "$hashfile")" == "$want" && "$(wc -l <"$hashfile")" -eq 1 ]]; then
    echo "ok: the file is one sha256sum-format line"
else
    echo "FAIL: unexpected hash file content"
    failures=$((failures + 1))
fi
check "--check passes on a pinned script" 0 "$pin" --check "$work/copy.js"
printf 'changed\n' >"$work/copy.js"
check "--check fails on a changed script" 1 "$pin" --check "$work/copy.js"
check "pin again, then --check passes" 0 "$pin" "$work/copy.js"
check "--check passes after re-pinning" 0 "$pin" --check "$work/copy.js"
rm -f "$hashfile"
check "--check fails with no hash file" 1 "$pin" --check "$work/copy.js"
check "pin fails on a missing script" 2 "$pin" "$work/none.js"
mkdir "$work/big"
head -c 2048 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$work/big/copy.js"
check "pin refuses a script over the gzip budget" 1 "$pin" "$work/big/copy.js"
check "usage error" 2 "$pin" a b c

# search.js has its own hash file, and the two do not touch each other.
printf 'document.documentElement.dataset.search="dark"\n' >"$work/search.js"
printf 'copy\n' >"$work/copy.js"
check "pin copy.js" 0 "$pin" "$work/copy.js"
copy_before="$(cat "$hashfile")"
check "pin search.js" 0 "$pin" "$work/search.js"
want="$(sha256sum "$work/search.js" | cut -d' ' -f1)  search.js"
if [[ "$(cat "$work/search.js.sha256")" == "$want" && "$(wc -l <"$work/search.js.sha256")" -eq 1 ]]; then
    echo "ok: search.js.sha256 is one sha256sum-format line"
else
    echo "FAIL: unexpected search.js.sha256 content"
    failures=$((failures + 1))
fi
if [[ "$(cat "$hashfile")" == "$copy_before" ]]; then
    echo "ok: pinning search.js left copy.js.sha256 alone"
else
    echo "FAIL: pinning search.js changed copy.js.sha256"
    failures=$((failures + 1))
fi
check "--check passes for both" 0 "$pin" --check "$work/search.js"
printf 'changed\n' >"$work/search.js"
check "--check fails on a changed search.js" 1 "$pin" --check "$work/search.js"
check "--check still passes for copy.js" 0 "$pin" --check "$work/copy.js"
rm -f "$work/search.js.sha256"
check "--check fails for search.js with no hash file" 1 "$pin" --check "$work/search.js"
printf 'x\n' >"$work/third.js"
check "a script that is not on the allowlist is refused" 2 "$pin" "$work/third.js"
check "--check refuses it too" 2 "$pin" --check "$work/third.js"
head -c 2048 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$work/search.js"
check "pin refuses a search.js over the gzip budget" 1 "$pin" "$work/search.js"
if [[ ! -f "$work/search.js.sha256" ]]; then
    echo "ok: a refused search.js wrote no hash file"
else
    echo "FAIL: a refused search.js left a hash file"
    failures=$((failures + 1))
fi
# With no argument both repository scripts are pinned or checked (the real
# static/ files against a scratch hash directory).
check "no argument pins every pinned script" 0 "$pin"
check "no argument: --check passes" 0 "$pin" --check
if [[ -f "$work/copy.js.sha256" && -f "$work/search.js.sha256" ]]; then
    echo "ok: no argument wrote both hash files"
else
    echo "FAIL: no argument did not write both hash files"
    failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all pin-script tests passed"
