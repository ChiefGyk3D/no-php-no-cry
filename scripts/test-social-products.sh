#!/usr/bin/env bash
# Test the Social hub (/social/) and the Products page (/products/).
#
# Builds the real site (HTML unminified, so the closing tags are all there) into the
# repository's gitignored tmp/, never /tmp, then asserts with Python's stdlib
# HTML parser:
#   social:   title and intro, one tile per data/socials.yaml entry, icon mask
#             classes with a CSS rule and a committed SVG each, Pixelfed is a live
#             link to its profile, rel="me" on exactly the networks whose rel_me
#             field in the data says true (the test follows the data), https only;
#   products: the disclosure copy in a bracket-frame panel before any item, the
#             groups in the order of data/products.yaml (security first, creator
#             and social media tools last, the first one open, a count in each
#             summary), and every item of the data file on the page with a name,
#             a line, a "Price checked on" note, an https link with
#             rel="sponsored noopener" and the vendor label the data says (none
#             when unset). The test reads the data file, so the maintainer can
#             swap links and vendors without touching it; a floor on the item
#             count catches an item lost by accident.
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

# Reading the page: some links are affiliate links, some go straight to the company.
DISCLOSURE = (
    "Some links on this page are affiliate links. If you buy something through one, "
    "I may earn a commission at no extra cost to you. Some products I link directly "
    "to the company instead of a store. I only list products I use myself or would recommend."
)
ASSOCIATE = "As an Amazon Associate I earn from qualifying purchases."
VENDORS = {"Amazon", "Direct"}
# Floor, not an exact count: 32 items on 2026-11-06. Lower it only on purpose.
MIN_ITEMS = 32
FIRST_GROUP_WORD = "Security"
LAST_GROUP = "Creator and social media tools"
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
            if e["url"] != "https://pics.chiefgyk3d.com/ChiefGyk3D":
                bad.append("Pixelfed url is not the profile on pics.chiefgyk3d.com")
            if "coming soon" in text.lower() or tile.find("div", "social-tile--soon"):
                bad.append("Pixelfed tile still has the coming-soon treatment")
        if len(links) != 1:
            bad.append("%s tile has %d links" % (name, len(links)))
            continue
        a = links[0]
        if a.attrs.get("href") != e["url"]:
            bad.append("%s href differs from data" % name)
        rel = (a.attrs.get("rel") or "").split()
        if e.get("rel_me") not in ("true", "false"):
            bad.append("%s rel_me in the data is not true or false: %r" % (name, e.get("rel_me")))
        elif (e["rel_me"] == "true") != ("me" in rel):
            bad.append("%s rel=me wrong for rel_me %s (%r)" % (name, e["rel_me"], rel))
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


