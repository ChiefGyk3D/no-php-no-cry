#!/usr/bin/env bash
# Tests for scripts/check-license.sh: the repository passes, and the guard bites
# on a missing or altered LICENSE, a missing content license and a missing or
# empty brand notice.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}

if "$root/scripts/check-license.sh" "$root" >"$work/repo.log" 2>&1; then
    ok "the repository passes"
else
    bad "the repository fails: $(cat "$work/repo.log")"
fi

fixture() { # fixture <name>: a copy of the three files
    local d="$work/$1"
    mkdir -p "$d"
    cp "$root/LICENSE" "$root/LICENSE-CONTENT" "$root/BRAND.md" "$d/"
    echo "$d"
}
expect() { # expect <name> <exit 0|1> <dir>
    local rc=0
    "$root/scripts/check-license.sh" "$3" >"$3.log" 2>&1 || rc=$?
    if [[ $rc -eq "$2" ]]; then ok "$1"; else bad "$1 (exit $rc, want $2)"; fi
}

d="$(fixture clean)"
expect clean-copy 0 "$d"

d="$(fixture no-license)"
rm "$d/LICENSE"
expect missing-license 1 "$d"

d="$(fixture edited-license)"
printf 'extra line\n' >>"$d/LICENSE"
expect edited-license 1 "$d"

d="$(fixture other-license)"
printf 'MIT License\n' >"$d/LICENSE"
expect other-license-text 1 "$d"

d="$(fixture no-content)"
rm "$d/LICENSE-CONTENT"
expect missing-content-license 1 "$d"

d="$(fixture bad-content)"
printf 'Some notice\n' >"$d/LICENSE-CONTENT"
expect content-license-without-url 1 "$d"

d="$(fixture no-brand)"
rm "$d/BRAND.md"
expect missing-brand-notice 1 "$d"

d="$(fixture empty-brand)"
printf '# Brand\n' >"$d/BRAND.md"
expect brand-notice-without-reservation 1 "$d"
exit "$fail"
