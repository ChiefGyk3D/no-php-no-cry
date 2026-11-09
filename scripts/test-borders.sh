#!/usr/bin/env bash
# Test the border system (docs/borders.md).
#
# Builds the site into the repository's gitignored tmp/ (never /tmp) and asserts:
#   - a frame never contains another frame: no element with class fx, btn or tile
#     (or a pre, table, blockquote or input) has one of those as a descendant;
#   - every page carries frames (its title is an "fx" banner), and the page types
#     the owner named (home, support, social, products, search, about, resume) each
#     carry at least five;
#   - the build holds no style attribute or style element (the CSP forbids both)
#     and no inline svg frame (the frame art is the four files under static/brand);
#   - assets/css/borders.css: the only url() are the four frame SVGs, no hex
#     color (colors come from the tokens), no animation outside a
#     prefers-reduced-motion: no-preference block, no rule that sets an amber
#     text color, a forced-colors block and a print block that drop the art;
#   - the four frame SVGs exist, hold no script, no text and no external reference.
# A self-test feeds the nesting checker a page with a frame in a frame and requires
# it to fail, so a green run cannot come from a checker that sees nothing. There is
# no per-page limit on frames. Needs the pinned Hugo; a missing Hugo is a failure.
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

# The nesting checker: prints "frames N" and one line per frame inside a frame.
checker="$work/nest.py"
cat >"$checker" <<'PY'
import sys
from html.parser import HTMLParser

CLASSES = {"fx", "btn", "tile"}
TAGS = {"pre", "table", "blockquote"}
VOID = {"img", "input", "br", "hr", "meta", "link", "source", "wbr", "col", "area", "base", "embed", "param", "track"}

class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []  # (tag, is_frame)
        self.frames = 0
        self.bad = []

    def is_frame(self, tag, attrs):
        cls = set((dict(attrs).get("class") or "").split())
        return bool(cls & CLASSES) or tag in TAGS or (tag == "input" and "search-input" in cls)

    def handle_starttag(self, tag, attrs):
        f = self.is_frame(tag, attrs)
        if f:
            self.frames += 1
            if any(x[1] for x in self.stack):
                self.bad.append("%s.%s inside a frame" % (tag, dict(attrs).get("class", "")))
        if tag not in VOID:
            self.stack.append((tag, f))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                del self.stack[i:]
                break

p = P()
p.feed(open(sys.argv[1], encoding="utf-8").read())
print("frames", p.frames)
for b in p.bad:
    print("nested", b)
sys.exit(1 if p.bad else 0)
PY

# Self-test: a frame in a frame must be reported, a sibling pair must not.
printf '<div class="fx"><a class="btn" href="#">x</a></div>\n' >"$work/nested.html"
printf '<div class="fx"><p>x</p></div><a class="btn" href="#">y</a>\n' >"$work/flat.html"
if ! python3 -I "$checker" "$work/nested.html" >/dev/null && python3 -I "$checker" "$work/flat.html" >/dev/null; then
    pass "the nesting checker flags a frame in a frame and accepts siblings"
else
    fail "the nesting checker is blind: it must fail on a nested fixture and pass on a flat one"
fi

out="$work/public"
(cd "$root" && hugo --minify --destination "$out" >"$work/hugo.log" 2>&1) || {
    cat "$work/hugo.log"
    fail "the site did not build"
    exit 1
}

nested=0
bare=0
while IFS= read -r -d '' page; do
    rel="${page#"$out"/}"
    res="$(python3 -I "$checker" "$page" || true)"
    if grep -q '^nested' <<<"$res"; then
        nested=$((nested + 1))
        fail "$rel: $(grep '^nested' <<<"$res" | head -3 | tr '\n' ';')"
    fi
    n="$(grep '^frames' <<<"$res" | cut -d' ' -f2)"
    # The Cloudflare redirect stubs for old addresses carry no template.
    if [[ "${n:-0}" -eq 0 ]] && grep -q '<main' "$page"; then
        bare=$((bare + 1))
        fail "$rel has a main element and no frame"
    fi
done < <(find "$out" -name '*.html' -print0)
[[ "$nested" -eq 0 ]] && pass "no frame contains another frame on any page"
[[ "$bare" -eq 0 ]] && pass "every page with a main element carries frames"

for p in index.html support/index.html social/index.html products/index.html search/index.html about/index.html resume/index.html; do
    n="$(python3 -I "$checker" "$out/$p" | grep '^frames' | cut -d' ' -f2)"
    [[ "$n" -ge 5 ]] && pass "$p carries $n frames" || fail "$p carries $n frames, wanted at least 5"
done

styled="$(grep -rlE '(<style[ >]|[[:space:]]style=)' "$out" --include='*.html' || true)"
[[ -z "$styled" ]] && pass "no style element or style attribute in any page" || fail "inline style in: $styled"

inline="$(grep -rlE '<svg[^>]*class="?fr[ "]' "$out" --include='*.html' || true)"
[[ -z "$inline" ]] && pass "no inline frame svg in any page" || fail "inline frame svg in: $inline"

css="$root/assets/css/borders.css"
if python3 -I - "$css" <<'PY'
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
bad = []
urls = re.findall(r"url\(([^)]*)\)", css)
allowed = {"../brand/frame-corners.svg", "../brand/frame-corners-dk.svg", "../brand/frame-plates-top.svg", "../brand/frame-plates-bottom.svg"}
for u in urls:
    if u.strip("\"' ") not in allowed:
        bad.append("url(%s)" % u)
if re.search(r"#[0-9A-Fa-f]{3,8}\b", css):
    bad.append("hex color")
if re.search(r"(^|[;{\s])color\s*:\s*var\(--accent\)", css):
    bad.append("amber text color")
allowed_motion = re.search(r"@media \(prefers-reduced-motion: no-preference\) \{.*?\n\}\n", css, flags=re.S)
rest = css.replace(allowed_motion.group(0), "") if allowed_motion else css
if re.search(r"(animation|transition)\s*:", rest):
    bad.append("motion outside prefers-reduced-motion: no-preference")
for need in ("@media (forced-colors: active)", "@media print"):
    if need not in css:
        bad.append("missing " + need)
m = re.search(r"@media print \{(.*)\}\s*$", css, flags=re.S)
if not m or "border-image: none" not in m.group(1) or "background: none" not in m.group(1):
    bad.append("print block does not drop the art")
m = re.search(r"@media \(forced-colors: active\) \{(.*?)\n\}\n", css, flags=re.S)
if not m or "border-image: none" not in m.group(1):
    bad.append("forced-colors block does not drop the art")
print("; ".join(bad))
sys.exit(1 if bad else 0)
PY
then
    pass "borders.css: only the four frame SVGs, no hex, no amber text, motion gated, forced-colors and print fall back"
else
    fail "borders.css breaks the token, motion, forced-colors or print contract"
fi

for f in frame-corners frame-corners-dk frame-plates-top frame-plates-bottom; do
    svg="$root/static/brand/$f.svg"
    if [[ -f "$svg" ]] && ! grep -qiE '<script|<text|href="(https?:|//|data:)|<image|<foreignObject' "$svg"; then
        pass "$f.svg is plain vector art"
    else
        fail "$f.svg is missing or carries script, text, an image or an external reference"
    fi
done

if ((failures > 0)); then
    echo "test-borders: ${failures} failure(s)"
    exit 1
fi
echo "test-borders: all passed"