def load_products(root):
    """data/products.yaml read without a YAML library: groups, then items with simple scalar keys."""
    groups = []
    for line in pathlib.Path(root, "data/products.yaml").read_text().splitlines():
        if line.startswith("- group:"):
            groups.append({"group": line.split(":", 1)[1].strip(), "items": []})
        elif line.startswith("    - name:"):
            groups[-1]["items"].append({"name": line.split(":", 1)[1].strip()})
        elif groups and groups[-1]["items"] and re.match(r"      [a-z_]+:", line):
            k, v = line.strip().split(":", 1)
            groups[-1]["items"][-1][k] = v.strip()
    return groups


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
    data = load_products(root)
    names = [g.find("h2")[0].all_text() if g.find("h2") else "" for g in first_group]
    if names != [g["group"] for g in data]:
        bad.append("groups %r differ from data/products.yaml" % names)
    if not names or FIRST_GROUP_WORD not in names[0]:
        bad.append("first group is not a security group: %r" % names[:1])
    if names and names[-1] != LAST_GROUP:
        bad.append("last group is not %r" % LAST_GROUP)
    for i, (g, dg) in enumerate(zip(first_group, data)):
        det = g.find("details")
        if len(det) != 1:
            bad.append("group %d is not one details element" % i)
            continue
        if ("open" in det[0].attrs) != (i == 0):
            bad.append("only the first group starts open (group %d)" % i)
        count = g.find("span", "product-count")
        want = "%d %s" % (len(dg["items"]), "item" if len(dg["items"]) == 1 else "items")
        if not count or count[0].all_text() != want:
            bad.append("group %d count is not %r" % (i, want))
    items = main.find("li", "product")
    all_data = [it for g in data for it in g["items"]]
    if len(all_data) < MIN_ITEMS:
        bad.append("data/products.yaml has %d items, fewer than %d" % (len(all_data), MIN_ITEMS))
    if len(items) != len(all_data):
        bad.append("page has %d items, data has %d" % (len(items), len(all_data)))
    seen = []
    labels = []
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
        v = it.find("span", "product-vendor")
        labels.append(v[0].all_text() if v else "")
        if v and v[0].all_text() not in VENDORS:
            bad.append("unknown vendor label %r: %s" % (v[0].all_text(), label))
        if not it.find("h3"):
            bad.append("item has no name: " + label)
        if len(it.find("p", "product-line")) != 1 or not it.find("p", "product-line")[0].all_text():
            bad.append("item has no one-line description: " + label)
        note = it.find("p", "product-checked")
        if len(note) != 1 or not re.fullmatch(r"Price checked on \w+ \d{1,2}, \d{4}", note[0].all_text()):
            bad.append("item lacks a 'Price checked on <date>' note: " + label)
        if re.search(r"[$]\s*\d", label):
            bad.append("item shows a price: " + label)
    # Audit: every item of the data file is on the page, in order, with its link and vendor label.
    if [i["name"] for i in all_data] != [i.find("h3")[0].all_text() for i in items if i.find("h3")]:
        bad.append("item names or order differ from data/products.yaml")
    if [i.get("url") for i in all_data] != seen:
        bad.append("item links differ from data/products.yaml")
    if [i.get("vendor", "") for i in all_data] != labels:
        bad.append("vendor labels differ from data/products.yaml")
    for i in all_data:
        if i.get("vendor", "") not in VENDORS | {""}:
            bad.append("data vendor not Amazon or Direct: " + i["name"])
    page_text = main.all_text()
    amazon_in_data = any(i.get("vendor") == "Amazon" for i in all_data)
    if amazon_in_data != (ASSOCIATE in page_text):
        bad.append("Amazon Associate line must show exactly when an item has vendor Amazon")
    for a in main.find("a"):
        if "public.com" in (a.attrs.get("href") or ""):
            bad.append("brokerage referral is listed (maintainer ruling: not on this page)")
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
    for slug in twitch youtube kick mastodon bluesky tiktok instagram threads discord matrix github pixelfed; do
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
    guard "pixelfed href altered" social "$social" 's/<a class="tile social-tile" href="https:\/\/pics\.chiefgyk3d\.com\/ChiefGyk3D" rel="me noopener">/<a class="tile social-tile" href="https:\/\/x.example\/" rel="me noopener">/'
    guard "pixelfed icon dropped" social "$social" 's/social-icon--pixelfed/social-icon--placeholder/'
    guard "vendor label wrong" products "$products" '0,/product-vendor">Amazon</{s/Amazon/Direct/}'
    guard "item dropped" products "$products" '0,/<li class="product">/s//<li class="product-x">/'
    guard "first group closed" products "$products" 's/<details class="accordion" open>/<details class="accordion">/'
    guard "sponsored dropped" products "$products" 's/rel="sponsored noopener"/rel="noopener"/'
    guard "disclosure changed" products "$products" 's/at no extra cost to you/at a cost to you/'
    guard "direct note dropped" products "$products" 's/Some products I link directly/Some products I link/'
    guard "price note removed" products "$products" 's/Price checked on/Seen on/'
    guard "rel=me added to a network the data does not mark" social "$social" 's/rel="noopener"/rel="me noopener"/g'
    guard "plain http link" products "$products" 's#href="https://amzn.to/#href="http://amzn.to/#'
fi

