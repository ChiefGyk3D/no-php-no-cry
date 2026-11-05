# shellcheck shell=bash
# Shared rules for scripts/check-output.sh and scripts/check-site-artifact.sh.
# Sourced, never run. The Content-Security-Policy says script-src 'self', and
# 'self' authorizes EVERY same-origin response, not one file. So the build is
# held to three things together:
#   1. only files of known non-script types ship, whatever their content
#      (artifact_name_ok): there is no second file a script could load;
#   2. nosniff is in the headers (headers_nosniff_ok), so a response that is not
#      served as JavaScript is not run as a script;
#   3. the one allowed script, /theme.js, is accepted only if its sha256 equals
#      the value in the committed hash file (theme_hash_state): with no hash
#      file no script is allowed at all, and any change to the script is a
#      reviewed change to that file (scripts/pin-theme.sh writes it);
#   4. the headers file is one "/*" rule block with no removal directive
#      (headers_policy_ok), so nothing detaches or overrides a header per path.

# artifact_name_ok <path relative to the site root>: succeeds for a file the
# build may carry. The three control files only at the root; everything else needs
# a listed extension, so no extension, a trailing dot, a dotfile and an unlisted
# extension (json, map, php, js, ...) all fail. /theme.js is checked by the caller.
artifact_name_ok() {
    local base="${1##*/}" ext
    case "$1" in
        _headers | _redirects | _routes.json) return 0 ;;
    esac
    [[ "$base" == *.* && "$base" != .* && "$base" != *. ]] || return 1
    ext="${base##*.}"
    ext="${ext,,}"
    case "$ext" in
        html | css | svg | xml | txt | png | jpg | jpeg | gif | webp | avif | ico | woff | woff2 | ttf | webmanifest) return 0 ;;
    esac
    return 1
}

# theme_hash_state <hash file>: prints the pinned sha256 and succeeds when the
# file is one line, "<64 lowercase hex>" optionally followed by spaces and
# theme.js (sha256sum format). Returns 1 for no file (no script is allowed) and
# 2 for a malformed one.
theme_hash_state() {
    local lines=()
    [[ -f "$1" ]] || return 1
    mapfile -t lines <"$1"
    [[ ${#lines[@]} -eq 1 ]] || return 2
    [[ "${lines[0]}" =~ ^([0-9a-f]{64})([[:space:]]+\*?theme\.js)?$ ]] || return 2
    printf '%s\n' "${BASH_REMATCH[1]}"
}

# svg_script_bad <file>: succeeds when an SVG carries a script element, an
# event-handler attribute or a javascript: URL.
svg_script_bad() {
    grep -qEi "<script|[[:space:]\"'/]on[a-z]+[[:space:]]*=|javascript:" "$1"
}

# headers_nosniff_ok <headers file>: succeeds when X-Content-Type-Options
# (any case) appears exactly once and its whole value is nosniff.
headers_nosniff_ok() {
    awk '
        { sub(/\r$/, "") }
        index($0, ":") && tolower(substr($0, 1, index($0, ":") - 1)) ~ /^[ \t]*x-content-type-options[ \t]*$/ {
            n++; v = tolower(substr($0, index($0, ":") + 1)); gsub(/^[ \t]+|[ \t]+$/, "", v)
            if (v != "nosniff") bad = 1
        }
        END { exit (n != 1 || bad) }' "$1"
}

# headers_policy_ok <headers file>: succeeds when the file has exactly one rule
# block, "/*", and no line that removes a header (one starting with "!"). A
# second block or a per-path rule could override a header; a removal directive
# could detach one.
headers_policy_ok() {
    awk '
        { sub(/\r$/, "") }
        /^[ \t]*$/ || /^[ \t]*#/ { next }
        /^[^ \t]/ { blocks++; if ($0 != "/*") bad = 1; next }
        { line = $0; sub(/^[ \t]+/, "", line); if (substr(line, 1, 1) == "!") bad = 1; if (blocks != 1) bad = 1 }
        END { exit (blocks != 1 || bad) }' "$1"
}

# routes_policy_ok <_routes.json file>: succeeds when the file is the strict
# subset of Cloudflare's routing file this site uses: a JSON object with exactly
# the keys version (1), include and exclude, both non-empty-or-empty lists of
# strings; every rule starts with "/", is at most 100 characters and has no
# space, control character or backslash; include and exclude together hold at
# most 100 rules; "include" has at least one rule; no duplicate JSON keys. The
# file only chooses which paths run the Pages Function; it cannot add code, but
# a loose file could silently send every asset request through the Function and
# spend the free request quota, so the shape is pinned. Needs python3.
routes_policy_ok() {
    python3 -I - "$1" <<'PY'
import json, sys

def pairs(items):
    keys = [k for k, _ in items]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate key")
    return dict(items)

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f, object_pairs_hook=pairs)
except (OSError, ValueError, RecursionError):
    sys.exit(1)

def rule_ok(r):
    return (isinstance(r, str) and r.startswith("/") and len(r) <= 100
            and all(32 < ord(c) < 127 and c != "\\" for c in r))

ok = (isinstance(data, dict) and set(data) == {"version", "include", "exclude"}
      and data["version"] == 1 and type(data["version"]) is int
      and isinstance(data["include"], list) and isinstance(data["exclude"], list)
      and len(data["include"]) >= 1
      and len(data["include"]) + len(data["exclude"]) <= 100
      and all(rule_ok(r) for r in data["include"] + data["exclude"]))
sys.exit(0 if ok else 1)
PY
}
