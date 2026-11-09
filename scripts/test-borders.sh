#!/usr/bin/env bash
# Test the border system (docs/borders.md).
#
# Builds the site into the repository's gitignored tmp/ (never /tmp) and asserts:
#   - no page carries more than ONE level 3 frame (svg class "fr fr-l3"), and the
#     two pages that own one (Home, Support) carry exactly one;
#   - every frame (svg class "fr") is aria-hidden and the build holds no style
#     attribute or style element (the CSP forbids both);
#   - assets/css/borders.css has no url(), no hex color (colors come from the
#     tokens in assets/css/tokens.css; the partial has none either), no animation
#     outside a prefers-reduced-motion: no-preference block, no rule that sets an
#     amber text color (color: var(--accent)), the support L3 label override, and
#     a print block that resets frame backgrounds and borders.
# A self-test feeds the counter a page with two L3 frames and requires it to fail,
# so a green run cannot come from a counter that counts nothing. Needs the pinned
# Hugo; a missing Hugo is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/borders.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if ! command -v hugo >/dev/null 2>&1; then
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
fi

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# l3_count <file>: number of level 3 frames in a page.
l3_count() { { grep -oE 'class="?fr fr-l3[" >]' "$1" || true; } | wc -l; }

# Self-test: the counter must see two frames in a fixture, and one in another.
printf '<svg class="fr fr-l3"></svg><svg class="fr fr-l3"></svg>\n' >"$work/two.html"
printf '<svg class="fr fr-l3"></svg><svg class="fr fr-l2"></svg>\n' >"$work/one.html"
if [[ "$(l3_count "$work/two.html")" -eq 2 && "$(l3_count "$work/one.html")" -eq 1 ]]; then
    pass "the L3 counter counts a fixture correctly"
else
    fail "the L3 counter is blind: it must count 2 and 1 on the fixtures"
fi

out="$work/public"
(cd "$root" && hugo --minify --destination "$out" >"$work/hugo.log" 2>&1) || {
    cat "$work/hugo.log"
    fail "the site did not build"
    exit 1
}

total=0
over=0
while IFS= read -r -d '' page; do
    n="$(l3_count "$page")"
    total=$((total + n))
    if [[ "$n" -gt 1 ]]; then
        over=$((over + 1))
        fail "${page#"$out"/} has $n level 3 frames, the limit is 1"
    fi
done < <(find "$out" -name '*.html' -print0)
[[ "$over" -eq 0 ]] && pass "no page has more than one L3 frame"

for p in index.html support/index.html; do
    n="$(l3_count "$out/$p")"
    [[ "$n" -eq 1 ]] && pass "$p has exactly one L3 frame" || fail "$p has $n L3 frames, wanted 1"
done

bad="$(for f in $(grep -rlE "class=.?fr fr-l[23]" "$out" --include="*.html"); do grep -qE "class=.?fr fr-l[23].? aria-hidden=" "$f" || echo "$f"; done)"
[[ -z "$bad" ]] && pass "every frame is aria-hidden" || fail "a frame is not aria-hidden: $bad"

styled="$(grep -rlE '(<style[ >]|[[:space:]]style=)' "$out" --include='*.html' || true)"
[[ -z "$styled" ]] && pass "no style element or style attribute in any page" || fail "inline style in: $styled"

css="$root/assets/css/borders.css"
# The only url() in borders.css are the two faithful button art files.
if python3 -I - "$css" <<'PY'
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
urls = set(re.findall(r"url\(\"?([^)\"]*)\"?\)", css))
ok = {"../brand/frame-faithful-button.svg", "../brand/frame-faithful-button-amber.svg"}
sys.exit(0 if urls == ok else 1)
PY
then pass "borders.css names only the two faithful button art files"; else fail "borders.css has an unexpected url()"; fi
for f in frame-faithful-button.svg frame-faithful-button-amber.svg; do
    if [[ -s "$root/static/brand/$f" ]] && ! grep -qiE '<script|<text|href=|<image' "$root/static/brand/$f"; then
        pass "$f exists with no script, text or reference"
    else
        fail "$f is missing or holds a script, text or reference"
    fi
done
if python3 -I "$root/scripts/gen-frame-art.py" --check; then pass "the button art matches scripts/gen-frame-art.py"; else fail "the button art is stale: run scripts/gen-frame-art.py"; fi

# No cream or white fill: the primary button hover is amber, never --text.
if grep -qE -- '--fill:[[:space:]]*var\(--text\)' "$css"; then fail "a fill is set to the text color (cream or white)"; else pass "no fill is cream or white"; fi

