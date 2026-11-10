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

# bad_case <name> <root start tag>: the build must fail with a root viewBox error
bad_case() {
    local name="$1" tag="$2" d="$work/$1"
    site "$d" "$tag"
    if hugo --source "$d" --destination "$d/public" >"$d/build.log" 2>&1; then
        fail "$name (build succeeded)"
    elif grep -q 'SVG whose root' "$d/build.log"; then
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

bad_case payload-with-invalid-root-viewbox "<svg aria-label='viewBox=\"0 0 999999999999999999999 1\"' $NS viewBox=\"invalid\">"
bad_case enormous-number "<svg $NS viewBox=\"0 0 999999999999999999999 1\">"
bad_case over-maximum "<svg $NS viewBox=\"0 0 10001 10\">"
bad_case zero-width "<svg $NS viewBox=\"0 0 0 10\">"
bad_case repeated-decimal-point "<svg $NS viewBox=\"0 0 1.2.3 4\">"
bad_case nonzero-origin "<svg $NS viewBox=\"1 0 10 10\">"
bad_case negative "<svg $NS viewBox=\"-1 0 10 10\">"
bad_case commas "<svg $NS viewBox=\"0,0,10,10\">"
bad_case exponent "<svg $NS viewBox=\"0 0 1e3 10\">"
bad_case no-root-viewbox "<svg $NS>"
bad_case viewbox-only-in-child "<svg $NS><g viewBox=\"0 0 10 10\"/>"
bad_case root-is-not-svg "<g $NS viewBox=\"0 0 10 10\">"

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all svg render hook checks passed"
