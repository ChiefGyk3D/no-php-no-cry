#!/usr/bin/env bash
# Test for scripts/verify-live.sh against a local fake server (no real network).
#
# scripts/test-verify-live-server.py serves a built site on 127.0.0.1 on an
# OS-chosen port, one server per mode. It serves (a) a small hand-made fixture
# and (b) the repository's real staging and production builds, with the real
# build's host rewritten to the server's. The good modes must pass; each
# fault mode must fail with its expected rule name, so every check has a
# negative case. The server is killed by PID in the exit trap.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verify="$root/scripts/verify-live.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/verify-live-test.XXXXXX")"
server_pid=""
stop_server() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=""
    fi
}
trap 'stop_server; rm -rf "$work"' EXIT

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

if ! command -v hugo >/dev/null 2>&1; then
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
fi

# --- fixture: a small built site ---------------------------------------------------
fx="$work/fixture"
mkdir -p "$fx/css" "$fx/about" "$fx/posts/sample-post" "$fx/posts"
csp="default-src 'none'; img-src 'self'; style-src 'self'; script-src 'self'"
printf '/*\n  Content-Security-Policy: %s\n  X-Content-Type-Options: nosniff\n  Strict-Transport-Security: max-age=31536000; includeSubDomains\n\n/css/*\n  Cache-Control: public, max-age=31536000, immutable\n' "$csp" >"$fx/_headers"
printf '# generated\n/old/ /posts/sample-post/ 301\n/old /posts/sample-post/ 301\n/contact /about/#contact 301\n/moved /about/ 302\n/old-tree/* /posts/ 301\n' >"$fx/_redirects"
page='<!doctype html><html><head><meta charset=utf-8><link rel=stylesheet href=/css/site.css><link rel=alternate type=application/rss+xml href=http://FX/index.xml><meta name=robots content="noindex, nofollow"></head><body>x</body></html>'
for p in index.html about/index.html posts/index.html posts/sample-post/index.html; do printf '%s' "$page" >"$fx/$p"; done
printf '<!doctype html><html><head><meta name=robots content="noindex"></head><body>404</body></html>' >"$fx/404.html"
printf 'body{color:#000}\n' >"$fx/css/site.css"
printf 'User-agent: *\nDisallow: /\n' >"$fx/robots.txt"
printf '<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>http://FX/</loc></url></urlset>' >"$fx/sitemap.xml"
printf '<?xml version="1.0"?><rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel><title>t</title><link>http://FX/</link><atom:link href="http://FX/index.xml" rel="self" type="application/rss+xml"/><item><title>i</title><link>http://FX/posts/sample-post/</link></item></channel></rss>' >"$fx/index.xml"
printf 'console.log(1)\n' >"$fx/copy.js"

# --- real builds, for the real _redirects, _headers and pages ------------------------
real_stg="$work/real-staging"
real_prod="$work/real-production"
HUGO_PARAMS_ENVIRONMENT=staging hugo --quiet --source "$root" --destination "$real_stg" >"$work/stg.log" 2>&1 || {
    echo "FAIL: staging build: $(tail -n 3 "$work/stg.log")"
    exit 1
}
hugo --quiet --source "$root" --destination "$real_prod" >"$work/prod.log" 2>&1 || {
    echo "FAIL: production build: $(tail -n 3 "$work/prod.log")"
    exit 1
}

# start_server <site-dir> <mode> [rewrite-from]: sets $port
start_server() {
    stop_server
    rm -f "$work/port"
    ROOT="$1" MODE="$2" REWRITE_FROM="${3:-}" PORTFILE="$work/port" python3 -I "$root/scripts/test-verify-live-server.py" &
    server_pid=$!
    for _ in $(seq 1 100); do
        [[ -s "$work/port" ]] && break
        sleep 0.1
    done
    [[ -s "$work/port" ]] || {
        echo "FAIL: the fake server did not start"
        exit 1
    }
    port="$(cat "$work/port")"
}

# The fixture's FX placeholder is the server's own base URL (REWRITE_FROM).
run_verify() { # run_verify <args...>: output in $out, exit code in $rc
    rc=0
    out="$(VERIFY_ALLOW_HTTP=1 "$verify" "$@" 2>&1)" || rc=$?
}

# expect_pass <label> <site-dir> <mode> <rewrite-from> <verify args...>
expect_pass() {
    local label="$1" site="$2" mode="$3" rw="$4"
    shift 4
    start_server "$site" "$mode" "$rw"
    run_verify "http://127.0.0.1:${port}" "$@"
    if [[ $rc -eq 0 && "$out" == *"0 failed"* ]]; then
        pass "$label"
    else
        fail "$label: exit ${rc}: $(grep -m3 -E '^(FAIL|input)' <<<"$out")"
    fi
}

