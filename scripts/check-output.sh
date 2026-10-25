#!/usr/bin/env bash
# Post-build checks on the generated site.
#
# Usage: scripts/check-output.sh [output-dir]      (default: public)
#
# Fails when the output contains anything the Content-Security-Policy in
# static/_headers would block or that makes a third-party request, or when a
# deliverable is missing. Findings are printed as "[rule] file"; page content
# is never printed.
#
# Rules: inline-script, script-element-present, style-element, style-attribute,
# event-handler, http-reference, external-asset, external-css-reference,
# xml-stylesheet, bad-xml, missing-robots, bad-robots, env-mismatch,
# noindex-mismatch, missing-head-tag, bad-head-value, missing-redirects, missing-alias, missing-feed,
# missing-headers, weak-csp, missing-output.
#
# Environment:
#   SITE_HOST     host that counts as first party (default: test-blog.chiefgyk3d.com)
#   EXPECT_ENV    staging or production: the environment this build must be.
#                 Unset, the environment is read from robots.txt and every page
#                 is checked against it.
#   EXPECT_ALIAS  an alias that must have a 301 line in _redirects
#                 (default: /2023/02/10/sample-post/, from the sample post)
#
# Environment: robots.txt decides it. Staging disallows everything, names no
# sitemap, and every page carries noindex. Production allows everything, names
# the sitemap on the site's own host, and no page carries noindex (alias pages
# are meta refresh stubs and always carry one). A tree that mixes the two fails.
#
# Head: the home page and every post and journal entry carry a description,
# canonical and icon links, Open Graph and Twitter card tags (og:url and
# og:image absolute on the site's own host); entries are og:type article with
# article:published_time, the home page is a website.
#
# Every alias in the build is also checked: each meta-refresh page Hugo wrote
# for an alias must have a 301 line in _redirects (directory-style aliases need
# the slash and the no-slash line; an alias ending in .html needs its one line).
set -euo pipefail

dir="${1:-public}"
site_host="${SITE_HOST:-test-blog.chiefgyk3d.com}"
expect_alias="${EXPECT_ALIAS:-/2023/02/10/sample-post/}"
findings=0

if [[ ! -d "$dir" ]]; then
    echo "[missing-output] $dir is not a directory"
    exit 1
fi

report() {
    # report <rule> <file>
    printf '[%s] %s\n' "$1" "$2"
    findings=$((findings + 1))
}

# has_redirect <path>: _redirects holds a 301 line whose source is <path>.
has_redirect() {
    [[ -f "$dir/_redirects" ]] &&
        awk -v p="$1" '$1 == p && $3 == "301" { found = 1 } END { exit !found }' "$dir/_redirects"
}

# Environment, from robots.txt.
env=""
if [[ ! -s "$dir/robots.txt" ]]; then
    report missing-robots "robots.txt"
elif grep -qE '^Disallow:[[:space:]]*/[[:space:]]*$' "$dir/robots.txt"; then
    env=staging
    if grep -qiE '^(Allow|Sitemap):' "$dir/robots.txt"; then
        report bad-robots "robots.txt (staging must disallow all and name no sitemap)"
    fi
elif grep -qE "^Sitemap:[[:space:]]*https://${site_host}/[^[:space:]]*[[:space:]]*\$" "$dir/robots.txt"; then
    env=production
else
    report bad-robots "robots.txt (neither disallow-all nor allow-all with a Sitemap line on ${site_host})"
fi
case "${EXPECT_ENV:-}" in
'') ;;
staging | production)
    if [[ -n "$env" && "$env" != "$EXPECT_ENV" ]]; then
        report env-mismatch "robots.txt (expected ${EXPECT_ENV}, found ${env})"
    fi
    ;;
*) report env-mismatch "EXPECT_ENV must be staging or production" ;;
esac

url_attr='(src|href|poster|action|data|srcset)=["'"'"']?https?://[^"'"'"' >]*'
asset_tag='<(img|script|iframe|source|link|video|audio|embed|object|form)[ >][^>]*>'

