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
#   footer:   the icon row (issue 169) on every page with a footer: one icon link
#             per live data/socials.yaml entry, an accessible name and https
#             url each, none for an empty url, between the sign-off line and the
#             credit, the balanced-row class matching the count;
#   products: the disclosure copy once, after the last group, the
#             groups in the order of data/products.yaml (security first, creator
#             and social media tools last, the first one open, a count in each
#             summary), and every item of the data file on the page with a name,
#             a line, no price or date note, an https link with
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
    "I may earn a commission at no extra cost to you. The label on each card says "
    "whether the link goes to Amazon or straight to the company."
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
        self.parts = []  # text and child nodes in document order

    def classes(self):
        return (self.attrs.get("class") or "").split()

    def walk(self):
        yield self
        for k in self.kids:
            yield from k.walk()

    def all_text(self):
        out = ""
        for part in self.parts:
            out += " " + (part if isinstance(part, str) else part.all_text()) + " "
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
        self.cur.parts.append(n)
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
        self.cur.parts.append(data)


def ancestors(n):
    n = n.parent
    while n is not None:
        yield n
        n = n.parent


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
    if "Livestreams are on Twitch and Kick, and videos are on YouTube and TikTok." not in main.all_text():
        bad.append("intro sentence missing")
    if "bridged" not in main.all_text():
        bad.append("Discord and Matrix bridge statement missing")
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
            # A fediverse handle has its inner @ in its own span (Cloudflare Email
            # Obfuscation), and all_text() puts a space around child spans, so
            # drop only whitespace and keep the @ in the comparison.
            squash = (lambda t: "".join(t.split())) if field == "handle" else (lambda t: t)
            if e.get(field, "") and squash(e[field]) not in squash(text):
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


def load_socials(root):
    """data/socials.yaml read without a YAML library: one '- name:' per entry, simple scalar keys."""
    entries = []
    for line in pathlib.Path(root, "data/socials.yaml").read_text().splitlines():
        if line.startswith("- name:"):
            entries.append({"name": line.split(":", 1)[1].strip()})
        elif entries and re.match(r"  [a-z_]+:", line):
            k, v = line.strip().split(":", 1)
            entries[-1][k] = v.strip().strip('"')
    return entries


