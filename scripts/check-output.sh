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
# Rules: inline-script, script-not-allowed, script-count, missing-script,
# extra-script-file, js-budget, javascript-url, style-element, style-attribute,
# event-handler, http-reference, external-asset, external-css-reference,
# skip-link, landmark, email-shaped-text, xml-stylesheet, bad-xml, base-element, unexpected-file, script-hash, script-hash-file, script-wrong-page, search-page-budget, headers-structure, missing-immutable, immutable-unhashed,
# script-in-markup, missing-nosniff, missing-robots, bad-robots, env-mismatch,
# noindex-mismatch, missing-head-tag, bad-head-value, bad-jsonld, duplicate-description, missing-sitemap,
# bad-sitemap, bad-feed, missing-redirects, missing-alias, missing-feed,
# missing-headers, weak-csp, template-element, missing-output, missing-llms,
# bad-llms, old-site-name, image-metadata, multiple-l3.
#
# multiple-l3: the border system (docs/borders.md) allows ONE level 3 frame, the
# full button frame, per page: more than one <svg class="fr fr-l3"> on a page is a
# finding. A page's frames are inline SVG from layouts/_partials/frame.html and
# carry no style attribute (style-attribute, below, covers them).
#
# Scripts: script-src is 'self' in static/_headers, which allows every
# same-origin script (it cannot name one file); these checks and the hash pins of
# /copy.js and /search.js make those two the only ones, each on ONE page. The
# allowlist (scripts/artifact-rules.sh) maps script -> page: /copy.js on
# /support/ and /search.js on /search/. The only script element allowed on a
# page is its own <script src=/NAME></script> (quotes optional, no other
# attribute, no body), at most once; the same tag on any other page is
# script-wrong-page. No other script element, no inline script, no event-handler
# attribute, no javascript: URL. The only script files in the build are those two,
# each under 1 KB gzip (docs/redesign-brief.md section 10). The search page's
# HTML is under 40 KB gzip (search-page-budget): it is the browse list with
# JavaScript off, and past that size the approach needs another look. The CSP
# must carry exactly one script-src, and it must be 'self' plus the one
# Cloudflare Web Analytics beacon URL (injected at the edge; never in built HTML).
#
# 'self' authorizes every same-origin response, so also: every file in the build
# is of a listed non-script type (unexpected-file; see scripts/artifact-rules.sh),
# nosniff is in _headers, _headers is one /* block with no removal directive plus
# the one long-cache block for /css/* (headers-structure, missing-immutable; every
# file under it must be named by its own sha256: immutable-unhashed), and each pinned script is accepted only if its sha256
# equals the one in its committed <name>.sha256 (SCRIPT_HASH_DIR overrides the
# directory; script-hash, script-hash-file). With no hash file for a script, no
# element and no file of that name may exist. URLs are judged as the browser reads them, after character
# references are decoded and tabs and newlines dropped (a parser pass per page):
# javascript: URLs, http: and scheme-relative or backslash URLs to another host
# on a tag that loads something, and any <base> element are findings.
#
# Environment:
#   SITE_HOST     host that counts as first party (default: test-blog.chiefgyk3d.com)
#   EXPECT_ENV    staging or production: the environment this build must be.
#                 Unset, the environment is read from robots.txt and every page
#                 is checked against it.
#   EXPECT_ALIAS  an alias that must have a 301 line in _redirects
#                 (default: the old WordPress permalink of a real post)
#
# Environment: robots.txt decides it. Staging disallows everything, names no
# sitemap, and every page carries noindex. Production allows everything, names
# the sitemap on the site's own host, and no page carries noindex (alias pages
# are meta refresh stubs and always carry one). A tree that mixes the two fails.
#
# Landmarks: every page has the skip link first (to #main), one header, one
# nav aria-label=Main, one main#main and one footer (scripts/check-landmarks.py).
#
# Head: the home page and every post and journal entry carry a description,
# theme-color, a manifest link, canonical and icon links, Open Graph and Twitter card tags (og:url and
# og:image absolute on the site's own host); entries are og:type article with
# article:published_time, the home page is a website.
#
# Structured data: a head may carry <script type="application/ld+json"> DATA
# blocks (exactly that tag, no other attribute, no src, no "<" in the body).
# A browser never runs them and script-src does not apply (checked in Chromium
# against static/_headers); every other script element is still a finding. The
# blocks are parsed (scripts/check-seo.py): valid JSON, schema.org, the display
# name ChiefGyk3D for any Person, https sameAs only, no personal-detail key; the
# home page needs the Person, a post or entry the Article. Twitter card is
# summary_large_image. In production the 404 page carries noindex and no other
# page does. Site-wide (scripts/check-seo.py): no two pages share a description;
# the feed has its atom self link on the site host; in production sitemap.xml
# lists every post and entry and no alias stub, noindex page or page that is not
# there, each url on the site host with a lastmod.
#
# Every alias in the build is also checked: each meta-refresh page Hugo wrote
# for an alias must have a 301 line in _redirects (directory-style aliases need
# the slash and the no-slash line; an alias ending in .html needs its one line).
set -euo pipefail

