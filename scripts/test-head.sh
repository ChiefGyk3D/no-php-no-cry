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
    ("property", "og:site_name"), ("property", "og:title"),
    ("property", "og:description"), ("property", "og:type"),
    ("property", "og:url"), ("property", "og:image"),
    ("property", "article:published_time"),
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
            self.scripts += 1
        elif tag == "title":
            self.in_title = True
        elif tag == "a" and "me" in (a.get("rel") or "").split():
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
    if t != want_title or page_title not in (want_title, want_title + " | no-php-no-cry"):
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

run_asserter() { python3 -I "$asserter" "$@"; }

# --- the throwaway site ---------------------------------------------------
site="$work/site"
mkdir -p "$site/content/posts/hostile" "$site/content/posts/plain"
cp -r "$root/layouts" "$root/assets" "$root/static" "$site/"
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

if out="$(run_asserter "$plain_page" "Placeholder site description." "Plain" 2>&1)"; then
    pass "no description in front matter falls back to the site description"
else
    fail "plain page: $out"
fi

if out="$(run_asserter "$site/public/index.html" "Placeholder site description." "no-php-no-cry" "https://social.example/@name" 2>&1)"; then
    pass "rel=me links render; the javascript: link is not emitted"
else
    fail "home page: $out"
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

# Production leaves robots to robots.txt; the default environment adds no meta.
if grep -qi 'name=robots\|name="robots"' "$hostile_page"; then
    fail "production build has a robots meta tag"
else
    pass "production build has no robots meta tag"
fi

# --- guard self-test: the asserter must fail on an injected tag ------------
inj="$work/injected.html"
sed 's#<meta property="og:site_name"#<meta property="og:site_name" content="x"><meta property="og:site_name"#; s#<meta property=og:site_name#<meta property=og:site_name content=x><meta property=og:site_name#' "$plain_page" >"$inj"
if run_asserter "$inj" "Placeholder site description." "Plain" >/dev/null 2>&1; then
    fail "guard: asserter passed a page with a duplicated tag"
else
    pass "guard: asserter fails a page with a duplicated tag"
fi
printf '<html><head><title>Plain | no-php-no-cry</title><meta name="description" content="x"><script>1</script></head></html>\n' >"$inj"
if run_asserter "$inj" "Placeholder site description." "Plain" >/dev/null 2>&1; then
    fail "guard: asserter passed a page with a script and a wrong description"
else
    pass "guard: asserter fails a page with a script and a wrong description"
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all head tests passed"