def check_footer(page, root, bad):
    """The footer social icon row (issue 169): on every page, one link per live entry of the data file."""
    doc = load(page)
    feet = doc.find("footer")
    if len(feet) != 1:
        bad.append("page has %d footers" % len(feet))
        return 0
    foot = feet[0]
    navs = [n for n in foot.find("nav") if n.attrs.get("aria-label") == "Social profiles"]
    live = [e for e in load_socials(root) if (e.get("url") or "").startswith("https://")]
    if len(navs) != 1:
        bad.append("footer has %d 'Social profiles' navs" % len(navs))
        return 0
    nav = navs[0]
    # Order: the sign-off line, then the icon row, then the credit.
    order = list(foot.walk())
    line = foot.find("p", "footer-line")
    credit = foot.find("p", "credit")
    if not line or not credit or not (order.index(line[0]) < order.index(nav) < order.index(credit[0])):
        bad.append("icon row is not between the sign-off line and the credit")
    # Desktop (issue 123): from 80rem the icons are ONE line, left aligned like the rest of the
    # footer; below that the centered balanced rows stay (the per-N cap).
    css = " ".join(pathlib.Path(root, "assets/css/main.css").read_text(encoding="utf-8").split())
    m = re.search(r"@media \(min-width: 80rem\) \{ \.footer-meta \{.*?\.footer-meta \.credit \{[^}]*\} \}", css)
    blk = m.group(0) if m else ""
    for need in (".footer-meta { justify-content: flex-start;", ".footer-social { flex: 0 0 auto; justify-content: flex-start; }",
                 ".footer-social-list { flex-wrap: nowrap; justify-content: flex-start; max-width: none; }"):
        if need not in blk:
            bad.append("main.css lacks the left-aligned one-line desktop footer rule: %s" % need)
    if "justify-content: center;" not in css.split(".footer-social-list {", 1)[-1][:200]:
        bad.append("main.css lost the centered balanced icon rows for phones")
    links = nav.find("a")
    if len(links) != len(live):
        bad.append("footer has %d icon links, data has %d live entries" % (len(links), len(live)))
    for e in (e for e in load_socials(root) if e not in live):
        if any(a.attrs.get("aria-label") == e["name"] for a in links):
            bad.append("%s has no https url in the data but renders in the footer" % e["name"])
    for a, e in zip(links, live):
        name = e["name"]
        href = a.attrs.get("href") or ""
        if not href.startswith("https://"):
            bad.append("%s footer link is not https" % name)
        if href != e["url"]:
            bad.append("%s footer href differs from data" % name)
        if (a.attrs.get("aria-label") or "").strip() != name:
            bad.append("%s footer link lacks its accessible name" % name)
        if a.all_text().strip():
            bad.append("%s footer link shows text (icons only)" % name)
        rel = (a.attrs.get("rel") or "").split()
        if "noopener" not in rel or (e.get("rel_me") == "true") != ("me" in rel):
            bad.append("%s footer rel wrong (%r)" % (name, rel))
        icon = a.find("span", "social-icon")
        if not icon or "social-icon--" + e["icon"] not in icon[0].classes() or icon[0].attrs.get("aria-hidden") != "true":
            bad.append("%s footer icon class or aria-hidden wrong" % name)
    # Balanced rows: the list carries the per-row cap, half the live count rounded up.
    ul = nav.find("ul")
    want = "footer-social-list--per-%d" % ((len(live) + 1) // 2)
    if not ul or want not in ul[0].classes():
        bad.append("icon list lacks the balanced-row class %s" % want)
    return len(links)


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
    # The disclosure is one note after the last group (owner ruling 2026-11-08, issue 123): it
    # appears exactly once on the page, after every group, and not before the first item.
    first_group = main.find("section", "product-group")
    notes = main.find(cls="disclosure")
    if len(notes) != 1:
        bad.append("disclosure must appear exactly once, found %d" % len(notes))
        return 0
    disc = notes[0]
    paras = [p.all_text() for p in disc.find("p")]
    if DISCLOSURE not in paras:
        bad.append("disclosure copy missing or changed")
    if main.all_text().count("Some links on this page are affiliate links") != 1:
        bad.append("disclosure text must be on the page exactly once")
    # Structure, not document order: the START of the last section precedes everything inside it,
    # so compare siblings. The note must not sit inside any group, and must follow the last
    # section as a later sibling under the same parent.
    if any(a.tag == "section" and "product-group" in a.classes() for a in ancestors(disc)):
        bad.append("disclosure is inside a group")
    if first_group:
        last = first_group[-1]
        sibs = disc.parent.kids if disc.parent else []
        if disc.parent is not last.parent or disc not in sibs or last not in sibs or sibs.index(disc) < sibs.index(last):
            bad.append("disclosure is not a sibling after the last group")
    if disc.find("a"):
        bad.append("disclosure holds a link")
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
        if it.find("p", "product-checked") or "checked on" in it.all_text().lower():
            bad.append("item shows a checked-on date, but no price is shown: " + label)
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


def rows(n, per):
    """Chip counts per row for n chips, per to a row."""
    out = []
    while n > 0:
        out.append(min(per, n))
        n -= per
    return out


def balanced(n):
    """Desktop rows for n chips (per = half rounded up): no orphan, rows within one chip of each other."""
    r = rows(n, (n + 1) // 2)
    return len(r) <= 2 and max(r) - min(r) <= 1 and (n < 4 or min(r) >= 2)


def check_home(page, root, bad):
    """Home: the Find me online chips (issue 123): the data's live networks in the data's order, in
    equal-width balanced rows (the per-row class, and the CSS that makes the columns equal)."""
    doc = load(page)
    lists = doc.find("ul", "home-social")
    live = [e for e in load_socials(root) if (e.get("url") or "").startswith("https://")]
    if len(lists) != 1:
        bad.append("home has %d chip lists" % len(lists))
        return 0
    ul = lists[0]
    chips = ul.find("a")
    names = [a.all_text() for a in chips]
    if names != [e["name"] for e in live]:
        bad.append("chips %r differ from the live networks of data/socials.yaml in order" % names)
    want = "home-social--per-%d" % ((len(live) + 1) // 2)
    if want not in ul.classes():
        bad.append("chip list lacks %s (balanced rows)" % want)
    for n in range(2, 13):
        if not balanced(n):
            bad.append("%d chips do not make balanced rows: %r" % (n, rows(n, (n + 1) // 2)))
    css = " ".join(pathlib.Path(root, "assets/css/pages/home.css").read_text(encoding="utf-8").split())
    for need, why in (
        (".home-social { --per: 2; display: flex; flex-wrap: wrap; justify-content: center;", "centered wrapping rows"),
        (".home-social li { flex: 0 0 calc((100% - (var(--per) - 1) * var(--space-2)) / var(--per));", "equal-width columns"),
        ("white-space: nowrap;", "no wrapped chip text"),
        ("min-height: var(--tap);", "44 px chips"),
        ("--per: var(--per-desk, 6);", "desktop per-row count from the class"),
    ):
        if need not in css:
            bad.append("home.css lacks %s (%s)" % (need, why))
    return len(chips)


def check_homeposts(page, root, bad):
    """Home Latest posts (issue 180): at most two entries, each a link, a date and a summary, then All posts.
    The count is min(2, posts on the build); the third argument is the number of posts the build holds."""
    doc = load(page)
    panels = doc.find("section", "home-latest")
    if len(panels) != 1:
        bad.append("home has %d Latest posts panels" % len(panels))
        return 0
    items = panels[0].find("li")
    posts = int(pathlib.Path(root, "posts.count").read_text().strip())
    if len(items) > 2:
        bad.append("Latest posts lists %d entries, at most 2 allowed" % len(items))
    if len(items) != min(2, posts):
        bad.append("Latest posts lists %d entries for %d posts, expected %d" % (len(items), posts, min(2, posts)))
    if not panels[0].find("p", "more-link"):
        bad.append("the All posts link is missing")
    return len(items)


def main(argv):
    kind, page, root = argv[1:4]
    bad = []
    n = {"social": check_social, "products": check_products, "footer": check_footer, "home": check_home, "homeposts": check_homeposts}[kind](page, root, bad)
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

# The footer icon row is on every full page (a page with a <footer>; alias
# stubs have none), and the home and 404 pages are among them.
footer_pages=0
while IFS= read -r -d '' page; do
    grep -q '<footer' "$page" || continue
    footer_pages=$((footer_pages + 1))
    if ! out="$(run_assert footer "$page")"; then
        fail "footer icons on ${page#"$public"}: $(tr '\n' ';' <<<"$out")"
    fi
done < <(find "$public" -name '*.html' -print0)
if ((footer_pages < 10)); then
    fail "footer icon row checked on only $footer_pages pages (expected at least 10)"
else
    pass "footer icon row checked on $footer_pages pages"
fi
for must in index.html 404.html social/index.html; do
    grep -q 'Social profiles' "$public/$must" || fail "footer icon row missing on /$must"
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

# Guard self-test of the footer asserter: a data file with one empty url must
# fail against the real page (the page still renders that entry), and so must
# pages with the row broken in each way.
if [[ -f "$public/index.html" ]]; then
    fguard() { # label sed-expression
        local label="$1" expr="$2" copy="$work/fguard.html"
        sed -E "$expr" "$public/index.html" >"$copy"
        if cmp -s "$public/index.html" "$copy"; then
            fail "footer guard '$label' did not change the page (the test is stale)"
        elif run_assert footer "$copy" >/dev/null; then
            fail "footer guard '$label': asserter accepted a broken page"
        else
            pass "footer guard '$label' fails as it should"
        fi
    }
    fguard "accessible name dropped" 's/aria-label="?Twitch"?//'
    fguard "link not https" 's#href="?https://twitch.tv/chiefgyk3d"?#href=http://twitch.tv/chiefgyk3d#'
    fguard "row removed" 's/aria-label="?Social profiles"?/aria-label=Other/'
    fguard "one icon removed" '/<li><a class="?footer-social-link"? href="?https:\/\/kick\.com/d'
    fguard "balanced-row class wrong" 's/footer-social-list--per-6/footer-social-list--per-11/'
    fguard "rel=me dropped" 's/rel="me noopener"/rel=noopener/g'
    # The CSS guard: a desktop footer with the icons centered again must fail.
    mkdir -p "$work/footroot/assets/css" "$work/footroot/data"
    cp "$root/data/socials.yaml" "$work/footroot/data/"
    sed -E '/^  \.footer-social \{/,/^  \}/s/justify-content: flex-start;/justify-content: center;/' "$root/assets/css/main.css" >"$work/footroot/assets/css/main.css"
    if cmp -s "$root/assets/css/main.css" "$work/footroot/assets/css/main.css"; then
        fail "footer css guard did not change the stylesheet (the test is stale)"
    elif python3 -I "$asserter" footer "$public/index.html" "$work/footroot" >/dev/null 2>&1; then
        fail "footer css guard: asserter accepted centered icons on desktop"
    else
        pass "footer css guard fails as it should"
    fi
    mkdir -p "$work/emptyroot/data"
    sed -E '/url: https:\/\/kick.com/s#url: .*#url: ""#' "$root/data/socials.yaml" >"$work/emptyroot/data/socials.yaml"
    if cmp -s "$root/data/socials.yaml" "$work/emptyroot/data/socials.yaml"; then
        fail "empty-url guard did not change the data (the test is stale)"
    elif python3 -I "$asserter" footer "$public/index.html" "$work/emptyroot" >/dev/null 2>&1; then
        fail "empty-url guard: asserter accepted an empty-url platform rendered in the footer"
    else
        pass "empty-url guard fails as it should"
    fi
fi

# The Home chips (issue 123): equal-width balanced rows, in data order.
if [[ -f "$public/index.html" ]]; then
    if out="$(run_assert home "$public/index.html")"; then
        pass "home chips: $(tr '\n' ' ' <<<"$out")"
    else
        fail "home chips: $(tr '\n' ';' <<<"$out")"
    fi
    hguard() { # label sed-expression
        local label="$1" expr="$2" copy="$work/hguard.html"
        sed -E "$expr" "$public/index.html" >"$copy"
        if cmp -s "$public/index.html" "$copy"; then
            fail "home guard '$label' did not change the page (the test is stale)"
        elif run_assert home "$copy" >/dev/null; then
            fail "home guard '$label': asserter accepted a broken page"
        else
            pass "home guard '$label' fails as it should"
        fi
    }
    hguard "per-row class wrong (orphan row)" 's/home-social--per-6/home-social--per-11/'
    hguard "a chip removed" '/<li><a class="?icon-kick"?/d'
    hguard "chip list class dropped" 's/class="?home-social home-social--per-6"?/class=home-social/'
    # The CSS guard: a stylesheet without the equal-width rule must fail.
    mkdir -p "$work/cssroot/assets/css/pages" "$work/cssroot/data"
    cp "$root/data/socials.yaml" "$work/cssroot/data/"
    sed -E 's/flex: 0 0 calc\(\(100% - \(var\(--per\) - 1\) \* var\(--space-2\)\) \/ var\(--per\)\);/flex: 0 0 auto;/' "$root/assets/css/pages/home.css" >"$work/cssroot/assets/css/pages/home.css"
    if cmp -s "$root/assets/css/pages/home.css" "$work/cssroot/assets/css/pages/home.css"; then
        fail "home css guard did not change the stylesheet (the test is stale)"
    elif python3 -I "$asserter" home "$public/index.html" "$work/cssroot" >/dev/null 2>&1; then
        fail "home css guard: asserter accepted a stylesheet without equal-width columns"
    else
        pass "home css guard fails as it should"
    fi
fi

# Home Latest posts (issue 180): the real build (one post) and a scratch site with ten posts. The
# panel never exceeds two entries, so Home stays one screen however many posts are published.
many="$work/many"
mkdir -p "$many/content/posts" "$many/content/search" "$many/content/social" "$many/content/support" "$many/content/about" "$many/content/products" "$many/content/privacy" "$many/content/resume" "$many/content/journal"
for d in layouts assets data static archetypes; do [[ -e "$root/$d" ]] && ln -s "$root/$d" "$many/$d"; done
ln -s "$root/hugo.toml" "$many/hugo.toml"
for f in content/_index.md content/posts/_index.md content/search/_index.md content/social/_index.md content/support/index.md content/about/index.md content/products/_index.md content/privacy/index.md content/resume/index.md content/journal/_index.md; do cp "$root/$f" "$many/$f"; done
for i in 01 02 03 04 05 06 07 08 09 10; do
    mkdir -p "$many/content/posts/post-$i"
    printf -- '---\ntitle: "Synthetic post %s"\ndate: 2026-10-%sT09:00:00-05:00\ndraft: false\ndescription: "Synthetic summary %s."\n---\n\nBody %s.\n' "$i" "$i" "$i" "$i" >"$many/content/posts/post-$i/index.md"
done
if (cd "$many" && HUGO_MINIFY_MINIFYOUTPUT=false hugo --destination "$many/public" --quiet >"$work/many-build.log" 2>&1); then
    echo 10 >"$many/posts.count"
    if out="$(python3 -I "$asserter" homeposts "$many/public/index.html" "$many" 2>&1)"; then
        pass "home Latest posts with ten posts: $(tr '\n' ' ' <<<"$out")"
    else
        fail "home Latest posts with ten posts: $(tr '\n' ';' <<<"$out")"
    fi
    # Negative: a third entry on the page must be refused.
    python3 -I - "$many/public/index.html" "$work/three.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<li>.*?</li>", s[s.index("home-latest"):], re.S)
k = s.index("home-latest") + m.end()
open(sys.argv[2], "w", encoding="utf-8").write(s[:k] + m.group(0) + s[k:])
PY
    if python3 -I "$asserter" homeposts "$work/three.html" "$many" >/dev/null 2>&1; then
        fail "home posts guard: asserter accepted three entries"
    else
        pass "home posts guard fails as it should (three entries)"
    fi
else
    fail "scratch site with ten posts does not build: $(tail -n 3 "$work/many-build.log" | tr '\n' ' ')"
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
    guard "disclosure moved to the top" products "$products" 's#<div class="disclosure" role="note">#<div class="disclosure" role="note"><p>Some links on this page are affiliate links. If you buy something through one, I may earn a commission at no extra cost to you. Some products I link directly to the company instead of a store.</p></div><div class="disclosure" role="note">#'
    guard "disclosure changed" products "$products" 's/at no extra cost to you/at a cost to you/'
    guard "vendor-label note dropped" products "$products" 's/says whether the link goes to Amazon or straight to the company/says where the link goes/'
    guard "price note restored" products "$products" '0,/<p class="product-line">/s//<p class="product-checked meta">Price checked on May 1, 2026<\/p><p class="product-line">/'
    guard "rel=me added to a network the data does not mark" social "$social" 's/rel="noopener"/rel="me noopener"/g'
    guard "fediverse handle loses its @" social "$social" 's#<span>@</span>(social\.chiefgyk3d\.com)#<span></span>\1#'
    guard "plain http link" products "$products" 's#href="https://amzn.to/#href="http://amzn.to/#'
    # The disclosure inside the last section (before its details) is not "after the last group".
    inside="$work/guard-inside.html"
    python3 -I - "$products" "$inside" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<div class="?disclosure"?[^>]*>.*?</div>', s, re.S)
s = s[:m.start()] + s[m.end():]
k = s.rindex("<details")
open(sys.argv[2], "w", encoding="utf-8").write(s[:k] + m.group(0) + s[k:])
PY
    if cmp -s "$products" "$inside"; then
        fail "guard 'disclosure inside the last section' did not change the page (the test is stale)"
    elif run_assert products "$inside" >/dev/null; then
        fail "guard 'disclosure inside the last section': asserter accepted a broken page"
    else
        pass "guard 'disclosure inside the last section' fails as it should"
    fi
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
