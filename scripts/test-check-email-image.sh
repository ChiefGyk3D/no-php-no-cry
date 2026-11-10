#!/usr/bin/env bash
# Tests for scripts/check-email-image.sh (issue 331): the repository passes, and the
# guard bites when the address changes but the image does not, when the PNG is
# swapped, when the font changes, and when the stamp or image is missing.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/email-image.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}
chk="$root/scripts/check-email-image.sh"

fixture() { # fixture <name>: a copy of the four inputs
    local d="$work/$1"
    mkdir -p "$d/data" "$d/assets/contact" "$d/static/fonts"
    cp "$root/data/about.yaml" "$d/data/"
    cp "$root/assets/contact/email-address.png" "$root/assets/contact/email-address.stamp" "$d/assets/contact/" 2>/dev/null || true
    cp "$root/static/fonts/orbitron-wght.ttf" "$d/static/fonts/"
    echo "$d"
}
expect() { # expect <name> <exit> <rule|-> <dir>
    local rc=0
    "$chk" "$4" >"$work/out.log" 2>&1 || rc=$?
    if [[ $rc -ne $2 ]]; then
        bad "$1 (exit $rc, want $2): $(tr '\n' ' ' <"$work/out.log")"
    elif [[ "$3" != - ]] && ! grep -q "\[$3\]" "$work/out.log"; then
        bad "$1 failed with the wrong rule: $(tr '\n' ' ' <"$work/out.log")"
    else
        ok "$1"
    fi
}

expect the-repository 0 - "$root"
d="$(fixture clean)"
expect clean-copy 0 - "$d"

d="$(fixture new-address)"
sed -i 's/^\(  email: "\)[^"]*"/\1someone-else@example.invalid"/' "$d/data/about.yaml"
expect address-changed-image-not 1 email-image-stale "$d"

d="$(fixture swapped-png)"
printf 'x' >>"$d/assets/contact/email-address.png"
expect png-modified-stamp-not 1 email-image-modified "$d"

d="$(fixture new-font)"
printf 'x' >>"$d/static/fonts/orbitron-wght.ttf"
expect font-changed 1 email-image-stale "$d"

d="$(fixture no-stamp)"
rm "$d/assets/contact/email-address.stamp"
expect missing-stamp 1 email-image-missing "$d"

d="$(fixture no-png)"
rm "$d/assets/contact/email-address.png"
expect missing-png 1 email-image-missing "$d"

d="$(fixture incomplete)"
sed -i 's/^\(  email: "\)[^"]*"/\1"/' "$d/data/about.yaml"
expect no-address-published 0 - "$d"

[[ $fail -eq 0 ]] || exit 1
echo "all email image checks passed"
