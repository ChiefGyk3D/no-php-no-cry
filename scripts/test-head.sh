#!/usr/bin/env bash
# Test the <head> metadata and footer identity links against hostile input.
#
# Builds a throwaway site (this repository's layouts, assets and static files,
# plus pages written here) under the repository's gitignored tmp/, never /tmp,
# and asserts with Python's stdlib HTML parser that front matter with quotes,
# angle brackets, ampersands and newlines (unminified, so a newline in an
# attribute would survive) cannot add, split or break a tag, and
# that a javascript: identity link is not emitted. Needs the pinned Hugo; a
# missing Hugo is a failure, not a skip. A guard self-test feeds the asserter a
# page with an injected tag and requires it to fail.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/head.XXXXXX")"
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

# The asserter. Usage: assert_head.py <page.html> <description> <title> [href|href...]
# Prints one line per violation and exits 1 when there is any.
asserter="$work/assert_head.py"
cat >"$asserter" <<'PY'
import sys
from html.parser import HTMLParser

EXPECTED = {
    ("name", "description"), ("name", "twitter:card"),
    ("name", "twitter:image"), ("name", "theme-color"),
    ("property", "og:site_name"), ("property", "og:title"),
    ("property", "og:description"), ("property", "og:type"),
    ("property", "og:url"), ("property", "og:image"),
    ("property", "article:published_time"), ("property", "article:modified_time"),
    ("property", "og:image:width"), ("property", "og:image:height"),
}


class Head(HTMLParser):
    def __init__(self):
        super().__init__()
        self.metas = []
        self.scripts = 0
        self.title = ""
        self.in_title = False
        self.me = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta":
            self.metas.append(a)
        elif tag == "script":
            # A JSON-LD data block is not executable and not a script for the
            # CSP; every other script element is a failure.
            if (a.get("type") or "").lower() != "application/ld+json":
                self.scripts += 1
        elif tag == "title":
            self.in_title = True
        elif tag in ("a", "link") and "me" in (a.get("rel") or "").split():
            self.me.append(a)

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title += data


def main(path, want_desc, want_title, want_me):
    p = Head()
    p.feed(open(path, encoding="utf-8").read())
    bad = []
    seen = {}
    for m in p.metas:
        for key in ("name", "property"):
            if key in m:
                seen.setdefault((key, m[key]), []).append(m.get("content", ""))
                if (key, m[key]) not in EXPECTED and m[key] not in ("viewport", "robots"):
                    bad.append("unexpected meta %s=%s" % (key, m[key]))
    for k, v in seen.items():
        if len(v) != 1:
            bad.append("%s=%s appears %d times" % (k[0], k[1], len(v)))
    d1 = (seen.get(("name", "description")) or [None])[0]
    d2 = (seen.get(("property", "og:description")) or [None])[0]
    if d1 != want_desc or d2 != want_desc:
        bad.append("description is %r / %r, want %r" % (d1, d2, want_desc))
    t = (seen.get(("property", "og:title")) or [None])[0]
    page_title = p.title.strip()
    if t != want_title or page_title not in (want_title, want_title + " | ChiefGyk3D"):
        bad.append("title is %r / %r, want %r" % (t, p.title, want_title))
    if p.scripts:
        bad.append("script element present")
    for a in p.me:
        if (a.get("href") or "").lower().startswith("javascript:"):
            bad.append("javascript: rel=me link emitted")
    if want_me is not None and [a.get("href") for a in p.me] != want_me:
        bad.append("rel=me hrefs are %r, want %r" % ([a.get("href") for a in p.me], want_me))
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    me = sys.argv[4].split("|") if len(sys.argv) > 4 and sys.argv[4] else None
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3], me))
PY

site_desc="$(sed -n 's/^  description = "\(.*\)"$/\1/p' "$root/hugo.toml")"
[[ -n "$site_desc" ]] || {
    echo "FAIL: hugo.toml has no params.description"
    exit 1
}

run_asserter() { python3 -I "$asserter" "$@"; }

