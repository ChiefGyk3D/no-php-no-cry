#!/usr/bin/env bash
# Test the SVG branch of layouts/_markup/render-image.html (issue 352): the img width and
# height come only from the ROOT element's viewBox ("0 0 width height", plain decimals, at
# most 10000), whatever the quoting, attribute order or whitespace, and a viewBox that sits
# inside another attribute's value, an enormous number or an invalid value never reaches the
# page (the build fails instead).
#
# Builds throwaway sites (this repository's layouts, assets, static files and data, plus a
# page written here) under the repository's gitignored tmp/, never /tmp. A missing Hugo is
# a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/svg-hook.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

command -v hugo >/dev/null 2>&1 || {
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
}

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# site <dir> <svg root start tag>: one post with a bundle file pic.svg that has the given root tag.
site() {
    local dir="$1" tag="$2"
    mkdir -p "$dir/content/posts/with"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$root/data" "$dir/"
    sed 's/^  minifyOutput = true/  minifyOutput = false/' "$root/hugo.toml" >"$dir/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$dir/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$dir/content/posts/_index.md"
    printf -- '---\ntitle: "With"\ndate: 2024-06-06T07:08:09-04:00\ndescription: "Has an svg."\n---\n\n![A diagram used by the test.](pic.svg)\n' >"$dir/content/posts/with/index.md"
    printf '%s<title>t</title></svg>\n' "$tag" >"$dir/content/posts/with/pic.svg"
}

NS='xmlns="http://www.w3.org/2000/svg"'

# ok_case <name> <root start tag> <width> <height>
ok_case() {
    local name="$1" tag="$2" w="$3" h="$4" d="$work/$1"
    site "$d" "$tag"
    if ! hugo --source "$d" --destination "$d/public" >"$d/build.log" 2>&1; then
        fail "$name (build failed: $(grep -m1 ERROR "$d/build.log"))"
        return
    fi
    local img
    img="$(tr '\n' ' ' <"$d/public/posts/with/index.html" | grep -o '<img[^>]*pic\.svg[^>]*>' | head -1 || true)"
    if grep -q "width=$w " <<<"$img" && grep -q "height=$h " <<<"$img" || grep -q "width=\"$w\"" <<<"$img" && grep -q "height=\"$h\"" <<<"$img"; then
        pass "$name"
    else
        fail "$name (img: $img, want ${w}x${h})"
    fi
}

# bad_case <name> <root start tag> <expected error text>: the build must fail with exactly that hook error
bad_case() {
    local name="$1" tag="$2" msg="$3" d="$work/$1"
    site "$d" "$tag"
    if hugo --source "$d" --destination "$d/public" >"$d/build.log" 2>&1; then
        fail "$name (build succeeded)"
    elif grep -q "$msg" "$d/build.log"; then
        pass "$name"
    else
        fail "$name (failed for another reason: $(grep -m1 ERROR "$d/build.log"))"
    fi
}

ok_case plain "<svg $NS viewBox=\"0 0 900 1230\">" 900 1230
ok_case single-quoted "<svg $NS viewBox='0 0 900 1230'>" 900 1230
ok_case viewbox-first "<svg viewBox=\"0 0 900 1230\" $NS>" 900 1230
ok_case attributes-before "<svg id=\"a\" role=\"img\" $NS width=\"1\" viewBox=\"0 0 900 1230\" height=\"2\">" 900 1230
ok_case whitespace "<svg $NS
   viewBox  =  \"  0	0   900
 1230  \"
 >" 900 1230
ok_case xml-declaration "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<svg $NS viewBox=\"0 0 900 1230\">" 900 1230
ok_case decimals-round "<svg $NS viewBox=\"0 0 900.4 1229.6\">" 900 1230
ok_case maximum "<svg $NS viewBox=\"0 0 10000 10000\">" 10000 10000
ok_case payload-in-earlier-attribute "<svg aria-label='viewBox=\"0 0 999999999999999999999 1\"' $NS viewBox=\"0 0 900 1230\">" 900 1230
ok_case payload-in-later-attribute "<svg $NS viewBox=\"0 0 900 1230\" aria-label='viewBox=\"0 0 5 5\"'>" 900 1230

bad_case payload-with-invalid-root-viewbox "<svg aria-label='viewBox=\"0 0 999999999999999999999 1\"' $NS viewBox=\"invalid\">" "root viewBox is not 0 0 width height in plain decimals"
bad_case enormous-number "<svg $NS viewBox=\"0 0 999999999999999999999 1\">" "root viewBox is not 0 0 width height in plain decimals"
bad_case over-maximum "<svg $NS viewBox=\"0 0 10001 10\">" "root viewBox size is outside 1 to 10000"
bad_case zero-width "<svg $NS viewBox=\"0 0 0 10\">" "root viewBox size is outside 1 to 10000"
bad_case repeated-decimal-point "<svg $NS viewBox=\"0 0 1.2.3 4\">" "root viewBox is not 0 0 width height in plain decimals"
bad_case nonzero-origin "<svg $NS viewBox=\"1 0 10 10\">" "root viewBox is not 0 0 width height in plain decimals"
bad_case negative "<svg $NS viewBox=\"-1 0 10 10\">" "root viewBox is not 0 0 width height in plain decimals"
bad_case commas "<svg $NS viewBox=\"0,0,10,10\">" "root viewBox is not 0 0 width height in plain decimals"
bad_case exponent "<svg $NS viewBox=\"0 0 1e3 10\">" "root viewBox is not 0 0 width height in plain decimals"
bad_case no-root-viewbox "<svg $NS>" "root element has no viewBox"
bad_case viewbox-only-in-child "<svg $NS><g viewBox=\"0 0 10 10\"/>" "root element has no viewBox"
bad_case root-is-not-svg "<g $NS viewBox=\"0 0 10 10\">" "root element has no viewBox"

# The gate (check-content.py) and the hook agree on small sizes: refused or accepted together,
# and the hook rounds half up. gate_verdict <width>: "ok" or "refused" for a square viewBox.
gate_verdict() {
    python3 -I - "$root/scripts/check-content.py" "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cc", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
v = sys.argv[2]
svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s"/>' % (v, v)
print("refused" if m.svg_findings(svg.encode()) else "ok")
PY
}
# agree_case <width> <expected verdict> <expected img size, or - when refused>
agree_case() {
    local v="$1" want="$2" size="$3" gate
    gate="$(gate_verdict "$v")"
    if [[ "$gate" != "$want" ]]; then
        fail "gate verdict for $v is $gate, want $want"
        return
    fi
    if [[ "$want" == "ok" ]]; then
        ok_case "agree-$v" "<svg $NS viewBox=\"0 0 $v $v\">" "$size" "$size"
    else
        bad_case "agree-$v" "<svg $NS viewBox=\"0 0 $v $v\">" "root viewBox size is outside 1 to 10000"
    fi
}
agree_case 0.4 refused -
agree_case 0.5 ok 1
agree_case 0.9 ok 1
agree_case 1 ok 1
agree_case 1.4 ok 1

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all svg render hook checks passed"
