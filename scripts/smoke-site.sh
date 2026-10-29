#!/usr/bin/env bash
# Usage: scripts/smoke-site.sh <site-url> <built-public-dir>
#
# Post-deploy smoke test. Against the deployed site it checks:
#   status        every page below answers as expected (200, and 404 for a name
#                 that does not exist)
#   missing-csp / duplicate-csp / wrong-csp
#                 on EVERY page below the response carries exactly one
#                 Content-Security-Policy header, equal to the one the build
#                 carries in <public-dir>/_headers (from static/_headers), which
#                 must itself carry script-src exactly 'self' (else exit 2)
#   missing-nosniff / wrong-nosniff
#                 on every page, exactly one X-Content-Type-Options header whose
#                 only value is nosniff
#   redirect      the first 301 line of <public-dir>/_redirects answers 301
#                 with the expected Location
#   theme-hash    when the build has a theme.js, the deployed /theme.js has the
#                 sha256 pinned in theme.js.sha256 (THEME_HASH_FILE overrides)
#   script-not-allowed / script-count / event-handler / javascript-url /
#   external-asset / http-reference / base-element
#                 the bytes each page SERVES (the same response as its headers)
#                 are read with scripts/scan-markup.py, the build check's parser:
#                 no script element other than one <script src=/theme.js></script>
#                 (and none at all without a pinned theme), no handler, no
#                 javascript: URL. It reads the served page only; it does not
#                 fetch or inspect any other script file (the build checks do).
# Pages checked, one per template, taken from the build: the home page, the
# first post and journal entry, the posts and journal lists, the first tag and
# category page, the feed (/index.xml) and the 404 page (asked for as
# /smoke-check-missing-page/). The build must hold at least one single page and
# one list page (else exit 2). The expectations are read from the build, so
# they follow the site.
#
# Environment: SMOKE_RETRIES (default 5) re-runs the WHOLE set of checks, up to
# that many more times, until all pass, for edge propagation after a deploy.
# SMOKE_RETRY_SLEEP (default 3) is the delay in seconds between attempts.
# SMOKE_ALLOW_HTTP=1 permits a non-https URL (tests only).
set -euo pipefail

# shellcheck source=scripts/artifact-rules.sh
source "$(dirname "${BASH_SOURCE[0]}")/artifact-rules.sh"

base="${1:?usage: smoke-site.sh <site-url> <public-dir>}"
dir="${2:?usage: smoke-site.sh <site-url> <public-dir>}"
retries="${SMOKE_RETRIES:-5}"
retry_sleep="${SMOKE_RETRY_SLEEP:-3}"
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

# The build's policy must allow scripts from 'self' only (the theme file): one
# script-src, exactly 'self'. 'none' would mean the header and the theme script
# drifted apart; anything looser is a weaker site than the one reviewed.
if ! awk -v csp="$csp_expected" 'BEGIN {
        n = split(csp, d, ";")
        for (i = 1; i <= n; i++) {
            gsub(/^[ \t]+|[ \t\r]+$/, "", d[i])
            name = tolower(d[i]); sub(/[ \t].*/, "", name)
            if (name == "script-src") { count++; v = d[i]; sub(/^[^ \t]+[ \t]*/, "", v); if (v != "'"'"'self'"'"'") bad = 1 }
            if (name == "script-src-elem" || name == "script-src-attr") bad = 1
        }
        exit (bad || count != 1)
    }'; then
    echo "input: the Content-Security-Policy in ${dir}/_headers must have script-src exactly 'self'"
    exit 2
fi

if ! headers_policy_ok "$dir/_headers"; then
    echo "input: ${dir}/_headers must be one /* rule block with no removal directive"
    exit 2
fi
if ! headers_nosniff_ok "$dir/_headers"; then
    echo "input: ${dir}/_headers must carry X-Content-Type-Options: nosniff exactly once"
    exit 2
fi

# first_page <section>: the path of the first page in a section of the build
# (posts, journal, tags, categories), or nothing.
first_page() {
    local p
    p="$(find "$dir/$1" -mindepth 2 -maxdepth 2 -name index.html 2>/dev/null | sort | head -n 1)" || true
    [[ -n "$p" ]] || return 0
    p="${p#"$dir"}"
    printf '%s/\n' "${p%/index.html}"
}

# The theme script: a theme.js in the build must match the pinned hash (else
# exit 2), and the deployed /theme.js must be exactly those bytes.
theme_hash_file="${THEME_HASH_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/theme.js.sha256}"
theme_pinned=""
if [[ -f "$dir/theme.js" ]]; then
    rc=0
    theme_pinned="$(theme_hash_state "$theme_hash_file")" || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "input: ${dir}/theme.js is in the build but there is no valid pinned hash at ${theme_hash_file}"
        exit 2
    fi
    if [[ "$(sha256sum "$dir/theme.js" | cut -d' ' -f1)" != "$theme_pinned" ]]; then
        echo "input: ${dir}/theme.js does not match the pinned hash in ${theme_hash_file}"
        exit 2
    fi
fi

scan_py="$(dirname "${BASH_SOURCE[0]}")/scan-markup.py"
site_host="${base#*://}"
site_host="${site_host%%/*}"
site_host="${site_host%%:*}"
missing_page=/smoke-check-missing-page/
singles=() lists=() pages=(/)
for section in posts journal; do
    p="$(first_page "$section")"
    [[ -n "$p" ]] && singles+=("$p")
    [[ -f "$dir/$section/index.html" ]] && lists+=("/$section/")
done
for section in tags categories; do
    p="$(first_page "$section")"
    [[ -n "$p" ]] && lists+=("$p")