# --- the throwaway site ---------------------------------------------------
site="$work/site"
mkdir -p "$site/content/posts/hostile" "$site/content/posts/plain"
cp -r "$root/layouts" "$root/assets" "$root/static" "$site/"
# data/socials.yaml exists in the real site, so the test has one too: the
# data-driven row and params.me must both render.
mkdir -p "$site/data"
cat >"$site/data/socials.yaml" <<'YAML'
- name: Data one
  icon: dataone
  url: https://data.example/@one
  rel_me: true
YAML
# The repository config with output minification off, so attribute values and
# newlines reach the parser as the templates wrote them.
sed 's/^  minifyOutput = true/  minifyOutput = false/' "$root/hugo.toml" >"$site/hugo.toml"
grep -q 'minifyOutput = false' "$site/hugo.toml" || {
    echo "FAIL: could not turn minification off in the test config"
    exit 1
}
cat >>"$site/hugo.toml" <<'TOML'

[[params.me]]
  name = "Fedi <b>one</b> & \"two\""
  url = "https://social.example/@name"

[[params.me]]
  name = "Bad scheme"
  url = "javascript:alert(1)"
TOML
printf -- '---\ntitle: "Home"\n---\n' >"$site/content/_index.md"
printf -- '---\ntitle: "Posts"\n---\n' >"$site/content/posts/_index.md"
cat >"$site/content/posts/hostile/index.md" <<'MD'
---
title: 'Say "hi" <i>& bye'
date: 2024-01-02T03:04:05-05:00
description: |
  She said "hi" & left. <script>alert(1)</script>
  Next line "><meta name="robots" content="noindex"> end.
---

Body.
MD
cat >"$site/content/posts/plain/index.md" <<'MD'
---
title: "Plain"
date: 2024-01-03T03:04:05-05:00
---

Body.
MD
(cd "$site" && hugo --quiet --destination "$site/public") || {
    echo "FAIL: hugo could not build the test site"
    exit 1
}

hostile_page="$site/public/posts/hostile/index.html"
plain_page="$site/public/posts/plain/index.html"

# plainify drops the script and meta tags from the description (their text stays
# or goes; the point is that nothing in it becomes a tag); the title is escaped
# text, so its angle brackets come back as the same characters after parsing.
want_desc='She said "hi" & left. Next line "> end.'
want_title='Say "hi" <i>& bye'

if out="$(run_asserter "$hostile_page" "$want_desc" "$want_title" 2>&1)"; then
    pass "hostile front matter stays inside its attributes and tags"
else
    fail "hostile front matter: $out"
fi

if out="$(run_asserter "$plain_page" "Body." "Plain" 2>&1)"; then
    pass "no description in front matter falls back to the page summary"
else
    fail "plain page: $out"
fi

if out="$(run_asserter "$site/public/index.html" "$site_desc" "ChiefGyk3D" "https://data.example/@one|https://social.example/@name" 2>&1)"; then
    pass "rel=me renders: head links from data/socials.yaml, then params.me; the javascript: link is not emitted"
else
    fail "home page: $out"
fi

# Guard: the rel=me check bites. A page without the head link must fail.
sed 's|<link rel="me"[^>]*>||g' "$site/public/index.html" >"$work/home-nome.html"
if run_asserter "$work/home-nome.html" "$site_desc" "ChiefGyk3D" "https://data.example/@one|https://social.example/@name" >/dev/null 2>&1; then
    fail "guard: a home page without the head rel=me links passed"
else
    pass "guard: a home page without the head rel=me links fails"
fi

if grep -q 'rel="me"' "$site/public/index.html" && ! grep -qi 'javascript:' "$site/public/index.html"; then
    pass "javascript: appears nowhere in the home page"
else
    fail "javascript: appears in the home page or rel=me is missing"
fi

if grep -q 'property="article:published_time" content="2024-01-02T03:04:05-05:00"' "$hostile_page"; then
    pass "article:published_time comes from the front matter date"