while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"

    # Inline script: a <script> tag with no src attribute.
    if grep -oEi '<script([ >][^>]*)?>' "$f" | grep -qiv 'src='; then
        report inline-script "$rel"
    fi
    # script-src is 'none' in static/_headers: any script element would be
    # blocked in production, so a script needs a CSP change and a reviewed
    # allow-list first.
    if grep -qEi '<script([ >]|$)' "$f"; then
        report script-element-present "$rel"
    fi
    if grep -qEi '<style[ >]' "$f"; then
        report style-element "$rel"
    fi
    if grep -qEi '[[:space:]]style=' "$f"; then
        report style-attribute "$rel"
    fi
    if grep -qEi '[[:space:]]on[a-z]+=' "$f"; then
        report event-handler "$rel"
    fi
    # pre-not-focusable: a scrollable code block must be reachable by keyboard.
    if grep -oEi '<pre([ >][^>]*)?>' "$f" | grep -qiv 'tabindex='; then
        report pre-not-focusable "$rel"
    fi

    # Absolute URLs inside tags that load something (anchors are not assets).
    urls="$(grep -oEi "$asset_tag" "$f" | grep -oEi "$url_attr" || true)"
    if [[ -n "$urls" ]]; then
        if grep -qEi '=["'"'"']?http://' <<<"$urls"; then
            report http-reference "$rel"
        fi
        if grep -Evi "=[\"']?https?://${site_host}([/:\"' >]|\$)" <<<"$urls" | grep -qE .; then
            report external-asset "$rel"
        fi
    fi

    # Alias pages (Hugo's meta refresh) name an old URL by their location.
    if ! grep -qEi 'http-equiv=["'"'"']?refresh' "$f" && [[ -n "$env" ]]; then
        if grep -qEi '<meta[^>]*name=["'"'"']?robots["'"'"']?[^>]*noindex' "$f"; then
            [[ "$env" == production ]] && report noindex-mismatch "$rel (noindex in a production build)"
        else
            [[ "$env" == staging ]] && report noindex-mismatch "$rel (no noindex in a staging build)"
        fi
    fi
    if grep -qEi 'http-equiv=["'"'"']?refresh' "$f"; then
        if [[ "$rel" == index.html ]]; then
            continue
        elif [[ "$rel" == */index.html ]]; then
            base="/${rel%/index.html}"
            for want in "$base" "$base/"; do
                has_redirect "$want" || report missing-alias "_redirects (no 301 line for ${want}, from ${rel})"
            done
        else
            has_redirect "/$rel" || report missing-alias "_redirects (no 301 line for /${rel})"
        fi
    fi
done < <(find "$dir" -type f -name '*.html' -print0 | sort -z)

# head_meta <file> <attribute> <value>: the content of the first
# <meta attribute=value ...>, quoted or not as the minifier wrote it. Empty when
# the tag or its content is missing.
head_meta() {
    local tag
    tag="$(grep -oEi "<meta[^>]*[[:space:]]$2=[\"']?$3[\"']?([[:space:]/][^>]*)?>" "$1" | head -n1 || true)"
    [[ -z "$tag" ]] && return 0
    sed -nE -e 's/.*[[:space:]]content="([^"]*)".*/\1/p' \
        -e "s/.*[[:space:]]content='([^']*)'.*/\\1/p" \
        -e 's/.*[[:space:]]content=([^[:space:]"'"'"'>]+).*/\1/p' <<<"$tag" | head -n1
}

# head_link <file> <rel>: succeeds when the page has <link rel=...>.
head_link() {
    grep -qEi "<link[^>]*[[:space:]]rel=[\"']?$2[\"']?([[:space:]/][^>]*)?>" "$1"
}

