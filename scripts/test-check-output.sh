#!/usr/bin/env bash
# Negative test for scripts/check-output.sh.
#
# Builds a small good output tree and one bad variant per rule in a scratch
# directory under the repository's own gitignored tmp/ (never /tmp), then
# asserts that the checker passes the good tree and fails each bad one with the
# expected rule name. If a real build exists in public/ it is checked too.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-output.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/check-output.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
# The pinned hash of each allowed script (copy.js, search.js) is a committed
# file named <script>.sha256; tests use their own directory, empty unless a case
# pins a script.
export SCRIPT_HASH_DIR="$work/hashes"
# pin_dir <site dir> [script name]: pins the script's current bytes.
pin_dir() { printf '%s  %s\n' "$(sha256sum "$1/${2:-copy.js}" | cut -d' ' -f1)" "${2:-copy.js}" >"$SCRIPT_HASH_DIR/${2:-copy.js}.sha256"; }

make_good() {
    local dir="$1"
    rm -rf "$SCRIPT_HASH_DIR"
    mkdir -p "$SCRIPT_HASH_DIR"
    rm -rf "$dir"
    mkdir -p "$dir/posts/sample-post"
    # Heads as Hugo's minifier writes them (attribute quotes dropped where legal).
    # Home is a website page; a post is an article with a published time.
    # The shell Hugo writes: skip link first, then header, the Main nav, main, footer.
    local shell_open='<a class=skip-link href=#main>Skip to main content</a><header><a class=site-title href=/>t</a><nav aria-label=Main><ul><li><a href=/posts/>Posts</a></ul></nav></header><main id=main>'
    local shell_close='</main><footer><a href=/about/#contact>Contact</a></footer>'
    # Page bodies the templates write (issues 58 and 59). The home hero and the
    # 404 carry the mascot with its dimensions; the archive groups by year.
    local mascot='<img class=hero-mascot src=/brand/mascot-256.webp width=256 height=256 alt="Renegade Tux">'
    local home_body="<section class=hero>${mascot}<h1>Cybersecurity, Linux, and whatever I'm building next.</h1><p>I'm a Senior Cybersecurity Engineer, Linux nerd, and open-source builder.<p><a class=\"btn btn-primary\" href=/posts/>Read the latest</a> <a class=btn href=/about/#projects>See my projects</a> <a class=btn href=/support/>Support my work</a></section><section class=panel><h2>Latest posts</h2><a href=/posts/>All posts</a></section><section class=panel><h2>Find me online</h2></section>"
    local archive_body='<h1>Posts</h1><a href=/posts/index.xml>RSS</a><h2 class=archive-year>2023</h2><ul><li><a href=/posts/sample-post/>Sample post</a></ul>'
    local not_found_body="<h1>Renegade Tux ran <code>rm -rf</code> again.</h1>${mascot}<p>The page is gone, and the penguin is refusing to answer questions.<p><a class=btn href=/>Start over</a> <a class=btn href=/posts/>Browse posts</a> <a class=btn href=/search/>Search the site</a> <a class=btn href=/social/>Find me online</a>"
    local post_body='<article><h1>Sample post</h1><time datetime=2023-02-10>February 10, 2023</time> <span class=reading-time>1 min read</span></article>'
    local person_ld='<script type=application/ld+json>{"@context":"https://schema.org","@graph":[{"@type":"WebSite","name":"t","url":"https://test-blog.chiefgyk3d.com/"},{"@type":"Person","name":"ChiefGyk3D","sameAs":["https://github.com/ChiefGyk3D"]}]}</script>'
    local article_ld='<script type=application/ld+json>{"@context":"https://schema.org","@type":"Article","headline":"Sample post","datePublished":"2023-02-10T09:00:00-05:00","author":{"@type":"Person","name":"ChiefGyk3D"}}</script>'
    local common='<meta name=twitter:card content=summary_large_image><meta name=theme-color content=#0F0F0F><meta name=twitter:image content=https://test-blog.chiefgyk3d.com/brand/og-card.png><link rel=manifest href=/site.webmanifest><meta property=og:site_name content=t><meta property=og:title content=t><meta property=og:image content=https://test-blog.chiefgyk3d.com/brand/penguin-color.png><link rel=icon href=/brand/penguin-glyph.svg type=image/svg+xml><link rel=icon href=/brand/penguin-color.png type=image/png sizes=512x512><link rel=apple-touch-icon href=/brand/penguin-color.png><link rel=stylesheet href=/css/site.min.css integrity=sha256-AAAA>'
    printf '%s\n' "<!doctype html><html lang=en-us><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><title>t</title>${common}<meta name=description content=\"Home description.\"><meta property=og:description content=\"Home description.\"><meta property=og:type content=website><meta property=og:url content=https://test-blog.chiefgyk3d.com/><link rel=canonical href=https://test-blog.chiefgyk3d.com/>${person_ld}</head><body>${shell_open}<a href=https://example.org/outbound>outbound links are fine</a><img src=/posts/sample-post/a.png width=1 height=1 alt=x>${home_body}${shell_close}</body></html>" >"$dir/index.html"
    printf '%s\n' "<!doctype html><html lang=en-us><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><title>t</title>${common}<meta name=description content=\"Post description.\"><meta property=og:description content=\"Post description.\"><meta property=og:type content=article><meta property=article:published_time content=2023-02-10T09:00:00-05:00><meta property=og:url content=https://test-blog.chiefgyk3d.com/posts/sample-post/><link rel=canonical href=https://test-blog.chiefgyk3d.com/posts/sample-post/>${article_ld}</head><body>${shell_open}<a href=https://example.org/outbound>outbound links are fine</a><img src=/posts/sample-post/a.png width=1 height=1 alt=x>${post_body}${shell_close}</body></html>" >"$dir/posts/sample-post/index.html"
    plain_page() { printf '%s\n' "<!doctype html><html lang=en-us><head><meta charset=utf-8><title>t</title></head><body>${shell_open}$1${shell_close}</body></html>" >"$2"; }
    mkdir -p "$dir/tags/lorem" "$dir/journal" "$dir/support" "$dir/search"
    plain_page '<h1>Support</h1>' "$dir/support/index.html"
    plain_page '<h1>Search</h1><ul><li><a href=/posts/sample-post/>Sample post</a></ul>' "$dir/search/index.html"
    plain_page "$archive_body" "$dir/posts/index.html"
    plain_page "$archive_body" "$dir/tags/lorem/index.html"
    plain_page "$archive_body" "$dir/journal/index.html"
    # The 404 carries noindex in production (and in staging, with nofollow).
    printf '%s\n' "<!doctype html><html lang=en-us><head><meta charset=utf-8><title>t</title><meta name=description content=\"Not found description.\"><meta name=robots content=noindex></head><body>${shell_open}${not_found_body}${shell_close}</body></html>" >"$dir/404.html"
    # Hugo's meta-refresh alias pages: one directory-style, one ending in .html.
    mkdir -p "$dir/2023/02/10/sample-post" "$dir/css"
    alias_page='<!doctype html><html lang=en-us><head><title>https://test-blog.chiefgyk3d.com/posts/sample-post/</title><link rel=canonical href=https://test-blog.chiefgyk3d.com/posts/sample-post/><meta name=robots content=noindex><meta http-equiv=refresh content="0; url=https://test-blog.chiefgyk3d.com/posts/sample-post/"></head></html>'
    printf '%s\n' "$alias_page" >"$dir/2023/02/10/sample-post/index.html"
    printf '%s\n' "$alias_page" >"$dir/sample-post.html"
    printf 'body{background:url(data:image/png;base64,AAAA);color:red}\n' >"$dir/css/site.min.css"
    printf '<?xml version="1.0"?><rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel><atom:link href="https://test-blog.chiefgyk3d.com/index.xml" rel="self" type="application/rss+xml"/></channel></rss>\n' >"$dir/index.xml"
    mkdir -p "$dir/feed"
    printf '<?xml version="1.0"?><rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel><atom:link href="https://test-blog.chiefgyk3d.com/feed/index.xml" rel="self" type="application/rss+xml"/></channel></rss>\n' >"$dir/feed/index.xml"
    printf '<?xml version="1.0" encoding="utf-8" standalone="yes"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://test-blog.chiefgyk3d.com/</loc><lastmod>2023-02-10T09:00:00-05:00</lastmod></url><url><loc>https://test-blog.chiefgyk3d.com/posts/sample-post/</loc><lastmod>2023-02-10T09:00:00-05:00</lastmod></url></urlset>\n' >"$dir/sitemap.xml"
    printf 'User-agent: *\nAllow: /\n\nSitemap: https://test-blog.chiefgyk3d.com/sitemap.xml\n' >"$dir/robots.txt"
    printf '# t\n\n> A site.\n\n## Sections\n- [Posts](https://test-blog.chiefgyk3d.com/posts/): Posts\n- [GitHub](https://github.com/ChiefGyk3D): Code\n' >"$dir/llms.txt"
    cat >"$dir/_redirects" <<'RED'
# generated
/2023/02/10/sample-post /posts/sample-post/ 301
/2023/02/10/sample-post/ /posts/sample-post/ 301
/sample-post.html /posts/sample-post/ 301
RED
    cat >"$dir/_headers" <<'HDR'
/*
  Content-Security-Policy: default-src 'none'; img-src 'self'; style-src 'self'; manifest-src 'self'; script-src 'self' https://static.cloudflareinsights.com/beacon.min.js; connect-src 'self'
  X-Content-Type-Options: nosniff
HDR
}

# expect_fail <label> <rule> <dir>: the checker must exit non-zero and name the rule.
expect_fail() {
    local label="$1" rule="$2" dir="$3" out rc=0
    out="$("$checker" "$dir" 2>&1)" || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "FAIL: $label: checker passed a bad tree"
        failures=$((failures + 1))
    elif ! grep -q "\[$rule\]" <<<"$out"; then
        echo "FAIL: $label: checker failed but did not name rule $rule"
        failures=$((failures + 1))
    else
        echo "ok: $label -> [$rule]"
    fi
}

good="$work/good"
make_good "$good"
if "$checker" "$good" >/dev/null 2>&1; then
    echo "ok: good fixture passes"
else
    echo "FAIL: good fixture was rejected"
    "$checker" "$good" || true
    failures=$((failures + 1))
fi

# variant <name> <rule> <command that mutates $d>
variant() {
    local name="$1" rule="$2"
    shift 2
    local d="$work/$name"
    make_good "$d"
    "$@" "$d"
    expect_fail "$name" "$rule" "$d"
}

append_html() { printf '%s\n' "$APPEND" >>"$1/${PAGE:-index.html}"; }

# A <link rel=me> to another host is an identity claim, not an asset: it must pass.
make_good "$work/rel-me"
printf '%s\n' '<link rel=me href=https://social.example.org/@x>' >>"$work/rel-me/index.html"
if "$checker" "$work/rel-me" >/dev/null 2>&1; then
    echo "ok: rel=me link to another host passes"
else
    echo "FAIL: rel=me link to another host was rejected"
    failures=$((failures + 1))
fi

# Landmarks: skip link first and targeting main, one header, one nav labeled
# Main, one main#main, one footer, on every page (not alias stubs).
swap_index() { sed -i "s|$FROM|$TO|" "$1/index.html"; }
FROM='<a class=skip-link href=#main>Skip to main content</a>' TO='' variant no-skip-link skip-link swap_index
FROM='<a class=skip-link href=#main>' TO='<a class=skip-link href=#content>' variant skip-link-wrong-target skip-link swap_index
FROM='<header>' TO='<div>' variant no-header landmark swap_index
FROM='</header>' TO='</div>' variant no-header-close landmark swap_index
FROM='<nav aria-label=Main>' TO='<nav>' variant nav-unlabeled landmark swap_index
FROM='<footer>' TO='<div>' variant no-footer landmark swap_index
FROM='<main id=main>' TO='<main>' variant main-without-id landmark swap_index
FROM='</main>' TO='</main><main id=again></main>' variant two-mains landmark swap_index
FROM='<footer>' TO='<footer></footer><footer>' variant two-footers landmark swap_index

# The project name is not the site name: the built output must not show it.
# Only the repository URL on github.com is allowed.
APPEND='<p>no-php-no-cry</p>' variant old-name-text old-site-name append_html
APPEND='<meta property=og:site_name content=no-php-no-cry>' variant old-name-meta old-site-name append_html
FROM='<title>t</title>' TO='<title>Posts \| no-php-no-cry</title>' variant old-name-title old-site-name swap_index
old_name_in_feed() { printf '<?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel><title>no-php-no-cry</title></channel></rss>\n' >"$1/index.xml"; }
variant old-name-feed old-site-name old_name_in_feed
old_name_in_manifest() { printf '{"name":"no-php-no-cry"}\n' >"$1/site.webmanifest"; }
variant old-name-manifest old-site-name old_name_in_manifest
# The browser shows the decoded text, so character references are decoded first.
APPEND='<p>no&#45;php&#45;no&#45;cry</p>' variant old-name-decimal-entity old-site-name append_html
APPEND='<p>no&#x2d;php&#x2D;no&#x2d;cry</p>' variant old-name-hex-entity old-site-name append_html
APPEND='<p>No-PHP-No-Cry</p>' variant old-name-mixed-case old-site-name append_html
APPEND='<p>no-php&#45;no-cry</p>' variant old-name-split-entity old-site-name append_html
APPEND='<p>n&#111;-php-n&#x6F;-cry</p>' variant old-name-letter-entity old-site-name append_html
APPEND='<meta name=x content="no&#45;php&#45;no&#45;cry">' variant old-name-attr-entity old-site-name append_html
# An encoded repository link is still the allowed link.
enc_allowed="$work/old-name-enc-allowed"
make_good "$enc_allowed"
printf '%s\n' '<p><a href="https://github.com/ChiefGyk3D/no&#45;php&#45;no&#45;cry">source</a></p>' >>"$enc_allowed/index.html"
if "$checker" "$enc_allowed" >/dev/null 2>&1; then
    echo "ok: encoded repository URL is allowed"
else
    echo "FAIL: encoded repository URL was rejected"
    failures=$((failures + 1))
fi
# Negative cases: the repository link is allowed, and so is a near miss.
allowed="$work/old-name-allowed"
make_good "$allowed"
printf '%s\n' '<p><a href="https://github.com/ChiefGyk3D/no-php-no-cry">source</a> <a href=https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/x.md>doc</a></p>' >>"$allowed/index.html"
if "$checker" "$allowed" >/dev/null 2>&1; then
    echo "ok: repository URL is allowed"
else
    echo "FAIL: repository URL was rejected"
    failures=$((failures + 1))
fi
lookalike="$work/old-name-lookalike"
make_good "$lookalike"
printf '%s\n' '<p>https://example.org/ChiefGyk3D/no-php-no-cry</p>' >>"$lookalike/index.html"
expect_fail old-name-lookalike-url old-site-name "$lookalike"

APPEND='<script>alert(1)</script>' variant inline-script inline-script append_html
APPEND='<style>body{color:red}</style>' variant style-element style-element append_html
APPEND='<p style="color:red">x</p>' variant style-attribute style-attribute append_html
APPEND='<pre><code>x</code></pre>' variant pre-not-focusable pre-not-focusable append_html
APPEND='<button onclick="go()">x</button>' variant event-handler event-handler append_html
APPEND='<img src="http://example.org/a.png" alt=x>' variant http-reference http-reference append_html
APPEND='<link rel=stylesheet href=https://fonts.example.org/css>' variant external-asset external-asset append_html
APPEND='<link rel="me stylesheet" href=https://fonts.example.org/css>' variant rel-me-stylesheet external-asset append_html
APPEND='<script src=https://cdn.example.org/x.js></script>' variant external-script external-asset append_html
APPEND='<script src=https://cdn.example.org/x.js></script>' variant external-script-element script-not-allowed append_html
APPEND='<script src=//cdn.example.org/x.js></script>' variant scheme-relative-script script-not-allowed append_html
APPEND='<script src=/app.js></script>' variant local-other-script script-not-allowed append_html
APPEND='<script>alert(1)</script>' variant inline-script-element script-not-allowed append_html
APPEND='<script src=/copy.js>alert(1)</script>' variant copy-script-with-inline-body script-not-allowed append_html
APPEND='<script src=/copy.js defer></script>' variant copy-script-extra-attribute script-not-allowed append_html
APPEND='<script type=module src=/copy.js></script>' variant copy-script-module script-not-allowed append_html
APPEND='<script src=data:text/javascript,alert(1)></script>' variant data-url-script script-not-allowed append_html
PAGE=support/index.html APPEND='<script src=/copy.js></script><script src=/copy.js></script>' variant copy-script-twice script-count append_html
APPEND='<script src=/copy.js></script><script src=/other.js></script>' variant second-script-file script-not-allowed append_html
APPEND='<script' variant unterminated-script-tag script-not-allowed append_html
APPEND='<a href="javascript:alert(1)">x</a>' variant javascript-href javascript-url append_html
APPEND="<a href='  JavaScript:alert(1)'>x</a>" variant javascript-href-spaced-quoted javascript-url append_html
APPEND='<iframe src=javascript:alert(1)></iframe>' variant javascript-iframe javascript-url append_html
APPEND='<img/onerror=alert(1) src=x>' variant handler-after-slash event-handler append_html
APPEND='<img src=x alt="a"onerror=alert(1)>' variant handler-after-quote event-handler append_html
APPEND='<p ONCLICK = "x">' variant handler-uppercase-spaced event-handler append_html
APPEND='<p
onclick=x>' variant handler-on-next-line event-handler append_html

# Character references are decoded by the browser before the URL is read, so the
# encoded forms must be caught as the plain ones are.
APPEND='<a href="java&#x73;cript:alert(1)">x</a>' variant javascript-href-hex-reference javascript-url append_html
APPEND='<a href="&#106;avascript:alert(1)">x</a>' variant javascript-href-decimal-reference javascript-url append_html
APPEND='<a href="javascript&colon;alert(1)">x</a>' variant javascript-href-named-colon javascript-url append_html
APPEND='<a href="java&Tab;script:alert(1)">x</a>' variant javascript-href-named-tab javascript-url append_html
APPEND='<a href="java&#9;script:alert(1)">x</a>' variant javascript-href-numeric-tab javascript-url append_html
APPEND='<a href="&#x20;javascript:alert(1)">x</a>' variant javascript-href-leading-space-reference javascript-url append_html
APPEND='<iframe src="&#106;avascript:alert(1)"></iframe>' variant javascript-iframe-reference javascript-url append_html
APPEND='<meta http-equiv=refresh content="0;url=javascript:alert(1)">' variant javascript-meta-refresh javascript-url append_html
# Attributes are read from real attributes: a ">" inside a quoted value does not
# end the tag, and text inside a value is not an attribute.
APPEND='<img alt="x>" onerror=alert(1)>' variant handler-after-quoted-gt event-handler append_html
APPEND="<img alt='x>' onerror=alert(1)>" variant handler-after-single-quoted-gt event-handler append_html
APPEND='<a title="a>b" href="javascript:alert(1)">x</a>' variant javascript-url-after-quoted-gt javascript-url append_html
APPEND='<img alt=x onerror=alert(1)>' variant handler-unquoted-attributes event-handler append_html
APPEND="<img alt='x' onerror='alert(1)'>" variant handler-single-quoted event-handler append_html
APPEND='<a title=x href=javascript:alert(1)>x</a>' variant javascript-url-unquoted javascript-url append_html
for form in '<a href=x alt="one=1">y</a>' '<img alt="one=1" src=/a.png>' '<img alt=one=1 src=/a.png>' '<p title="onerror=alert(1) is text">x</p>' "<p title='onclick=x'>x</p>" '<p title="a>b">x</p>'; do
    d="$work/ok-attribute"
    make_good "$d"
    APPEND="$form" append_html "$d"
    if "$checker" "$d" >/dev/null 2>&1; then
        echo "ok: benign attribute passes ($form)"
    else
        echo "FAIL: benign attribute was rejected ($form)"
        "$checker" "$d" || true
        failures=$((failures + 1))
    fi
done

# The same rules apply to svg, xml and xhtml outputs.
markup_file() {
    mkdir -p "$(dirname "$1/$FILE")"
    printf '%s\n' "$CONTENT" >"$1/$FILE"
}
FILE=logo.svg CONTENT='<svg xmlns="http://www.w3.org/2000/svg"><script href="/copy.js"/></svg>' variant svg-script-element script-not-allowed markup_file
FILE=logo.svg CONTENT='<svg xmlns="http://www.w3.org/2000/svg" onload="x()"/>' variant svg-event-handler event-handler markup_file
FILE=logo.svg CONTENT='<svg xmlns="http://www.w3.org/2000/svg"><a href="javascript:x()"><text>t</text></a></svg>' variant svg-javascript-url javascript-url markup_file
FILE=logo.svg CONTENT='<svg xmlns="http://www.w3.org/2000/svg"><a title="a>b" onclick="x()"/></svg>' variant svg-handler-after-quoted-gt event-handler markup_file
FILE=index.xml CONTENT='<?xml version="1.0"?><rss version="2.0"><channel><script/></channel></rss>' variant xml-script-element script-not-allowed markup_file
FILE=index.xml CONTENT='<?xml version="1.0"?><rss version="2.0"><channel><a onclick="x()"/></channel></rss>' variant xml-event-handler event-handler markup_file
FILE=posts/sample-post/index.xml CONTENT='<?xml version="1.0"?><rss version="2.0"><a href="javascript:x()"/></rss>' variant nested-xml-javascript-url javascript-url markup_file
FILE=page.xhtml CONTENT='<html xmlns="http://www.w3.org/1999/xhtml"><body onload="x()"/></html>' variant xhtml-event-handler event-handler markup_file
d="$work/ok-feed"
make_good "$d"
printf '%s\n' '<?xml version="1.0"?><rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel><atom:link href="https://test-blog.chiefgyk3d.com/index.xml" rel="self" type="application/rss+xml"/><item><description>&lt;a onclick="x"&gt; one=1 &lt;script&gt;</description></item></channel></rss>' >"$d/index.xml"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: escaped markup text inside a feed passes"
else
    echo "FAIL: escaped markup text in a feed was rejected"
    "$checker" "$d" || true
    failures=$((failures + 1))
fi

# Scheme-relative and backslash forms leave the site without http(s):.
APPEND='<iframe src="//evil.example/frame"></iframe>' variant protocol-relative-iframe external-asset append_html
APPEND='<object data="//evil.example/payload"></object>' variant protocol-relative-object external-asset append_html
APPEND='<embed src="//evil.example/payload">' variant protocol-relative-embed external-asset append_html
APPEND='<link rel=stylesheet href=//evil.example/x.css>' variant protocol-relative-stylesheet external-asset append_html
APPEND='<img src="\\evil.example/a.png" alt=x>' variant backslash-host-image external-asset append_html
APPEND='<img src="/\evil.example/a.png" alt=x>' variant slash-backslash-host-image external-asset append_html
APPEND='<form action="//evil.example/post"></form>' variant protocol-relative-form external-asset append_html
APPEND='<img srcset="/a.png 1x, //evil.example/b.png 2x" alt=x>' variant protocol-relative-srcset external-asset append_html
APPEND='<img src="https&colon;//evil.example/a.png" alt=x>' variant encoded-scheme-image external-asset append_html
APPEND='<img src="h&#116;tp://evil.example/a.png" alt=x>' variant encoded-http-image http-reference append_html
APPEND='<video poster="//evil.example/p.png"></video>' variant protocol-relative-poster external-asset append_html
APPEND='<base href="//evil.example/">' variant base-protocol-relative base-element append_html
APPEND='<base href=/>' variant base-same-site base-element append_html
APPEND='<BASE target=_top>' variant base-target-only base-element append_html
for form in '<img src="//test-blog.chiefgyk3d.com/a.png" alt=x>' '<a href="//example.org/x">outbound</a>' '<a href="&#104;ttps://example.org/x">outbound</a>' '<p title="a javascript: word">x</p>'; do
    d="$work/ok-reference"
    make_good "$d"
    APPEND="$form" append_html "$d"
    if "$checker" "$d" >/dev/null 2>&1; then
        echo "ok: allowed reference passes ($form)"
    else
        echo "FAIL: allowed reference was rejected ($form)"
        "$checker" "$d" || true
        failures=$((failures + 1))
    fi
done

# The pinned scripts. Each is allowed on its own page only (scripts/artifact-rules.sh
# maps script -> page): /copy.js on /support/, /search.js on /search/. The tag is
# as the minifier writes it (no quotes), or with quotes, once per page.
COPY_JS='document.documentElement.dataset.copy="dark"'
SEARCH_JS='document.documentElement.dataset.search="dark"'
js_body() { if [[ "$1" == copy.js ]]; then printf '%s\n' "$COPY_JS"; else printf '%s\n' "$SEARCH_JS"; fi; }
home_of() { if [[ "$1" == copy.js ]]; then printf 'support/index.html'; else printf 'search/index.html'; fi; }
# place <dir> <script> [page] [tag]: appends the tag to the page (default: the
# script's own), writes the script and pins it.
place() {
    local name="$2" page="${3:-$(home_of "$2")}" tag="${4:-<script src=/$2></script>}"
    printf '%s\n' "$tag" >>"$1/$page"
    js_body "$name" >"$1/$name"
    pin_dir "$1" "$name"
}
for name in copy.js search.js; do
    for form in "<script src=/$name></script>" "<script src=\"/$name\"></script>" "<script src='/$name'></script>" "<SCRIPT SRC=/$name></SCRIPT>"; do
        d="$work/script-ok"
        make_good "$d"
        place "$d" "$name" "" "$form"
        if "$checker" "$d" >/dev/null 2>&1; then
            echo "ok: $name is allowed on its own page ($form)"
        else
            echo "FAIL: $name was rejected on its own page ($form)"
            "$checker" "$d" || true
            failures=$((failures + 1))
        fi
    done
done
d="$work/script-both"
make_good "$d"
place "$d" copy.js
place "$d" search.js
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: both pinned scripts, each on its own page, pass"
else
    echo "FAIL: both pinned scripts on their own pages were rejected"
    "$checker" "$d" || true
    failures=$((failures + 1))
fi

# A pinned script on any page other than its own is refused, with the other
# script's page as the wrong page too.
wrong() { place "$1" "$NAME" "$ON"; }
NAME=copy.js ON=index.html variant copy-on-home script-wrong-page wrong
NAME=copy.js ON=search/index.html variant copy-on-search-page script-wrong-page wrong
NAME=copy.js ON=posts/sample-post/index.html variant copy-on-a-post script-wrong-page wrong
NAME=search.js ON=index.html variant search-on-home script-wrong-page wrong
NAME=search.js ON=support/index.html variant search-on-support-page script-wrong-page wrong
NAME=search.js ON=404.html variant search-on-404 script-wrong-page wrong
wrong_and_right() {
    place "$1" copy.js
    place "$1" copy.js index.html
}
variant copy-on-both-support-and-home script-wrong-page wrong_and_right

# The page references the script but the file is not in the build.
script_missing() {
    printf '%s\n' "<script src=/$NAME></script>" >>"$1/$(home_of "$NAME")"
    printf '%s  %s\n' "$(printf 'a%.0s' $(seq 1 64))" "$NAME" >"$SCRIPT_HASH_DIR/$NAME.sha256"
}
NAME=copy.js variant copy-script-file-missing missing-script script_missing
NAME=search.js variant search-script-file-missing missing-script script_missing

# Once per page.
twice() { place "$1" "$NAME" "" "<script src=/$NAME></script><script src=/$NAME></script>"; }
NAME=copy.js variant copy-script-twice-on-own-page script-count twice
NAME=search.js variant search-script-twice script-count twice

# Script files: only the two pinned ones, each under 1 KB gzip (brief section
# 10); a third .js, in any directory or case, is refused.
both_pinned() {
    place "$1" copy.js
    place "$1" search.js
}
extra_js() {
    both_pinned "$1"
    mkdir -p "$(dirname "$1/$FILE")"
    printf 'x\n' >"$1/$FILE"
}
FILE=app.js variant extra-js-file extra-script-file extra_js
FILE=third.js variant third-js-file extra-script-file extra_js
FILE=js/other.js variant nested-js-file extra-script-file extra_js
FILE=other.mjs variant extra-mjs-file extra-script-file extra_js
FILE=Other.JS variant extra-uppercase-js-file extra-script-file extra_js
FILE=js/copy.js variant copy-js-in-subdirectory extra-script-file extra_js
FILE=js/search.js variant search-js-in-subdirectory extra-script-file extra_js
js_only_file() { printf 'x\n' >"$1/app.js"; }
variant js-file-without-page-reference extra-script-file js_only_file
# 4 KB of incompressible bytes is over the gzip budget; a 1 KB compressible
# file is not.
big_js() {
    place "$1" "$NAME"
    head -c 4096 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$1/$NAME"
    pin_dir "$1" "$NAME"
}
NAME=copy.js variant copy-js-over-budget js-budget big_js
NAME=search.js variant search-js-over-budget js-budget big_js
for name in copy.js search.js; do
    d="$work/js-compressible"
    make_good "$d"
    place "$d" "$name"
    for _ in $(seq 1 1024); do printf 'var a=1;'; done >"$d/$name"
    pin_dir "$d" "$name"
    if "$checker" "$d" >/dev/null 2>&1; then
        echo "ok: a $name that is large raw but under 1 KB gzip passes"
    else
        echo "FAIL: a compressible $name under 1 KB gzip was rejected"
        failures=$((failures + 1))
    fi
done

# The search page is the browse list with JS off, so its HTML is held to a
# budget: 40 KB gzip. Past it the approach (one static page listing every post)
# needs another look (docs/pinned-script.md).
big_search_page() { head -c 80000 /dev/urandom | od -An -tx1 | tr -d ' \n' | fold -w 70 | sed 's#^#<p>#' >>"$1/search/index.html"; }
variant search-page-over-budget search-page-budget big_search_page
d="$work/search-compressible"
make_good "$d"
for _ in $(seq 1 4000); do printf '<li><a href=/posts/x/>A post title</a>\n'; done >>"$d/search/index.html"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: a large but compressible search page under 40 KB gzip passes"
else
    echo "FAIL: a compressible search page under 40 KB gzip was rejected"
    "$checker" "$d" || true
    failures=$((failures + 1))
fi
# The same bytes on another page are no search-page finding.
big_other_page() { head -c 80000 /dev/urandom | od -An -tx1 | tr -d ' \n' | fold -w 70 | sed 's#^#<p>#' >>"$1/support/index.html"; }
d="$work/support-big"
make_good "$d"
big_other_page "$d"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: the search page budget applies to the search page only"
else
    echo "FAIL: a large page other than the search page was rejected"
    failures=$((failures + 1))
fi

append_file() { printf '%s\n' "$APPEND" >>"$1/$FILE"; }
FILE=css/site.min.css APPEND='@import "https://fonts.example.org/css";' variant css-import external-css-reference append_file
FILE=css/site.min.css APPEND='@import url(//fonts.example.org/css);' variant css-import-scheme-relative external-css-reference append_file
FILE=css/site.min.css APPEND='a{background:url(https://cdn.example.org/a.png)}' variant css-url-https external-css-reference append_file
FILE=css/site.min.css APPEND='a{background:url("//cdn.example.org/a.png")}' variant css-url-scheme-relative external-css-reference append_file
FILE=css/site.min.css APPEND='a{background:url(http://cdn.example.org/a.png)}' variant css-url-http external-css-reference append_file
FILE=logo.svg APPEND='<svg xmlns="http://www.w3.org/2000/svg"><image href="https://cdn.example.org/a.png"/></svg>' variant svg-external external-css-reference append_file
FILE=index.xml APPEND='<?xml-stylesheet type="text/xsl" href="/feed.xsl"?>' variant feed-stylesheet xml-stylesheet append_file

# Malformed XML: the bug that shipped (an HTML-escaped declaration), a truncated
# feed, and a bad file outside the feeds (every *.xml is parsed).
escaped_decl() { printf '&lt;?xml version="1.0" encoding="utf-8"?><rss version="2.0"></rss>\n' >"$1/index.xml"; }
variant escaped-xml-declaration bad-xml escaped_decl
truncated_feed() { printf '<?xml version="1.0"?><rss version="2.0"><channel>\n' >"$1/index.xml"; }
variant truncated-feed bad-xml truncated_feed
other_bad_xml() { printf 'not xml\n' >"$1/posts/sample-post/index.xml"; }
variant other-bad-xml bad-xml other_bad_xml

rm_file() { rm -f "$2/$1"; }
variant no-redirects missing-redirects rm_file _redirects
variant no-feed missing-feed rm_file index.xml
variant no-site-feed missing-feed rm_file feed/index.xml
variant no-headers missing-headers rm_file _headers
variant no-llms missing-llms rm_file llms.txt
llms_set() { printf '%b' "$LLMS" >"$1/llms.txt"; }
LLMS='no heading\n\n> s\n- [a](https://test-blog.chiefgyk3d.com/)\n' variant llms-no-h1 bad-llms llms_set
LLMS='# t\n\n- [a](https://test-blog.chiefgyk3d.com/)\n' variant llms-no-summary bad-llms llms_set
LLMS='# t\n\n> s\n- [a](http://test-blog.chiefgyk3d.com/)\n' variant llms-http-link bad-llms llms_set
LLMS='# t\n\n> s\n- [a](https://elsewhere.example/)\n' variant llms-no-own-link bad-llms llms_set
LLMS='# t\n\n> s\n- [a](https://test-blog.chiefgyk3d.com/)\n<script>x</script>\n' variant llms-markup bad-llms llms_set
LLMS='# t\n\n> <script>x</script>\n- [a](https://test-blog.chiefgyk3d.com/)\n' variant llms-markup-in-summary bad-llms llms_set
LLMS='# t\n\n> s\nno links here\n' variant llms-no-links bad-llms llms_set

no_alias() { printf '# generated\n' >"$1/_redirects"; }
variant no-alias missing-alias no_alias

wrong_status() { printf '/2023/02/10/sample-post/ /posts/sample-post/ 302\n' >"$1/_redirects"; }
variant wrong-status missing-alias wrong_status

no_html_alias() { sed -i '/sample-post.html/d' "$1/_redirects"; }
variant html-alias-missing missing-alias no_html_alias

no_slash_variant() { sed -i '\#^/2023/02/10/sample-post/ #d' "$1/_redirects"; }
variant slash-variant-missing missing-alias no_slash_variant

# CSP: script-src must be exactly 'self'. 'none' is rejected too (the header and
# the template must not drift apart once the copy script ships).
set_script_src() { sed -i "s#script-src 'self'#script-src ${SRC}#" "$1/_headers"; }
SRC="'unsafe-inline'" variant weak-csp weak-csp set_script_src
SRC="'none'" variant csp-script-src-none weak-csp set_script_src
SRC="https:" variant csp-script-src-https weak-csp set_script_src
SRC="'self' https://cdn.example.org" variant csp-script-src-host weak-csp set_script_src
SRC="*" variant csp-script-src-star weak-csp set_script_src
SRC="'self' data:" variant csp-script-src-data weak-csp set_script_src
SRC="'self' blob:" variant csp-script-src-blob weak-csp set_script_src
SRC="'self' 'unsafe-eval'" variant csp-script-src-eval weak-csp set_script_src
SRC="'self' 'nonce-abc'" variant csp-script-src-nonce weak-csp set_script_src
SRC="'self' 'strict-dynamic'" variant csp-script-src-strict-dynamic weak-csp set_script_src
SRC="'self' http://example.org" variant csp-script-src-http weak-csp set_script_src
csp_no_script_src() { sed -i "s#; script-src 'self'##" "$1/_headers"; }
variant csp-without-script-src weak-csp csp_no_script_src
csp_two_script_src() { sed -i "s#script-src 'self'#script-src 'self'; script-src 'self'#" "$1/_headers"; }
variant csp-two-script-src weak-csp csp_two_script_src
csp_script_src_elem() { sed -i "s#script-src 'self'#script-src 'self'; script-src-elem https:#" "$1/_headers"; }
variant csp-script-src-elem weak-csp csp_script_src_elem
csp_script_src_attr() { sed -i "s#script-src 'self'#script-src 'self'; script-src-attr 'unsafe-hashes'#" "$1/_headers"; }
variant csp-script-src-attr weak-csp csp_script_src_attr
# Cloudflare Web Analytics (issue 159): the policy carries exactly the beacon URL in
# script-src and 'self' in connect-src, nothing wider, and the built HTML still
# rejects a third-party script tag (the beacon is injected at the edge).
csp_no_connect() { sed -i "s#; connect-src 'self'##" "$1/_headers"; }
variant csp-without-connect-src weak-csp csp_no_connect
csp_wide_connect() { sed -i "s#connect-src 'self'#connect-src 'self' https:#" "$1/_headers"; }
variant csp-wide-connect-src weak-csp csp_wide_connect
csp_connect_other() { sed -i "s#connect-src 'self'#connect-src https://cloudflareinsights.com#" "$1/_headers"; }
variant csp-other-connect-src weak-csp csp_connect_other
csp_beacon_origin() { sed -i "s#static.cloudflareinsights.com/beacon.min.js#static.cloudflareinsights.com#" "$1/_headers"; }
variant csp-beacon-origin-only weak-csp csp_beacon_origin
csp_beacon_wild() { sed -i "s#static.cloudflareinsights.com/beacon.min.js#*.cloudflareinsights.com/beacon.min.js#" "$1/_headers"; }
variant csp-beacon-wildcard weak-csp csp_beacon_wild
csp_beacon_twice() { sed -i "s#script-src 'self' \(https://static.cloudflareinsights.com/beacon.min.js\)#script-src 'self' \1 \1#" "$1/_headers"; }
variant csp-beacon-twice weak-csp csp_beacon_twice
APPEND='<script src=https://static.cloudflareinsights.com/beacon.min.js></script>' variant beacon-script-in-html script-not-allowed append_html
csp_no_manifest_src() { sed -i "s#manifest-src 'self'; ##" "$1/_headers"; }
variant csp-without-manifest-src weak-csp csp_no_manifest_src
csp_default_open() { sed -i "s#default-src 'none'#default-src 'self'#" "$1/_headers"; }
variant csp-default-src-self weak-csp csp_default_open
csp_second_line() { printf '/other/*\n  Content-Security-Policy: default-src %s; script-src %s\n' "'none'" "'none'" >>"$1/_headers"; }
variant csp-second-block-weak weak-csp csp_second_line

# 'self' authorizes any same-origin response: only files of known non-script
# types may ship (plus /copy.js), and nosniff must be in the headers.
other_file() {
    mkdir -p "$(dirname "$1/$FILE")"
    printf 'x\n' >"$1/$FILE"
}
FILE=payload variant extensionless-file unexpected-file other_file
FILE=posts/sample-post/payload variant nested-extensionless-file unexpected-file other_file
FILE=data.json variant unlisted-extension unexpected-file other_file
FILE=.hidden variant dotfile unexpected-file other_file
FILE=page.html.php variant double-extension unexpected-file other_file
# The script is accepted only by hash: unpinned, changed after pinning, or with
# a malformed hash file it fails; with no hash file no script element passes.
# Each pinned script has its own hash file: drift in one fails that script only.
no_hash_file_with_script() {
    place "$1" "$NAME"
    rm -f "$SCRIPT_HASH_DIR/$NAME.sha256"
}
NAME=copy.js variant copy-without-hash-file script-not-allowed no_hash_file_with_script
NAME=copy.js variant copy-file-without-hash-file extra-script-file no_hash_file_with_script
NAME=search.js variant search-without-hash-file script-not-allowed no_hash_file_with_script
NAME=search.js variant search-file-without-hash-file extra-script-file no_hash_file_with_script
only_other_pinned() {
    place "$1" search.js
    rm -f "$SCRIPT_HASH_DIR/search.js.sha256"
    printf '%s  copy.js\n' "$(printf 'a%.0s' $(seq 1 64))" >"$SCRIPT_HASH_DIR/copy.js.sha256"
}
variant search-with-only-copys-hash-file script-not-allowed only_other_pinned
js_changed() {
    place "$1" "$NAME"
    printf '%s\n' "/\"/;eval('x');//\"" >"$1/$NAME"
}
NAME=copy.js variant copy-changed-after-pinning script-hash js_changed
NAME=search.js variant search-changed-after-pinning script-hash js_changed
swapped_hashes() {
    both_pinned "$1"
    cp "$SCRIPT_HASH_DIR/copy.js.sha256" "$work/copy-hash"
    printf '%s  search.js\n' "$(cut -d' ' -f1 "$work/copy-hash")" >"$SCRIPT_HASH_DIR/search.js.sha256"
}
variant search-pinned-to-copys-hash script-hash swapped_hashes
bad_hash_file() {
    place "$1" "$NAME"
    printf 'not a hash\n' >"$SCRIPT_HASH_DIR/$NAME.sha256"
}
NAME=copy.js variant copy-malformed-hash-file script-hash-file bad_hash_file
NAME=search.js variant search-malformed-hash-file script-hash-file bad_hash_file
wrong_name_in_hash_file() {
    place "$1" search.js
    printf '%s  copy.js\n' "$(sha256sum "$1/search.js" | cut -d' ' -f1)" >"$SCRIPT_HASH_DIR/search.js.sha256"
}
variant search-hash-file-names-another-script script-hash-file wrong_name_in_hash_file
svg_script() {
    printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg"><script>x</script></svg>' >"$1/logo.svg"
}
variant svg-with-script script-in-markup svg_script
no_nosniff() { sed -i '/X-Content-Type-Options/d' "$1/_headers"; }
variant headers-without-nosniff missing-nosniff no_nosniff
dup_nosniff() { printf '  X-Content-Type-Options: sniff\n' >>"$1/_headers"; }
variant headers-conflicting-nosniff missing-nosniff dup_nosniff
dup_nosniff_same() { printf '  x-content-type-options: nosniff\n' >>"$1/_headers"; }
variant headers-duplicate-nosniff missing-nosniff dup_nosniff_same
headers_extra() { printf '%b' "$EXTRA" >>"$1/_headers"; }
EXTRA='/admin/*\n  ! X-Content-Type-Options\n' variant headers-removal-nosniff headers-structure headers_extra
EXTRA='/admin/*\n  ! Content-Security-Policy\n' variant headers-removal-policy headers-structure headers_extra
EXTRA='/admin/*\n\t! X-Content-Type-Options\n' variant headers-removal-tab headers-structure headers_extra
EXTRA='  ! Referrer-Policy\n' variant headers-removal-first-block headers-structure headers_extra
EXTRA='/other/*\n  Referrer-Policy: no-referrer\n' variant headers-second-block headers-structure headers_extra
EXTRA='/api/*\n  X-Content-Type-Options: sniff\n' variant headers-path-override-nosniff headers-structure headers_extra
EXTRA="/api/*\\n  Content-Security-Policy: default-src 'none'; script-src 'self'\\n" variant headers-path-override-policy headers-structure headers_extra

# Environment rules. The good fixture is a production tree (robots.txt allows
# all and names the sitemap; pages carry no noindex).
robots_staging() { printf 'User-agent: *\nDisallow: /\n' >"$1/robots.txt"; }
add_noindex() { sed -i 's#<head>#<head><meta name=robots content="noindex, nofollow">#' "$1/index.html" "$1/posts/sample-post/index.html" "$1/404.html" "$1/posts/index.html" "$1/tags/lorem/index.html" "$1/journal/index.html" "$1/support/index.html" "$1/search/index.html"; }
staging_tree() {
    robots_staging "$1"
    add_noindex "$1"
}

variant no-robots missing-robots rm_file robots.txt
variant staging-robots-in-production-pages noindex-mismatch robots_staging
variant noindex-in-production-pages noindex-mismatch add_noindex
only_one_noindex() {
    robots_staging "$1"
    sed -i 's#<head>#<head><meta name=robots content="noindex, nofollow">#' "$1/index.html"
}
variant staging-page-without-noindex noindex-mismatch only_one_noindex
no_sitemap_line() { printf 'User-agent: *\nAllow: /\n' >"$1/robots.txt"; }
variant production-robots-without-sitemap bad-robots no_sitemap_line
sitemap_in_staging() {
    staging_tree "$1"
    printf 'Sitemap: https://test-blog.chiefgyk3d.com/sitemap.xml\n' >>"$1/robots.txt"
}
variant staging-robots-names-sitemap bad-robots sitemap_in_staging
empty_robots() { : >"$1/robots.txt"; }
variant empty-robots missing-robots empty_robots
foreign_sitemap() { printf 'User-agent: *\nAllow: /\nSitemap: https://example.org/sitemap.xml\n' >"$1/robots.txt"; }
variant sitemap-on-another-host bad-robots foreign_sitemap

# The robots policy is the wildcard group's. A rule under another crawler's
# group, or before any User-agent line, says nothing about everyone else.
host=https://test-blog.chiefgyk3d.com
robots_file() { printf '%b' "$ROBOTS" >"$1/robots.txt"; }
ROBOTS='User-agent: Googlebot\nDisallow: /\n' variant robots-named-crawler-only bad-robots robots_file
ROBOTS='Disallow: /\n' variant robots-disallow-before-user-agent bad-robots robots_file
ROBOTS='User-agent: *\nDisallow: /\nAllow: /private\n' variant robots-wildcard-disallow-allow-reopens bad-robots robots_file
ROBOTS="User-agent: Googlebot\nDisallow: /\n\nSitemap: $host/sitemap.xml\n" variant robots-production-named-crawler-only bad-robots robots_file
ROBOTS="User-agent: *\nDisallow: /drafts/\n\nSitemap: $host/sitemap.xml\n" variant robots-production-wildcard-partial-disallow bad-robots robots_file
# Comments, CRLF line endings and a second group for another crawler are fine.
d="$work/robots-ok"
make_good "$d"
printf 'User-agent: Googlebot\r\nDisallow: /nothing-here/ # a named crawler\r\n\r\n# everyone else\r\nUser-agent: *\r\nAllow: /\r\n\r\nSitemap: %s/sitemap.xml\r\n' "$host" >"$d/robots.txt"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: production robots with comments, CRLF and a named-crawler group passes"
else
    echo "FAIL: production robots with comments, CRLF and a named-crawler group was rejected"
    failures=$((failures + 1))
fi
d="$work/robots-stg-ok"
make_good "$d"
staging_tree "$d"
printf 'User-agent: Googlebot\nUser-agent: *\nDisallow: /\n' >"$d/robots.txt"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: staging robots with a shared User-agent group passes"
else
    echo "FAIL: staging robots with a shared User-agent group was rejected"
    failures=$((failures + 1))
fi

# A consistent staging tree passes, and EXPECT_ENV pins which environment a
# build must be: a staging tree fails when production is expected, and back.
d="$work/staging-ok"
make_good "$d"
staging_tree "$d"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: consistent staging tree passes"
else
    echo "FAIL: consistent staging tree was rejected"
    failures=$((failures + 1))
fi
EXPECT_ENV=staging expect_fail expect-staging-got-production env-mismatch "$good"
EXPECT_ENV=production expect_fail expect-production-got-staging env-mismatch "$d"
if EXPECT_ENV=staging "$checker" "$d" >/dev/null 2>&1 && EXPECT_ENV=production "$checker" "$good" >/dev/null 2>&1; then
    echo "ok: EXPECT_ENV accepts the matching environment"
else
    echo "FAIL: EXPECT_ENV rejected the matching environment"
    failures=$((failures + 1))
fi
EXPECT_ENV=bogus expect_fail bad-expect-env env-mismatch "$good"

# Head tags (issue 30): required on the home page and on every post and journal
# entry; each one removed in turn must be reported by name.
drop_tag() { sed -i -E "s#<(meta|link)[^>]*${TAG}[^>]*>##" "$1/$PAGE"; }
for tag in 'name=description' 'rel=canonical' 'rel=icon' 'rel=apple-touch-icon' 'property=og:title' 'property=og:description' 'property=og:type' 'property=og:url' 'property=og:image ' 'property=og:site_name' 'name=twitter:card' 'name=theme-color' 'name=twitter:image' 'rel=manifest'; do
    TAG="$tag" PAGE=index.html variant "home-without-${tag//[^a-z:]/}" missing-head-tag drop_tag
    TAG="$tag" PAGE=posts/sample-post/index.html variant "post-without-${tag//[^a-z:]/}" missing-head-tag drop_tag
done
# Both rel=icon links are required: dropping only the PNG one must fail too.
drop_png_icon() { sed -i -E 's#<link rel=icon href=/brand/penguin-color.png[^>]*>##' "$1/$PAGE"; }
PAGE=index.html variant home-without-png-icon missing-head-tag drop_png_icon
PAGE=posts/sample-post/index.html variant post-without-png-icon missing-head-tag drop_png_icon
TAG='property=article:published_time' PAGE=posts/sample-post/index.html variant post-without-published-time missing-head-tag drop_tag
relative_og_image() { sed -i -E 's#(property=og:image content=)https://test-blog.chiefgyk3d.com#\1#' "$1/index.html"; }
variant relative-og-image bad-head-value relative_og_image
relative_twitter_image() { sed -i -E 's#(name=twitter:image content=)https://test-blog.chiefgyk3d.com#\1#' "$1/index.html"; }
variant relative-twitter-image bad-head-value relative_twitter_image
foreign_og_url() { sed -i -E 's#(property=og:url content=)https://test-blog.chiefgyk3d.com#\1https://example.org#' "$1/index.html"; }
variant foreign-og-url bad-head-value foreign_og_url
home_as_article() { sed -i 's#property=og:type content=website#property=og:type content=article#' "$1/index.html"; }
variant home-typed-article bad-head-value home_as_article
post_as_website() { sed -i 's#property=og:type content=article#property=og:type content=website#' "$1/posts/sample-post/index.html"; }
variant post-typed-website bad-head-value post_as_website

# SEO (issue 64). A JSON-LD data block is the one inline script-element form
# allowed; everything else about script elements is unchanged.
d="$work/ld-extra-block-ok"
make_good "$d"
sed -i 's#</head>#<script type=application/ld+json>{"@context":"https://schema.org","@type":"Thing","name":"x"}</script></head>#' "$d/index.html"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: an extra valid JSON-LD block passes"
else
    echo "FAIL: an extra valid JSON-LD block was rejected"
    failures=$((failures + 1))
fi
home_edit() { sed -i "s#${FROM}#${TO}#" "$1/index.html"; }
post_edit() { sed -i "s#${FROM}#${TO}#" "$1/posts/sample-post/index.html"; }
FROM='<script type=application/ld+json>' TO='<script type=application/ld+json src=/x.js>' variant ld-block-with-src script-not-allowed home_edit
FROM='<script type=application/ld+json>' TO='<script type=text/javascript>' variant ld-type-swapped-to-javascript script-not-allowed home_edit
FROM='<script type=application/ld+json>' TO='<script type=application/ld+json defer>' variant ld-block-extra-attribute script-not-allowed home_edit
FROM='"@graph":\[' TO='alert(1);"@graph":[' variant ld-block-not-json bad-jsonld home_edit
FROM='"name":"ChiefGyk3D"' TO='"name":"Somebody Else"' variant ld-person-wrong-name bad-jsonld home_edit
FROM='"name":"ChiefGyk3D"' TO='"name":"ChiefGyk3D","worksFor":{"name":"Corp"}' variant ld-person-employer bad-jsonld home_edit
FROM='"name":"ChiefGyk3D"' TO='"name":"ChiefGyk3D","givenName":"First"' variant ld-person-first-name bad-jsonld home_edit
FROM='https://github.com/ChiefGyk3D' TO='http://github.com/ChiefGyk3D' variant ld-sameas-not-https bad-jsonld home_edit
FROM='https://schema.org' TO='https://example.org/vocab' variant ld-wrong-context bad-jsonld home_edit
FROM='"@type":"Person"' TO='"@type":"Organization"' variant ld-home-without-person bad-jsonld home_edit
FROM='"@type":"Article"' TO='"@type":"Thing"' variant ld-post-without-article bad-jsonld post_edit
FROM='"headline":"Sample post",' TO='' variant ld-article-without-headline bad-jsonld post_edit
FROM='"datePublished":"2023-02-10T09:00:00-05:00",' TO='' variant ld-article-without-date bad-jsonld post_edit
FROM='"author":{"@type":"Person","name":"ChiefGyk3D"}' TO='"author":{"@type":"Person","name":"Other"}' variant ld-article-wrong-author bad-jsonld post_edit
drop_ld() { sed -i -E 's#<script type=application/ld\+json>[^<]*</script>##' "$1/$PAGE"; }
PAGE=index.html variant home-without-jsonld bad-jsonld drop_ld
PAGE=posts/sample-post/index.html variant post-without-jsonld bad-jsonld drop_ld
FROM='content=summary_large_image' TO='content=summary' variant twitter-card-summary bad-head-value home_edit

# The 404 is noindex in production; the other pages are not.
no404_noindex() { sed -i 's#<meta name=robots content=noindex>##' "$1/404.html"; }
variant production-404-without-noindex noindex-mismatch no404_noindex

# Sitemap: present, parsed, on the site host, lastmod on every url, no alias
# stub, no url that has no page, no noindex page.
variant missing-sitemap missing-sitemap rm_file sitemap.xml
sitemap_edit() { sed -i "s#${FROM}#${TO}#" "$1/sitemap.xml"; }
FROM='<lastmod>2023-02-10T09:00:00-05:00</lastmod></url><url>' TO='</url><url>' variant sitemap-url-without-lastmod bad-sitemap sitemap_edit
FROM='</urlset>' TO='<url><loc>https://test-blog.chiefgyk3d.com/2023/02/10/sample-post/</loc><lastmod>2023-02-10T09:00:00-05:00</lastmod></url></urlset>' variant sitemap-lists-alias-stub bad-sitemap sitemap_edit
FROM='</urlset>' TO='<url><loc>https://test-blog.chiefgyk3d.com/404.html</loc><lastmod>2023-02-10T09:00:00-05:00</lastmod></url></urlset>' variant sitemap-lists-404 bad-sitemap sitemap_edit
FROM='</urlset>' TO='<url><loc>https://test-blog.chiefgyk3d.com/gone/</loc><lastmod>2023-02-10T09:00:00-05:00</lastmod></url></urlset>' variant sitemap-lists-missing-page bad-sitemap sitemap_edit
FROM='https://test-blog.chiefgyk3d.com/posts/sample-post/' TO='https://example.org/posts/sample-post/' variant sitemap-foreign-host bad-sitemap sitemap_edit
FROM='</urlset>' TO='' variant sitemap-not-xml bad-sitemap sitemap_edit
FROM='<url><loc>https://test-blog.chiefgyk3d.com/posts/sample-post/</loc><lastmod>2023-02-10T09:00:00-05:00</lastmod></url>' TO='' variant sitemap-without-the-post bad-sitemap sitemap_edit

# Feed: the self-hosted atom link.
feed_edit() { sed -i "s#${FROM}#${TO}#" "$1/index.xml"; }
FROM='rel="self"' TO='rel="alternate"' variant feed-without-self-link bad-feed feed_edit
FROM='https://test-blog.chiefgyk3d.com/index.xml' TO='https://example.org/index.xml' variant feed-self-link-foreign-host bad-feed feed_edit
site_feed_edit() { sed -i "s#${FROM}#${TO}#" "$1/feed/index.xml"; }
FROM='https://test-blog.chiefgyk3d.com/feed/index.xml' TO='https://test-blog.chiefgyk3d.com/index.xml' variant site-feed-self-link-not-feed bad-feed site_feed_edit
FROM='rel="self"' TO='rel="alternate"' variant site-feed-without-self-link bad-feed site_feed_edit
FROM='<rss' TO='<!DOCTYPE rss [<!ENTITY e "x">]><rss' variant feed-with-doctype bad-feed feed_edit
FROM='<urlset' TO='<!DOCTYPE urlset [<!ENTITY e "x">]><urlset' variant sitemap-with-doctype bad-sitemap sitemap_edit

# One description per page.
dup_desc() { sed -i 's#Post description\.#Home description.#g' "$1/posts/sample-post/index.html"; }
variant duplicate-description duplicate-description dup_desc

# Templates (issues 58 and 59): home hero, 404, archive and post elements. Each
# required piece removed in turn must be reported by name.
cut_text() { sed -i "s#${CUT}##g" "$1/$PAGE"; }
for pair in 'index.html|Read the latest' 'index.html|Find me online' 'index.html|Support my work' 'index.html|Latest posts' 'index.html|All posts' 'index.html|See my projects' 'index.html|building next' 'index.html|Senior Cybersecurity Engineer' \
    '404.html|rm -rf' '404.html|Start over' '404.html|Browse posts' '404.html|Search the site' '404.html|Find me online' '404.html|refusing to answer questions' \
    'posts/index.html|archive-year' 'posts/index.html|index.xml' 'tags/lorem/index.html|archive-year' 'journal/index.html|archive-year' \
    'posts/sample-post/index.html|reading-time' 'posts/sample-post/index.html|<time'; do
    page="${pair%%|*}"
    cut="${pair#*|}"
    PAGE="$page" CUT="$cut" variant "cut-${page//\//-}-${cut//[^a-zA-Z-]/}" template-element cut_text
done
drop_mascot_size() { sed -i -E 's# width=256 height=256##' "$1/$PAGE"; }
PAGE=index.html variant home-mascot-without-size template-element drop_mascot_size
PAGE=404.html variant 404-mascot-without-size template-element drop_mascot_size
drop_mascot() { sed -i -E 's#<img class=hero-mascot[^>]*>##' "$1/index.html"; }
variant home-without-mascot template-element drop_mascot
drop_404() { rm -f "$1/404.html"; }
variant missing-404 template-element drop_404
drop_archive() { rm -f "$1/posts/index.html"; }
variant missing-posts-archive template-element drop_archive

# email-shaped-text: a user@host handle in page text is rewritten by Cloudflare
# Email Obfuscation (and a script injected). The split form must pass.
APPEND='<p>@someone@social.example.org</p>' variant email-shaped-handle email-shaped-text append_html
APPEND='<p>mail me at a.b@example.org</p>' variant email-shaped-address email-shaped-text append_html
APPEND='<a href="mailto:a@example.org">mail</a>' variant mailto-link email-shaped-text append_html
# An archived comment (issue 121) is page text like any other: an address or a
# mailto: link in the comments section is caught, and a clean one passes.
COMMENT_OPEN='<section class="comments-archive" aria-labelledby="comments-archive-title"><h2 id="comments-archive-title">Comments from the old site</h2><figure class="comment"><blockquote><p>Nice post.</p></blockquote><figcaption><span>Name</span>, <time datetime="2023-01-02">January 2, 2023</time>'
APPEND="${COMMENT_OPEN} a.b@example.org</figcaption></figure></section>" PAGE=posts/sample-post/index.html variant comment-email email-shaped-text append_html
APPEND="${COMMENT_OPEN} <a href=\"mailto:a@example.org\">mail</a></figcaption></figure></section>" PAGE=posts/sample-post/index.html variant comment-mailto email-shaped-text append_html
comment_ok="$work/comment-ok"
make_good "$comment_ok"
printf '%s\n' "${COMMENT_OPEN}</figcaption></figure></section>" >>"$comment_ok/posts/sample-post/index.html"
if "$checker" "$comment_ok" >/dev/null 2>&1; then
    echo "ok: a clean archived comment passes"
else
    echo "FAIL: a clean archived comment was rejected"
    failures=$((failures + 1))
fi
split="$work/split-handle"
make_good "$split"
printf '%s\n' '<p>@someone<span>@</span>social.example.org <a href=https://youtube.com/@Chan>@Chan</a></p>' >>"$split/index.html"
if "$checker" "$split" >/dev/null 2>&1; then
    echo "ok: split handle passes"
else
    echo "FAIL: split handle was rejected"
    "$checker" "$split" || true
    failures=$((failures + 1))
fi

if [[ -f "$root/public/index.html" ]]; then
    if env -u SCRIPT_HASH_DIR "$checker" "$root/public" >/dev/null 2>&1; then
        echo "ok: real build in public/ passes"
    else
        echo "FAIL: real build in public/ was rejected"
        env -u SCRIPT_HASH_DIR "$checker" "$root/public" || true
        failures=$((failures + 1))
    fi
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checker tests passed"
