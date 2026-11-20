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
run_case "a beacon with a non-module type is rejected" script-type "script-not-allowed: /"
run_case "a beacon with leading space in its type is rejected" spaced-type "script-not-allowed: /"
run_case "a beacon with a newline in its type is rejected" newline-type "script-not-allowed: /"
run_case "a beacon without integrity is rejected" no-integrity "script-not-allowed: /"
run_case "a beacon with credentialed CORS is rejected" bad-crossorigin "script-not-allowed: /"
run_case "a module beacon with an unknown attribute is rejected" extra-attribute "script-not-allowed: /"
run_case "a module beacon with an inline body is rejected" inline-body "script-not-allowed: /"

# Cloudflare Precursor: the edge injects one inline script into every HTML page
# (observed 2026-11-20, issue 410). Exactly that shape is allowed, once per page;
# anything near it is not. The stub adds the variant to every HTML page, and a
# page that is not the home page has no beacon requirement.
precursor_case() {
    local label="$1" mode="$2" want="$3" out rc=0
    out="$(PATH="$work/bin:$PATH" CURL_STUB_CSP="$csp" CURL_STUB_BEACON=one CURL_STUB_PRECURSOR="$mode" SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=0 "$smoke" https://test-blog.chiefgyk3d.com "$pub" 2>&1)" || rc=$?
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

precursor_case "the observed Precursor snippet, once per page, is allowed" one pass
precursor_case "another valid 10 digit time in t is allowed" t-other-time pass
precursor_case "a t of ten zero bytes is rejected" t-zero-bytes "script-not-allowed: /"
precursor_case "a t of ten letters is rejected" t-letters "script-not-allowed: /"
precursor_case "a t with a non-ASCII byte is rejected" t-non-ascii "script-not-allowed: /"
precursor_case "a t of nine digits and a letter is rejected" t-nine-digits-letter "script-not-allowed: /"
precursor_case "a t of ten bytes with a leading space is rejected" t-leading-space "script-not-allowed: /"
precursor_case "a t of nine digits is rejected" t-nine-digits "script-not-allowed: /"
precursor_case "a t of eleven digits is rejected" t-eleven-digits "script-not-allowed: /"
precursor_case "a t with invalid padding is rejected" t-bad-padding "script-not-allowed: /"
precursor_case "a t with characters outside the base64 alphabet is rejected" t-bad-alphabet "script-not-allowed: /"
precursor_case "the Precursor snippet twice is rejected" two "script-count: /"
precursor_case "the Precursor snippet with code appended is rejected" appended "script-not-allowed: /"
precursor_case "the Precursor snippet with code before it is rejected" prefixed "script-not-allowed: /"
precursor_case "a different Precursor loader path is rejected" wrong-path "script-not-allowed: /"
precursor_case "a Precursor loader on another host is rejected" wrong-host "script-not-allowed: /"
precursor_case "a loader ray that differs from the params ray is rejected" wrong-ray "script-not-allowed: /"
precursor_case "a loader without a ray is rejected" no-ray "script-not-allowed: /"
precursor_case "a loader with an extra query is rejected" extra-query "script-not-allowed: /"
precursor_case "the snippet with a type attribute is rejected" attr-type "script-not-allowed: /"
precursor_case "the snippet with a src attribute is rejected" attr-src "script-not-allowed: /"
precursor_case "the snippet with a nonce attribute is rejected" attr-nonce "script-not-allowed: /"
precursor_case "the snippet with a defer attribute is rejected" attr-defer "script-not-allowed: /"
precursor_case "the snippet with trailing whitespace is rejected" trailing-space "script-not-allowed: /"
precursor_case "a self-closing script with a comment before the exact body is rejected" self-closing-comment "script-not-allowed: /"
precursor_case "a self-closing script with the exact body is rejected" self-closing "script-not-allowed: /"
precursor_case "an upper case self-closing script with a space is rejected" self-closing-space-upper "script-not-allowed: /"
precursor_case "a self-closing script with an attribute is rejected" self-closing-attribute "script-not-allowed: /"
precursor_case "the exact body after a self-closing sibling script is rejected" self-closing-sibling "script-not-allowed: /"
precursor_case "a comment marker in the candidate body is rejected because the body must match exactly" comment-in-body "script-not-allowed: /"
precursor_case "a CDATA marker in the candidate body is rejected because the body must match exactly" cdata-in-body "script-not-allowed: /"
precursor_case "a plain inline script is still rejected" alert "script-not-allowed: /"

# Encoding: the scanner reads UTF-8, so a page a browser would read as something
# else (a UTF-16 or UTF-32 BOM, a declared charset) must fail, not pass unseen.
encoding_case() {
    local label="$1" encoding="$2" ctype="$3" want="$4" ctype2="${5:-}" out rc=0
    out="$(PATH="$work/bin:$PATH" CURL_STUB_CSP="$csp" CURL_STUB_BEACON=one CURL_STUB_ENCODING="$encoding" CURL_STUB_CTYPE="$ctype" CURL_STUB_CTYPE2="$ctype2" SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=0 "$smoke" https://test-blog.chiefgyk3d.com "$pub" 2>&1)" || rc=$?
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

encoding_case "a UTF-16LE page with a BOM is rejected" utf16le "" "bad-encoding: /posts/"
encoding_case "a UTF-16BE page with a BOM is rejected" utf16be "" "bad-encoding: /posts/"
encoding_case "a UTF-32LE page with a BOM is rejected" utf32le "" "bad-encoding: /posts/"
encoding_case "a UTF-32BE page with a BOM is rejected" utf32be "" "bad-encoding: /posts/"
encoding_case "a NUL byte in a page is rejected" nul "" "bad-encoding: /posts/"
encoding_case "invalid UTF-8 in a page is rejected" invalid-utf8 "" "bad-encoding: /posts/"
encoding_case "a UTF-8 BOM in a page is rejected" utf8-bom "" "bad-encoding: /posts/"
encoding_case "a meta charset other than UTF-8 is rejected" meta-charset "" "bad-encoding: /posts/"
encoding_case "a meta http-equiv charset other than UTF-8 is rejected" meta-http-equiv "" "bad-encoding: /posts/"
encoding_case "a Content-Type header charset other than UTF-8 is rejected" "" "text/html; charset=iso-8859-1" "bad-encoding: /posts/"
encoding_case "a UTF-16 Content-Type header charset is rejected" "" "text/html; charset=utf-16" "bad-encoding: /posts/"
encoding_case "a meta with a duplicate charset attribute is rejected" dup-meta-charset "" "bad-encoding: /posts/"
encoding_case "a meta http-equiv with a duplicate content attribute is rejected" dup-meta-http-equiv "" "bad-encoding: /posts/"
encoding_case "a meta with the same charset attribute twice is rejected" dup-meta-charset-same "" "bad-encoding: /posts/"
encoding_case "a meta http-equiv with the same content attribute twice is rejected" dup-meta-http-equiv-same "" "bad-encoding: /posts/"
encoding_case "an ESC byte in a page is rejected" esc "" "bad-encoding: /posts/"
encoding_case "a BEL control byte in a page is rejected" bell "" "bad-encoding: /posts/"
encoding_case "tab, line feed, carriage return and form feed are allowed" controls-ok "" pass
encoding_case "a Content-Type header without a charset is rejected" "" "text/html" "bad-encoding: /posts/"
encoding_case "a second Content-Type header is rejected" "" "" "bad-encoding: /posts/" "text/html; charset=iso-8859-1"
encoding_case "a second Content-Type header with the same value is rejected" "" "" "bad-encoding: /posts/" "text/html; charset=utf-8"
encoding_case "UTF-8 declared in meta tags passes" utf8-meta "" pass
encoding_case "a UTF-8 Content-Type header charset passes" "" "text/html; charset=UTF-8" pass

((failures == 0)) || exit 1
echo "all browser-request smoke checks passed"
