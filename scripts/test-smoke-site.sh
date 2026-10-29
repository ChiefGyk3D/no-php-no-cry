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

csp="default-src 'none'; script-src 'self'"
pub="$work/public"
mkdir -p "$pub"
printf '/*\n  Content-Security-Policy: %s\n  X-Content-Type-Options: nosniff\n' "$csp" >"$pub/_headers"
printf '# generated\n/2023/02/10/sample-post/ /posts/sample-post/ 301\n/2023/02/10/sample-post /posts/sample-post/ 301\n' >"$pub/_redirects"
# One page per template the deployed site serves: home, a post, a journal entry,
# the two section lists, a tag page, a category page and the feed. The 404 page
# is asked for by a name that does not exist.
for p in posts/sample-post journal/sample-entry posts journal tags/lorem categories/sample; do
    mkdir -p "$pub/$p"
    printf '<!doctype html>\n' >"$pub/$p/index.html"
done
printf '<!doctype html>\n' >"$pub/index.html"
printf '<!doctype html>\n' >"$pub/404.html"
printf '<rss/>\n' >"$pub/index.xml"
# The pinned hash of the theme script: a file of the test's own, absent unless a
# case pins it.
export THEME_HASH_FILE="$work/theme.sha256"
theme_file="$work/theme-served.js"
known="/,/posts/sample-post/,/journal/sample-entry/,/posts/,/journal/,/tags/lorem/,/categories/sample/,/index.xml"
# Requests per full attempt: nine pages (eight above and the 404) and the redirect.
per_attempt=10

# start_server <mode>: sets $url
start_server() {
    stop_server
    rm -f "$work/port" "$work/port.count"
    MODE="$1" CSP="$csp" KNOWN="$known" THEME_FILE="$theme_file" PORTFILE="$work/port" python3 -I -c '
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

mode, csp = os.environ["MODE"], os.environ["CSP"]
known = set(os.environ["KNOWN"].split(","))
# "<fault>@<path>" breaks one page: nocsp (no CSP header), dupcsp (the header
# twice, the second in lower case), joined (one header holding the policy twice),
# diffcsp (a different policy), nonosniff, status (HTTP 500). The path "*404"
# means the page served for a name that does not exist.
fault, _, fpath = mode.partition("@")
# "stale-N" answers the first N requests with wrong data (a 404 page without
# the CSP header, a 200 where the 301 belongs), then answers correctly.
stale = int(mode.split("-")[1]) if mode.startswith("stale-") else 0
seen = 0


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        global seen
        seen += 1
        with open(os.environ["PORTFILE"] + ".count", "w") as f:
            f.write(str(seen))
        if seen <= stale:
            self.send_response(404 if self.path == "/" else 200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/2023/02/10/sample-post/":
            if mode == "no-redirect":
                self.send_response(200)
            elif mode == "wrong-redirect":
                self.send_response(301)
                self.send_header("Location", "/elsewhere/")
            else:
                self.send_response(301)
                self.send_header("Location", "/posts/sample-post/")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = b"ok"
        is_known = self.path in known
        if self.path == "/theme.js" and os.path.exists(os.environ["THEME_FILE"]):
            is_known = True
            body = open(os.environ["THEME_FILE"], "rb").read()
            if fault == "tampertheme":
                body += b"x"
        hit = self.path == fpath or (fpath == "*404" and not is_known)
        code = 200 if is_known else 404
        if mode == "bad-status" and self.path == "/":
            code = 404
        if fault == "status" and hit:
            code = 500
        self.send_response(code)
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
for page in /posts/sample-post/ /journal/sample-entry/ /posts/ /journal/ /tags/lorem/ /categories/sample/ /index.xml '*404'; do
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
began=$SECONDS
out="$(SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=3 SMOKE_RETRY_SLEEP=0.1 "$smoke" "$url" "$pub" 2>&1)" || rc=$?
if [[ $rc -ne 0 && "$out" == *"status:"* && $((SECONDS - began)) -lt 5 && "$(cat "$work/port.count")" == $((4 * per_attempt)) ]]; then
    echo "ok: never-correct site fails after bounded retries"
else
    echo "FAIL: never-correct site (rc=$rc, took $((SECONDS - began)) s, requests $(cat "$work/port.count"))"
    echo "$out"
    failures=$((failures + 1))
fi

# The expectations come from the build, so a build without them must fail.
mkdir -p "$work/nohdr" "$work/noredir"
cp "$pub/_redirects" "$work/nohdr/"
cp "$pub/_headers" "$work/noredir/"
printf '# nothing\n' >"$work/noredir/_redirects"
mkdir -p "$work/nopages"
cp "$pub/_redirects" "$pub/_headers" "$work/nopages/"
printf '<!doctype html>\n' >"$work/nopages/index.html"
expect build-without-pages input good "$work/nopages"
expect no-headers-file input good "$work/nohdr"
expect no-redirect-line input good "$work/noredir"

# The expected policy must carry script-src exactly 'self': 'none' (the header
# and the theme script would have drifted apart) and anything looser are refused
# before any request is made.
for src in "'none'" "'self' https:" "'unsafe-inline'" "*" "'self' data:"; do
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
for variant in 'removal-nosniff:/admin/*\n  ! X-Content-Type-Options\n' 'removal-policy:/admin/*\n  ! Content-Security-Policy\n' 'removal-first-block:  ! Referrer-Policy\n' 'second-block:/other/*\n  Referrer-Policy: no-referrer\n' 'path-override-nosniff:/api/*\n  X-Content-Type-Options: sniff\n' 'duplicate-nosniff:  X-Content-Type-Options: nosniff\n'; do
    d="$work/hdr-${variant%%:*}"
    mkdir -p "$d"
    cp "$pub/_redirects" "$d/"
    cp -r "$pub/posts" "$pub/journal" "$d/"
    cp "$pub/_headers" "$d/_headers"
    printf '%b' "${variant#*:}" >>"$d/_headers"
    expect "headers-structure-${variant%%:*}" input good "$d"
done

# The theme script is judged by its pinned hash: the build's file must match it,
# and so must the bytes the site serves. With no hash file a theme.js is refused.
tpub="$work/public-theme"
cp -r "$pub" "$tpub"
printf 'document.documentElement.dataset.theme="dark"\n' >"$tpub/theme.js"
cp "$tpub/theme.js" "$theme_file"
printf '%s  theme.js\n' "$(sha256sum "$tpub/theme.js" | cut -d' ' -f1)" >"$THEME_HASH_FILE"
known="$known,/theme.js"
expect "pinned theme served unchanged" pass good "$tpub"
expect "theme served with different bytes" "theme-hash: /theme.js" tampertheme@/theme.js "$tpub"
expect "no CSP on the theme script" "missing-csp: /theme.js" nocsp@/theme.js "$tpub"
rm -f "$THEME_HASH_FILE"
expect "theme.js in the build with no hash file" input good "$tpub"
printf '%s  theme.js\n' "$(printf 'a%.0s' $(seq 1 64))" >"$THEME_HASH_FILE"
expect "build theme.js differs from the pinned hash" input good "$tpub"
rm -f "$THEME_HASH_FILE" "$theme_file"

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
