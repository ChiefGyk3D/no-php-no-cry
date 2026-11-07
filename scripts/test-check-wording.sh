#!/usr/bin/env bash
# Tests for scripts/check-wording.sh: the repository is clean, and the guard bites
# on the bare short form (several spellings and places) while letting the
# cryptography words and "cryptocurrency" through.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
short="$(printf 'cry%s' pto)"
fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}

if "$root/scripts/check-wording.sh" "$root" >"$work/repo.log" 2>&1; then
    ok "the repository is clean"
else
    bad "the repository has the short form: $(cat "$work/repo.log")"
fi

expect() { # expect <name> <exit 0|1> <file content>
    local d="$work/$1"
    mkdir -p "$d"
    printf '%s\n' "$3" >"$d/page.md"
    local rc=0
    "$root/scripts/check-wording.sh" "$d" >"$d.log" 2>&1 || rc=$?
    if [[ $rc -eq "$2" ]]; then ok "$1"; else bad "$1 (exit $rc, want $2)"; fi
}
expect lower-case 1 "Tips in $short are welcome"
expect upper-case 1 "$(printf '%s' "$short" | tr a-z A-Z) tips"
expect capitalized 1 "${short^} wallet"
expect hyphenated 1 "a $short-friendly page"
expect in-a-class-name 1 "<div class=\"$short\">"
expect cryptocurrency-ok 0 "Tips in ${short}currency are welcome"
expect cryptography-ok 0 "TLS is ${short}graphy"
expect cryptographic-ok 0 "a ${short}graphic hash"
expect cryptosystem-ok 0 "a ${short}system"

# The vendored axe-core build is exempt (it uses the browser's crypto object),
# but only under tools/axe/: the same text elsewhere still fails.
mkdir -p "$work/vendored/tools/axe" "$work/elsewhere/tools/other"
printf 'var r=window.%s||1;\n' "$short" >"$work/vendored/tools/axe/axe.min.js"
printf 'var r=window.%s||1;\n' "$short" >"$work/elsewhere/tools/other/axe.min.js"
if "$root/scripts/check-wording.sh" "$work/vendored" >/dev/null 2>&1; then ok "vendored axe build is exempt"; else bad "vendored axe build was flagged"; fi
if "$root/scripts/check-wording.sh" "$work/elsewhere" >/dev/null 2>&1; then bad "same text outside tools/axe passed"; else ok "same text outside tools/axe fails"; fi
exit "$fail"
