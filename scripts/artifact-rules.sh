# shellcheck shell=bash
# Shared rules for scripts/check-output.sh and scripts/check-site-artifact.sh.
# Sourced, never run. The Content-Security-Policy says script-src 'self', and
# 'self' authorizes EVERY same-origin response, not one file. So the build is
# held to three things together:
#   1. only files of known non-script types ship, whatever their content
#      (artifact_name_ok): there is no second file a script could load;
#   2. nosniff is in the headers (headers_nosniff_ok), so a response that is not
#      served as JavaScript is not run as a script;
#   3. the one allowed script, /theme.js, cannot load or build code
#      (theme_capability_bad), so it cannot reach for a file in any case.

# artifact_name_ok <path relative to the site root>: succeeds for a file the
# build may carry. The two control files only at the root; everything else needs
# a listed extension, so no extension, a trailing dot, a dotfile and an unlisted
# extension (json, map, php, js, ...) all fail. /theme.js is checked by the caller.
artifact_name_ok() {
    local base="${1##*/}" ext
    case "$1" in
        _headers | _redirects) return 0 ;;
    esac
    [[ "$base" == *.* && "$base" != .* && "$base" != *. ]] || return 1
    ext="${base##*.}"
    ext="${ext,,}"
    case "$ext" in
        html | css | svg | xml | txt | png | jpg | jpeg | gif | webp | avif | ico | woff | woff2) return 0 ;;
    esac
    return 1
}

# theme_capability_bad <file>: succeeds (a finding) when the script can load or
# build code. Banned: bracket access, escape sequences, template literals and
# block comments (a name can be computed or hidden with them), and the names of
# the APIs that create elements, parse markup, navigate, fetch, spawn workers,
# run strings or reach the global object by name. A plain theme toggle needs
# none of them.
theme_capability_bad() {
    local names='import|importScripts|eval|Function|constructor|__proto__|createElement|createElementNS|createContextualFragment|createRange|importNode|adoptNode|cloneNode|appendChild|append|prepend|before|after|insertBefore|insertAdjacentHTML|insertAdjacentElement|replaceWith|replaceChild|replaceChildren|innerHTML|outerHTML|srcdoc|write|writeln|setAttribute|setAttributeNS|setAttributeNode|src|href|data|action|formAction|open|location|fetch|XMLHttpRequest|Worker|SharedWorker|serviceWorker|WebSocket|EventSource|sendBeacon|postMessage|DOMParser|Reflect|Proxy|Object|globalThis|top|parent|opener|frames|with|setTimeout|setInterval|execScript|Image|Audio|Option|Blob|URL|createObjectURL'
    grep -qE '\[|\\|`|/\*' "$1" && return 0
    grep -qE "(^|[^A-Za-z0-9_\$])(${names})([^A-Za-z0-9_\$]|\$)" "$1" && return 0
    return 1
}

# svg_script_bad <file>: succeeds when an SVG carries a script element, an
# event-handler attribute or a javascript: URL.
svg_script_bad() {
    grep -qEi "<script|[[:space:]\"'/]on[a-z]+[[:space:]]*=|javascript:" "$1"
}

# headers_nosniff_ok <headers file>: succeeds when X-Content-Type-Options is
# nosniff.
headers_nosniff_ok() {
    grep -qEi '^[[:space:]]*X-Content-Type-Options:[[:space:]]*nosniff[[:space:]]*$' "$1"
}
