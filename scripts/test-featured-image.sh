#!/usr/bin/env bash
# Test the headline (featured) image slot (issue 217).
#
# Builds throwaway sites (this repository's layouts, assets, static files and data,
# plus pages written here) under the repository's gitignored tmp/, never /tmp, and
# asserts: a post with image + imageAlt shows a hero above the title (not lazy, with
# width, height and alt), a thumbnail on the list page, and its own social card; a
# post with no image shows no hero, no thumbnail and the default card; and the build
# FAILS for a missing imageAlt, a placeholder imageAlt, and an image that is not a
# page-bundle file. A missing Hugo is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/featured.XXXXXX")"
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

# A valid 1x1 PNG, so the resize pipeline has real pixels.
png="$work/featured.png"
base64 -d >"$png" <<'B64'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/
iZk9HQAAAABJRU5ErkJggg==
B64

# make_site <dir> <extra front matter>: a site with one post that has a bundle
# file featured.png (and the given front matter) and one that has no image.
make_site() {
    local dir="$1" extra="$2"
    mkdir -p "$dir/content/posts/with" "$dir/content/posts/without"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$root/data" "$dir/"
    sed 's/^  minifyOutput = true/  minifyOutput = false/' "$root/hugo.toml" >"$dir/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$dir/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$dir/content/posts/_index.md"
    printf -- '---\ntitle: "With Image"\ndate: 2024-06-06T07:08:09-04:00\ndescription: "Has a headline image."\n%s---\n\nBody with.\n' "$extra" >"$dir/content/posts/with/index.md"
    printf -- '---\ntitle: "No Image"\ndate: 2024-05-06T07:08:09-04:00\ndescription: "Has none."\n---\n\nBody without.\n' >"$dir/content/posts/without/index.md"
    cp "$png" "$dir/content/posts/with/featured.png"
    cp "$png" "$dir/content/posts/with/extra.png"
}

# The asserter: hero before h1, attributes, thumb, card.
asserter="$work/assert.py"
cat >"$asserter" <<'PY'
import re, sys

def page(path):
    return open(path, encoding="utf-8").read()

def post(path, want_image):
    t, bad = page(path), []
    hero = re.search(r'<figure class="post-hero">\s*<img ([^>]*)>', t)
    h1 = t.find("<h1>")
    if want_image:
        if not hero:
            return ["no hero figure"]
        a = hero.group(1)
        if hero.start() > h1:
            bad.append("hero is not above the title")
        if "loading=" in a:
            bad.append("hero must not set loading (it is above the fold)")
        for need in ('fetchpriority="high"', 'alt="A real description of the picture"', "width=", "height="):
            if need not in a:
                bad.append("hero lacks " + need)
        if not re.search(r'<meta property="og:image" content="https://[^"]*/posts/with/featured_hu_[0-9a-f]+\.jpg">', t):
            bad.append("og:image is not a processed JPEG card of the featured image")
        if not re.search(r'<meta property="og:image:width" content="1">', t):
            bad.append("og:image:width is not the real width of the card")
    else:
        if "post-hero" in t:
            bad.append("a post with no image has a hero")
        if not re.search(r'<meta property="og:image" content="https://[^"]*/brand/og-card\.png">', t):
            bad.append("og:image is not the default card")
    return bad

def listing(path):
    t, bad = page(path), []
    items = re.findall(r"<li[^>]*>.*?</li>", t, re.S)
    with_i = [i for i in items if "With Image" in i]
    without = [i for i in items if "No Image" in i]
    if len(with_i) != 1 or len(without) != 1:
        return ["list items not found (%d, %d)" % (len(with_i), len(without))]
    if 'class="post-thumb"' not in with_i[0] or 'class="has-thumb"' not in with_i[0]:
        bad.append("no thumbnail on the card with an image")
    if 'loading="lazy"' not in with_i[0]:
        bad.append("thumbnail is not lazy")
    if "post-thumb" in without[0]:
        bad.append("thumbnail on a card with no image")
    return bad

kind, path = sys.argv[1], sys.argv[2]
bad = {"hero": lambda: post(path, True), "none": lambda: post(path, False), "list": lambda: listing(path)}[kind]()
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY

check() { # check <label> <kind> <file>
    local out
    if out="$(python3 -I "$asserter" "$2" "$3" 2>&1)"; then pass "$1"; else fail "$1: $out"; fi
}

good="$work/good"
make_site "$good" 'image: "featured.png"
imageAlt: "A real description of the picture"
build:
  publishResources: false
'
if (cd "$good" && hugo --quiet --destination "$good/public" 2>"$work/good.err"); then
    pass "site with a headline image builds"
    check "post page: hero above the title, not lazy, alt and size" hero "$good/public/posts/with/index.html"
    check "post with no image: no hero, default card" none "$good/public/posts/without/index.html"
    check "list page: thumbnail only on the card with an image" list "$good/public/posts/index.html"
    if [[ -f "$good/public/posts/with/extra.png" && ! -e "$good/public/posts/with/featured.png" ]]; then
        pass "the featured original is not published; another bundle file still is"
    else
        fail "publishing: expected extra.png published and featured.png not ($(find "$good/public/posts/with" -type f -printf '%f ' | head -c 300))"
    fi
    # Guard self-test: the asserter must reject a page where the hero is lazy and the alt is gone.
    bad="$work/bad.html"
    sed -e 's/fetchpriority="high"/loading="lazy"/' -e 's/alt="A real description of the picture"/alt=""/' "$good/public/posts/with/index.html" >"$bad"
    if python3 -I "$asserter" hero "$bad" >/dev/null 2>&1; then fail "guard: the asserter accepted a lazy hero with no alt"; else pass "guard: a lazy hero with no alt is rejected"; fi
else
    fail "site with a headline image did not build: $(cat "$work/good.err")"
fi

must_fail() { # must_fail <label> <expected message> <extra front matter> [remove]
    local label="$1" want="$2" extra="$3" dir out
    dir="$(mktemp -d "$work/neg.XXXXXX")"
    make_site "$dir" "$extra"
    [[ -z "${4:-}" ]] || rm -f "$dir/content/posts/with/featured.png"
    if out="$(cd "$dir" && hugo --logLevel error --destination "$dir/public" 2>&1)"; then
        fail "$label: the build passed"
    elif grep -q -- "$want" <<<"$out"; then
        pass "$label: the build fails"
    else
        fail "$label: failed for another reason: $out"
    fi
}
must_fail "image without imageAlt" "has no imageAlt" 'image: "featured.png"
'
must_fail "placeholder imageAlt" "placeholder imageAlt" 'image: "featured.png"
imageAlt: "TODO alt text"
'
must_fail "image that is not a bundle file" "not a page-bundle resource" 'image: "featured.png"
imageAlt: "A real description of the picture"
' remove

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all featured-image checks passed"
