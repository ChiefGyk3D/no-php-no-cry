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

# theme_capability_bad <file>: succeeds (a finding) when the script is not
# plainly a theme toggle. It is an ALLOWLIST, so a DOM API nobody listed (new or
# old) is refused instead of needing to be thought of:
#   - ASCII only; no backslash (escapes), backtick (templates), bracket access,
#     or comment (// and /* */);
#   - a member after a dot must be one of PROPS below (names after "dataset."
#     are free); string arguments are checked for createElement (only "button")
#     and setAttribute (only the listed attribute names);
#   - a bare name must be a keyword or global from BARE below, or at most three
#     characters (a local such as t or e).
# To let the theme toggle use another API, add its name to PROPS or BARE here,
# in a reviewed change that also adds a test, and list it in docs/theme-script.md.
theme_capability_bad() {
    python3 -I -c '
import re
import sys

PROPS = set("""documentElement body head dataset classList add remove toggle contains
getItem setItem matches matchMedia addEventListener getAttribute removeAttribute
setAttribute createElement appendChild textContent type hidden title className
querySelector getElementById preventDefault target currentTarget document
localStorage""".split())
BARE = set("""var let const function if else return try catch finally new typeof true false
null undefined this document window localStorage matchMedia""".split())
ATTRS = ("data-theme", "aria-pressed", "aria-label", "type", "title", "class", "hidden")

raw = open(sys.argv[1], "rb").read()
try:
    text = raw.decode("ascii")
except UnicodeDecodeError:
    sys.exit(0)
if "\\" in text or "`" in text:
    sys.exit(0)

# String-argument rules, on the text as written.
n_create = len(re.findall(r"\bcreateElement\b", text))
ok_create = len(re.findall(r"\.\s*createElement\s*\(\s*([\"\x27])button\1\s*\)", text))
attr_alt = "|".join(re.escape(a) for a in ATTRS)
n_set = len(re.findall(r"\bsetAttribute\b", text))
ok_set = len(re.findall(r"\.\s*setAttribute\s*\(\s*([\"\x27])(?:%s)\1\s*," % attr_alt, text))
if n_create != ok_create or n_set != ok_set:
    sys.exit(0)

# Strings out (they hold no code once eval, Function and timers are not names).
code = re.sub(r"\"[^\"\n]*\"|\x27[^\x27\n]*\x27", "\"\"", text)
if "[" in code or "//" in code or "/*" in code:
    sys.exit(0)
code = re.sub(r"\bdataset\s*\.\s*[A-Za-z_$][\w$]*", "dataset", code)
for m in re.finditer(r"(?<![\w$])([A-Za-z_$][\w$]*)", code):
    name = m.group(1)
    before = code[: m.start()].rstrip()
    if before.endswith("."):
        if name not in PROPS:
            sys.exit(0)
    elif name not in BARE and len(name) > 3:
        sys.exit(0)
sys.exit(1)
' "$1"
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
