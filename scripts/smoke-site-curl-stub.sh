#!/usr/bin/env bash
set -euo pipefail

body_file=""
user_agent=""
accept=""
url=""
while (($#)); do
    case "$1" in
        -o)
            body_file="$2"
            shift 2
            ;;
        -H | --header)
            case "$2" in
                Accept:*) accept="${2#Accept: }" ;;
                User-Agent:*) user_agent="${2#User-Agent: }" ;;
            esac
            shift 2
            ;;
        -D | --max-time)
            shift 2
            ;;
        -sS)
            shift
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done

remainder="${url#*://}"
path="/${remainder#*/}"
status=200
content_type=text/html
location=""
body=ok
if [[ "$path" != / && (-n "$user_agent" || -n "$accept") ]]; then
    echo "browser headers sent for non-home request $path" >&2
    exit 91
fi
case "$path" in
    /old/)
        status=301
        location=/posts/N0CALL/
        body=""
        ;;
    /feed/)
        status=301
        location=/feed/index.xml
        body=""
        ;;
    /feed/index.xml)
        content_type=application/xml
        body='<rss/>'
        ;;
    /smoke-check-missing-page/) status=404 ;;
    /)
        if [[ "${CURL_STUB_BEACON:-one}" != missing && "$user_agent" == *Firefox/* && "$accept" == "text/html,application/xhtml+xml" ]]; then
            beacon='<script defer src="https://static.cloudflareinsights.com/beacon.min.js/vTEST" integrity="sha512-test" data-cf-beacon="{&quot;token&quot;:&quot;public-test-token&quot;}"></script>'
            case "${CURL_STUB_BEACON:-one}" in
                one) body="<html>${beacon}</html>" ;;
                two) body="<html>${beacon}${beacon}</html>" ;;
                no-token) body="<html>${beacon/public-test-token/}</html>" ;;
            esac
        fi
        ;;
esac
printf '%s' "$body" >"$body_file"
printf 'HTTP/1.1 %s Test\r\n' "$status"
printf 'Content-Type: %s\r\n' "$content_type"
printf 'Content-Security-Policy: %s\r\n' "$CURL_STUB_CSP"
printf 'X-Content-Type-Options: nosniff\r\n'
[[ -z "$location" ]] || printf 'Location: %s\r\n' "$location"
printf '\r\n'
