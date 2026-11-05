#!/usr/bin/env bash
# Test the Social hub (/social/) and the Products page (/products/).
#
# Builds the real site (HTML unminified, so the closing tags are all there) into the
# repository's gitignored tmp/, never /tmp, then asserts with Python's stdlib
# HTML parser:
#   social:   title and intro, one tile per data/socials.yaml entry, icon mask
#             classes with a CSS rule and a committed SVG each, Pixelfed is not a
#             link, rel="me" on exactly the verifying networks, https only;
#   products: the approved disclosure copy in a bracket-frame panel before any
#             item, the four groups in order, every item with name, line, a
#             "Price checked on" note and an https link with
#             rel="sponsored noopener", all 22 affiliate links from the old posts.
# A guard self-test feeds each asserter a broken page and requires it to fail,
# so a green run cannot come from an asserter that checks nothing. Needs the
# pinned Hugo; a missing Hugo is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/social-products.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

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

asserter="$work/assert_pages.py"
cat >"$asserter" <<'PY'
import hashlib
import json
import pathlib
import re
import sys
from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

DISCLOSURE = (
    "Some links on this page are affiliate links. If you buy something through one, "
    "I may earn a commission at no extra cost to you. I only list products I use "
    "myself or would recommend."
)
GROUPS = ["Audio", "3D printing and PC repair", "Air quality", "Software and services"]
# The 22 amzn.to links of the three old affiliate posts (docs/baseline-chiefgyk3d-com.md).
POST_LINKS = """426GlTk 3LljKfH 3JEiy69 3JBRGDC 3yBttak 3ZHCWss 3JCuOnG 401gsCy 3FnNyVs 3Tf7oIf
3Fm0LxN 3mFk52A 3JBzTwg 41bnwNJ 3K1j8tu 3nu4F1y 3GbQGUI 3Ga4VJs 40xqyMg 41ifQJi 3zMszbu 41dhv2Q""".split()
VERIFY_RME = {"Mastodon", "GitHub"}
MATRIX_SHA = "07e6a16f5437fb0e7704c15b97bd50f46f3fa8968e022af2b9f2395fe0419d72"


class Node:
    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.kids, self.text = [], []

    def classes(self):
        return (self.attrs.get("class") or "").split()

    def walk(self):
        yield self
        for k in self.kids:
            yield from k.walk()

    def all_text(self):
        out = "".join(self.text)
        for k in self.kids:
            out += " " + k.all_text()
        return " ".join(out.split())

    def find(self, tag=None, cls=None):
        return [n for n in self.walk() if (tag is None or n.tag == tag) and (cls is None or cls in n.classes())]