# Mutation check: the rel="me" assertion follows data/socials.yaml. Flip one rel_me value
# in a copy of the repository, rebuild, and the asserter must still pass (the template follows
# the data, so the test must too). Then run the asserter on the ORIGINAL page against the
# changed data: it must fail, proving the data is what the test compares against.
if [[ -f "$social" ]]; then
    mroot="$work/mutroot"
    mkdir -p "$mroot"
    for d in archetypes assets content data layouts static i18n; do
        [[ -e "$root/$d" ]] && cp -R "$root/$d" "$mroot/$d"
    done
    for f in hugo.toml hugo.yaml config.toml .hugo-version; do
        [[ -f "$root/$f" ]] && cp "$root/$f" "$mroot/$f"
    done
    [[ -d "$root/config" ]] && cp -R "$root/config" "$mroot/config"
    # Flip the first rel_me: false (Twitch) to true.
    sed -i '0,/rel_me: false/s//rel_me: true/' "$mroot/data/socials.yaml"
    if cmp -s "$root/data/socials.yaml" "$mroot/data/socials.yaml"; then
        fail "mutation did not change the data (the test is stale)"
    elif (cd "$mroot" && HUGO_MINIFY_MINIFYOUTPUT=false hugo --destination "$work/mutpublic" --quiet >"$work/mutbuild.log" 2>&1); then
        if python3 -I "$asserter" social "$work/mutpublic/social/index.html" "$mroot" >/dev/null 2>&1; then
            pass "mutation: flipped rel_me in the data, rebuilt page, test follows the data"
        else
            fail "mutation: test failed falsely after a rel_me change in the data"
        fi
        if python3 -I "$asserter" social "$social" "$mroot" >/dev/null 2>&1; then
            fail "mutation: stale page accepted against changed data"
        else
            pass "mutation: page not matching the changed data is caught"
        fi
    else
        fail "mutation build failed ($(tail -n 3 "$work/mutbuild.log" | tr '\n' ' '))"
    fi
fi

# --- a network that is not live, and the dead .coming-soon rule ---------------
# data/socials.yaml allows an empty url ("not live"); the template renders that
# entry as a tile that is not a link (div.social-tile--soon), which is why the
# fallback and its CSS stay. The class .coming-soon is rendered by nothing and
# must not come back as a rule.
nolive="$work/nolive"
mkdir -p "$nolive/content" "$nolive/data"
cp -r "$root/layouts" "$root/assets" "$root/static" "$nolive/"
cp "$root/hugo.toml" "$nolive/hugo.toml"
cp -r "$root/content/social" "$nolive/content/"
printf -- '---\ntitle: "Home"\n---\n' >"$nolive/content/_index.md"
printf -- '- name: Live\n  icon: github\n  url: https://example.org/live\n  handle: live\n  rel_me: false\n  blurb: A live one\n- name: Later\n  icon: ""\n  url: ""\n  handle: later\n  rel_me: false\n  blurb: Not live yet\n' >"$nolive/data/socials.yaml"
if (cd "$nolive" && hugo --destination "$nolive/public" >"$nolive/build.log" 2>&1); then
    page="$nolive/public/social/index.html"
    if python3 -I - "$page" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
items = re.findall(r"<li class=\"?tile-item\"?>(.*?)</li>", html, re.S)
assert len(items) == 2, len(items)
assert "<a " in items[0] and "social-tile--soon" not in items[0]
assert "<a " not in items[1] and "social-tile--soon" in items[1] and "Later" in items[1]
assert "social-icon--placeholder" in items[1]
PY
    then
        pass "an entry with an empty url renders as a tile that is not a link"
    else
        fail "an entry with an empty url did not render as a non-link tile"
    fi
    if grep -rq 'social-tile--soon' "$root/assets/css/pages/social.css"; then
        pass "the CSS for the not-live tile is present"
    else
        fail "the not-live tile has no CSS rule"
    fi
else
    fail "the not-live site did not build: $(tail -n 3 "$nolive/build.log")"
fi
dead_class() { # dead_class <dir>...: files that still mention the dead class
    grep -rl 'coming-soon' "$@" 2>/dev/null || true
}
if [[ -z "$(dead_class "$root/assets" "$root/layouts" "$root/content")" ]]; then
    pass "no .coming-soon class in the CSS, layouts or content"
else
    fail ".coming-soon is back: $(dead_class "$root/assets" "$root/layouts" "$root/content")"
fi
mkdir -p "$work/deadguard"
printf '.coming-soon {\n  color: red;\n}\n' >"$work/deadguard/x.css"
if [[ -n "$(dead_class "$work/deadguard")" ]]; then
    pass "guard: a .coming-soon rule is reported"
else
    fail "guard: a .coming-soon rule was not reported"
fi

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all social and products checks passed"