done
if [[ ${#singles[@]} -eq 0 || ${#lists[@]} -eq 0 ]]; then
    echo "input: ${dir} has no post or journal page, or no list page, to check"
    exit 2
fi
pages+=("${singles[@]}" "${lists[@]}")
[[ -f "$dir/index.xml" ]] && pages+=(/index.xml)
[[ -n "$theme_pinned" ]] && pages+=(/theme.js)

from="" to=""
if [[ -f "$dir/_redirects" ]]; then
    read -r from to < <(awk '$1 ~ /^\// && $3 == "301" { print $1, $2; exit }' "$dir/_redirects") || true
fi
if [[ -z "$from" || -z "$to" ]]; then
    echo "input: no 301 line in ${dir}/_redirects"
    exit 2
fi

# fetch <path>: prints the status line and headers, fails if no response.
# The body goes to $body_file from the same request, so headers and body are
# judged from ONE response (a second request could be answered differently).
body_dir="$(mktemp -d)"
trap 'rm -rf "$body_dir"' EXIT
body_file="$body_dir/body"
fetch() {
    : >"$body_file"
    curl -sS -o "$body_file" -D - --max-time 20 "${base}$1"
}

status_of() { printf '%s' "$1" | tr -d '\r' | awk 'NR == 1 { print $2 }'; }

# header_values <name>: reads a response's headers on stdin and prints the value
# of each header of that name (any case), one per line.
header_values() {
    awk -v want="$1" '{ sub(/\r$/, "") }
        index($0, ":") && tolower(substr($0, 1, index($0, ":") - 1)) == want {
            v = substr($0, index($0, ":") + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v
        }'
}

# check_page <path>: status, exactly one expected Content-Security-Policy, and
# nosniff on one page. Prints a line per result; fails if any check does.
check_page() {
    local path="$1" want=200 got resp="" code csp_count csp_actual nosniff_values ok=0 failed=0
    [[ "$path" == "$missing_page" ]] && want=404
    if resp="$(fetch "$path")"; then
        code="$(status_of "$resp")"
        if [[ "$code" == "$want" ]]; then
            ok=1
        else
            echo "status: ${path} answered '${code}', wanted ${want}"
            failed=1
        fi
    else
        resp=""
        echo "status: no response from ${path}"
        failed=1
    fi
    csp_count="$(printf '%s' "$resp" | header_values content-security-policy | wc -l)"
    csp_actual="$(printf '%s' "$resp" | header_values content-security-policy | head -n 1)"
    if [[ "$csp_count" -eq 0 ]]; then
        echo "missing-csp: ${path} has no Content-Security-Policy header"
        failed=1
    elif [[ "$csp_count" -gt 1 ]]; then
        echo "duplicate-csp: ${path} has ${csp_count} Content-Security-Policy headers, wanted 1"
        failed=1
    elif [[ "$csp_actual" != "$csp_expected" ]]; then
        echo "wrong-csp: ${path} has Content-Security-Policy '${csp_actual}', wanted '${csp_expected}'"
        failed=1
    fi
    nosniff_values="$(printf '%s' "$resp" | header_values x-content-type-options)"
    if [[ -z "$nosniff_values" ]]; then
        echo "missing-nosniff: ${path} has no X-Content-Type-Options header"
        failed=1
    elif [[ "${nosniff_values,,}" != nosniff ]]; then
        echo "wrong-nosniff: ${path} must have exactly one X-Content-Type-Options header with the value nosniff"
        failed=1
    fi
    if [[ "$path" == /theme.js ]]; then
        got="$(sha256sum <"$body_file" | cut -d' ' -f1)"
        if [[ "$got" != "$theme_pinned" ]]; then
            echo "theme-hash: ${path} served by the site does not match the pinned sha256"
            failed=1
        fi
    fi
    # What the site serves, read with the build check's parser (same request as
    # the headers above): no extra, inline, remote or handler scripts.
    if [[ "$path" != /theme.js && $ok -eq 1 ]]; then
        local opts=(--scripts none) found rule
        [[ -n "$theme_pinned" ]] && opts=(--scripts theme)
        [[ "$path" == *.xml ]] && opts=(--markup)
        found="$(python3 -I "$scan_py" "${opts[@]}" "$site_host" "$body_file")" || found="unparseable-html"
        while IFS= read -r rule; do
            [[ -n "$rule" ]] || continue
            echo "${rule}: ${path} serves markup the policy does not allow"
            failed=1
        done <<<"$found"
    fi
    if [[ $failed -eq 0 && $ok -eq 1 ]]; then
        echo "ok: ${path} answers ${want} with the expected policy and nosniff"
    fi
    return "$failed"
}

# attempt: runs every check once, printing one line per check. Returns 0 only
# if all passed.
attempt() {
    local failed=0 page code redir rcode loc loc_path

    for page in "${pages[@]}" "$missing_page"; do
        check_page "$page" || failed=1
    done

    redir="$(fetch "$from")" || redir=""
    rcode="$(status_of "$redir")"
    loc="$(printf '%s' "$redir" | tr -d '\r' | sed -n 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//p' | head -n 1)"
    loc_path="${loc#"$base"}"
    if [[ "$rcode" == 301 && "$loc_path" == "$to" ]]; then
        echo "ok: ${from} redirects 301 to ${to}"
    else
        echo "redirect: ${from} answered '${rcode}' Location '${loc}', wanted 301 to ${to}"
        failed=1
    fi

    return "$failed"
}

n=0
while :; do
    if out="$(attempt)"; then
        printf '%s\n' "$out"
        exit 0
    fi
    if [[ $n -ge $retries ]]; then
        printf '%s\n' "$out"
        echo "smoke: still failing after $((n + 1)) attempt(s)"
        exit 1
    fi
    n=$((n + 1))
    echo "retry ${n}/${retries}: not ready, waiting ${retry_sleep} s"
    sleep "$retry_sleep"
done
