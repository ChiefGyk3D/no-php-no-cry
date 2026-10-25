#!/usr/bin/env bash
# Tests for scripts/check-hugo-version.sh: accepts the pinned standard edition
# (build metadata after '-' or '+'), rejects extended, other versions and junk.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-hugo-version.sh"
failures=0

# expect <pass|fail> <label> <version-output>
expect() {
    local want="$1" label="$2" out="$3" rc=0
    "$checker" 0.168.0 "$out" >/dev/null 2>&1 || rc=$?
    if [[ "$want" == pass && $rc -eq 0 ]] || [[ "$want" == fail && $rc -ne 0 ]]; then
        echo "ok: $label"
    else
        echo "FAIL: $label (wanted $want, exit $rc)"
        failures=$((failures + 1))
    fi
}

expect pass "hyphen metadata" "hugo v0.168.0-e27a6760c5547237f87d353aebe0580feadb20f4 linux/amd64 BuildDate=2026-10-13T16:42:50Z VendorInfo=gohugoio"
expect pass "plus metadata" "hugo v0.168.0+e27a6760c5547237f87d353aebe0580feadb20f4 linux/amd64 BuildDate=2026-10-13T16:42:50Z VendorInfo=gohugoio"
expect fail "extended (hyphen)" "hugo v0.168.0-e27a676+extended linux/amd64 BuildDate=x VendorInfo=gohugoio"
expect fail "extended (plus)" "hugo v0.168.0+extended linux/amd64 BuildDate=x VendorInfo=gohugoio"
expect fail "extended+withdeploy" "hugo v0.168.0-e27a676+extended+withdeploy linux/amd64"
expect fail "other version" "hugo v0.167.0-e27a676 linux/amd64"
expect fail "prefix collision" "hugo v0.168.01-e27a676 linux/amd64"
expect fail "no delimiter" "hugo v0.168.0 linux/amd64"
expect fail "junk" "something else entirely"
expect fail "empty" ""

if [[ $failures -gt 0 ]]; then
    echo "$failures version check test(s) failed"
    exit 1
fi
echo "all version check tests passed"