else
    fail "article:published_time is missing or wrong"
fi

# Journal is in the Main nav only once /journal has a published page.
if grep -q 'href="/journal/"' "$site/public/index.html"; then
    fail "Journal is in the nav with no journal entry"
else
    pass "Journal is hidden from the nav while /journal is empty"
fi
mkdir -p "$site/content/journal/entry"
printf -- '---\ntitle: "Journal"\n---\n' >"$site/content/journal/_index.md"
printf -- '---\ntitle: "Entry"\ndate: 2024-01-04T03:04:05-05:00\n---\n\nBody.\n' >"$site/content/journal/entry/index.md"
(cd "$site" && hugo --quiet --destination "$site/public2") || {
    echo "FAIL: hugo could not build the test site with a journal entry"
    exit 1
}
if grep -q '<a href="/journal/">Journal</a>' "$site/public2/index.html"; then
    pass "Journal shows in the nav once an entry is published"
else
    fail "Journal is missing from the nav with a published entry"
fi

# Print: chrome hidden, system colors only, inside @media print.
css="$(cat "$site/public/css/"site*.css 2>/dev/null || true)"
if printf '%s' "$css" | grep -q '@media print'; then
    pass "stylesheet has @media print rules"
else
    fail "stylesheet has no @media print rules"
fi
# Reusable HUD surfaces use the carbon tokens.
if printf '%s' "$css" | grep -q '\.carbon{' && printf '%s' "$css" | grep -q '\.glow{'; then
    pass "stylesheet defines .carbon and .glow"
else
    fail "stylesheet is missing .carbon or .glow"
fi

# Production leaves robots to robots.txt; the default environment adds no meta.
if grep -qi 'name=robots\|name="robots"' "$hostile_page"; then
    fail "production build has a robots meta tag"
else
    pass "production build has no robots meta tag"
fi

# --- SEO: canonical, cards, JSON-LD, sitemap, feed, robots, 404 -------------
# A second throwaway site on the repository's real config and real data
# (data/socials.yaml), with synthetic content, so sameAs is judged against the
# data file itself.
seo_py="$work/assert_seo.py"
cat >"$seo_py" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

FORBIDDEN = {"givenName", "familyName", "additionalName", "worksFor", "jobTitle",
             "affiliation", "email", "telephone", "address", "birthDate"}


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.metas, self.links, self.blocks, self.other_scripts = [], [], [], 0
        self._ld = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta":
            self.metas.append(a)
        elif tag == "link":
            self.links.append(a)
        elif tag == "script":
            if (a.get("type") or "").lower() == "application/ld+json" and "src" not in a:
                self._ld = []
            else:
                self.other_scripts += 1

    def handle_data(self, data):
        if self._ld is not None:
            self._ld.append(data)

    def handle_endtag(self, tag):
        if tag == "script" and self._ld is not None:
            self.blocks.append("".join(self._ld))
            self._ld = None


def load(path):
    p = Page()
    p.feed(open(path, encoding="utf-8").read())
    return p


def meta(p, key, name):
    v = [m.get("content") for m in p.metas if m.get(key) == name]
    return v


def nodes(p, bad):
    out = []
    for raw in p.blocks:
        if "</" in raw or "<!--" in raw:
            bad.append("json-ld block holds markup-like text")
        try:
            d = json.loads(raw)
        except ValueError:
            bad.append("json-ld block is not valid JSON")
            continue
        if d.get("@context") != "https://schema.org":
            bad.append("json-ld @context is not https://schema.org")
        out.extend(d.get("@graph", [d]) if isinstance(d, dict) else [])

    def walk(x):
        if isinstance(x, dict):
            for k, v in x.items():
                if k in FORBIDDEN:
                    bad.append("json-ld carries forbidden key %s" % k)
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(out)
    return out


