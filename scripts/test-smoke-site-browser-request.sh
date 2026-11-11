#!/usr/bin/env bash
# Focused curl-stub test for the browser-like home-page request used by
# scripts/smoke-site.sh. No socket or network access is needed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smoke="$root/scripts/smoke-site.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/smoke-browser-request.XXXXXX")"
trap 'rm -rf "$work"' EXIT

csp="default-src 'none'; manifest-src 'self'; script-src 'self' https://static.cloudflareinsights.com/beacon.min.js/; connect-src 'self'"
pub="$work/public"
mkdir -p "$pub/posts/N0CALL" "$pub/posts" "$pub/feed" "$work/bin"
printf '/*\n  Content-Security-Policy: %s\n  X-Content-Type-Options: nosniff\n' "$csp" >"$pub/_headers"
printf '/old/ /posts/N0CALL/ 301\n/feed/ /feed/index.xml 301\n' >"$pub/_redirects"
for page in index.html posts/index.html posts/N0CALL/index.html; do
    printf '<!doctype html>\n' >"$pub/$page"
done
printf '<rss/>\n' >"$pub/feed/index.xml"

cp "$root/scripts/smoke-site-curl-stub.sh" "$work/bin/curl"
chmod +x "$work/bin/curl"

failures=0
run_case() {
    local label="$1" mode="$2" want="$3" out rc=0
    out="$(PATH="$work/bin:$PATH" CURL_STUB_CSP="$csp" CURL_STUB_BEACON="$mode" SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=0 "$smoke" https://test-blog.chiefgyk3d.com "$pub" 2>&1)" || rc=$?
    if [[ "$want" == pass && $rc -eq 0 ]]; then
        echo "ok: $label"
    elif [[ "$want" != pass && $rc -eq 1 && "$out" == *"$want"* ]]; then
        echo "ok: $label"
    else
        echo "FAIL: $label (exit $rc, wanted $want)"
        echo "$out"
        failures=$((failures + 1))
    fi
}

run_case "browser-like headers receive one beacon" one pass
run_case "a response without the browser-only beacon is rejected" missing "missing-beacon: /"
run_case "two beacons are rejected" two "script-count: /"
run_case "a beacon without a token is rejected" no-token "missing-beacon: /"

((failures == 0)) || exit 1
echo "all browser-request smoke checks passed"