# expect_fail <label> <rule> <site-dir> <mode> <rewrite-from> <verify args...>
expect_fail() {
    local label="$1" rule="$2" site="$3" mode="$4" rw="$5"
    shift 5
    start_server "$site" "$mode" "$rw"
    run_verify "http://127.0.0.1:${port}" "$@"
    if [[ $rc -eq 1 && "$out" == *"FAIL: ${rule}:"* ]]; then
        pass "$label fails with ${rule}"
    else
        fail "$label: wanted exit 1 and '${rule}', got exit ${rc}: $(grep -m3 -E '^(FAIL|input)' <<<"$out")"
    fi
}

fxp=(--public "$fx")
rw_fx=http://FX
rw_real=https://test-blog.chiefgyk3d.com

# --- good runs ---------------------------------------------------------------------
expect_pass "fixture, good" "$fx" good "$rw_fx" "${fxp[@]}"
expect_pass "fixture, absolute Location" "$fx" redirect-absolute "$rw_fx" "${fxp[@]}"
expect_pass "real staging build served locally" "$real_stg" good "$rw_real" --public "$real_stg"
expect_pass "real production build served locally" "$real_prod" good "$rw_real" --public "$real_prod"
expect_pass "real staging, default build path (no --public)" "$real_stg" good "$rw_real"
expect_pass "--env staging agrees" "$real_stg" good "$rw_real" --public "$real_stg" --env staging

# --- one negative case per check -----------------------------------------------------
expect_fail "redirect: wrong status" redirect "$fx" redirect-wrong-status "$rw_fx" "${fxp[@]}"
expect_fail "redirect: a 302 rule answered 301" redirect "$fx" redirect-302-as-301 "$rw_fx" "${fxp[@]}"
expect_fail "redirect: wrong Location" redirect "$fx" redirect-wrong-location "$rw_fx" "${fxp[@]}"
expect_fail "redirect: other host" redirect "$fx" redirect-other-host "$rw_fx" "${fxp[@]}"
expect_fail "redirect: rule not served" redirect "$fx" redirect-missing "$rw_fx" "${fxp[@]}"
expect_fail "status: page 500" status "$fx" page-500 "$rw_fx" "${fxp[@]}"
expect_fail "not-found: 404 answered 200" not-found "$fx" no-404 "$rw_fx" "${fxp[@]}"
expect_fail "not-found: 404 page indexable" not-found "$fx" 404-indexable "$rw_fx" "${fxp[@]}"
expect_fail "csp: different policy" header-wrong "$fx" csp-wrong "$rw_fx" "${fxp[@]}"
expect_fail "csp: missing" header-missing "$fx" csp-missing "$rw_fx" "${fxp[@]}"
expect_fail "csp: duplicated" header-duplicate "$fx" csp-dup "$rw_fx" "${fxp[@]}"
expect_fail "hsts: missing" header-missing "$fx" hsts-missing "$rw_fx" "${fxp[@]}"
expect_fail "nosniff: wrong value" header-wrong "$fx" nosniff-wrong "$rw_fx" "${fxp[@]}"
expect_fail "cache: immutable Cache-Control on HTML" header-unexpected "$fx" immutable-on-html "$rw_fx" "${fxp[@]}"
expect_fail "cache: immutable as the second Cache-Control field on HTML" header-unexpected "$fx" immutable-second-field "$rw_fx" "${fxp[@]}"
expect_fail "cache: immutable combined into one Cache-Control field on HTML" header-unexpected "$fx" immutable-combined "$rw_fx" "${fxp[@]}"
expect_fail "cache: CSS without the immutable Cache-Control" header-missing "$fx" css-immutable-missing "$rw_fx" "${fxp[@]}"
expect_fail "sitemap: truncated" sitemap "$fx" sitemap-bad "$rw_fx" "${fxp[@]}"
expect_fail "sitemap: another host" sitemap "$fx" sitemap-host "$rw_fx" "${fxp[@]}"
expect_fail "feed: truncated" feed "$fx" feed-bad "$rw_fx" "${fxp[@]}"
expect_fail "feed: missing" feed "$fx" feed-missing "$rw_fx" "${fxp[@]}"
expect_fail "feed: DOCTYPE refused" feed "$fx" feed-doctype "$rw_fx" "${fxp[@]}"
expect_fail "feed: atom self link on another host" feed "$fx" feed-self-other "$rw_fx" "${fxp[@]}"
expect_fail "feed: atom self link missing" feed "$fx" feed-self-missing "$rw_fx" "${fxp[@]}"
expect_fail "feed: two atom self links" feed "$fx" feed-self-twice "$rw_fx" "${fxp[@]}"
expect_fail "robots: missing" robots "$fx" robots-missing "$rw_fx" "${fxp[@]}"
expect_fail "robots: production pages under a staging robots.txt" robots-meta "$real_prod" robots-flip "$rw_real" --public "$real_prod"
expect_fail "env-mismatch: --env production against staging" env-mismatch "$real_stg" good "$rw_real" --public "$real_stg" --env production
expect_fail "env-mismatch: --env staging against production" env-mismatch "$real_prod" good "$rw_real" --public "$real_prod" --env staging
expect_fail "third-party: remote image on the home page" third-party "$fx" third-party "$rw_fx" "${fxp[@]}"
expect_fail "third-party: stylesheet @import" third-party "$fx" css-external "$rw_fx" "${fxp[@]}"
expect_fail "copy-js: different bytes" copy-js "$fx" copy-js-wrong "$rw_fx" "${fxp[@]}"
# The sitemap/feed of a build whose baseURL is not the host being checked (the
# cutover step "change baseURL" forgotten) is caught as well.
expect_fail "baseURL: build still names the staging host" sitemap "$real_prod" good "" --public "$real_prod"