def cmd_page(path, permalink, og_image, kind, sameas_file):
    p = load(path)
    bad = []
    canon = [l.get("href") for l in p.links if l.get("rel") == "canonical"]
    if canon != [permalink]:
        bad.append("canonical is %r, want [%r]" % (canon, permalink))
    if meta(p, "property", "og:url") != [permalink]:
        bad.append("og:url is not the permalink")
    if meta(p, "property", "og:image") != [og_image] or meta(p, "name", "twitter:image") != [og_image]:
        bad.append("og:image / twitter:image are not %s" % og_image)
    if meta(p, "name", "twitter:card") != ["summary_large_image"]:
        bad.append("twitter:card is not summary_large_image")
    robots = meta(p, "name", "robots")
    if kind == "404":
        if len(robots) != 1 or "noindex" not in robots[0]:
            bad.append("404 must carry exactly one noindex robots meta, has %r" % robots)
    elif robots:
        bad.append("indexable page carries a robots meta %r" % robots)
    if p.other_scripts:
        bad.append("script element other than a JSON-LD block")
    ns = nodes(p, bad)
    types = [n.get("@type") for n in ns]
    sameas = [l.strip() for l in open(sameas_file) if l.strip()]
    persons = [n for n in ns if n.get("@type") == "Person"]
    arts = [n for n in ns if n.get("@type") == "Article"]
    if kind == "home":
        if len(persons) != 1:
            bad.append("home needs exactly one Person, has %d" % len(persons))
        else:
            if persons[0].get("name") != "ChiefGyk3D":
                bad.append("Person name is %r" % persons[0].get("name"))
            if persons[0].get("sameAs") != sameas:
                bad.append("Person sameAs does not equal the https urls in data/socials.yaml")
        if arts:
            bad.append("home carries an Article")
    elif kind == "article":
        if len(arts) != 1:
            bad.append("post needs exactly one Article, has %d" % len(arts))
        else:
            a = arts[0]
            pub = meta(p, "property", "article:published_time")
            if a.get("datePublished") not in pub:
                bad.append("Article datePublished does not match article:published_time")
            if not a.get("headline"):
                bad.append("Article has no headline")
            if (a.get("author") or {}).get("name") != "ChiefGyk3D":
                bad.append("Article author name is not ChiefGyk3D")
            if not a.get("image", "").startswith("https://"):
                bad.append("Article image is not absolute")
    else:
        if arts:
            bad.append("%s page carries an Article" % kind)
    for n in persons:
        if n.get("name") != "ChiefGyk3D":
            bad.append("a Person is named %r" % n.get("name"))
    for b in bad:
        print(b)
    return 1 if bad else 0


def cmd_descs(paths):
    seen, bad = {}, []
    for path in paths:
        d = meta(load(path), "name", "description")
        if len(d) != 1 or not d[0].strip():
            bad.append("%s: description missing or repeated" % path)
            continue
        seen.setdefault(d[0], []).append(path)
    for d, ps in seen.items():
        if len(ps) > 1:
            bad.append("same description on %s" % ", ".join(ps))
    for b in bad:
        print(b)
    return 1 if bad else 0


def cmd_sitemap(path, host, must, must_not):
    ns = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
    bad, locs = [], []
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        print("sitemap does not parse")
        return 1
    for u in root.iter(ns + "url"):
        loc = (u.findtext(ns + "loc") or "").strip()
        lm = (u.findtext(ns + "lastmod") or "").strip()
        locs.append(loc)
        if not loc.startswith("https://%s/" % host):
            bad.append("url not on the site host: %s" % loc)
        if not lm or "T" not in lm:
            bad.append("no lastmod timestamp on %s" % loc)
    if not locs:
        bad.append("sitemap lists no urls")
    for m in must:
        if "https://%s%s" % (host, m) not in locs:
            bad.append("sitemap lacks %s" % m)
    for m in must_not:
        if "https://%s%s" % (host, m) in locs:
            bad.append("sitemap lists %s" % m)
    for b in bad:
        print(b)
    return 1 if bad else 0