# check_head <file> <website|article>
check_head() {
    local f="$1" kind="$2" rel="${1#"$dir"/}" pair attr name val
    for pair in name:description name:twitter:card property:og:title property:og:description \
        property:og:type property:og:url property:og:image property:og:site_name; do
        attr="${pair%%:*}"
        name="${pair#*:}"
        val="$(head_meta "$f" "$attr" "$name")"
        [[ -z "$val" ]] && report missing-head-tag "$rel (${name})"
    done
    for name in canonical icon; do
        head_link "$f" "$name" || report missing-head-tag "$rel (link rel=${name})"
    done
    for name in og:url og:image; do
        val="$(head_meta "$f" property "$name")"
        if [[ -n "$val" && ! "$val" =~ ^https://${site_host//./\\.}/ ]]; then
            report bad-head-value "$rel (${name} must be an absolute URL on ${site_host})"
        fi
    done
    val="$(head_meta "$f" property og:type)"
    if [[ -n "$val" && "$val" != "$kind" ]]; then
        report bad-head-value "$rel (og:type must be ${kind})"
    fi
    if [[ "$kind" == article ]]; then
        val="$(head_meta "$f" property article:published_time)"
        if [[ -z "$val" ]]; then
            report missing-head-tag "$rel (article:published_time)"
        elif [[ ! "$val" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+ ]]; then
            report bad-head-value "$rel (article:published_time is not a timestamp)"
        fi
    fi
}

is_alias_page() { grep -qEi 'http-equiv=["'"'"']?refresh' "$1"; }

if [[ -f "$dir/index.html" ]] && ! is_alias_page "$dir/index.html"; then
    check_head "$dir/index.html" website
fi
while IFS= read -r -d '' f; do
    is_alias_page "$f" || check_head "$f" article
done < <(find "$dir/posts" "$dir/journal" -mindepth 2 -maxdepth 2 -name index.html -print0 2>/dev/null | sort -z)

# Stylesheets and SVG: no @import or url() that leaves the site, and no
# scheme-relative (//host) form either. Feeds and SVG: no stylesheet processing
# instruction (it would load a file the CSP does not cover).
css_ref='(@import[[:space:]]*(url\()?|url\()[[:space:]]*["'"'"']?(https?:)?//[^"'"'"') ;]*'
while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    refs="$(grep -oEi "$css_ref" "$f" || true)"
    if [[ -n "$refs" ]] &&
        grep -Evi "//${site_host}([/:\"' );]|\$)" <<<"$refs" | grep -qE .; then
        report external-css-reference "$rel"
    fi
    if [[ "$f" == *.svg ]] &&
        grep -oEi '(xlink:)?href=["'"'"']?(https?:)?//[^"'"'"' >]*' "$f" |
        grep -Evi "//${site_host}([/:\"' >]|\$)" | grep -qE .; then
        report external-css-reference "$rel"
    fi
done < <(find "$dir" -type f \( -name '*.css' -o -name '*.svg' \) -print0 | sort -z)

while IFS= read -r -d '' f; do
    if grep -qF '<?xml-stylesheet' "$f"; then
        report xml-stylesheet "${f#"$dir"/}"
    fi
done < <(find "$dir" -type f \( -name '*.xml' -o -name '*.svg' -o -name '*.xsl' \) -print0 | sort -z)

# Every *.xml must parse (a feed that starts with an escaped declaration is
# not XML). Python's stdlib parser, isolated mode; file names go in as
# arguments and only the path is reported, never the content.
xml_files=()
while IFS= read -r -d '' f; do
    xml_files+=("$f")
done < <(find "$dir" -type f -name '*.xml' -print0 | sort -z)
if [[ ${#xml_files[@]} -gt 0 ]]; then
    while IFS= read -r bad; do
        [[ -n "$bad" ]] && report bad-xml "${bad#"$dir"/}"
    done < <(python3 -I -c '
import sys
import xml.etree.ElementTree as ET

for path in sys.argv[1:]:
    try:
        ET.parse(path)
    except (ET.ParseError, OSError):
        print(path)
' "${xml_files[@]}")
fi

if [[ ! -s "$dir/_redirects" ]]; then
    report missing-redirects "_redirects"
elif ! has_redirect "$expect_alias"; then
    report missing-alias "_redirects (no 301 line for ${expect_alias})"
fi

if [[ ! -s "$dir/index.xml" ]]; then
    report missing-feed "index.xml"
fi

if [[ ! -s "$dir/_headers" ]]; then
    report missing-headers "_headers"
else
    csp="$(grep -i 'Content-Security-Policy:' "$dir/_headers" || true)"
    if ! grep -qF "default-src 'none'" <<<"$csp" ||
        grep -qE "unsafe-inline|unsafe-eval|script-src[^;]*(\*|https?:)" <<<"$csp"; then
        report weak-csp "_headers"
    fi
fi

if [[ $findings -gt 0 ]]; then
    echo "check-output: $findings finding(s)"
    exit 1
fi
echo "check-output: ok ($dir)"
