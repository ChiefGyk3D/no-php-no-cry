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
# The pinned hash of the one allowed script is a committed file; tests use their
# own, absent unless a case pins it.
export THEME_HASH_FILE="$work/theme.sha256"
pin_dir() { printf '%s  theme.js\n' "$(sha256sum "$1/theme.js" | cut -d' ' -f1)" >"$THEME_HASH_FILE"; }

make_good() {
    local dir="$1"
    rm -f "$THEME_HASH_FILE"
    rm -rf "$dir"
    mkdir -p "$dir/posts/sample-post"
    # Heads as Hugo's minifier writes them (attribute quotes dropped where legal).
    # Home is a website page; a post is an article with a published time.
    local common='<meta name=description content="A description."><meta name=twitter:card content=summary><meta property=og:site_name content=t><meta property=og:title content=t><meta property=og:description content="A description."><meta property=og:image content=https://test-blog.chiefgyk3d.com/brand/penguin-color.png><link rel=icon href=/brand/penguin-glyph.svg type=image/svg+xml><link rel=icon href=/brand/penguin-color.png type=image/png sizes=512x512><link rel=apple-touch-icon href=/brand/penguin-color.png><link rel=stylesheet href=/css/site.min.css integrity=sha256-AAAA>'
    printf '%s\n' "<!doctype html><html lang=en-us><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><title>t</title>${common}<meta property=og:type content=website><meta property=og:url content=https://test-blog.chiefgyk3d.com/><link rel=canonical href=https://test-blog.chiefgyk3d.com/></head><body><a href=https://example.org/outbound>outbound links are fine</a><img src=/posts/sample-post/a.png width=1 height=1 alt=x></body></html>" >"$dir/index.html"
    printf '%s\n' "<!doctype html><html lang=en-us><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><title>t</title>${common}<meta property=og:type content=article><meta property=article:published_time content=2023-02-10T09:00:00-05:00><meta property=og:url content=https://test-blog.chiefgyk3d.com/posts/sample-post/><link rel=canonical href=https://test-blog.chiefgyk3d.com/posts/sample-post/></head><body><a href=https://example.org/outbound>outbound links are fine</a><img src=/posts/sample-post/a.png width=1 height=1 alt=x></body></html>" >"$dir/posts/sample-post/index.html"
    # Hugo's meta-refresh alias pages: one directory-style, one ending in .html.
    mkdir -p "$dir/2023/02/10/sample-post" "$dir/css"
    alias_page='<!doctype html><html lang=en-us><head><title>https://test-blog.chiefgyk3d.com/posts/sample-post/</title><link rel=canonical href=https://test-blog.chiefgyk3d.com/posts/sample-post/><meta name=robots content=noindex><meta http-equiv=refresh content="0; url=https://test-blog.chiefgyk3d.com/posts/sample-post/"></head></html>'
    printf '%s\n' "$alias_page" >"$dir/2023/02/10/sample-post/index.html"
    printf '%s\n' "$alias_page" >"$dir/sample-post.html"
    printf 'body{background:url(data:image/png;base64,AAAA);color:red}\n' >"$dir/css/site.min.css"
    printf '<?xml version="1.0"?><rss version="2.0"></rss>\n' >"$dir/index.xml"
    printf 'User-agent: *\nAllow: /\n\nSitemap: https://test-blog.chiefgyk3d.com/sitemap.xml\n' >"$dir/robots.txt"
    cat >"$dir/_redirects" <<'RED'
# generated
/2023/02/10/sample-post /posts/sample-post/ 301
/2023/02/10/sample-post/ /posts/sample-post/ 301
/sample-post.html /posts/sample-post/ 301
RED
    cat >"$dir/_headers" <<'HDR'
/*
  Content-Security-Policy: default-src 'none'; img-src 'self'; style-src 'self'; script-src 'self'
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

append_html() { printf '%s\n' "$APPEND" >>"$1/index.html"; }

APPEND='<script>alert(1)</script>' variant inline-script inline-script append_html
APPEND='<style>body{color:red}</style>' variant style-element style-element append_html
APPEND='<p style="color:red">x</p>' variant style-attribute style-attribute append_html
APPEND='<pre><code>x</code></pre>' variant pre-not-focusable pre-not-focusable append_html
APPEND='<button onclick="go()">x</button>' variant event-handler event-handler append_html
APPEND='<img src="http://example.org/a.png" alt=x>' variant http-reference http-reference append_html
APPEND='<link rel=stylesheet href=https://fonts.example.org/css>' variant external-asset external-asset append_html
APPEND='<script src=https://cdn.example.org/x.js></script>' variant external-script external-asset append_html
APPEND='<script src=https://cdn.example.org/x.js></script>' variant external-script-element script-not-allowed append_html
APPEND='<script src=//cdn.example.org/x.js></script>' variant scheme-relative-script script-not-allowed append_html
APPEND='<script src=/app.js></script>' variant local-other-script script-not-allowed append_html
APPEND='<script>alert(1)</script>' variant inline-script-element script-not-allowed append_html
APPEND='<script src=/theme.js>alert(1)</script>' variant theme-script-with-inline-body script-not-allowed append_html
APPEND='<script src=/theme.js defer></script>' variant theme-script-extra-attribute script-not-allowed append_html
APPEND='<script type=module src=/theme.js></script>' variant theme-script-module script-not-allowed append_html
APPEND='<script src=data:text/javascript,alert(1)></script>' variant data-url-script script-not-allowed append_html
APPEND='<script src=/theme.js></script><script src=/theme.js></script>' variant theme-script-twice script-count append_html
APPEND='<script src=/theme.js></script><script src=/other.js></script>' variant second-script-file script-not-allowed append_html
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

# The one allowed script: <script src=/theme.js></script> (as the minifier writes
# it, or with quotes) with a small theme.js. It is allowed once, in any page.
with_theme() {
    printf '%s\n' "$APPEND" >>"$1/index.html"
    printf '%s\n' "$THEME_JS" >"$1/theme.js"
    pin_dir "$1"
}
THEME_JS='document.documentElement.dataset.theme="dark"'
for form in '<script src=/theme.js></script>' '<script src="/theme.js"></script>' "<script src='/theme.js'></script>" '<SCRIPT SRC=/theme.js></SCRIPT>'; do
    d="$work/theme-ok"
    make_good "$d"
    APPEND="$form" THEME_JS="$THEME_JS" with_theme "$d"
    if "$checker" "$d" >/dev/null 2>&1; then
        echo "ok: the theme script is allowed ($form)"
    else
        echo "FAIL: the theme script was rejected ($form)"
        "$checker" "$d" || true
        failures=$((failures + 1))
    fi
done

# The page references /theme.js but the file is not in the build.
theme_missing() {
    printf '%s\n' '<script src=/theme.js></script>' >>"$1/index.html"
    printf '%s  theme.js\n' "$(printf 'a%.0s' $(seq 1 64))" >"$THEME_HASH_FILE"
}
variant theme-script-file-missing missing-script theme_missing

# Script files: only /theme.js, under 1 KB gzip (brief section 10).
good_theme() {
    printf '%s\n' '<script src=/theme.js></script>' >>"$1/index.html"
    printf '%s\n' "$THEME_JS" >"$1/theme.js"
    pin_dir "$1"
}
extra_js() {
    good_theme "$1"
    mkdir -p "$(dirname "$1/$FILE")"
    printf 'x\n' >"$1/$FILE"
}
FILE=app.js variant extra-js-file extra-script-file extra_js
FILE=js/other.js variant nested-js-file extra-script-file extra_js
FILE=other.mjs variant extra-mjs-file extra-script-file extra_js
FILE=Other.JS variant extra-uppercase-js-file extra-script-file extra_js
FILE=js/theme.js variant theme-js-in-subdirectory extra-script-file extra_js
js_only_file() { printf 'x\n' >"$1/app.js"; }
variant js-file-without-page-reference extra-script-file js_only_file
# 4 KB of incompressible bytes is over the gzip budget; a 1 KB compressible
# file is not.
big_theme() {
    good_theme "$1"
    head -c 4096 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$1/theme.js"
    pin_dir "$1"
}
variant theme-js-over-budget js-budget big_theme
d="$work/theme-compressible"
make_good "$d"
good_theme "$d"
for _ in $(seq 1 1024); do printf 'var a=1;'; done >"$d/theme.js"
pin_dir "$d"
if "$checker" "$d" >/dev/null 2>&1; then
    echo "ok: a theme.js that is large raw but under 1 KB gzip passes"
else
    echo "FAIL: a compressible theme.js under 1 KB gzip was rejected"
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
variant no-headers missing-headers rm_file _headers

no_alias() { printf '# generated\n' >"$1/_redirects"; }
variant no-alias missing-alias no_alias

wrong_status() { printf '/2023/02/10/sample-post/ /posts/sample-post/ 302\n' >"$1/_redirects"; }
variant wrong-status missing-alias wrong_status

no_html_alias() { sed -i '/sample-post.html/d' "$1/_redirects"; }
variant html-alias-missing missing-alias no_html_alias

no_slash_variant() { sed -i '\#^/2023/02/10/sample-post/ #d' "$1/_redirects"; }
variant slash-variant-missing missing-alias no_slash_variant

# CSP: script-src must be exactly 'self'. 'none' is rejected too (the header and
# the template must not drift apart once the theme script ships).
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
csp_default_open() { sed -i "s#default-src 'none'#default-src 'self'#" "$1/_headers"; }
variant csp-default-src-self weak-csp csp_default_open
csp_second_line() { printf '/other/*\n  Content-Security-Policy: default-src %s; script-src %s\n' "'none'" "'none'" >>"$1/_headers"; }
variant csp-second-block-weak weak-csp csp_second_line

# 'self' authorizes any same-origin response: only files of known non-script
# types may ship (plus /theme.js), and nosniff must be in the headers.
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
no_hash_file() { rm -f "$THEME_HASH_FILE"; }
no_hash_file_with_script() {
    good_theme "$1"
    no_hash_file
}
variant theme-without-hash-file script-not-allowed no_hash_file_with_script
variant theme-file-without-hash-file extra-script-file no_hash_file_with_script
theme_changed() {
    good_theme "$1"
    printf '%s\n' "/\"/;eval('x');//\"" >"$1/theme.js"
}
variant theme-changed-after-pinning theme-hash theme_changed
theme_bad_hash_file() {
    good_theme "$1"
    printf 'not a hash\n' >"$THEME_HASH_FILE"
}
variant theme-malformed-hash-file theme-hash-file theme_bad_hash_file
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
add_noindex() { sed -i 's#<head>#<head><meta name=robots content="noindex, nofollow">#' "$1/index.html" "$1/posts/sample-post/index.html"; }
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
for tag in 'name=description' 'rel=canonical' 'rel=icon' 'rel=apple-touch-icon' 'property=og:title' 'property=og:description' 'property=og:type' 'property=og:url' 'property=og:image ' 'property=og:site_name' 'name=twitter:card'; do
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
foreign_og_url() { sed -i -E 's#(property=og:url content=)https://test-blog.chiefgyk3d.com#\1https://example.org#' "$1/index.html"; }
variant foreign-og-url bad-head-value foreign_og_url
home_as_article() { sed -i 's#property=og:type content=website#property=og:type content=article#' "$1/index.html"; }
variant home-typed-article bad-head-value home_as_article
post_as_website() { sed -i 's#property=og:type content=article#property=og:type content=website#' "$1/posts/sample-post/index.html"; }
variant post-typed-website bad-head-value post_as_website

if [[ -f "$root/public/index.html" ]]; then
    if "$checker" "$root/public" >/dev/null 2>&1; then
        echo "ok: real build in public/ passes"
    else
        echo "FAIL: real build in public/ was rejected"
        "$checker" "$root/public" || true
        failures=$((failures + 1))
    fi
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checker tests passed"