def cmd_rss(path, host, needle, absent):
    bad = []
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        print("feed does not parse")
        return 1
    atom = "{http://www.w3.org/2005/Atom}"
    selfs = [l for l in root.iter(atom + "link") if l.get("rel") == "self"]
    if len(selfs) != 1 or not (selfs[0].get("href") or "").startswith("https://%s/" % host):
        bad.append("feed needs one atom:link rel=self on the site host")
    items = list(root.iter("item"))
    if not items:
        bad.append("feed has no items")
    texts = [(i.findtext("description") or "") for i in items]
    if not any(needle in t for t in texts):
        bad.append("no item description carries the full body (%s)" % needle)
    if any(absent in t for t in texts):
        bad.append("an item description carries %s" % absent)
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    c, a = sys.argv[1], sys.argv[2:]
    if c == "page":
        sys.exit(cmd_page(*a))
    if c == "descs":
        sys.exit(cmd_descs(a))
    if c == "sitemap":
        i = a.index("--")
        sys.exit(cmd_sitemap(a[0], a[1], a[2:i], a[i + 1:]))
    if c == "rss":
        sys.exit(cmd_rss(*a))
    sys.exit(2)
PY
run_seo() { python3 -I "$seo_py" "$@"; }

site2="$work/site2"
mkdir -p "$site2/content/posts/a" "$site2/content/posts/b" "$site2/content/about" "$site2/content/social"
cp -r "$root/layouts" "$root/assets" "$root/static" "$root/data" "$site2/"
sed 's/^  minifyOutput = true/  minifyOutput = false/' "$root/hugo.toml" >"$site2/hugo.toml"
host="$(sed -n 's#^baseURL = "https://\([^/"]*\)/".*#\1#p' "$root/hugo.toml")"
[[ -n "$host" ]] || {
    echo "FAIL: hugo.toml baseURL is not an https URL"
    exit 1
}
printf -- '---\ntitle: "Home"\n---\n' >"$site2/content/_index.md"
printf -- '---\ntitle: "Posts"\n---\n' >"$site2/content/posts/_index.md"
printf -- '---\ntitle: "About"\ndescription: "About page description."\ndate: 2026-01-02\n---\n\nAbout body.\n' >"$site2/content/about/index.md"
printf -- '---\ntitle: "Undated"\ndescription: "A page with no date."\n---\n' >"$site2/content/social/_index.md"
cat >"$site2/content/posts/a/index.md" <<'MD'
---
title: "Post A"
date: 2024-05-06T07:08:09-04:00
tags: ["alpha"]
aliases:
  - /old-post-a/
---

First paragraph is the summary.

<!--more-->

FULLBODYMARKER second part of the post.
MD
cat >"$site2/content/posts/b/index.md" <<'MD'
---
title: "Post B"
date: 2024-06-06T07:08:09-04:00
description: "Post B has its own description."
image: "/brand/penguin-color.png"
tags: ["alpha"]
---

Body B.
MD
(cd "$site2" && hugo --quiet --destination "$site2/public") || {
    echo "FAIL: hugo could not build the SEO test site"
    exit 1
}
pub="$site2/public"
sameas="$work/sameas.txt"
awk '$1 == "url:" && $2 ~ /^https:\/\// { print $2 }' "$root/data/socials.yaml" >"$sameas"
[[ -s "$sameas" ]] || {
    echo "FAIL: data/socials.yaml has no https url"
    exit 1
}
card="https://$host/brand/og-card.png"

