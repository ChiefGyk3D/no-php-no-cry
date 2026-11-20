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
            beacon='<script type="module" src="https://static.cloudflareinsights.com/beacon.min.js/vTEST" integrity="sha512-test" data-cf-beacon='"'"'{"version":"2024.11.0","token":"N0TST","r":1,"spa":2}'"'"' crossorigin="anonymous"></script>'
            case "${CURL_STUB_BEACON:-one}" in
                one) body="<html>${beacon}</html>" ;;
                two) body="<html>${beacon}${beacon}</html>" ;;
                no-token) body="<html>${beacon/N0TST/}</html>" ;;
                script-type) body="<html>${beacon/type=\"module\"/type=\"text\/javascript\"}</html>" ;;
                spaced-type) body="<html>${beacon/type=\"module\"/type=\" module\"}</html>" ;;
                newline-type) body="<html>${beacon/type=\"module\"/$'type="mo\ndule"'}</html>" ;;
                no-integrity) body="<html>${beacon/ integrity=\"sha512-test\"/}</html>" ;;
                bad-crossorigin) body="<html>${beacon/crossorigin=\"anonymous\"/crossorigin=\"use-credentials\"}</html>" ;;
                extra-attribute) body="<html>${beacon/<script /<script data-test=unknown }</html>" ;;
                inline-body) body="<html>${beacon/<\/script>/x()<\/script>}</html>" ;;
            esac
        fi
        ;;
esac
# CURL_STUB_PRECURSOR adds the snippet Cloudflare injects at the edge (Precursor,
# observed on 2026-11-20; the per-request values are replaced by fixed ones of
# the same shape) to every HTML page that answers 200, as the real edge does.
# One variant per case of scripts/test-smoke-site-browser-request.sh.
if [[ -n "${CURL_STUB_PRECURSOR:-}" && "$status" == 200 && "$content_type" == text/html ]]; then
    ray=a5d75b7a99234fa9
    pre_a=$'window.__CF$cv$params={r:\''
    pre_b=$'\',t:\'MTc5NTE3NjY4Nw==\',u:\'01a1f8de693b77ff8797ecd89f056a26\',ut:\'qSfHbBdqBR2fpGPmsiATGAzCUzUlQAEQRmh5UW2JC7Y-1795176687-1.2.1.1-EB.WKWouzfLG1PX4s2FeKYZlPMcQUx2DKthc8hxIWSUgwDAxaO1SJz9zNWpVeygeVqPHHaR_Fepiblcr.SNIhpc8aXaYj_OP0YafcMHZYvY\',i:60};(function(){if(!document.body)return;var l=window.location,o;try{o=new URL(l.origin).origin}catch(e){try{o=new URL(new URL(l.href).origin).origin}catch(e){o=\'\'}}var u=\''
    pre_c=$'\',s=document.createElement(\'script\');s.src=o?new URL(u,o).href:u;document.head.appendChild(s);})();'
    pre_path=/cdn-cgi/challenge-platform/scripts/precursor/main.js
    pre_query="?ray=${ray}"
    pre_open="<script>"
    pre_before="" pre_after="" pre_repeat=1
    case "$CURL_STUB_PRECURSOR" in
        one) ;;
        two) pre_repeat=2 ;;
        appended) pre_after="alert(1);" ;;
        prefixed) pre_before="alert(1);" ;;
        wrong-path) pre_path=/cdn-cgi/challenge-platform/scripts/other/main.js ;;
        wrong-host) pre_path=https://e.example/cdn-cgi/challenge-platform/scripts/precursor/main.js ;;
        wrong-ray) pre_query="?ray=0123456789abcdef" ;;
        no-ray) pre_query="" ;;
        extra-query) pre_query="?ray=${ray}&x=1" ;;
        attr-type) pre_open="<script type=text/javascript>" ;;
        attr-src) pre_open="<script src=/x.js>" ;;
        attr-nonce) pre_open="<script nonce=abc>" ;;
        attr-defer) pre_open="<script defer>" ;;
        trailing-space) pre_after=" " ;;
        self-closing-comment)
            pre_open="<script/>"
            pre_before=$'<!--\nalert(1)\n-->'
            ;;
        self-closing) pre_open="<script/>" ;;
        self-closing-space-upper) pre_open="<SCRIPT />" ;;
        self-closing-attribute) pre_open="<script a=b />" ;;
        self-closing-sibling) pre_open="<script/><script>" ;;
        comment-in-body) pre_before="<!--" ;;
        cdata-in-body) pre_before="<![CDATA[" ;;
        alert) pre_before="alert(1)" pre_a="" pre_b="" pre_c="" pre_path="" pre_query="" ray="" ;;
    esac
    pre="${pre_open}${pre_before}${pre_a}${ray}${pre_b}${pre_path}${pre_query}${pre_c}${pre_after}</script>"
    for ((i = 0; i < pre_repeat; i++)); do
        body="${body}${pre}"
    done
fi
printf '%s' "$body" >"$body_file"
printf 'HTTP/1.1 %s Test\r\n' "$status"
printf 'Content-Type: %s\r\n' "$content_type"
printf 'Content-Security-Policy: %s\r\n' "$CURL_STUB_CSP"
printf 'X-Content-Type-Options: nosniff\r\n'
[[ -z "$location" ]] || printf 'Location: %s\r\n' "$location"
printf '\r\n'