# shellcheck source=scripts/artifact-rules.sh
source "$(dirname "${BASH_SOURCE[0]}")/artifact-rules.sh"
# shellcheck source=scripts/robots-wildcard.sh
source "$(dirname "${BASH_SOURCE[0]}")/robots-wildcard.sh"

dir="${1:-public}"
site_host="${SITE_HOST:-test-blog.chiefgyk3d.com}"
expect_alias="${EXPECT_ALIAS:-/stream-daemon-the-secure-open-source-stream-automation-engine-for-modern-creators/}"
findings=0

if [[ ! -d "$dir" ]]; then
    echo "[missing-output] $dir is not a directory"
    exit 1
fi

declare -A reported=()
report() {
    # report <rule> <file>; the same rule for the same file is printed once
    [[ -n "${reported["$1|$2"]:-}" ]] && return 0
    reported["$1|$2"]=1
    printf '[%s] %s\n' "$1" "$2"
    findings=$((findings + 1))
}

# decoded_findings <site-host> <file> [--markup]: prints one rule name per line
# for what the file's tags say once a browser has read them (see
# scripts/scan-markup.py): quote-aware attribute parsing, character references
# decoded, tabs and newlines dropped from URLs. Only rule names are printed.
decoded_findings() {
    local host="$1" file="$2"
    shift 2
    python3 -I "$(dirname "${BASH_SOURCE[0]}")/scan-markup.py" "$@" "$host" "$file"
}

# has_redirect <path>: _redirects holds a 301 line whose source is <path>.
has_redirect() {
    [[ -f "$dir/_redirects" ]] &&
        awk -v p="$1" '$1 == p && $3 == "301" { found = 1 } END { exit !found }' "$dir/_redirects"
}

# Environment, from robots.txt: robots_wildcard comes from scripts/robots-wildcard.sh.

# csp_scripts_ok: reads Content-Security-Policy header lines on stdin. Succeeds
# when every policy has exactly one script-src whose whole value is 'self' plus
# the one Cloudflare Web Analytics beacon URL (BEACON), exactly one connect-src
# that is 'self', and no script-src-elem or script-src-attr (either would
# override script-src).
csp_scripts_ok() {
    awk -v beacon="https://static.cloudflareinsights.com/beacon.min.js" '
        { sub(/^[^:]*:/, ""); n = split($0, d, ";"); count = 0; cs = 0; ok = 1
          for (i = 1; i <= n; i++) {
              gsub(/^[ \t]+|[ \t\r]+$/, "", d[i])
              name = tolower(d[i]); sub(/[ \t].*/, "", name)
              if (name == "script-src") { count++; v = d[i]; sub(/^[^ \t]+[ \t]*/, "", v); if (v != "'"'"'self'"'"' " beacon) ok = 0 }
              if (name == "connect-src") { cs++; v = d[i]; sub(/^[^ \t]+[ \t]*/, "", v); if (v != "'"'"'self'"'"'") ok = 0 }
              if (name == "script-src-elem" || name == "script-src-attr") ok = 0
          }
          if (count != 1 || cs != 1 || !ok) bad = 1; seen = 1 }
        END { exit (bad || !seen) }'
}

