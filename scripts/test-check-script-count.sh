#!/usr/bin/env bash
# Tests for scripts/check-script-count.sh (issue 271): the repository passes, clean text
# passes, and each stale phrasing is caught, in a docs file and in a script comment.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/script-count.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}
chk="$root/scripts/check-script-count.sh"

case_() { # case_ <name> <exit> <file> <text>
    local d="$work/$1"
    mkdir -p "$d/$(dirname "$3")"
    printf '%s\n' "$4" >"$d/$3"
    local rc=0
    "$chk" "$d" >"$work/out.log" 2>&1 || rc=$?
    if [[ $rc -ne $2 ]]; then
        bad "$1 (exit $rc, want $2): $(tr '\n' ' ' <"$work/out.log")"
    elif [[ $2 -eq 1 ]] && ! grep -q "\[stale-script-count\] $3:1" "$work/out.log"; then
        bad "$1 did not name $3:1: $(tr '\n' ' ' <"$work/out.log")"
    else
        ok "$1"
    fi
}

rc=0
"$chk" "$root" >"$work/repo.log" 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then ok "the repository passes"; else bad "the repository fails: $(cat "$work/repo.log")"; fi

case_ clean 0 docs/a.md 'The site ships three pinned scripts: copy.js, search.js and share.js.'
case_ title 1 docs/a.md '# The two pinned scripts'
case_ one-of-two 1 layouts/x.html '/copy.js, one of the two pinned scripts, reveals it'
case_ two-small 1 docs/b.md 'Size budget enforced in CI, two small scripts on one page each.'
case_ those-two 1 scripts/c.sh '# /copy.js and /search.js make those two the only ones'
case_ only-two-names 1 scripts/d.sh '# Only the two names; a third script file fails'
case_ unrelated-two 0 docs/e.md 'The credentialed job checks out two scripts and re-checks the build.'
[[ $fail -eq 0 ]] || exit 1
echo "all script count checks passed"
