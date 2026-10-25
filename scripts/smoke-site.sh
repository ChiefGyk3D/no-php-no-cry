#!/usr/bin/env bash
# Usage: scripts/smoke-site.sh <site-url> <built-public-dir>
#
# Post-deploy smoke test. Against the deployed site it checks:
#   status        the home page answers HTTP 200
#   missing-csp   the Content-Security-Policy header equals the one the build
#                 carries in <public-dir>/_headers (from static/_headers)
#   redirect      the first 301 line of <public-dir>/_redirects answers 301
#                 with the expected Location
# The expectations are read from the build artifact, so they follow the site.
#
# Environment: SMOKE_RETRIES (default 5) retries each request with a delay, for
# edge propagation after a deploy. SMOKE_ALLOW_HTTP=1 permits a non-https URL
# (tests only).
set -euo pipefail

base="${1:?usage: smoke-site.sh <site-url> <public-dir>}"
dir="${2:?usage: smoke-site.sh <site-url> <public-dir>}"
retries="${SMOKE_RETRIES:-5}"
base="${base%/}"

if [[ "$base" != https://* && "${SMOKE_ALLOW_HTTP:-}" != 1 ]]; then
    echo "input: the site URL must be https (got ${base})"
    exit 2
fi

csp_expected=""
if [[ -f "$dir/_headers" ]]; then
    csp_expected="$(sed -n 's/^[[:space:]]*Content-Security-Policy:[[:space:]]*//p' "$dir/_headers" | head -n 1)"
fi
if [[ -z "$csp_expected" ]]; then
    echo "input: no Content-Security-Policy in ${dir}/_headers"
    exit 2
fi

from="" to=""
if [[ -f "$dir/_redirects" ]]; then
    read -r from to < <(awk '$1 ~ /^\// && $3 == "301" { print $1, $2; exit }' "$dir/_redirects") || true
fi
if [[ -z "$from" || -z "$to" ]]; then
    echo "input: no 301 line in ${dir}/_redirects"
    exit 2
fi

# fetch <path>: prints the status line and headers, fails if no response.
fetch() {
    curl -sS -o /dev/null -D - --max-time 20 \
        --retry "$retries" --retry-delay 3 --retry-all-errors \
        "${base}$1"
}

failed=0

home="$(fetch /)" || {
    echo "status: no response from ${base}/"
    exit 1
}
code="$(printf '%s' "$home" | tr -d '\r' | awk 'NR == 1 { print $2 }')"
# An edge that has not caught up yet can serve a stale or empty page; retry
# the whole check on a non-200 before failing.
attempt=0
while [[ "$code" != 200 && $attempt -lt "$retries" ]]; do
    sleep 3
    attempt=$((attempt + 1))
    home="$(fetch /)" || true
    code="$(printf '%s' "$home" | tr -d '\r' | awk 'NR == 1 { print $2 }')"
done
if [[ "$code" == 200 ]]; then
    echo "ok: ${base}/ answers 200"
else
    echo "status: ${base}/ answered '${code}', wanted 200"
    failed=1
fi

csp_actual="$(printf '%s' "$home" | tr -d '\r' | sed -n 's/^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]-[Ss][Ee][Cc][Uu][Rr][Ii][Tt][Yy]-[Pp][Oo][Ll][Ii][Cc][Yy]:[[:space:]]*//p' | head -n 1)"
if [[ "$csp_actual" == "$csp_expected" ]]; then
    echo "ok: Content-Security-Policy matches _headers"
else
    echo "missing-csp: Content-Security-Policy is '${csp_actual}', wanted '${csp_expected}'"
    failed=1
fi

redir="$(fetch "$from")" || redir=""
rcode="$(printf '%s' "$redir" | tr -d '\r' | awk 'NR == 1 { print $2 }')"
loc="$(printf '%s' "$redir" | tr -d '\r' | sed -n 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//p' | head -n 1)"
loc_path="${loc#"$base"}"
if [[ "$rcode" == 301 && "$loc_path" == "$to" ]]; then
    echo "ok: ${from} redirects 301 to ${to}"
else
    echo "redirect: ${from} answered '${rcode}' Location '${loc}', wanted 301 to ${to}"
    failed=1
fi

exit "$failed"
