#!/usr/bin/env bash
# Test that scripts/verify-live.sh fails on every finding of scripts/scan-markup.py
# that it does not explicitly excuse (issue 410: bad-encoding alone used to print
# OK). It lifts the third_party function out of verify-live.sh and runs it with the
# real scanner and a stub scanner; no Hugo, no network (test-verify-live.sh builds
# the site and so needs Hugo; this one does not).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/verify-live-findings.XXXXXX")"
trap 'rm -rf "$work"' EXIT

func="$(awk '/^third_party\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$root/scripts/verify-live.sh")"
if [[ -z "$func" ]]; then
    echo "FAIL: third_party not found in scripts/verify-live.sh"
    exit 1
fi

# The caller's helpers, as verify-live.sh defines them, reduced to one line each.
ok() { echo "OK $1"; }
bad() { echo "BAD $1 $2"; }
host=example.test
eval "$func"

# A scanner that prints a code verify-live.sh has never heard of.
printf 'print("made-up-rule")\n' >"$work/stub.py"

failures=0
check() { # check <label> <want OK|BAD> <scan_py> <scheme> <mode> <body-file>
    local out
    scan_py="$3" scheme="$4" body="$6"
    out="$(third_party "$1" "$5")"
    if [[ "$out" == "$2"* ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1 (wanted $2, got '$out')"
        failures=$((failures + 1))
    fi
}

real="$root/scripts/scan-markup.py"
printf '<p>hello</p>\n' >"$work/clean.html"
python3 -I -c 'import sys; sys.stdout.buffer.write(b"\xff\xfe" + "<script src=https://evil.example/x.js></script>".encode("utf-16le"))' >"$work/utf16.html"
printf '<p>\033</p>\n' >"$work/esc.html"
printf '<img src=https://evil.example/a.png>\n' >"$work/external.html"
printf '<img src=http://example.test/a.png>\n' >"$work/http.html"

check "a clean page is ok" OK "$real" https html "$work/clean.html"
check "a UTF-16 page (bad-encoding alone) fails" BAD "$real" https html "$work/utf16.html"
check "a UTF-16 page fails in markup mode too" BAD "$real" https markup "$work/utf16.html"
check "an ESC byte (bad-encoding alone) fails" BAD "$real" https html "$work/esc.html"
check "an external asset still fails" BAD "$real" https html "$work/external.html"
check "an http reference fails on https" BAD "$real" https html "$work/http.html"
check "an http reference to the own host is ok on http" OK "$real" http html "$work/http.html"
check "an unknown finding code fails" BAD "$work/stub.py" https html "$work/clean.html"

((failures == 0)) || exit 1
echo "all verify-live finding checks passed"
