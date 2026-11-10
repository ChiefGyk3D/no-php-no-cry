#!/usr/bin/env bash
# Read-only crosscheck of legacy WordPress URL paths against a built site.
#
#   scripts/crosscheck-redirects.sh [--allow-gaps] <paths-file> <output-dir>
#
# <paths-file> holds one legacy URL path per line (a full URL is cut down to its
# path; blank lines and '#' comments are skipped). <output-dir> is a built site
# (hugo --destination). For each path the script applies the generated
# <output-dir>/_redirects the way Cloudflare Pages does (the first matching rule
# wins, a trailing '*' is a splat, ':splat' in the target is replaced, redirects
# run before static files) and follows up to 5 hops, then reports:
#
#   ok    redirect   a 301 chain that ends on a path that exists in the build
#   ok    served     no rule, but the build has a file there
#   ok    alias      no rule, but an alias stub page (meta refresh) whose target exists
#   FAIL  <detail>   a rule or stub whose target is missing, a loop, or a bad status
#   GAP   no rule    no rule and no file: the path would be a 404
#
# Exit 0 when nothing failed and there is no gap (--allow-gaps tolerates gaps),
# 1 otherwise, 2 for a usage error. It makes no network calls and writes nothing.
set -uo pipefail

allow_gaps=0
if [[ "${1:-}" == "--allow-gaps" ]]; then
    allow_gaps=1
    shift
fi
if [[ $# -ne 2 ]]; then
    echo "usage: crosscheck-redirects.sh [--allow-gaps] <paths-file> <output-dir>" >&2
    exit 2
fi
list="$1"
out="$2"
if [[ ! -f "$list" ]]; then
    echo "crosscheck: no such paths file: $list" >&2
    exit 2
fi
if [[ ! -d "$out" ]]; then
    echo "crosscheck: no such output directory: $out" >&2
    exit 2
fi
if [[ ! -f "$out/_redirects" ]]; then
    echo "crosscheck: $out/_redirects is missing (is this a built site?)" >&2
    exit 2
fi

# The rules, in file order: from, to, status.
rf=()
rt=()
rs=()
while read -r from to status _; do
    [[ -z "${from:-}" || "$from" == \#* ]] && continue
    rf+=("$from")
    rt+=("$to")
    rs+=("${status:-301}")
done <"$out/_redirects"

# decode <path>: percent-decode a URL path.
decode() {
    local s="$1" r="" h
    while [[ "$s" == *%* ]]; do
        r+="${s%%%*}"
        s="${s#*%}"
        h="${s:0:2}"
        if [[ "$h" =~ ^[0-9A-Fa-f]{2}$ ]]; then
            r+="$(printf "\\x$h")"
            s="${s:2}"
        else
            r+="%"
        fi
    done
    printf '%s' "$r$s"
}

# file_for <path>: the file in the build that serves this URL path, if any.
file_for() {
    local p f
    p="$(decode "${1%%#*}")"
    f="$out$p"
    if [[ "$p" == */ ]]; then
        [[ -f "${f}index.html" ]] && printf '%s' "${f}index.html"
    elif [[ -f "$f" ]]; then
        printf '%s' "$f"
    elif [[ -f "$f/index.html" ]]; then
        printf '%s' "$f/index.html"
    else
        return 1
    fi
}

# match <path>: set m_to and m_status from the first rule that matches, else return 1.
match() {
    local p="$1" i f pre
    for i in "${!rf[@]}"; do
        f="${rf[$i]}"
        if [[ "$f" == *'*' ]]; then
            pre="${f%\*}"
            if [[ "$p" == "$pre"* ]]; then
                m_to="${rt[$i]//:splat/${p#"$pre"}}"
                m_status="${rs[$i]}"
                return 0
            fi
        elif [[ "$p" == "$f" ]]; then
            m_to="${rt[$i]}"
            m_status="${rs[$i]}"
            return 0
        fi
    done
    return 1
}

# stub_target <file>: the meta-refresh target path of an alias stub page.
stub_target() {
    grep -ioE 'http-equiv="?refresh"?[^>]*url=[^"> ]+' "$1" | head -n 1 | sed -E 's/.*url=//I; s#^https?://[^/]+##'
}

ok=0
gap=0
fail=0
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    p="$line"
    if [[ "$p" == http*://* ]]; then
        p="${p#*://}"
        p="/${p#*/}"
    fi
    [[ "$p" == /* ]] || p="/$p"
    p="${p%%#*}"
    p="${p%%\?*}"
    cur="$p"
    hops=0
    verdict=""
    while :; do
        if match "$cur"; then
            if [[ "$m_status" != 301 ]]; then
                verdict="FAIL status $m_status on $cur"
                break
            fi
            hops=$((hops + 1))
            cur="${m_to%%#*}"
            if [[ $hops -gt 5 ]]; then
                verdict="FAIL redirect loop"
                break
            fi
            continue
        fi
        # No (further) rule: the path must be a file in the build.
        if [[ $hops -gt 0 ]]; then
            if file_for "$cur" >/dev/null; then
                verdict="ok redirect -> $cur"
            else
                verdict="FAIL redirect to missing $cur"
            fi
        elif f="$(file_for "$cur")"; then
            tgt="$(stub_target "$f")"
            if [[ -z "$tgt" ]]; then
                verdict="ok served"
            elif file_for "$tgt" >/dev/null; then
                verdict="ok alias -> $tgt"
            else
                verdict="FAIL alias to missing $tgt"
            fi
        else
            verdict="GAP no rule"
        fi
        break
    done
    case "$verdict" in
        ok*) ok=$((ok + 1)) ;;
        GAP*) gap=$((gap + 1)) ;;
        *) fail=$((fail + 1)) ;;
    esac
    printf '%s\t%s\n' "$p" "$verdict"
done <"$list"

echo "crosscheck: ok $ok, gap $gap, fail $fail"
if [[ $fail -gt 0 ]]; then exit 1; fi
if [[ $gap -gt 0 && $allow_gaps -eq 0 ]]; then exit 1; fi
exit 0
