#!/usr/bin/env bash
# Test for scripts/smoke-site.sh against a local fake server (no real network).
#
# One fake server per mode runs on 127.0.0.1 with an OS-chosen port. The good
# mode must pass; each bad mode must fail with its expected rule name.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smoke="$root/scripts/smoke-site.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/smoke-site.XXXXXX")"
server_pid=""
stop_server() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=""
    fi
}
trap 'stop_server; rm -rf "$work"' EXIT

csp="default-src 'none'; script-src 'self' https://static.cloudflareinsights.com/beacon.min.js; connect-src 'self'"
pub="$work/public"
mkdir -p "$pub"
printf '/*\n  Content-Security-Policy: %s\n  X-Content-Type-Options: nosniff\n' "$csp" >"$pub/_headers"
# The first 301 line is the required one; the sample of the other classes (a
# date archive, a category, a tag, an old upload) is taken from the lines below.
# The two dynamic rules are not sampled (a splat has no one address).
cat >"$pub/_redirects" <<'RULES'
# generated
/2023/02/10/sample-post/ /posts/sample-post/ 301
/2023/02/10/sample-post /posts/sample-post/ 301
/2023/ /posts/ 301
/category/sample/ /categories/sample/ 301
/feed/ /feed/index.xml 301
/tag/lorem/ /tags/lorem/ 301
/wp-content/uploads/2023/02/pic.jpg /posts/sample-post/pic.png 301
/category/* /posts/ 301
RULES
# One page per template the deployed site serves: home, a post, a journal entry,
# the two section lists, a tag page, a category page and the feed. The 404 page
# is asked for by a name that does not exist.
for p in posts/sample-post journal/sample-entry posts journal tags/lorem categories/sample feed; do
    mkdir -p "$pub/$p"
    printf '<!doctype html>\n' >"$pub/$p/index.html"
done
printf '<!doctype html>\n' >"$pub/index.html"
printf '<!doctype html>\n' >"$pub/404.html"
printf '<rss/>\n' >"$pub/index.xml"
printf '<rss/>\n' >"$pub/feed/index.xml"
# The pinned hash of each script (copy.js, search.js): files of the test's own in
# a directory of the test's own, absent unless a case pins them.
export SCRIPT_HASH_DIR="$work/hashes"
mkdir -p "$SCRIPT_HASH_DIR"
served_dir="$work/served"
mkdir -p "$served_dir"
known="/,/posts/sample-post/,/journal/sample-entry/,/posts/,/journal/,/tags/lorem/,/categories/sample/,/index.xml,/feed/index.xml"
# The redirects the fake server answers (from=to, ';' apart): the required first
# line, /feed/, and the sample (date archive, category, tag, upload).
redirs="/2023/02/10/sample-post/=/posts/sample-post/;/feed/=/feed/index.xml;/2023/=/posts/;/category/sample/=/categories/sample/;/tag/lorem/=/tags/lorem/;/wp-content/uploads/2023/02/pic.jpg=/posts/sample-post/pic.png"
# Requests per full attempt: ten pages (nine above and the 404) and six redirects.
per_attempt=16

# start_server <mode>: sets $url
start_server() {
    stop_server
    rm -f "$work/port" "$work/port.count"
    MODE="$1" CSP="$csp" KNOWN="$known" REDIRS="$redirs" SERVED_DIR="$served_dir" PORTFILE="$work/port" python3 -I -c '
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

mode, csp = os.environ["MODE"], os.environ["CSP"]
known = set(os.environ["KNOWN"].split(","))
redirs = dict(r.split("=") for r in os.environ["REDIRS"].split(";"))
first_redirect = "/2023/02/10/sample-post/"
# "<fault>@<path>" breaks one page: nocsp (no CSP header), dupcsp (the header
# twice, the second in lower case), joined (one header holding the policy twice),
# diffcsp (a different policy), nonosniff, status (HTTP 500). On a redirect path:
# noredirect (answers 200), wrongredirect (a different Location), found (302).
# On /feed/index.xml: feedhtml, feednone (Content-Type text/html, or none).
# The path "*404" means the page served for a name that does not exist.
fault, _, fpath = mode.partition("@")
# "stale-N" answers the first N requests with wrong data (a 404 page without
# the CSP header, a 200 where the 301 belongs), then answers correctly.
stale = int(mode.split("-")[1]) if mode.startswith("stale-") else 0
seen = 0
copy_seen = 0


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        global seen, copy_seen
        seen += 1
        with open(os.environ["PORTFILE"] + ".count", "w") as f:
            f.write(str(seen))
        if seen <= stale:
            self.send_response(404 if self.path == "/" else 200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path in redirs:
            first = self.path == first_redirect
            if (mode == "no-redirect" and first) or (fault == "noredirect" and fpath == self.path):
                self.send_response(200)
            elif (mode == "wrong-redirect" and first) or (fault == "wrongredirect" and fpath == self.path):
                self.send_response(301)
                self.send_header("Location", "/elsewhere/")
            else:
                self.send_response(302 if fault == "found" and fpath == self.path else 301)
                self.send_header("Location", redirs[self.path])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = b"ok"
        pages = {
            "inlinescript": b"<html><script>x()</script></html>",
            "extrascript": b"<html><script src=/other.js></script></html>",
            "remotescript": b"<html><script src=https://e.example/x.js></script></html>",
            "handlerpage": b"<html><body onload=x()></body></html>",
            "quotedgt": b"<html><img alt=\"x>\" onerror=x()></html>",
            "jsurl": b"<html><a href=\"javascript:x()\">y</a></html>",
            "copyref": b"<html><script src=/copy.js></script></html>",
            "copytwice": b"<html><script src=/copy.js></script><script src=/copy.js></script></html>",
            "searchref": b"<html><script src=/search.js></script></html>",
            "searchtwice": b"<html><script src=/search.js></script><script src=/search.js></script></html>",
            "bothref": b"<html><script src=/copy.js></script><script src=/search.js></script></html>",
            "searchbody": b"<html><script src=/search.js>x()</script></html>",
            "benignpage": b"<html><img alt=\"one=1\" src=/a.png><a href=\"https://example.org/\">y</a></html>",
            "badfeed": b"<rss><a onclick=\"x\"/></rss>",
        }
        is_known = self.path in known
        served = os.path.join(os.environ["SERVED_DIR"], self.path.lstrip("/"))
        if self.path in ("/copy.js", "/search.js") and os.path.exists(served):
            is_known = True
            body = open(served, "rb").read()
            if fault == "tampercopy" and fpath == self.path:
                body += b"x"
            if fault == "alternatecopy" and fpath == self.path:
                # every other request gets different bytes
                copy_seen += 1
                if copy_seen % 2 == 1:
                    body += b"x"
        hit = self.path == fpath or (fpath == "*404" and not is_known)
        code = 200 if is_known else 404
        if mode == "bad-status" and self.path == "/":
            code = 404
        if fault == "status" and hit:
            code = 500
        if fault in pages and (self.path == fpath or (fpath == "*404" and not is_known)):
            body = pages[fault]
        self.send_response(code)
        if self.path == "/feed/index.xml" and fault != "feednone":
            self.send_header("Content-Type", "text/html" if fault == "feedhtml" else os.environ.get("FEED_TYPE", "application/xml"))
        if mode != "no-csp" and not (fault == "nocsp" and hit):
            value = "default-src *" if mode == "weak-csp" else csp
            if fault == "diffcsp" and hit:
                value = csp + "; script-src-elem https:"
            if fault == "joined" and hit:
                value = csp + ", " + csp
            self.send_header("Content-Security-Policy", value)
            if fault == "dupcsp" and hit:
                self.send_header("content-security-policy", value)
        if not (fault == "nonosniff" and hit):
            self.send_header("X-Content-Type-Options", "sniff" if fault == "othernosniff" and hit else "nosniff")
            if fault == "dupnosniff" and hit:
                self.send_header("X-Content-Type-Options", "nosniff")
            if fault == "conflictnosniff" and hit:
                self.send_header("x-content-type-options", "sniff")
            if fault == "joinednosniff" and hit:
                self.send_header("x-content-type-options", "nosniff, sniff")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


srv = HTTPServer(("127.0.0.1", 0), H)
with open(os.environ["PORTFILE"], "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
' &
    server_pid=$!
    for _ in $(seq 1 50); do
        [[ -s "$work/port" ]] && break
        sleep 0.1
    done
    [[ -s "$work/port" ]] || {
        echo "FAIL: fake server did not start"
        exit 1
    }
    url="http://127.0.0.1:$(cat "$work/port")"
}

failures=0

# expect <name> <pass|rule> <mode> [dir]
expect() {
    local name="$1" want="$2" mode="$3" dir="${4:-$pub}" out rc=0
    start_server "$mode"
    out="$(SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=0 SMOKE_RETRY_SLEEP=0 "$smoke" "$url" "$dir" 2>&1)" || rc=$?
    if [[ "$want" == pass ]]; then
        if [[ $rc -eq 0 ]]; then
            echo "ok: $name"
        else
            echo "FAIL: $name (rc=$rc)"
            echo "$out"
            failures=$((failures + 1))
        fi
    elif [[ $rc -ne 0 && "$out" == *"$want"* ]]; then
        echo "ok: $name"
    else
        echo "FAIL: $name (rc=$rc, wanted rule $want)"
        echo "$out"
        failures=$((failures + 1))
    fi
}

expect good pass good
expect bad-status status bad-status
expect no-csp missing-csp no-csp
expect weak-csp wrong-csp weak-csp
expect no-redirect redirect no-redirect
expect wrong-redirect redirect wrong-redirect

# The policy is checked on every page template, not on the home page alone: a
# fault on any one page fails, naming the page and the problem.
for page in /posts/sample-post/ /journal/sample-entry/ /posts/ /journal/ /tags/lorem/ /categories/sample/ /index.xml /feed/index.xml '*404'; do
    shown="$page"
    [[ "$page" == '*404' ]] && shown="/smoke-check-missing-page/"
    expect "no CSP on $page" "missing-csp: $shown" "nocsp@$page"
    expect "duplicate CSP on $page" "duplicate-csp: $shown" "dupcsp@$page"
    expect "different CSP on $page" "wrong-csp: $shown" "diffcsp@$page"
    expect "no nosniff on $page" "missing-nosniff: $shown" "nonosniff@$page"
    expect "duplicate nosniff on $page" "wrong-nosniff: $shown" "dupnosniff@$page"
    expect "conflicting nosniff on $page" "wrong-nosniff: $shown" "conflictnosniff@$page"
done
expect "different nosniff value on a post" "wrong-nosniff: /posts/sample-post/" "othernosniff@/posts/sample-post/"
expect "joined nosniff values on a post" "wrong-nosniff: /posts/sample-post/" "joinednosniff@/posts/sample-post/"
expect "joined duplicate CSP on a post" "wrong-csp: /posts/sample-post/" "joined@/posts/sample-post/"
expect "server error on a post" "status: /posts/sample-post/" "status@/posts/sample-post/"
expect "server error on the 404 page" "status: /smoke-check-missing-page/" "status@*404"
expect "no CSP on the home page" "missing-csp: /" "nocsp@/"
expect "duplicate CSP on the home page" "duplicate-csp: /" "dupcsp@/"

# The legacy WordPress addresses answer as the build declares them: /feed/ is a
# 301 to the real feed file, which is served as XML, and a sample of the other
# rules (date archive, category, tag, old upload) answers with its own target.
expect "feed file served as XML" pass good
expect "feed redirect missing" "redirect: /feed/ answered '200'" noredirect@/feed/
expect "feed redirect to the wrong place" "redirect: /feed/ answered '301' Location '/elsewhere/'" wrongredirect@/feed/
expect "feed redirect is temporary" "redirect: /feed/ answered '302'" found@/feed/
expect "feed file served as HTML" "feed-type: /feed/index.xml" feedhtml@/feed/index.xml
expect "feed file with no content type" "feed-type: /feed/index.xml" feednone@/feed/index.xml
expect "feed file missing" "status: /feed/index.xml" status@/feed/index.xml
for from in /2023/ /category/sample/ /tag/lorem/ /wp-content/uploads/2023/02/pic.jpg; do
    expect "sampled rule $from missing" "redirect: ${from} answered '200'" "noredirect@$from"
    expect "sampled rule $from to the wrong place" "redirect: ${from} answered '301' Location '/elsewhere/'" "wrongredirect@$from"
    expect "sampled rule $from is temporary" "redirect: ${from} answered '302'" "found@$from"
done
# The feed type is any XML type a reader accepts.
for ft in application/rss+xml text/xml "application/xml; charset=utf-8"; do
    FEED_TYPE="$ft" expect "feed served as $ft" pass good
done

# Edge propagation: wrong answers first, correct ones later. The first twenty
# requests are two full attempts (every page, then redirect), so the third
# attempt is the first good one: three retries pass, none fail.
start_server "stale-$((2 * per_attempt))"
rc=0
out="$(SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=3 SMOKE_RETRY_SLEEP=0.1 "$smoke" "$url" "$pub" 2>&1)" || rc=$?
if [[ $rc -eq 0 ]]; then
    echo "ok: stale edge passes with retries"
else
    echo "FAIL: stale edge did not pass with retries (rc=$rc)"
    echo "$out"
    failures=$((failures + 1))
fi
start_server "stale-$((2 * per_attempt))"
rc=0
out="$(SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=0 "$smoke" "$url" "$pub" 2>&1)" || rc=$?
if [[ $rc -ne 0 && "$out" == *"status:"* ]]; then
    echo "ok: stale edge fails without retries"
else
    echo "FAIL: stale edge passed without retries (rc=$rc)"
    echo "$out"
    failures=$((failures + 1))
fi

# A site that never becomes correct fails after the bounded retries, fast, and
# the retries re-ran the whole set ($per_attempt requests per attempt, 4 attempts).
start_server bad-status
rc=0
out="$(SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=3 SMOKE_RETRY_SLEEP=0.1 "$smoke" "$url" "$pub" 2>&1)" || rc=$?
# Bounded means exactly 4 attempts: the fake server saw 4 full sets of requests
# and the script said so. No wall-clock limit is involved.
if [[ $rc -ne 0 && "$out" == *"status:"* && "$out" == *"still failing after 4 attempt(s)"* && "$(cat "$work/port.count")" == $((4 * per_attempt)) ]]; then
    echo "ok: never-correct site fails after bounded retries"
else
    echo "FAIL: never-correct site (rc=$rc, requests $(cat "$work/port.count"), wanted $((4 * per_attempt)))"
    echo "$out"
    failures=$((failures + 1))
fi

# The expectations come from the build, so a build without them must fail.
mkdir -p "$work/nohdr" "$work/noredir"
cp "$pub/_redirects" "$work/nohdr/"
cp "$pub/_headers" "$work/noredir/"
printf '# nothing\n' >"$work/noredir/_redirects"
mkdir -p "$work/nopages" "$work/nofeed" "$work/lean"
cp -r "$pub/." "$work/nofeed/"
rm -r "$work/nofeed/feed"
cp "$pub/_redirects" "$pub/_headers" "$work/nopages/"
printf '<!doctype html>\n' >"$work/nopages/index.html"
expect build-without-pages input good "$work/nopages"
expect no-headers-file input good "$work/nohdr"
expect no-redirect-line input good "$work/noredir"
expect build-without-feed input good "$work/nofeed"
# A build with no sampled class (only the one required 301 line) still passes:
# the sample is whatever the build holds, so it follows the site.
cp -r "$pub/." "$work/lean/"
printf '# generated\n/2023/02/10/sample-post/ /posts/sample-post/ 301\n' >"$work/lean/_redirects"
expect "build holding only the required redirect" pass good "$work/lean"

# The expected policy must carry script-src exactly 'self' plus the Cloudflare beacon URL: 'none' (the header
# and the copy script would have drifted apart) and anything looser are refused
# before any request is made.
for src in "'none'" "'self' https:" "'unsafe-inline'" "*" "'self' data:" "'self'" "'self' https://static.cloudflareinsights.com"; do
    d="$work/csp-$(printf '%s' "$src" | tr -c '[:lower:]' '_')"
    mkdir -p "$d"
    cp "$pub/_redirects" "$d/"
    printf '/*\n  Content-Security-Policy: default-src %s; script-src %s\n' "'none'" "$src" >"$d/_headers"
    expect "expected-script-src-$src" input good "$d"
done
d="$work/csp-no-script-src"
mkdir -p "$d"
cp "$pub/_redirects" "$d/"
printf '/*\n  Content-Security-Policy: default-src %s\n' "'none'" >"$d/_headers"
expect expected-without-script-src input good "$d"

# Header structure of the build's own _headers: one "/*" block, no removal
# directive, one nosniff, one policy. Refused before any request is made.
for variant in 'removal-nosniff:/admin/*\n  ! X-Content-Type-Options\n' 'removal-policy:/admin/*\n  ! Content-Security-Policy\n' 'removal-first-block:  ! Referrer-Policy\n' 'second-block:/other/*\n  Referrer-Policy: no-referrer\n' 'path-override-nosniff:/api/*\n  X-Content-Type-Options: sniff\n' 'duplicate-nosniff:  X-Content-Type-Options: nosniff\n' 'immutable-fonts:/fonts/*\n  Cache-Control: public, max-age=31536000, immutable\n'; do
    d="$work/hdr-${variant%%:*}"
    mkdir -p "$d"
    cp "$pub/_redirects" "$d/"
    cp -r "$pub/posts" "$pub/journal" "$d/"
    cp "$pub/_headers" "$d/_headers"
    printf '%b' "${variant#*:}" >>"$d/_headers"
    expect "headers-structure-${variant%%:*}" input good "$d"
done

# The served bytes of each page are read with the same parser as the build check:
# a script element, a handler or a javascript: URL in what the site serves fails,
# naming the page. Benign text (alt="one=1", an outbound link) passes.
expect "inline script served on a post" "script-not-allowed: /posts/sample-post/" inlinescript@/posts/sample-post/
expect "extra script file served on the home page" "script-not-allowed: /" extrascript@/
expect "remote script served on a list" "script-not-allowed: /journal/" remotescript@/journal/
expect "handler served on the 404 page" "event-handler: /smoke-check-missing-page/" handlerpage@'*404'
expect "handler after a quoted > on a post" "event-handler: /posts/sample-post/" quotedgt@/posts/sample-post/
expect "javascript URL served on a tag page" "javascript-url: /tags/lorem/" jsurl@/tags/lorem/
expect "handler in the served feed" "event-handler: /index.xml" badfeed@/index.xml
expect "benign served markup passes" pass benignpage@/posts/

# The pinned scripts are judged by their pinned hashes: the build's file must
# match, and so must the bytes the site serves. With no hash file a script in the
# build is refused. Each script is loaded by its own page only (/copy.js by
# /support/, /search.js by /search/): the tag served anywhere else is a
# script-wrong-page finding.
pin_in() { # pin_in <build dir> <name>: writes the script into the build, serves the same bytes, pins it
    printf 'document.documentElement.dataset.x="%s"\n' "$2" >"$1/$2"
    cp "$1/$2" "$served_dir/$2"
    printf '%s  %s\n' "$(sha256sum "$1/$2" | cut -d' ' -f1)" "$2" >"$SCRIPT_HASH_DIR/$2.sha256"
}
known_base="$known"
for name in copy.js search.js; do
    page=support
    [[ $name == search.js ]] && page=search
    tpub="$work/public-$name"
    cp -r "$pub" "$tpub"
    mkdir -p "$tpub/$page"
    printf '<!doctype html>\n' >"$tpub/$page/index.html"
    pin_in "$tpub" "$name"
    known="$known_base,/$name,/$page/"
    ref=copyref
    [[ $name == search.js ]] && ref=searchref
    twice=copytwice
    [[ $name == search.js ]] && twice=searchtwice
    expect "pinned $name served unchanged" pass good "$tpub"
    expect "$name served with different bytes" "script-hash: /$name" tampercopy@/$name "$tpub"
    expect "the pinned $name tag served on its own page passes" pass "$ref@/$page/" "$tpub"
    expect "the $name tag served twice" "script-count: /$page/" "$twice@/$page/" "$tpub"
    expect "the $name tag served on the home page" "script-wrong-page: /" "$ref@/" "$tpub"
    expect "the $name tag served on a post" "script-wrong-page: /posts/sample-post/" "$ref@/posts/sample-post/" "$tpub"
    expect "an extra script next to $name" "script-not-allowed: /posts/" extrascript@/posts/ "$tpub"
    expect "$name bytes alternate between responses" "script-hash: /$name" alternatecopy@/$name "$tpub"
    expect "no CSP on $name" "missing-csp: /$name" nocsp@/$name "$tpub"
    expect "a script tag with a body on the $name page" "script-not-allowed: /$page/" searchbody@/$page/ "$tpub"
    rm -f "$SCRIPT_HASH_DIR/$name.sha256"
    expect "$name in the build with no hash file" input good "$tpub"
    printf '%s  %s\n' "$(printf 'a%.0s' $(seq 1 64))" "$name" >"$SCRIPT_HASH_DIR/$name.sha256"
    expect "build $name differs from the pinned hash" input good "$tpub"
    rm -f "$SCRIPT_HASH_DIR/$name.sha256" "$served_dir/$name"
done
# One script's tag on the other's page, with both pinned: each is the other's wrong page.
tpub="$work/public-both"
cp -r "$pub" "$tpub"
mkdir -p "$tpub/support" "$tpub/search"
printf '<!doctype html>\n' >"$tpub/support/index.html"
printf '<!doctype html>\n' >"$tpub/search/index.html"
pin_in "$tpub" copy.js
pin_in "$tpub" search.js
known="$known_base,/copy.js,/search.js,/support/,/search/"
expect "both pinned scripts served unchanged" pass good "$tpub"
expect "the search tag on the support page" "script-wrong-page: /support/" searchref@/support/ "$tpub"
expect "the copy tag on the search page" "script-wrong-page: /search/" copyref@/search/ "$tpub"
expect "both tags on one page" "script-wrong-page: /search/" bothref@/search/ "$tpub"
rm -f "$SCRIPT_HASH_DIR"/*.sha256 "$served_dir"/*
known="$known_base"
expect "copy script tag served with no pinned script" "script-not-allowed: /" copyref@/
expect "search script tag served with no pinned script" "script-not-allowed: /" searchref@/

# Plain http is refused unless the test switch is set.
rc=0
out="$(SMOKE_RETRIES=0 "$smoke" "http://127.0.0.1:1" "$pub" 2>&1)" || rc=$?
if [[ $rc -ne 0 && "$out" == *"https"* ]]; then
    echo "ok: http refused"
else
    echo "FAIL: http was not refused"
    failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all smoke tests passed"