env=""
if [[ ! -s "$dir/robots.txt" ]]; then
    report missing-robots "robots.txt"
else
    read -r has_wild dis_all allow_any dis_other < <(robots_wildcard "$dir/robots.txt")
    sitemap_ok=0
    grep -qiE "^Sitemap:[[:space:]]*https://${site_host}/[^[:space:]]*[[:space:]]*\r?\$" "$dir/robots.txt" && sitemap_ok=1
    sitemap_any=0
    grep -qiE '^Sitemap:' "$dir/robots.txt" && sitemap_any=1
    if [[ $has_wild -eq 0 ]]; then
        report bad-robots "robots.txt (no User-agent: * group)"
    elif [[ $dis_all -eq 1 ]]; then
        env=staging
        if [[ $allow_any -eq 1 || $sitemap_any -eq 1 ]]; then
            report bad-robots "robots.txt (staging must disallow all for User-agent: *, re-open nothing and name no sitemap)"
        fi
    elif [[ $dis_other -eq 1 || $sitemap_ok -eq 0 ]]; then
        report bad-robots "robots.txt (production must allow everything for User-agent: * and name a Sitemap on ${site_host})"
    else
        env=production
    fi
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

# The pinned script hashes: a missing hash file means that script is not
# allowed in the build.
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

# jsonld_check <file> <home|article|other>: the JSON-LD rules of scripts/check-seo.py.
jsonld_check() {
    local rule
    rule="$(python3 -I "$(dirname "${BASH_SOURCE[0]}")/check-seo.py" jsonld "$2" "$1")"
    [[ -n "$rule" ]] && report "$rule" "${1#"$dir"/}"
    return 0
}

url_attr='(src|href|poster|action|data|srcset)=["'"'"']?https?://[^"'"'"' >]*'
asset_tag='<(img|script|iframe|source|link|video|audio|embed|object|form)[ >][^>]*>'

