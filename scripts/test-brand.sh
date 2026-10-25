#!/usr/bin/env bash
# Tests for the brand checks: scripts/check-contrast.py (WCAG AA on the design
# tokens) and scripts/check-brand-assets.sh (approved-assets manifest).
#
# Each check is run on the real repository (must pass) and on a scratch copy
# with one deliberate defect (must fail with the expected message), so a check
# that silently passes everything is caught. Scratch lives under the
# repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/brand.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
ok() { printf 'ok   %s\n' "$1"; }
bad() {
    printf 'FAIL %s\n' "$1"
    failures=$((failures + 1))
}

# expect_pass <name> <cmd...>
expect_pass() {
    local name="$1"
    shift
    if "$@" >"$work/out.txt" 2>&1; then ok "$name"; else
        bad "$name"
        cat "$work/out.txt"
    fi
}

# expect_fail <name> <pattern> <cmd...>: command exits non-zero and output matches.
expect_fail() {
    local name="$1" pattern="$2"
    shift 2
    if "$@" >"$work/out.txt" 2>&1; then
        bad "$name (expected failure, got exit 0)"
    elif grep -q -- "$pattern" "$work/out.txt"; then ok "$name"; else
        bad "$name (failed, but without '$pattern')"
        cat "$work/out.txt"
    fi
}

contrast="$root/scripts/check-contrast.py"
assets="$root/scripts/check-brand-assets.sh"
tokens="$root/assets/css/tokens.css"

# --- contrast -------------------------------------------------------------
expect_pass "tokens meet WCAG AA" python3 -I "$contrast" "$tokens"

sed 's/--text: #F0F0F0;/--text: #3A3A3A;/' "$tokens" >"$work/low-text.css"
expect_fail "low-contrast dark text is caught" "FAIL.*dark.*text on bg" python3 -I "$contrast" "$work/low-text.css"

sed 's/--on-accent: #1A1A1A;/--on-accent: #FFFFFF;/' "$tokens" >"$work/low-on-accent.css"
expect_fail "white on amber is caught" "FAIL.*on-accent on accent" python3 -I "$contrast" "$work/low-on-accent.css"

# A light-mode defect: amber used as light-mode link text.
sed 's/--link: #8A5A00;/--link: #FBB03B;/' "$tokens" >"$work/low-link.css"
expect_fail "amber link on light bg is caught" "FAIL.*light.*link on bg" python3 -I "$contrast" "$work/low-link.css"

grep -v -e '--muted:' "$tokens" >"$work/no-muted.css"
expect_fail "missing token is caught" "missing" python3 -I "$contrast" "$work/no-muted.css"

# --- no hard-coded colors outside tokens.css ------------------------------
if grep -n -E '#[0-9A-Fa-f]{3,8}\b|rgba?\(' "$root/assets/css/main.css" >"$work/hard.txt"; then
    bad "main.css hard-codes a color (use a token)"
    cat "$work/hard.txt"
else
    ok "main.css hard-codes no color"
fi

# --- asset manifest -------------------------------------------------------
expect_pass "asset manifest matches the tree" "$assets" "$root"

mk_tree() {
    rm -rf "$1"
    mkdir -p "$1"
    cp -R "$root/static" "$root/brand" "$1/"
}

mk_tree "$work/t1"
printf 'x' >"$work/t1/static/brand/stray.png"
expect_fail "unlisted image is caught" "not in approved-assets.txt" "$assets" "$work/t1"

mk_tree "$work/t2"
printf 'tampered' >>"$work/t2/static/brand/penguin-glyph.svg"
expect_fail "modified image is caught" "sha256 mismatch" "$assets" "$work/t2"

mk_tree "$work/t3"
sed -i '/penguin-glyph.svg/d' "$work/t3/brand/approved-assets.txt"
expect_fail "missing manifest line is caught" "not in approved-assets.txt" "$assets" "$work/t3"

mk_tree "$work/t4"
rm "$work/t4/static/brand/penguin-color.png"
expect_fail "listed file that is gone is caught" "listed but missing" "$assets" "$work/t4"

mk_tree "$work/t5"
cp "$work/t5/static/brand/penguin-color.png" "$work/t5/static/brand/Twitter V2.png"
expect_fail "banned file name is caught" "banned" "$assets" "$work/t5"

mk_tree "$work/t6"
rm "$work/t6/static/fonts/OFL.txt"
expect_fail "font without license text is caught" "OFL.txt" "$assets" "$work/t6"

if ((failures > 0)); then
    printf '%d failure(s)\n' "$failures"
    exit 1
fi
echo "all brand tests passed"