# --- production robots checks (the fixture is staging; build a production one) ---------
prod_fx="$work/fixture-production"
cp -r "$fx" "$prod_fx"
printf 'User-agent: *\nAllow: /\n\nSitemap: http://FX/sitemap.xml\n' >"$prod_fx/robots.txt"
sed -i 's#<meta name=robots content="noindex, nofollow">##' "$prod_fx/index.html" "$prod_fx/about/index.html" "$prod_fx/posts/index.html" "$prod_fx/posts/sample-post/index.html"
expect_pass "fixture production, good" "$prod_fx" good "$rw_fx" --public "$prod_fx"
printf 'User-agent: *\nAllow: /\n' >"$prod_fx/robots.txt"
expect_fail "robots: production without a Sitemap line" robots "$prod_fx" good "$rw_fx" --public "$prod_fx"

# A crawler-specific Disallow must not classify the host as staging.
printf 'User-agent: Googlebot\nDisallow: /\n\nUser-agent: *\nAllow: /\n\nSitemap: http://FX/sitemap.xml\n' >"$prod_fx/robots.txt"
expect_pass "robots: crawler-specific Disallow, wildcard Allow is production" "$prod_fx" good "$rw_fx" --public "$prod_fx"
# Allow and a Sitemap line, but no User-agent: * group, decide nothing.
printf 'User-agent: Googlebot\nAllow: /\n\nSitemap: http://FX/sitemap.xml\n' >"$prod_fx/robots.txt"
expect_fail "robots: no wildcard group" robots "$prod_fx" good "$rw_fx" --public "$prod_fx"
printf 'Allow: /\nSitemap: http://FX/sitemap.xml\n' >"$prod_fx/robots.txt"
expect_fail "robots: rules before any User-agent line" robots "$prod_fx" good "$rw_fx" --public "$prod_fx"
printf 'User-agent: *\nAllow: /\nDisallow: /private/\n\nSitemap: http://FX/sitemap.xml\n' >"$prod_fx/robots.txt"
expect_fail "robots: production with a partial Disallow" robots "$prod_fx" good "$rw_fx" --public "$prod_fx"
stg_fx="$work/fixture-staging2"
cp -r "$fx" "$stg_fx"
printf 'User-agent: Bingbot\nAllow: /\n\nUser-agent: *\nDisallow: /\n' >"$stg_fx/robots.txt"
expect_pass "robots: staging with a crawler-specific Allow" "$stg_fx" good "$rw_fx" --public "$stg_fx"

# --- the redirect status is the declared one; other statuses are refused -----------------
bad_fx="$work/fixture-308"
cp -r "$fx" "$bad_fx"
printf '/old/ /posts/sample-post/ 301\n/old /posts/sample-post/ 308\n' >"$bad_fx/_redirects"
expect_fail "redirect: unsupported status 308 in _redirects" redirect "$bad_fx" good "$rw_fx" --public "$bad_fx"