while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"

    # Scripts. flat is the page on one line, so a tag split across lines is
    # still one tag. Inline script: a <script> tag with no src attribute.
    flat="$(tr '\n\r' '  ' <"$f" | sed -E 's#<script type=("application/ld\+json"|application/ld\+json)>[^<]*</script>##g')"
    if grep -oEi '<script([^a-z0-9_>-][^>]*)?>' <<<"$flat" | grep -qiv 'src='; then
        report inline-script "$rel"
    fi
    # Every script element must be exactly a pinned script on its own page. Any
    # other form (a body, another attribute, another file, a tag with no closing
    # >) is blocked or unreviewed.
    script_total="$(grep -oEi '<script([^a-z0-9_-]|$)' <<<"$flat" | wc -l || true)"
    script_known=0
    for name in "${script_names[@]}"; do
        quoted="${name//./\\.}"
        n="$(grep -oEi "<script src=(\"/${quoted}\"|'/${quoted}'|/${quoted})></script>" <<<"$flat" | wc -l || true)"
        [[ "$n" -gt 0 ]] || continue
        script_known=$((script_known + n))
        if ! pinned_script_on_page "$name" "$rel"; then
            report script-wrong-page "$rel (/${name} belongs on $(pinned_script_page "$name") only)"
            continue
        fi
        [[ "$n" -gt 1 ]] && report script-count "$rel"
        if [[ -z "${pinned[$name]}" ]]; then
            report script-not-allowed "$rel (no pinned hash for /${name}: the script is not allowed)"
        elif [[ ! -f "$dir/$name" ]]; then
            report missing-script "$rel (references /${name}, which is not in the build)"
        fi
    done
    if [[ "$script_total" -ne "$script_known" ]]; then
        report script-not-allowed "$rel"
    fi
    if [[ "$rel" == search/index.html ]]; then
        gz="$(gzip -9 -n -c "$f" | wc -c)"
        if [[ "$gz" -ge "$(search_page_gzip_budget)" ]]; then
            report search-page-budget "$rel (${gz} bytes gzip, budget is under $(search_page_gzip_budget): revisit the search approach, docs/pinned-script.md)"
        fi
    fi
    if grep -qEi '<style[ >]' "$f"; then
        report style-element "$rel"
    fi
    if grep -qEi '[[:space:]]style=' "$f"; then
        report style-attribute "$rel"
    fi
    # Border system: one level 3 frame per page at most (docs/borders.md).
    if [[ "$(grep -oE 'class="?fr fr-l3[" >]' "$f" | wc -l)" -gt 1 ]]; then
        report multiple-l3 "$rel"
    fi
    # Event-handler attributes and javascript: URLs are read from real
    # attributes by the parser pass below (scripts/scan-markup.py).
    # pre-not-focusable: a scrollable code block must be reachable by keyboard.
    if grep -oEi '<pre([ >][^>]*)?>' "$f" | grep -qiv 'tabindex='; then
        report pre-not-focusable "$rel"
    fi

    # The one owner-approved business address (data/about.yaml) may appear on the
    # About page only, as text and as a mailto: link to exactly that address.
    email_opts=()
    if [[ "$rel" == about/index.html ]]; then
        about_email="$("$(dirname "${BASH_SOURCE[0]}")/about-email.sh")"
        [[ -n "$about_email" ]] && email_opts=(--allow-email "$about_email")
    fi
    while IFS= read -r rule; do
        [[ -n "$rule" ]] && report "$rule" "$rel"
    done < <(decoded_findings "$site_host" "$f" ${email_opts[@]+"${email_opts[@]}"})
    jsonld_check "$f" other

    # Landmarks and the skip link, on every page except Hugo's alias stubs.
    if ! grep -qEi 'http-equiv=["'"'"']?refresh' "$f"; then
        while IFS= read -r rule; do
            [[ -n "$rule" ]] && report "$rule" "$rel"
        done < <(python3 -I "$(dirname "${BASH_SOURCE[0]}")/check-landmarks.py" "$f")
    fi

    # Absolute URLs inside tags that load something (anchors are not assets).
    # A <link rel=me> is an identity claim (Mastodon, GitHub read it); a browser fetches nothing for it.
    urls="$(grep -oEi "$asset_tag" "$f" | grep -vEi '^<link[ ]+([^>]* )?rel=["'"'"']?me["'"'"']?[ >/]' | grep -oEi "$url_attr" || true)"
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
        if [[ "$rel" == 404.html && "$env" == production ]]; then
            # The 404 is the one noindex page in production.
            grep -qEi '<meta[^>]*name=["'"'"']?robots["'"'"']?[^>]*noindex' "$f" ||
                report noindex-mismatch "$rel (the 404 page must carry noindex)"
        elif grep -qEi '<meta[^>]*name=["'"'"']?robots["'"'"']?[^>]*noindex' "$f"; then
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

# The same attribute rules on svg, xml and xhtml outputs, and any script element
# there is a finding.
while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    while IFS= read -r rule; do
        [[ -n "$rule" ]] && report "$rule" "$rel"
    done < <(decoded_findings "$site_host" "$f" --markup)
done < <(find "$dir" -type f \( -iname '*.svg' -o -iname '*.xml' -o -iname '*.xhtml' \) -print0 | sort -z)

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
    for pair in name:description name:twitter:card name:twitter:image name:theme-color property:og:title property:og:description \
        property:og:type property:og:url property:og:image property:og:site_name; do
        attr="${pair%%:*}"
        name="${pair#*:}"
        val="$(head_meta "$f" "$attr" "$name")"
        [[ -z "$val" ]] && report missing-head-tag "$rel (${name})"
    done
    for name in canonical apple-touch-icon manifest; do
        head_link "$f" "$name" || report missing-head-tag "$rel (link rel=${name})"
    done
    # Two rel=icon links (the SVG and the PNG).
    if [[ "$(grep -oEi "<link[^>]*[[:space:]]rel=[\"']?icon[\"']?([[:space:]/][^>]*)?>" "$f" | wc -l)" -lt 2 ]]; then
        report missing-head-tag "$rel (two link rel=icon)"
    fi
    for name in og:url og:image; do
        val="$(head_meta "$f" property "$name")"
        if [[ -n "$val" && ! "$val" =~ ^https://${site_host//./\\.}/ ]]; then
            report bad-head-value "$rel (${name} must be an absolute URL on ${site_host})"
        fi
    done
    val="$(head_meta "$f" name twitter:image)"
    if [[ -n "$val" && ! "$val" =~ ^https://${site_host//./\\.}/ ]]; then
        report bad-head-value "$rel (twitter:image must be an absolute URL on ${site_host})"
    fi
    val="$(head_meta "$f" name twitter:card)"
    if [[ -n "$val" && "$val" != summary_large_image ]]; then
        report bad-head-value "$rel (twitter:card must be summary_large_image)"
    fi
    if [[ "$kind" == article ]]; then jsonld_check "$f" article; else jsonld_check "$f" home; fi
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

# Template contract (issues 58 and 59): the pieces the home, 404, archive, term
# and post templates must render. Fixed strings and attribute names only; page
# content is never printed.
need_text() { grep -qF -- "$2" "$1" || report template-element "${1#"$dir"/} (missing: $2)"; }
# need_mascot <file>: an <img> of a mascot WebP that carries width and height.
need_mascot() {
    local tag
    tag="$(grep -oEi '<img[^>]*mascot-[0-9]+\.webp[^>]*>' "$1" | head -n1 || true)"
    if [[ -z "$tag" ]]; then
        report template-element "${1#"$dir"/} (missing: mascot image)"
    elif ! grep -qEi '[[:space:]]width=' <<<"$tag" || ! grep -qEi '[[:space:]]height=' <<<"$tag"; then
        report template-element "${1#"$dir"/} (mascot image without width and height)"
    fi
}
if [[ -f "$dir/index.html" ]] && ! is_alias_page "$dir/index.html"; then
    for t in "and whatever I" "building next" "Senior Cybersecurity Engineer" "Read the latest" "See my projects" \
        "Find me online" "Support my work" "Latest posts" "All posts"; do
        need_text "$dir/index.html" "$t"
    done
    need_mascot "$dir/index.html"
fi
if [[ ! -f "$dir/404.html" ]]; then
    report template-element "404.html (missing)"
else
    for t in "rm -rf" "refusing to answer questions" "Start over" "Browse posts" "Search the site" "Find me online"; do
        need_text "$dir/404.html" "$t"
    done
    need_mascot "$dir/404.html"
fi
if [[ ! -f "$dir/posts/index.html" ]]; then
    report template-element "posts/index.html (missing archive)"
fi
for f in "$dir/posts/index.html" "$dir/journal/index.html" "$dir"/tags/*/index.html "$dir"/categories/*/index.html; do
    [[ -f "$f" ]] || continue
    need_text "$f" "archive-year"
    # Only the posts archive has a feed link of its own here (terms have none).
    [[ "$f" == "$dir/posts/index.html" ]] && need_text "$f" "index.xml"
done
while IFS= read -r -d '' f; do
    is_alias_page "$f" && continue
    need_text "$f" "<time"
    need_text "$f" "reading-time"
done < <(find "$dir/posts" -mindepth 2 -maxdepth 2 -name index.html -print0 2>/dev/null | sort -z)

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

# Site-wide SEO rules: duplicate descriptions, the feed's atom link, the sitemap.
while IFS=$'\t' read -r rule where; do
    [[ -n "$rule" ]] && report "$rule" "$where"
done < <(python3 -I "$(dirname "${BASH_SOURCE[0]}")/check-seo.py" site "$dir" "$site_host" "$env")

if [[ ! -s "$dir/_redirects" ]]; then
    report missing-redirects "_redirects"
elif ! has_redirect "$expect_alias"; then
    report missing-alias "_redirects (no 301 line for ${expect_alias})"
fi

if [[ ! -s "$dir/index.xml" ]]; then
    report missing-feed "index.xml"
fi
# The site feed, /feed/index.xml: the _redirects rules for the old WordPress
# feed addresses (layouts/home.redirects) land on this file.
if [[ ! -s "$dir/feed/index.xml" ]]; then
    report missing-feed "feed/index.xml"
fi

# /llms.txt (layouts/home.llms.txt): the llms.txt convention. An H1 first line,
# a "> " summary line, https links only (no markup anywhere: the summary is
# scanned too, minus its leading "> " marker), and at least one link on this
# site.
# Pages serves .txt as text/plain, so _headers (one /* block) needs no entry.
if [[ ! -s "$dir/llms.txt" ]]; then
    report missing-llms "llms.txt"
else
    llms_links="$(grep -oE '\]\([^)]*\)' "$dir/llms.txt" || true)"
    if ! head -n1 "$dir/llms.txt" | grep -qE '^# .+'; then
        report bad-llms "llms.txt (first line must be an H1: '# name')"
    elif ! grep -qE '^> .+' "$dir/llms.txt"; then
        report bad-llms "llms.txt (no '> ' summary line)"
    elif grep -qE '[<>]|javascript:' <<<"$(sed -E 's/^> //' "$dir/llms.txt")"; then
        report bad-llms "llms.txt (markup or script in a plain text file)"
    elif [[ -z "$llms_links" ]] || grep -vE '^\]\(https://' <<<"$llms_links" | grep -qE .; then
        report bad-llms "llms.txt (every link must be https)"
    elif ! grep -qE "^\]\(https://${site_host//./\\.}/" <<<"$llms_links"; then
        report bad-llms "llms.txt (no link to this site's own host)"
    fi
fi

if [[ ! -s "$dir/_headers" ]]; then
    report missing-headers "_headers"
else
    csp="$(grep -i 'Content-Security-Policy:' "$dir/_headers" || true)"
    if [[ -z "$csp" ]] || ! grep -qF "default-src 'none'" <<<"$csp" ||
        grep -qE "unsafe-inline|unsafe-eval|script-src[^;]*(\*|https?:)" <<<"${csp//https:\/\/static.cloudflareinsights.com\/beacon.min.js/}"; then
        report weak-csp "_headers"
    elif ! csp_scripts_ok <<<"$csp"; then
        report weak-csp "_headers (script-src must be exactly 'self' plus the Cloudflare beacon URL, once, connect-src exactly 'self', no script-src-elem or script-src-attr)"
    elif ! grep -qF "manifest-src 'self'" <<<"$csp"; then
        report weak-csp "_headers (manifest-src 'self' is required: default-src 'none' blocks the web app manifest every page links)"
    fi
fi

if [[ -s "$dir/_headers" ]] && ! headers_policy_ok "$dir/_headers"; then
    report headers-structure "_headers (must be one /* rule block with no removal directive)"
fi
if [[ -s "$dir/_headers" ]] && ! headers_immutable_ok "$dir/_headers"; then
    report missing-immutable "_headers (no long-cache block for the content-hashed assets: ${IMMUTABLE_PATHS[*]})"
fi
# The long-cache block is only safe because each file under it is named by its
# own sha256. A new stylesheet name or a changed file with an old name fails here.
while IFS= read -r bad; do
    [[ -n "$bad" ]] && report immutable-unhashed "$bad (under a long-cache path but not named by its own sha256)"
done < <(immutable_assets_bad "$dir" || true)
if [[ -s "$dir/_headers" ]] && ! headers_nosniff_ok "$dir/_headers"; then
    report missing-nosniff "_headers (X-Content-Type-Options must be nosniff)"
fi

# 'self' authorizes every same-origin response: every file must be of a listed
# non-script type (the js files are reported below).
while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    case "${rel,,}" in
        *.js | *.mjs | *.cjs) continue ;;
    esac
    artifact_name_ok "$rel" || report unexpected-file "$rel"
    if [[ "${rel,,}" == *.svg ]] && svg_script_bad "$f"; then
        report script-in-markup "$rel"
    fi
done < <(find "$dir" -type f -print0 | sort -z)

# Script files: the pinned ones only, each only if its sha256 is the pinned one,
# under 1 KB gzip. No hash file, no script.
while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    if [[ -z "${pinned[$rel]:-}" ]]; then
        report extra-script-file "$rel"
    fi
done < <(find "$dir" -type f \( -iname '*.js' -o -iname '*.mjs' -o -iname '*.cjs' \) -print0 | sort -z)
for name in "${script_names[@]}"; do
    [[ -f "$dir/$name" ]] || continue
    if [[ -n "${pinned[$name]}" && "$(sha256sum "$dir/$name" | cut -d' ' -f1)" != "${pinned[$name]}" ]]; then
        report script-hash "$name (does not match the pinned sha256)"
    fi
    gz="$(gzip -9 -n -c "$dir/$name" | wc -c)"
    if [[ "$gz" -ge "$(script_gzip_budget)" ]]; then
        report js-budget "$name (${gz} bytes gzip, budget is under $(script_gzip_budget))"
    fi
done

# The site's public name is ChiefGyk3D (hugo.toml title). The project name
# no-php-no-cry must not appear in the output, in text, titles, meta, feeds or
# the manifest. The one allowed form is a link to the repository, which starts
# with https://github.com/ChiefGyk3D/no-php-no-cry followed by end, a slash, a
# quote, whitespace or an angle bracket. Anything else is a finding.
# html, xml and svg are read with character references decoded, as a browser
# shows them (scripts/old-name-scan.py); the other types are read as written.
while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    mode=raw
    case "${rel,,}" in *.html | *.xml | *.svg) mode=decode ;; esac
    if python3 -I "$(dirname "${BASH_SOURCE[0]}")/old-name-scan.py" "$mode" "$f"; then
        report old-site-name "$rel"
    fi
done < <(find "$dir" -type f \( -iname '*.html' -o -iname '*.xml' -o -iname '*.txt' -o -iname '*.json' -o -iname '*.webmanifest' -o -iname '*.svg' -o -name '_redirects' -o -name '_headers' \) -print0 | sort -z)

# Published images carry no EXIF (GPS, camera, dates), XMP or IPTC metadata. The
# owner's portrait ships as a stripped copy only (scripts/check-image-metadata.py;
# docs/redesign-brief.md, "Portrait"). Skipped only when the build has no image at all.
if [[ -n "$(find "$dir" -type f \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print -quit)" ]]; then
    meta_rc=0
    meta_out="$(python3 -I "$(dirname "${BASH_SOURCE[0]}")/check-image-metadata.py" "$dir" 2>&1)" || meta_rc=$?
    if [[ $meta_rc -ne 0 ]]; then
        # A finding line names the file; anything else (a crash) is still a finding, never a pass.
        found_line=0
        while IFS= read -r line; do
            if [[ "$line" == "[image-metadata] "* ]]; then
                report image-metadata "${line#\[image-metadata\] }"
                found_line=1
            fi
        done <<<"$meta_out"
        [[ $found_line -eq 1 ]] || report image-metadata "check-image-metadata.py failed"
    fi
fi

if [[ $findings -gt 0 ]]; then
    echo "check-output: $findings finding(s)"
    exit 1
fi
echo "check-output: ok ($dir)"
