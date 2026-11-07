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

# Highlight colors: a comment color too faint on the code background.
sed 's/--code-comment: #A8A093;/--code-comment: #3A3530;/' "$tokens" >"$work/low-code-dark.css"
expect_fail "faint dark highlight color is caught" "FAIL.*dark.*code-comment on surface" python3 -I "$contrast" "$work/low-code-dark.css"

grep -v -e '--code-string:' "$tokens" >"$work/no-code-string.css"
expect_fail "missing highlight token is caught" "missing" python3 -I "$contrast" "$work/no-code-string.css"

grep -v -e '--muted:' "$tokens" >"$work/no-muted.css"
expect_fail "missing token is caught" "missing" python3 -I "$contrast" "$work/no-muted.css"

# A token that survives only inside a comment must not count as declared.
sed 's#^\( *\)--muted: \(.*\);#\1/* --muted: \2; */#' "$tokens" >"$work/commented-muted.css"
expect_fail "token left only in a comment is caught" "missing" python3 -I "$contrast" "$work/commented-muted.css"

# --- surfaces, focus pairs, dark only (issue 49, kit decision L) ------------
# Focus below 3:1 on each dark surface makes the checker exit 1.
for surface in carbon-base carbon-line plate; do
    sed -E "s/^( *)--${surface}: #[0-9A-Fa-f]{6};/\\1--${surface}: #F5B040;/" "$tokens" >"$work/low-focus-$surface.css"
    expect_fail "focus below 3:1 on $surface is caught" "FAIL.*dark.*focus on $surface" python3 -I "$contrast" "$work/low-focus-$surface.css"
done

sed 's/--muted: #B5ADA2;/--muted: #4A4540;/' "$tokens" >"$work/low-muted-carbon.css"
expect_fail "faint muted text on carbon is caught" "FAIL.*dark.*muted on carbon-line" python3 -I "$contrast" "$work/low-muted-carbon.css"

sed 's/--gray: #808080;/--gray: #404040;/' "$tokens" >"$work/low-gray.css"
expect_fail "gray below 4.5:1 on the ground is caught" "FAIL.*dark.*gray on bg" python3 -I "$contrast" "$work/low-gray.css"

# The palette matches the brand kit (decision A).
for pair in "accent:#FBB03B" "bg:#0F0F0F" "surface:#202020" "gray:#808080"; do
    if grep -q -e "^ *--${pair%%:*}: ${pair#*:};" "$tokens"; then ok "kit palette: --${pair%%:*} is ${pair#*:}"; else bad "kit palette: --${pair%%:*} is not ${pair#*:}"; fi
done

# Dark only: no light palette, no data-theme selector, no retired light or
# ghost colors, and the guard bites when one is added back.
if grep -n -i -E 'data-theme|prefers-color-scheme|color-scheme: *light|8A5A00|383838|--ghost|plate-light' "$tokens" "$source_json" >"$work/light.txt"; then
    bad "light-mode or retired tokens remain"
    cat "$work/light.txt"
else
    ok "tokens are dark only (no light block, #8A5A00 or ghost gray)"
fi
{
    cat "$tokens"
    printf ':root[data-theme="light"] {\n  --bg: #FAF7F2;\n}\n'
} >"$work/with-light.css"
expect_fail "a light block is caught" "FAIL.*unexpected block" python3 -I "$contrast" "$work/with-light.css"

if grep -q 'color-scheme: dark;' "$tokens"; then ok ":root declares color-scheme: dark"; else bad ":root lacks color-scheme: dark"; fi

# Display font: a token only; the font file is not bundled (license unverified).
if grep -q -e '^ *--font-display: "Cyber City"' "$tokens"; then ok "Cyber City is a display token"; else bad "--font-display token missing"; fi
if find "$root/static" -type f -iname '*cyber*' | grep -q .; then bad "a Cyber City font file is bundled"; else ok "no Cyber City font file is bundled"; fi

