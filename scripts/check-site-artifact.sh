#!/usr/bin/env bash
# Usage: scripts/check-site-artifact.sh <site-dir> [expected-headers-file]
#
# Run on a built site directory before it is published to Cloudflare Pages. It
# rejects the files Pages treats as code or routing control that this site does
# not intentionally ship, and pins the two control files it does ship:
#   - _worker.js, _routes.json, a root functions/ directory, or anything whose
#     name begins with _worker (any depth, any type): Pages would run it
#   - symlinks anywhere (an artifact must be plain files)
#   - _headers that differs byte for byte from the repository's static/_headers
#     (the expected file must also carry script-src exactly 'self')
#   - any script file (.js, .mjs, .cjs, any depth) other than /theme.js, and a
#     /theme.js that is 1 KB gzip (1024 bytes) or more
#   - any file of a type not on the list (html css svg xml txt png jpg jpeg gif
#     webp avif ico woff woff2, plus _headers and _redirects at the root),
#     whatever its content or name: script-src 'self' authorizes every
#     same-origin response, so there must be no file a script could load
#   - /theme.js whose sha256 is not the one in the committed theme.js.sha256
#     (THEME_HASH_FILE overrides the path); with no such file no script at all
#   - a _headers that is not exactly one "/*" block, or has a removal directive
#   - an SVG with a script element, event handler or javascript: URL
#   - expected headers without X-Content-Type-Options: nosniff
#   - _redirects with a line that is not a comment, blank, or
#     "/source /target 301|302" with internal targets only, or over 2000 lines
#
# The default expected headers file is static/_headers next to this script's
# repository root. Prints one line per problem; exit 1 on any, 2 on bad usage.
set -euo pipefail

# shellcheck source=scripts/artifact-rules.sh
source "$(dirname "${BASH_SOURCE[0]}")/artifact-rules.sh"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: check-site-artifact.sh <site-dir> [expected-headers-file]" >&2
    exit 2
fi
dir="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected_headers="${2:-$root/static/_headers}"
theme_hash_file="${THEME_HASH_FILE:-$root/theme.js.sha256}"
[[ -d "$dir" ]] || {
    echo "check-site-artifact: not a directory: $dir" >&2
    exit 2
}
[[ -f "$expected_headers" ]] || {
    echo "check-site-artifact: expected headers file not found: $expected_headers" >&2
    exit 2
}

max_redirect_lines=2000
findings=0
report() {
    printf '::error title=Site artifact::[%s] %s\n' "$1" "$2"
    findings=$((findings + 1))
}

# Reserved names, any depth, any file type (a _worker.js directory counts).
while IFS= read -r -d '' p; do
    report reserved-name "${p#"$dir"/}"
done < <(find "$dir" -iname '_worker*' -print0 | sort -z)

for name in _routes.json functions; do
    while IFS= read -r -d '' p; do
        report reserved-name "${p#"$dir"/}"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -iname "$name" -print0)
done

while IFS= read -r -d '' p; do
    report symlink "${p#"$dir"/}"
done < <(find "$dir" -type l -print0 | sort -z)

# _headers: byte for byte the repository's file.
if [[ ! -f "$dir/_headers" || -L "$dir/_headers" ]]; then
    report headers-missing "_headers"
elif ! cmp -s "$dir/_headers" "$expected_headers"; then
    report headers-differ "_headers differs from the repository's static/_headers"
fi

# The expected policy: one script-src, exactly 'self' (the theme file only),
# and no script-src-elem or script-src-attr to override it.
if ! awk '
    /^[[:space:]]*Content-Security-Policy:/ {
        sub(/^[^:]*:/, ""); n = split($0, d, ";"); count = 0
        for (i = 1; i <= n; i++) {
            gsub(/^[ \t]+|[ \t\r]+$/, "", d[i])
            name = tolower(d[i]); sub(/[ \t].*/, "", name)
            if (name == "script-src") { count++; v = d[i]; sub(/^[^ \t]+[ \t]*/, "", v); if (v != "'"'"'self'"'"'") bad = 1 }
            if (name == "script-src-elem" || name == "script-src-attr") bad = 1
        }
        if (count != 1) bad = 1
        seen = 1
    }
    END { exit (bad || !seen) }' "$expected_headers"; then
    report headers-script-src "expected headers: script-src must be exactly 'self', once"
