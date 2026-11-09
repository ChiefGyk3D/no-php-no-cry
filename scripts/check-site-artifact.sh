#!/usr/bin/env bash
# Usage: scripts/check-site-artifact.sh <site-dir> [expected-headers-file]
#
# Run on a built site directory before it is published to Cloudflare Pages. It
# rejects the files Pages treats as code or routing control that this site does
# not intentionally ship, and pins the two control files it does ship:
#   - _worker.js, a root functions/ directory, or anything whose name begins
#     with _worker (any depth, any type): Pages would run it. The Pages
#     Functions source lives in the repository's functions/ directory, outside
#     the upload directory that this script checks; a functions/ inside the
#     upload is still rejected
#   - symlinks anywhere (an artifact must be plain files)
#   - _headers that differs byte for byte from the repository's static/_headers
#     (the expected file must also carry script-src exactly 'self')
#   - _routes.json, REQUIRED at the root (with the Pages Function enabled, no
#     file would leave nothing limiting execution to HTML routes), that is not
#     the strict routing shape (routes_policy_ok) or differs byte for byte from
#     the repository's static/_routes.json (ROUTES_FILE overrides the path)
#   - any script file (.js, .mjs, .cjs, any depth) other than /copy.js and
#     /search.js, and a pinned script that is 1 KB gzip (1024 bytes) or more
#   - a page that loads a pinned script other than its own: /copy.js belongs to
#     /support/ and /search.js to /search/ (scripts/artifact-rules.sh)
#   - any file of a type not on the list (html css svg xml txt png jpg jpeg gif
#     webp avif ico woff woff2 ttf webmanifest asc (the public PGP key), plus _headers and _redirects at the root),
#     whatever its content or name: script-src 'self' authorizes every
#     same-origin response, so there must be no file a script could load
#   - a pinned script whose sha256 is not the one in its committed hash file,
#     copy.js.sha256 or search.js.sha256 at the repository root (SCRIPT_HASH_DIR
#     overrides the directory); with no such file that script is not allowed
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
expected_routes="${ROUTES_FILE:-$root/static/_routes.json}"
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

while IFS= read -r -d '' p; do
    report reserved-name "${p#"$dir"/}"
done < <(find "$dir" -mindepth 1 -maxdepth 1 -iname functions -print0)

while IFS= read -r -d '' p; do
    report symlink "${p#"$dir"/}"
done < <(find "$dir" -type l -print0 | sort -z)

# _headers: byte for byte the repository's file.
if [[ ! -f "$dir/_headers" || -L "$dir/_headers" ]]; then
    report headers-missing "_headers"
elif ! cmp -s "$dir/_headers" "$expected_headers"; then
    report headers-differ "_headers differs from the repository's static/_headers"
fi

# _routes.json (required): byte for byte the repository's file, and that file
# must itself be the strict shape. It decides which paths run the Function.
if [[ ! -e "$dir/_routes.json" && ! -L "$dir/_routes.json" ]]; then
    report routes-missing "_routes.json"
else
    if [[ -L "$dir/_routes.json" || ! -f "$dir/_routes.json" ]]; then
        report routes-invalid "_routes.json must be a plain file"
    elif [[ ! -f "$expected_routes" ]]; then
        report routes-missing-expected "no expected routes file at $(basename "$expected_routes")"
    elif ! routes_policy_ok "$expected_routes"; then
        report routes-invalid "expected routes file is not the strict shape"
    elif ! cmp -s "$dir/_routes.json" "$expected_routes"; then
        report routes-differ "_routes.json differs from the repository's static/_routes.json"
    fi
fi