# Orbitron: one self-hosted @font-face (ttf, swap) and a display token that names it.
if grep -q -e '^  font-family: Orbitron;' "$tokens" && grep -q -e 'src: url("../fonts/orbitron-wght.ttf") format("truetype");' "$tokens"; then ok "Orbitron has a self-hosted ttf @font-face"; else bad "no Orbitron @font-face"; fi
if [[ "$(grep -c -e '^  font-display: swap;' "$tokens")" -eq 2 ]]; then ok "both @font-face rules use font-display: swap"; else bad "@font-face rules lack font-display: swap"; fi
if grep -q -e '^ *--font-display: .*Orbitron' "$tokens"; then ok "--font-display names Orbitron"; else bad "--font-display does not name Orbitron"; fi
if grep -q -e '^ *--font-body: Jost' "$tokens" && ! grep -q -e '^ *--font-body:.*Orbitron' "$tokens"; then ok "body font is Jost, never Orbitron"; else bad "body font token names Orbitron"; fi
# The display font is used on headings only: --font-display appears in main.css
# for h1/h2/HUD headings and the wordmark, and body never sets it.
if grep -n 'var(--font-display)' "$root/assets/css/main.css" | grep -q .; then ok "main.css uses --font-display"; else bad "--font-display is unused"; fi
if awk '/^body *\{/,/^\}/' "$root/assets/css/main.css" | grep -q 'font-display'; then bad "body sets the display font"; else ok "body does not set the display font"; fi

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
    cp -R "$root/static" "$root/brand" "$root/content" "$root/assets" "$1/"
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

mk_tree "$work/t7"
rm "$work/t7/static/fonts/OFL-Orbitron.txt"
expect_fail "Orbitron without its own license text is caught" "OFL-Orbitron.txt" "$assets" "$work/t7"

mk_tree "$work/t8"
cp "$work/t8/static/fonts/orbitron-wght.ttf" "$work/t8/static/fonts/Cyber City.otf"
expect_fail "a Cyber City font file is caught" "banned" "$assets" "$work/t8"

mk_tree "$work/t9"
cp "$work/t9/static/brand/og-card.png" "$work/t9/content/posts/sample-post/extra.png"
expect_fail "unlisted image under content/ is caught" "extra.png is not in approved-assets.txt" "$assets" "$work/t9"

mk_tree "$work/t10"
cp "$work/t10/static/brand/og-card.png" "$work/t10/static/brand/star-card.png"
expect_fail "a starred file name is caught" "banned" "$assets" "$work/t10"

# Every tracked image and font is listed (git is the source of truth).
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    tracked="$(git -C "$root" ls-files | grep -i -E '\.(png|jpe?g|webp|gif|ico|avif|woff2?|ttf|otf|svg)$' || true)"
    if [[ -z "$tracked" ]]; then bad "no tracked images found (check is blind)"; fi
    unlisted=0
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if ! grep -q -F -e "$f | " "$root/brand/approved-assets.txt"; then
            printf 'tracked binary not in approved-assets.txt: %s\n' "$f"
            unlisted=1
        fi
    done <<<"$tracked"
    if ((unlisted)); then bad "tracked binaries missing from the manifest"; else ok "every tracked image and font is in approved-assets.txt"; fi
fi

# No excluded or starred file is present under static/ (names from
# brand/EXCLUDED.md), and no Cyber City file is tracked.
if find "$root/static" -type f | grep -i -E 'star|twitter|soundcloud|tinker|do not use|linux ?penguin|linux[ _]a[ _]v2|linux white|freebsd|kisspng|png-clipart|png-transparent|beasty|banhammer|dealwithit|penguinhype|penguinrip|cyber|[.]stl$|[.]pdf$' >"$work/excl.txt"; then
    bad "an excluded or starred file is present"
    cat "$work/excl.txt"
else
    ok "no excluded or starred file under static/"
fi
if git -C "$root" ls-files | grep -i -E 'cyber' >"$work/cyber.txt"; then
    bad "a Cyber City file is tracked"
    cat "$work/cyber.txt"
else
    ok "no Cyber City file is tracked"
fi

# Image sizes, and the checker bites on a wrong size.
dims="$root/scripts/check-brand-dims.py"
expect_pass "brand image dimensions" python3 -I "$dims" "$root/static/brand"
mk_tree "$work/t11"
cp "$work/t11/static/brand/mascot-128.webp" "$work/t11/static/brand/mascot-256.webp"
expect_fail "a wrongly sized mascot WebP is caught" "mascot-256.webp: size" python3 -I "$dims" "$work/t11/static/brand"
mkdir -p "$work/empty"
expect_fail "a folder with no images is caught" "no WebP files found" python3 -I "$dims" "$work/empty"

