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
gen="$root/scripts/gen-tokens.py"
source_json="$root/brand/tokens.json"
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

# Highlight colors: a comment color too faint on the code background, in each mode.
sed 's/--code-comment: #A8A093;/--code-comment: #3A3530;/' "$tokens" >"$work/low-code-dark.css"
expect_fail "faint dark highlight color is caught" "FAIL.*dark.*code-comment on surface" python3 -I "$contrast" "$work/low-code-dark.css"

sed 's/--code-keyword: #8A5A00;/--code-keyword: #FBB03B;/' "$tokens" >"$work/low-code-light.css"
expect_fail "faint light highlight color is caught" "FAIL.*light.*code-keyword on surface" python3 -I "$contrast" "$work/low-code-light.css"

grep -v -e '--code-string:' "$tokens" >"$work/no-code-string.css"
expect_fail "missing highlight token is caught" "missing" python3 -I "$contrast" "$work/no-code-string.css"

grep -v -e '--muted:' "$tokens" >"$work/no-muted.css"
expect_fail "missing token is caught" "missing" python3 -I "$contrast" "$work/no-muted.css"

# A token that survives only inside a comment must not count as declared.
sed 's#^\( *\)--muted: \(.*\);#\1/* --muted: \2; */#' "$tokens" >"$work/commented-muted.css"
expect_fail "token left only in a comment is caught" "missing" python3 -I "$contrast" "$work/commented-muted.css"

# --- new surfaces, focus pairs, theme blocks (issue 49) --------------------
# Focus below 3:1 on each new dark surface makes the checker exit 1.
for surface in carbon-base carbon-line plate ghost; do
    sed -E "s/^( *)--${surface}: #[0-9A-Fa-f]{6};/\\1--${surface}: #F5B040;/" "$tokens" >"$work/low-focus-$surface.css"
    expect_fail "focus below 3:1 on $surface is caught" "FAIL.*dark.*focus on $surface" python3 -I "$contrast" "$work/low-focus-$surface.css"
done

sed 's/--focus-on-plate: #8A5A00;/--focus-on-plate: #FBB03B;/' "$tokens" >"$work/low-plate-light.css"
expect_fail "amber focus on the cream plate is caught" "FAIL.*focus-on-plate on plate-light" python3 -I "$contrast" "$work/low-plate-light.css"

sed 's/--muted: #B5ADA2;/--muted: #4A4540;/' "$tokens" >"$work/low-muted-carbon.css"
expect_fail "faint muted text on carbon is caught" "FAIL.*dark.*muted on carbon-line" python3 -I "$contrast" "$work/low-muted-carbon.css"

# The contrast script reads all three theme blocks: a defect in only one of
# them (a hand-edited copy) is caught, as is drift between the light copies.
sed '/^:root\[data-theme="light"\]/,/^}/ s/--link: #8A5A00;/--link: #FBB03B;/' "$tokens" >"$work/low-link-forced.css"
expect_fail "defect only in the forced-light block is caught" 'FAIL.*light\[data-theme\].*link on bg' python3 -I "$contrast" "$work/low-link-forced.css"
expect_fail "drift between the light blocks is caught" "FAIL.*drift" python3 -I "$contrast" "$work/low-link-forced.css"

sed '/^:root\[data-theme="dark"\]/,/^}/ s/--text: #F0F0F0;/--text: #3A3A3A;/' "$tokens" >"$work/low-text-pinned.css"
expect_fail "defect only in the forced-dark block is caught" 'FAIL.*dark\[data-theme\].*text on bg' python3 -I "$contrast" "$work/low-text-pinned.css"

grep -v -e 'data-theme="dark"' "$tokens" >"$work/no-dark-block.css"
expect_fail "missing forced-dark block is caught" "missing" python3 -I "$contrast" "$work/no-dark-block.css"

# --- token generator ------------------------------------------------------
expect_pass "tokens.css is current with brand/tokens.json" python3 -I "$gen" --check
python3 -I "$gen" --out "$work/gen1.css"
python3 -I "$gen" --out "$work/gen2.css"
if cmp -s "$work/gen1.css" "$work/gen2.css" && cmp -s "$work/gen1.css" "$tokens"; then
    ok "generator is deterministic and matches tokens.css"
else
    bad "generator output differs between runs or from tokens.css"
fi

cp "$tokens" "$work/drifted.css"
printf '/* hand edit */\n' >>"$work/drifted.css"
expect_fail "hand-edited tokens.css is caught by --check" "drift" python3 -I "$gen" --check --out "$work/drifted.css"

sed 's/"#B5ADA2"/"#B5ADA3"/' "$source_json" >"$work/changed.json"
expect_fail "changed tokens.json without regenerating is caught" "drift" python3 -I "$gen" --check --source "$work/changed.json"

sed 's/"focus": "#FBB03B"/"focus": "#FBB03Z"/' "$source_json" >"$work/bad-hex.json"
expect_fail "malformed color in tokens.json is rejected" "tokens.json" python3 -I "$gen" --source "$work/bad-hex.json" --out "$work/x.css"

# --- no hard-coded colors outside tokens.css ------------------------------
if grep -n -E '#[0-9A-Fa-f]{3,8}\b|rgba?\(' "$root/assets/css/main.css" "$root/assets/css/highlight.css" >"$work/hard.txt"; then
    bad "main.css or highlight.css hard-codes a color (use a token)"
    cat "$work/hard.txt"
else
    ok "main.css and highlight.css hard-code no color"
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
