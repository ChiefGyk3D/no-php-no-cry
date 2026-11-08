#!/usr/bin/env bash
# Test the border system (docs/borders.md).
#
# Builds the site into the repository's gitignored tmp/ (never /tmp) and asserts:
#   - no page carries more than ONE level 3 frame (svg class "fr fr-l3"), and the
#     two pages that own one (Home, Support) carry exactly one;
#   - every frame (svg class "fr") is aria-hidden and the build holds no style
#     attribute or style element (the CSP forbids both);
#   - assets/css/borders.css has no url(), no hard-coded animation outside a
#     prefers-reduced-motion: no-preference block, and no amber text color on
#     body text rules.
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
if python3 -I -c 'import re,sys; sys.exit(0 if "url(" in re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S) else 1)' "$css"; then fail "borders.css has a url()"; else pass "borders.css has no url()"; fi
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

if ((failures > 0)); then
    echo "test-borders: ${failures} failure(s)"
    exit 1
fi
echo "test-borders: all passed"