fi

for f in "$expected_headers" "$dir/_headers"; do
    if [[ -f "$f" && ! -L "$f" ]] && ! headers_policy_ok "$f"; then
        report headers-structure "${f#"$dir"/} must be one /* rule block with no removal directive"
    fi
done
if ! headers_nosniff_ok "$expected_headers"; then
    report headers-nosniff "expected headers: X-Content-Type-Options must be nosniff"
fi

# Every file must be of a listed type (js files are reported below, and
# /theme.js is checked for what it can do).
while IFS= read -r -d '' p; do
    rel="${p#"$dir"/}"
    case "${rel,,}" in
        *.js | *.mjs | *.cjs) continue ;;
    esac
    artifact_name_ok "$rel" || report unexpected-file "$rel"
    if [[ "${rel,,}" == *.svg ]] && svg_script_bad "$p"; then
        report script-in-markup "$rel"
    fi
done < <(find "$dir" -type f -print0 | sort -z)

# Script files: the CSP allows 'self' scripts, so the only one is /theme.js, and
# only if its sha256 is the one pinned in the committed hash file. No hash file,
# no script.
pinned=""
rc=0
pinned="$(theme_hash_state "$theme_hash_file")" || rc=$?
if [[ $rc -eq 2 ]]; then
    report theme-hash-file "$(basename "$theme_hash_file") must be one line: 64 lowercase hex characters (sha256sum format)"
    pinned=""
fi
while IFS= read -r -d '' p; do
    rel="${p#"$dir"/}"
    if [[ "$rel" != theme.js || -z "$pinned" ]]; then
        report extra-script "$rel"
    fi
done < <(find "$dir" -type f \( -iname '*.js' -o -iname '*.mjs' -o -iname '*.cjs' \) -print0 | sort -z)
if [[ -f "$dir/theme.js" && ! -L "$dir/theme.js" ]]; then
    if [[ -n "$pinned" && "$(sha256sum "$dir/theme.js" | cut -d' ' -f1)" != "$pinned" ]]; then
        report theme-hash "theme.js does not match the sha256 pinned in $(basename "$theme_hash_file")"
    fi
    gz="$(gzip -9 -n -c "$dir/theme.js" | wc -c)"
    if ((gz >= 1024)); then
        report js-budget "theme.js is ${gz} bytes gzip (budget: under 1024)"
    fi
fi

# _redirects: internal 301/302 rules only.
if [[ -f "$dir/_redirects" && ! -L "$dir/_redirects" ]]; then
    total="$(wc -l <"$dir/_redirects")"
    # A last line without a newline is not counted by wc -l.
    if [[ -n "$(tail -c1 "$dir/_redirects")" ]]; then
        total=$((total + 1))
    fi
    if ((total > max_redirect_lines)); then
        report redirects-too-long "_redirects has ${total} lines (limit ${max_redirect_lines})"
    fi
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        [[ -z "$line" || "$line" == '#'* ]] && continue
        # The target must also not start with // or /\ (a scheme-relative or
        # backslash host form), which the pattern alone would allow.
        if [[ ! "$line" =~ ^/[^[:space:]]*\ /[^[:space:]]*\ 30[12]$ ]] ||
            [[ "$line" == *' //'* || "$line" == *' /\'* || "$line" == *'\'* ]]; then
            report redirects-line "_redirects line ${n} is not '/from /to 301|302' with internal paths"
        fi
    done <"$dir/_redirects"
fi

if [[ $findings -gt 0 ]]; then
    echo "check-site-artifact: $findings finding(s)"
    exit 1
fi
echo "check-site-artifact: ok ($dir)"