seo_ok() { # seo_ok <label> <args...>
    local label="$1" out
    shift
    if out="$(run_seo "$@" 2>&1)"; then pass "$label"; else fail "$label: $out"; fi
}
seo_ok "home: canonical, card, Person JSON-LD with the public sameAs links" page "$pub/index.html" "https://$host/" "$card" home "$sameas"
seo_ok "post: canonical, default OG card, Article JSON-LD" page "$pub/posts/a/index.html" "https://$host/posts/a/" "$card" article "$sameas"
seo_ok "post with an image: its own image and Article JSON-LD" page "$pub/posts/b/index.html" "https://$host/posts/b/" "https://$host/brand/penguin-color.png" article "$sameas"
seo_ok "about page: no Article, no robots meta" page "$pub/about/index.html" "https://$host/about/" "$card" page "$sameas"
seo_ok "404 page: noindex, canonical, card" page "$pub/404.html" "https://$host/404.html" "$card" 404 "$sameas"
seo_ok "every indexable page has its own description" descs "$pub/index.html" "$pub/posts/index.html" "$pub/posts/a/index.html" "$pub/posts/b/index.html" "$pub/about/index.html" "$pub/tags/alpha/index.html"
seo_ok "sitemap: lastmod on every url, no alias, no 404" sitemap "$pub/sitemap.xml" "$host" /posts/a/ /posts/b/ /about/ /social/ / -- /old-post-a/ /404.html /contact/
seo_ok "feed: atom self link and the full post body" rss "$pub/index.xml" "$host" FULLBODYMARKER "<script"

if grep -q '^Sitemap: https://'"$host"'/sitemap.xml$' "$pub/robots.txt"; then
    pass "robots.txt names the sitemap on the site host"
else
    fail "robots.txt does not name the sitemap"
fi
if ! grep -qi 'api.github\|googletagmanager\|//fonts\.' "$pub/index.html" "$pub/posts/a/index.html"; then
    pass "no third-party host in the head"
else
    fail "a third-party host appears in a page"
fi

# Guards: each assertion must bite.
cp "$pub/posts/a/index.html" "$work/g.html"
sed -i 's#"name":"ChiefGyk3D"#"name":"Someone Else"#g' "$work/g.html"
if run_seo page "$work/g.html" "https://$host/posts/a/" "$card" article "$sameas" >/dev/null 2>&1; then
    fail "guard: a wrong author name was accepted"
else
    pass "guard: a wrong author name is rejected"
fi
cp "$pub/404.html" "$work/g404.html"
sed -i 's#noindex#index#g' "$work/g404.html"
if run_seo page "$work/g404.html" "https://$host/404.html" "$card" 404 "$sameas" >/dev/null 2>&1; then
    fail "guard: a 404 without noindex was accepted"
else
    pass "guard: a 404 without noindex is rejected"
fi
sed 's#<lastmod>[^<]*</lastmod>##' "$pub/sitemap.xml" >"$work/g-sitemap.xml"
if run_seo sitemap "$work/g-sitemap.xml" "$host" / -- >/dev/null 2>&1; then
    fail "guard: a sitemap without lastmod was accepted"
else
    pass "guard: a sitemap without lastmod is rejected"
fi
if run_seo rss "$pub/index.xml" "$host" NOSUCHMARKER "<script" >/dev/null 2>&1; then
    fail "guard: a feed lacking the needle was accepted"
else
    pass "guard: a feed lacking the needle is rejected"
fi
if run_seo descs "$pub/posts/a/index.html" "$pub/posts/a/index.html" >/dev/null 2>&1; then
    fail "guard: a duplicate description was accepted"
else
    pass "guard: a duplicate description is rejected"
fi

# --- guard self-test: the asserter must fail on an injected tag ------------
inj="$work/injected.html"
sed 's#<meta property="og:site_name"#<meta property="og:site_name" content="x"><meta property="og:site_name"#; s#<meta property=og:site_name#<meta property=og:site_name content=x><meta property=og:site_name#' "$plain_page" >"$inj"
if run_asserter "$inj" "Body." "Plain" >/dev/null 2>&1; then
    fail "guard: asserter passed a page with a duplicated tag"
else
    pass "guard: asserter fails a page with a duplicated tag"
fi
printf '<html><head><title>Plain | ChiefGyk3D</title><meta name="description" content="x"><script>1</script></head></html>\n' >"$inj"
if run_asserter "$inj" "Body." "Plain" >/dev/null 2>&1; then
    fail "guard: asserter passed a page with a script and a wrong description"
else
    pass "guard: asserter fails a page with a script and a wrong description"
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all head tests passed"
