#!/usr/bin/env bash
# Test for scripts/pin-theme.sh: it writes the one-line hash file, --check agrees
# with it, and a changed or missing script or hash file fails.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pin="$root/scripts/pin-theme.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/pin-theme.XXXXXX")"
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

printf 'document.documentElement.dataset.theme="dark"\n' >"$work/theme.js"
hashfile="$work/theme.js.sha256"
export THEME_HASH_FILE="$hashfile"

check "pin writes the hash file" 0 "$pin" "$work/theme.js"
want="$(sha256sum "$work/theme.js" | cut -d' ' -f1)  theme.js"
if [[ "$(cat "$hashfile")" == "$want" && "$(wc -l <"$hashfile")" -eq 1 ]]; then
    echo "ok: the file is one sha256sum-format line"
else
    echo "FAIL: unexpected hash file content"
    failures=$((failures + 1))
fi
check "--check passes on a pinned script" 0 "$pin" --check "$work/theme.js"
printf 'changed\n' >"$work/theme.js"
check "--check fails on a changed script" 1 "$pin" --check "$work/theme.js"
check "pin again, then --check passes" 0 "$pin" "$work/theme.js"
check "--check passes after re-pinning" 0 "$pin" --check "$work/theme.js"
rm -f "$hashfile"
check "--check fails with no hash file" 1 "$pin" --check "$work/theme.js"
check "pin fails on a missing script" 2 "$pin" "$work/none.js"
head -c 2048 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$work/big.js"
check "pin refuses a script over the gzip budget" 1 "$pin" "$work/big.js"
check "usage error" 2 "$pin" a b c

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all pin-theme tests passed"