# The expected policy: one script-src, exactly 'self' plus the Cloudflare Web Analytics beacon URL, one connect-src, exactly 'self',
# and no script-src-elem or script-src-attr to override it.
if ! awk -v beacon="https://static.cloudflareinsights.com/beacon.min.js/" '
    /^[[:space:]]*Content-Security-Policy:/ {
        sub(/^[^:]*:/, ""); n = split($0, d, ";"); count = 0; cs = 0
        for (i = 1; i <= n; i++) {
            gsub(/^[ \t]+|[ \t\r]+$/, "", d[i])
            name = tolower(d[i]); sub(/[ \t].*/, "", name)
            if (name == "script-src") { count++; v = d[i]; sub(/^[^ \t]+[ \t]*/, "", v); if (v != "'"'"'self'"'"' " beacon) bad = 1 }
            if (name == "connect-src") { cs++; v = d[i]; sub(/^[^ \t]+[ \t]*/, "", v); if (v != "'"'"'self'"'"'") bad = 1 }
            if (name == "script-src-elem" || name == "script-src-attr") bad = 1
        }
        if (count != 1 || cs != 1) bad = 1
        seen = 1
    }
    END { exit (bad || !seen) }' "$expected_headers"; then
    report headers-script-src "expected headers: script-src must be exactly 'self' plus the Cloudflare beacon URL, once, and connect-src exactly 'self'"
fi

for f in "$expected_headers" "$dir/_headers"; do
    if [[ -f "$f" && ! -L "$f" ]] && ! headers_policy_ok "$f"; then
        report headers-structure "${f#"$dir"/} must be one /* rule block with no removal directive"
    fi
done
if ! headers_nosniff_ok "$expected_headers"; then
    report headers-nosniff "expected headers: X-Content-Type-Options must be nosniff"
fi

# Every file must be of a listed type (js files are reported below, and the
# pinned scripts are checked for what they can do).
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

# Script files: the CSP allows 'self' scripts, so the only ones are the pinned
# scripts (artifact-rules.sh), and only if each one's sha256 is the one pinned in
# its committed hash file. No hash file, no script. Each is loaded by its own
# page only.
mapfile -t script_names < <(pinned_script_names)
declare -A pinned=()
for name in "${script_names[@]}"; do
    hash_file="$(pinned_hash_file "$name")"
    rc=0
    pinned[$name]="$(script_hash_state "$hash_file" "$name")" || rc=$?
    if [[ $rc -eq 2 ]]; then
        report script-hash-file "$(basename "$hash_file") must be one line: 64 lowercase hex characters (sha256sum format)"
        pinned[$name]=""
    fi
done
while IFS= read -r -d '' p; do
    rel="${p#"$dir"/}"
    if [[ -z "${pinned[$rel]:-}" ]]; then
        report extra-script "$rel"
    fi
done < <(find "$dir" -type f \( -iname '*.js' -o -iname '*.mjs' -o -iname '*.cjs' \) -print0 | sort -z)
for name in "${script_names[@]}"; do
    [[ -f "$dir/$name" && ! -L "$dir/$name" ]] || continue
    if [[ -n "${pinned[$name]}" && "$(sha256sum "$dir/$name" | cut -d' ' -f1)" != "${pinned[$name]}" ]]; then
        report script-hash "$name does not match the sha256 pinned in $(basename "$(pinned_hash_file "$name")")"
    fi
    gz="$(gzip -9 -n -c "$dir/$name" | wc -c)"
    if ((gz >= $(script_gzip_budget))); then
        report js-budget "$name is ${gz} bytes gzip (budget: under $(script_gzip_budget))"
    fi
done
# A page that loads a pinned script other than its own (a plain grep of the
# page: the markup rules are check-output.sh's).
while IFS= read -r -d '' p; do
    rel="${p#"$dir"/}"
    for name in "${script_names[@]}"; do
        if ! pinned_script_on_page "$name" "$rel" &&
            grep -qEi "<script[^>]*[[:space:]]src=[\"']?/${name//./\\.}([\"'[:space:]>]|\$)" "$p"; then
            report script-wrong-page "$rel loads /${name}, which belongs on $(pinned_script_page "$name") only"
        fi
    done
done < <(find "$dir" -type f -name '*.html' -print0 | sort -z)

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
