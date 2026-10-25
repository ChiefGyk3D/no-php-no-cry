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

make_good() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir/posts/sample-post"
    cat >"$dir/index.html" <<'HTML'
<!doctype html><html lang=en-us><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><title>t</title><link rel=canonical href=https://test-blog.chiefgyk3d.com/><link rel=stylesheet href=/css/site.min.css integrity=sha256-AAAA></head><body><a href=https://example.org/outbound>outbound links are fine</a><img src=/posts/sample-post/a.png width=1 height=1 alt=x></body></html>
HTML
    cp "$dir/index.html" "$dir/posts/sample-post/index.html"
    # Hugo's meta-refresh alias pages: one directory-style, one ending in .html.
    mkdir -p "$dir/2023/02/10/sample-post" "$dir/css"
    alias_page='<!doctype html><html lang=en-us><head><title>https://test-blog.chiefgyk3d.com/posts/sample-post/</title><link rel=canonical href=https://test-blog.chiefgyk3d.com/posts/sample-post/><meta name=robots content=noindex><meta http-equiv=refresh content="0; url=https://test-blog.chiefgyk3d.com/posts/sample-post/"></head></html>'
    printf '%s\n' "$alias_page" >"$dir/2023/02/10/sample-post/index.html"
    printf '%s\n' "$alias_page" >"$dir/sample-post.html"
    printf 'body{background:url(data:image/png;base64,AAAA);color:red}\n' >"$dir/css/site.min.css"
    printf '<?xml version="1.0"?><rss version="2.0"></rss>\n' >"$dir/index.xml"
    cat >"$dir/_redirects" <<'RED'
# generated
/2023/02/10/sample-post /posts/sample-post/ 301
/2023/02/10/sample-post/ /posts/sample-post/ 301
/sample-post.html /posts/sample-post/ 301
RED
    cat >"$dir/_headers" <<'HDR'
/*
  Content-Security-Policy: default-src 'none'; img-src 'self'; style-src 'self'; script-src 'none'
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
APPEND='<button onclick="go()">x</button>' variant event-handler event-handler append_html
APPEND='<img src="http://example.org/a.png" alt=x>' variant http-reference http-reference append_html
APPEND='<link rel=stylesheet href=https://fonts.example.org/css>' variant external-asset external-asset append_html
APPEND='<script src=https://cdn.example.org/x.js></script>' variant external-script external-asset append_html
APPEND='<script src=https://cdn.example.org/x.js></script>' variant external-script-element script-element-present append_html
APPEND='<script src=/app.js></script>' variant local-script script-element-present append_html
APPEND='<script>alert(1)</script>' variant inline-script-element script-element-present append_html

append_file() { printf '%s\n' "$APPEND" >>"$1/$FILE"; }
FILE=css/site.min.css APPEND='@import "https://fonts.example.org/css";' variant css-import external-css-reference append_file
FILE=css/site.min.css APPEND='@import url(//fonts.example.org/css);' variant css-import-scheme-relative external-css-reference append_file
FILE=css/site.min.css APPEND='a{background:url(https://cdn.example.org/a.png)}' variant css-url-https external-css-reference append_file
FILE=css/site.min.css APPEND='a{background:url("//cdn.example.org/a.png")}' variant css-url-scheme-relative external-css-reference append_file
FILE=css/site.min.css APPEND='a{background:url(http://cdn.example.org/a.png)}' variant css-url-http external-css-reference append_file
FILE=logo.svg APPEND='<svg xmlns="http://www.w3.org/2000/svg"><image href="https://cdn.example.org/a.png"/></svg>' variant svg-external external-css-reference append_file
FILE=index.xml APPEND='<?xml-stylesheet type="text/xsl" href="/feed.xsl"?>' variant feed-stylesheet xml-stylesheet append_file

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

weak_csp() { sed -i "s/script-src 'none'/script-src 'unsafe-inline'/" "$1/_headers"; }
variant weak-csp weak-csp weak_csp

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
