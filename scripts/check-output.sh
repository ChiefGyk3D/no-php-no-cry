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
# Environment:
#   SITE_HOST     host that counts as first party (default: test-blog.chiefgyk3d.com)
#   EXPECT_ALIAS  an alias that must have a 301 line in _redirects
#                 (default: /2023/02/10/sample-post/, from the sample post)
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

url_attr='(src|href|poster|action|data|srcset)=["'"'"']?https?://[^"'"'"' >]*'
asset_tag='<(img|script|iframe|source|link|video|audio|embed|object|form)[ >][^>]*>'

while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"

    # Inline script: a <script> tag with no src attribute.
    if grep -oEi '<script([ >][^>]*)?>' "$f" | grep -qiv 'src='; then
        report inline-script "$rel"
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
done < <(find "$dir" -type f -name '*.html' -print0 | sort -z)

if [[ ! -s "$dir/_redirects" ]]; then
    report missing-redirects "_redirects"
elif ! grep -qE "^${expect_alias//./\\.}[[:space:]]+/[^[:space:]]*[[:space:]]+301([[:space:]]|\$)" "$dir/_redirects"; then
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