# --- placeholder rules other than a trailing splat are refused, not guessed -----------------
ph_fx="$work/fixture-placeholder"
cp -r "$fx" "$ph_fx"
printf '/:year/:month/ /posts/ 301\n' >"$ph_fx/_redirects"
expect_fail "redirect: unsupported :placeholder rule" redirect "$ph_fx" good "$rw_fx" --public "$ph_fx"

# --- _headers patterns the verifier cannot interpret are refused, not ignored -----------------
for pat in '/a/*/b' '/:id/*' 'https://x.example/*' '*.css' '/foo*' '/*bar' '/a*/b' '/*/x' '/a?b' '/a[b]'; do
    pat_fx="$work/fixture-pattern"
    rm -rf "$pat_fx"
    cp -r "$fx" "$pat_fx"
    printf '\n%s\n  Cache-Control: no-store\n' "$pat" >>"$pat_fx/_headers"
    rc=0
    out="$(VERIFY_ALLOW_HTTP=1 "$verify" http://127.0.0.1:1 --public "$pat_fx" 2>&1)" || rc=$?
    if [[ $rc -eq 2 && "$out" == *"_headers"* ]]; then
        pass "input error: unsupported _headers pattern ${pat}"
    else
        fail "unsupported _headers pattern ${pat}: exit ${rc}"
    fi
done

# --- the feed path comes from the build (alternate link) or VERIFY_FEED_PATH -----------------
feed_fx="$work/fixture-feedpath"
cp -r "$fx" "$feed_fx"
mkdir -p "$feed_fx/feed"
mv "$feed_fx/index.xml" "$feed_fx/feed/index.xml"
sed -i 's#http://FX/index.xml#http://FX/feed/index.xml#g' "$feed_fx/feed/index.xml" "$feed_fx/index.html" "$feed_fx/about/index.html" "$feed_fx/posts/index.html" "$feed_fx/posts/sample-post/index.html"
expect_pass "feed at /feed/index.xml, found from the alternate link" "$feed_fx" good "$rw_fx" --public "$feed_fx"
expect_fail "feed at /feed/index.xml: feed-missing is noticed" feed "$feed_fx" feed-missing "$rw_fx" --public "$feed_fx"
start_server "$fx" good "$rw_fx"
rc=0
out="$(VERIFY_FEED_PATH=/nonexistent.xml VERIFY_ALLOW_HTTP=1 "$verify" "http://127.0.0.1:${port}" --public "$fx" 2>&1)" || rc=$?
if [[ $rc -eq 1 && "$out" == *"FAIL: feed: /nonexistent.xml"* ]]; then
    pass "VERIFY_FEED_PATH overrides the path found in the build"
else
    fail "VERIFY_FEED_PATH: exit ${rc}: $(grep -m3 -E '^(FAIL|input)' <<<"$out")"
fi

# --- --resolve-ip: a name the local resolver cannot see, mapped to loopback ----------------
start_server "$fx" good "$rw_fx"
run_verify "http://verify-live-test.invalid:${port}" --public "$fx" --resolve-ip 127.0.0.1
if [[ $rc -eq 0 && "$out" == *"0 failed"* ]]; then
    pass "--resolve-ip reaches a name the resolver cannot resolve"
else
    fail "--resolve-ip: exit ${rc}: $(grep -m3 -E '^(FAIL|input)' <<<"$out")"
fi
run_verify "http://verify-live-test.invalid:${port}" --public "$fx"
if [[ $rc -ne 0 ]]; then
    pass "without --resolve-ip the same name fails (the option is what makes it work)"
else
    fail "the unresolvable name passed without --resolve-ip"
fi

# --- input errors exit 2 -----------------------------------------------------------------------
input_rc() { # input_rc <label> <env> <args...>
    local label="$1" envv="$2"
    shift 2
    rc=0
    out="$(env "$envv" "$verify" "$@" 2>&1)" || rc=$?
    if [[ $rc -eq 2 ]]; then
        pass "input error: ${label}"
    else
        fail "input error: ${label}: exit ${rc}"
    fi
}
input_rc "no arguments" X=1
input_rc "http without VERIFY_ALLOW_HTTP" X=1 http://example.com --public "$fx"
input_rc "bad host characters" X=1 'exa mple.com' --public "$fx"
input_rc "bad resolve ip" X=1 example.com --resolve-ip 'not-an-ip' --public "$fx"
input_rc "bad env" X=1 example.com --env nope --public "$fx"
input_rc "unknown option" X=1 example.com --nope
mkdir -p "$work/empty"
input_rc "build without _headers" X=1 example.com --public "$work/empty"

if ((failures > 0)); then
    echo "${failures} failure(s)"
    exit 1
fi
echo "all verify-live checks passed"