# Button levels (params.frames): the default marks only the primary button; a level or a per-class
# override adds bf-none or bf-faithful to the buttons it names; a bad level fails.
default_bf="$(grep -rhoE 'bf-[a-z]+' "$out" --include='*.html' | sort -u | tr '\n' ' ')"
[[ "$default_bf" == "bf-faithful " ]] && pass "the default is faithful on the primary button and minimal elsewhere" || fail "unexpected bf- classes at the default level: $default_bf"
if grep -rqE 'btn-ghost[^"]* bf-' "$out" --include='*.html'; then fail "a ghost button is marked at the default level"; else pass "ghost buttons carry no bf- class at the default level"; fi
build_with() { # build_with <name> <toml body>: prints the destination
    printf '[params.frames]\n%s\n' "$2" >"$work/$1.toml"
    (cd "$root" && hugo --minify --config hugo.toml,"$work/$1.toml" --destination "$work/pub-$1" >"$work/$1.log" 2>&1) && echo "$work/pub-$1"
}
if dest="$(build_with none '  level = "none"')" && grep -rqE 'class="[^"]*\bbf-none' "$dest" --include='*.html'; then
    pass "level none puts bf-none on the buttons"
else
    fail "level none did not build or did not mark the buttons"
fi
faith_body='  level = "minimal"
  [params.frames.classes]
  btn-primary = "faithful"'
if dest="$(build_with faith "$faith_body")" &&
    grep -qE 'btn-primary bf-faithful' "$dest/index.html" && ! grep -qE 'btn-ghost[^"]* bf-' "$dest/index.html"; then
    pass "a per-class override marks only the primary buttons"
else
    fail "the per-class override did not build or marked the wrong buttons"
fi
if build_with bad '  level = "glowing"' >/dev/null; then fail "an unknown frame level built"; else pass "an unknown frame level fails the build"; fi
if python3 -I - "$css" <<'PY'
import re, sys
css = open(sys.argv[1]).read()
css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
# remove the one allowed block, then no animation may remain
allowed = re.search(r"@media \(prefers-reduced-motion: no-preference\) \{.*?\n\}\n", css, flags=re.S)
rest = css.replace(allowed.group(0), "") if allowed else css
sys.exit(1 if re.search(r"animation\s*:", rest) or not allowed else 0)
PY
then pass "animation only under prefers-reduced-motion: no-preference"; else fail "borders.css animates outside no-preference"; fi

# Colors come from tokens.css (brand rule), and no frame rule sets amber text.
if python3 -I - "$css" "$root/layouts/_partials/frame.html" <<'PY'
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
part = re.sub(r"\{\{-?\s*/\*.*?\*/\s*-?\}\}", "", open(sys.argv[2]).read(), flags=re.S)
bad = []
if re.search(r"#[0-9A-Fa-f]{3,8}\b", css):
    bad.append("hex color in borders.css")
if re.search(r"(stop-color|fill)=\"#", part):
    bad.append("hex color in frame.html")
if re.search(r"(^|[;{\s])color\s*:\s*var\(--accent\)", css):
    bad.append("amber text color in borders.css")
if not re.search(r"\.tile\.bx \.support-tile-name\s*\{\s*color:\s*var\(--text\)", css):
    bad.append("support L3 label override missing")
m = re.search(r"@media print \{(.*)\}\s*$", css, flags=re.S)
if not m or "background: none" not in m.group(1) or "border: 1px solid CanvasText" not in m.group(1) or "::before" not in m.group(1):
    bad.append("print block does not reset frames")
print("; ".join(bad))
sys.exit(1 if bad else 0)
PY
then
    pass "colors come from tokens, no amber frame text, print falls back to a border"
else
    fail "borders.css or frame.html breaks the token, text-color or print contract"
fi

# Forced colors: the framed elements' background layers are reset, so the plain
# CanvasText border is all that shows (not the L1 ticks or the L2/L3 gradients).
if python3 -I - "$css" <<'PY'
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
blocks = re.findall(r"@media \(forced-colors: active\) \{(.*?)\n\}\n", css, flags=re.S)
ok = False
for b in blocks:
    for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", b):
        names = {x.strip() for x in sel.split(",")}
        if {".bx.l2", ".bx.l3", ".l1", ".panel", ".tile", ".btn"} <= names and "background: none" in body and "CanvasText" in body:
            ok = True
sys.exit(0 if ok else 1)
PY
then pass "forced colors resets the framed elements' backgrounds"; else fail "the forced-colors block leaves the frame backgrounds in place"; fi

if ((failures > 0)); then
    echo "test-borders: ${failures} failure(s)"
    exit 1
fi
echo "test-borders: all passed"