# Generator: refuses a wrong master before writing anything.
printf 'not the master' >"$work/fake-master.jpg"
mkdir -p "$work/kit" "$work/gen-root"
expect_fail "generator rejects a master with the wrong hash" "sha256 mismatch" python3 -I "$root/scripts/gen-brand-assets.py" --master "$work/fake-master.jpg" --kit "$work/kit" --out-root "$work/gen-root"
if [[ -z "$(find "$work/gen-root" -type f)" ]]; then ok "generator wrote nothing for a wrong master"; else bad "generator wrote files for a wrong master"; fi

# The build record names the approved master's hash.
if grep -q '"sha256": "82edc2004ced79de845a04c466ac39604ffd3e9c961e89f205f4bee4be361189"' "$root/brand/assets-build.json"; then ok "build record carries the master sha256"; else bad "build record lacks the master sha256"; fi

# Every icon file has an .icon-<slug> rule in icons.css (a missing rule renders
# a solid square: the mask is empty and only the text color shows).
icon_gaps() {
    local css="$1" f slug n=0
    for f in "$root"/static/brand/icons/*.svg; do
        [[ -e "$f" ]] || continue
        n=$((n + 1))
        slug="$(basename "$f" .svg)"
        grep -q -F ".icon-${slug} {" "$css" || printf 'no .icon-%s rule in %s\n' "$slug" "$css"
    done
    ((n > 0)) || printf 'no icon files found (check is blind)\n'
}
gaps="$(icon_gaps "$root/assets/css/pages/icons.css")"
if [[ -z "$gaps" ]]; then ok "every brand icon has an .icon-<slug> rule"; else
    printf '%s\n' "$gaps"
    bad "brand icons without a CSS rule"
fi
grep -v -F '.icon-matrix {' "$root/assets/css/pages/icons.css" >"$work/icons-nomatrix.css"
if icon_gaps "$work/icons-nomatrix.css" | grep -q 'no .icon-matrix rule'; then ok "a missing icon rule is caught"; else bad "a missing icon rule was not caught"; fi

# Coin marks are plain SVGs with a square viewBox of any size (the generator
# scales by the box, so coin-xmr at 1068 and coin-sol at 72 both work). Collect
# every coin file loosely, assert each is square, and require something found.
coin_gaps() {
    local dir="$1" f n=0 vb
    for f in "$dir"/coin-*.svg; do
        [[ -e "$f" ]] || continue
        n=$((n + 1))
        vb="$(sed -n 's/^<svg [^>]*viewBox="0 0 \([0-9][0-9]*\) \([0-9][0-9]*\)".*/\1 \2/p' "$f" | head -n 1)"
        if [[ -z "$vb" ]]; then
            printf '%s: no "0 0 W H" viewBox\n' "$(basename "$f")"
        elif [[ "${vb% *}" != "${vb#* }" ]]; then
            printf '%s: viewBox %s is not square\n' "$(basename "$f")" "$vb"
        fi
    done
    ((n >= 4)) || printf 'fewer than 4 coin files found (check is blind)\n'
}
gaps="$(coin_gaps "$root/static/support")"
if [[ -z "$gaps" ]]; then ok "every coin mark has a square viewBox"; else
    printf '%s\n' "$gaps"
    bad "coin marks without a square viewBox"
fi
mkdir -p "$work/coins"
for c in btc eth xmr sol; do
    cp "$root/static/support/coin-$c.svg" "$work/coins/"
done
sed -i 's/viewBox="0 0 72 72"/viewBox="0 0 72 64"/' "$work/coins/coin-sol.svg"
if coin_gaps "$work/coins" | grep -q 'coin-sol.svg: viewBox 72 64 is not square'; then ok "a non-square coin mark is caught"; else bad "a non-square coin mark was not caught"; fi

if ((failures > 0)); then
    printf '%d failure(s)\n' "$failures"
    exit 1
fi
echo "all brand tests passed"