class Dom(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", [], None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs, self.cur)
        self.cur.kids.append(n)
        if tag not in VOID:
            self.cur = n

    def handle_endtag(self, tag):
        n = self.cur
        while n is not None and n.tag != tag:
            n = n.parent
        if n is not None and n.parent is not None:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.text.append(data)


def load(path):
    d = Dom()
    d.feed(pathlib.Path(path).read_text(encoding="utf-8"))
    return d.root


def check_common(doc, bad):
    for n in doc.walk():
        if n.tag == "script":
            bad.append("script element")
        if "style" in n.attrs:
            bad.append("style attribute")
        for k in n.attrs:
            if k.startswith("on"):
                bad.append("event handler " + k)
        href = n.attrs.get("href") or ""
        if n.tag == "a" and href and not re.match(r"(https://|/|#|mailto:)", href):
            bad.append("link not https: " + href)


def check_social(page, root, bad):
    doc = load(page)
    check_common(doc, bad)
    main = doc.find("main")[0]
    h1 = main.find("h1")
    if not h1 or h1[0].all_text() != "Find me online":
        bad.append("h1 is not 'Find me online'")
    if "Follow along, catch a stream, or jump into the community." not in main.all_text():
        bad.append("intro sentence missing")
    # data/socials.yaml is simple enough to read without a YAML library: one "- name:" per entry.
    entries = []
    for line in pathlib.Path(root, "data/socials.yaml").read_text().splitlines():
        if line.startswith("- name:"):
            entries.append({"name": line.split(":", 1)[1].strip()})
        elif entries and re.match(r"  [a-z_]+:", line):
            k, v = line.strip().split(":", 1)
            entries[-1][k] = v.strip().strip('"')
    want = ["Twitch", "YouTube", "Kick", "Mastodon", "Bluesky", "TikTok", "Instagram", "Pixelfed",
            "Threads", "Discord", "Matrix", "GitHub"]
    if [e["name"] for e in entries] != want:
        bad.append("socials.yaml networks/order: %r" % [e["name"] for e in entries])
    tiles = main.find("li", "tile-item")
    if len(tiles) != len(entries):
        bad.append("tile count %d, entries %d" % (len(tiles), len(entries)))
    for tile, e in zip(tiles, entries):
        name = e["name"]
        text = tile.all_text()
        for field, label in (("handle", "handle"), ("blurb", "role line")):
            if e.get(field, "") and e[field] not in text:
                bad.append("%s tile lacks %s" % (name, label))
        if name not in text:
            bad.append("%s tile lacks name" % name)
        links = tile.find("a")
        if name == "Pixelfed":
            if links:
                bad.append("Pixelfed tile is a link")
            if "coming soon" not in text.lower():
                bad.append("Pixelfed tile lacks 'coming soon'")
            if not tile.find("span", "social-icon--placeholder"):
                bad.append("Pixelfed tile lacks the placeholder icon")
            continue
        if len(links) != 1:
            bad.append("%s tile has %d links" % (name, len(links)))
            continue
        a = links[0]
        if a.attrs.get("href") != e["url"]:
            bad.append("%s href differs from data" % name)
        rel = (a.attrs.get("rel") or "").split()
        if (name in VERIFY_RME) != ("me" in rel):
            bad.append("%s rel=me wrong (%r)" % (name, rel))
        if "noopener" not in rel:
            bad.append("%s link lacks noopener" % name)
        icon = a.find("span", "social-icon")
        want_cls = "social-icon--" + e["icon"]
        if not icon or want_cls not in icon[0].classes():
            bad.append("%s tile lacks %s" % (name, want_cls))
        if icon and icon[0].attrs.get("aria-hidden") != "true":
            bad.append("%s icon not aria-hidden" % name)
        svg = pathlib.Path(root, "static/brand/icons", e["icon"] + ".svg")
        if not svg.is_file():
            bad.append("%s icon file missing" % name)
    if hashlib.sha256(pathlib.Path(root, "static/brand/icons/matrix.svg").read_bytes()).hexdigest() != MATRIX_SHA:
        bad.append("matrix.svg differs from the kit hash")
    return len(tiles)


def check_products(page, root, bad):
    doc = load(page)
    check_common(doc, bad)
    main = doc.find("main")[0]
    # The first thing in the content, before any heading of a group or item, is the disclosure panel.
    panels = main.find(cls="panel")
    first_group = main.find("section", "product-group")
    if not panels:
        bad.append("no bracket-frame panel")
        return 0
    disc = panels[0]
    if "disclosure" not in disc.classes():
        bad.append("first panel is not the disclosure")
    paras = [p.all_text() for p in disc.find("p")]
    if DISCLOSURE not in paras:
        bad.append("disclosure copy missing or changed")
    order = list(main.walk())
    if first_group and order.index(disc) > order.index(first_group[0]):
        bad.append("disclosure comes after the first group")
    for n in order:
        if n is disc:
            break
        if n.tag in ("a", "li"):
            bad.append("link or item before the disclosure")
    names = [g.find("h2")[0].all_text() if g.find("h2") else "" for g in first_group]
    if names != GROUPS:
        bad.append("groups %r" % names)
    items = main.find("li", "product")
    seen = []
    for it in items:
        links = it.find("a")
        label = it.all_text()[:40]
        if len(links) != 1:
            bad.append("item has %d links: %s" % (len(links), label))
            continue
        a = links[0]
        rel = (a.attrs.get("rel") or "").split()
        if "sponsored" not in rel or "noopener" not in rel:
            bad.append("link rel lacks sponsored noopener: " + label)
        href = a.attrs.get("href") or ""
        if not href.startswith("https://"):
            bad.append("item link not https: " + label)
        seen.append(href)
        if not it.find("h3"):
            bad.append("item has no name: " + label)
        if len(it.find("p", "product-line")) != 1 or not it.find("p", "product-line")[0].all_text():
            bad.append("item has no one-line description: " + label)
        note = it.find("p", "product-checked")
        if len(note) != 1 or not re.fullmatch(r"Price checked on \w+ \d{1,2}, \d{4}", note[0].all_text()):
            bad.append("item lacks a 'Price checked on <date>' note: " + label)
        if re.search(r"[$]\s*\d", label):
            bad.append("item shows a price: " + label)
    for code in POST_LINKS:
        if "https://amzn.to/" + code not in seen:
            bad.append("missing affiliate link " + code)
    for g in first_group:
        if not g.find("li", "product"):
            bad.append("empty group")
    return len(items)


def main(argv):
    kind, page, root = argv[1:4]
    bad = []
    n = {"social": check_social, "products": check_products}[kind](page, root, bad)
    for b in sorted(set(bad)):
        print(b)
    print("count=%s" % n)
    return 1 if bad else 0


sys.exit(main(sys.argv))
PY

# The built site, plus the stylesheet where the asserter can find it.
public="$work/public"
if HUGO_MINIFY_MINIFYOUTPUT=false hugo --destination "$public" --quiet >"$work/build.log" 2>&1; then
    pass "site builds"
else
    fail "site builds ($(tail -n 3 "$work/build.log" | tr '\n' ' '))"
fi

run_assert() { # kind page
    python3 -I "$asserter" "$1" "$2" "$root" 2>&1
}

social="$public/social/index.html"
products="$public/products/index.html"
for pair in "social:$social" "products:$products"; do
    kind="${pair%%:*}"
    page="${pair#*:}"
    if [[ ! -f "$page" ]]; then
        fail "$kind page exists ($page)"
        continue
    fi
    if out="$(run_assert "$kind" "$page")"; then
        pass "$kind page: $(tail -n 1 <<<"$out")"
    else
        fail "$kind page: $(tr '\n' ';' <<<"$out")"
    fi
done

# Every icon class used by a tile has a mask rule in the built stylesheet and
# a CSS-only placeholder exists for the tile without an icon.
css="$(cat "$public"/css/*.css 2>/dev/null || true)"
if [[ -z "$css" ]]; then
    fail "built stylesheet found"
else
    for slug in twitch youtube kick mastodon bluesky tiktok instagram threads discord matrix github; do
        if ! grep -q "social-icon--${slug}" <<<"$css"; then
            fail "css rule for social-icon--${slug}"
        fi
    done
    if grep -q 'social-icon--placeholder' <<<"$css"; then
        pass "css rules for icons and placeholder"
    else
        fail "css rule for the placeholder"
    fi
    if [[ ! -f "$root/assets/css/pages/social.css" || ! -f "$root/assets/css/pages/products.css" ]]; then
        fail "assets/css/pages/social.css and products.css exist"
    elif grep -Eq '#[0-9a-fA-F]{3,8}\b' "$root/assets/css/pages/social.css" "$root/assets/css/pages/products.css"; then
        fail "page css writes a color outside tokens.css"
    else
        pass "page css uses tokens only"
    fi
fi

# Guard self-test: the asserters must fail on broken pages.
if [[ -f "$social" && -f "$products" ]]; then
    guard() { # label kind source sed-expression
        local label="$1" kind="$2" src="$3" expr="$4" copy="$work/guard.html"
        sed -E "$expr" "$src" >"$copy"
        if cmp -s "$src" "$copy"; then
            fail "guard '$label' did not change the page (the test is stale)"
        elif run_assert "$kind" "$copy" >/dev/null; then
            fail "guard '$label': asserter accepted a broken page"
        else
            pass "guard '$label' fails as it should"
        fi
    }
    guard "rel=me dropped" social "$social" 's/rel="me noopener"/rel="noopener"/g'
    guard "pixelfed linked" social "$social" 's/<span class="social-icon social-icon--placeholder"/<a href="https:\/\/x.example\/"><span class="social-icon social-icon--placeholder"/'
    guard "sponsored dropped" products "$products" 's/rel="sponsored noopener"/rel="noopener"/'
    guard "disclosure changed" products "$products" 's/at no extra cost to you/at a cost to you/'
    guard "price note removed" products "$products" 's/Price checked on/Seen on/'
    guard "plain http link" products "$products" 's#href="https://amzn.to/#href="http://amzn.to/#'
fi

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all social and products checks passed"
