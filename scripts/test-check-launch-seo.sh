#!/usr/bin/env bash
# Tests for scripts/check-launch-seo.py: a good production-mode fixture passes, and each
# launch blocker (noindex, robots disallow all, no Sitemap line, wrong host in the sitemap
# or a canonical, missing or duplicate titles and descriptions, a post with no canonical,
# a missing WordPress redirect map) fails with its rule name.
#
# Fixtures are throwaway directories under the repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/check-launch-seo.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

host="example.test"
fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}

page() { # page <file> <title> <description> <canonical-path> [extra head markup]
    mkdir -p "$(dirname "$1")"
    printf '<!doctype html><html><head><title>%s</title><meta name=description content="%s"><link rel=canonical href=https://%s%s>%s</head><body><h1>x</h1></body></html>\n' \
        "$2" "$3" "$host" "$4" "${5:-}" >"$1"
}

good() { # good <dir>: a small production-mode build for $host
    local d="$1"
    mkdir -p "$d"
    page "$d/index.html" "Home" "The home page." "/"
    page "$d/about/index.html" "About" "About the author." "/about/"
    page "$d/posts/one/index.html" "Post one | Site" "The first post." "/posts/one/"
    printf '<!doctype html><html><head><title>404</title><meta name=description content="Not found."><meta name=robots content=noindex></head></html>\n' >"$d/404.html"
    mkdir -p "$d/old"
    printf '<!doctype html><html><head><title>x</title><meta http-equiv=refresh content="0; url=/posts/one/"></head></html>\n' >"$d/old/index.html"
    printf 'User-agent: *\nAllow: /\n\nSitemap: https://%s/sitemap.xml\n' "$host" >"$d/robots.txt"
    printf '<?xml version="1.0" encoding="utf-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://%s/</loc><lastmod>2026-01-01T00:00:00Z</lastmod></url><url><loc>https://%s/posts/one/</loc><lastmod>2026-01-01T00:00:00Z</lastmod></url></urlset>\n' "$host" "$host" >"$d/sitemap.xml"
    printf '# rules\n/feed/ /feed/index.xml 301\n/feed /feed/index.xml 301\n/old-post /posts/one/ 301\n' >"$d/_redirects"
}

run() { python3 -I "$root/scripts/check-launch-seo.py" "$@"; }

# expect <name> <exit> <rule or -> <mutation command run in the fixture dir>
expect() {
    local name="$1" want="$2" rule="$3" d="$work/$1" out rc=0
    good "$d"
    (cd "$d" && eval "$4")
    out="$(run "$d" "$host" 2>&1)" || rc=$?
    if [[ $rc -ne $want ]]; then
        bad "$name: exit $rc, wanted $want: $out"
    elif [[ "$rule" != "-" ]] && ! grep -q "^$rule	" <<<"$out"; then
        bad "$name: no $rule line: $out"
    else
        ok "$name"
    fi
}

expect good 0 - ':'
expect noindex 1 noindex "sed -i 's#</head>#<meta name=robots content=\"noindex, follow\"></head>#' about/index.html"
expect robots-disallow-all 1 robots-disallow-all "printf 'User-agent: *\nDisallow: /\n' >robots.txt"
expect robots-no-sitemap 1 robots-no-sitemap "printf 'User-agent: *\nAllow: /\n' >robots.txt"
# RFC 9309: a group is one or more User-agent lines followed by rules; a blank line inside it
# does not end it, so this is still a wildcard disallow-all (fail closed).
expect robots-blank-line-in-group 1 robots-disallow-all "printf 'User-agent: *\nAllow: /\n\nDisallow: /\nSitemap: https://example.test/sitemap.xml\n' >robots.txt"
# Several User-agent lines share the rules that follow them.
expect robots-shared-group 1 robots-disallow-all "printf 'User-agent: Bingbot\nUser-agent: *\nDisallow: /\nSitemap: https://example.test/sitemap.xml\n' >robots.txt"
# A rule before any User-agent line belongs to no group; a new User-agent starts a new group.
expect robots-orphan-rule 0 - "printf 'Disallow: /\n\nUser-agent: *\nAllow: /\nSitemap: https://example.test/sitemap.xml\n' >robots.txt"
expect robots-other-agent-only 0 - "printf 'User-agent: *\nAllow: /\n\nUser-agent: BadBot\nDisallow: /\nSitemap: https://example.test/sitemap.xml\n' >robots.txt"
expect robots-missing 1 robots-missing "rm robots.txt"
expect robots-host 1 robots-host "sed -i 's#example.test#staging.example.test#' robots.txt"
expect sitemap-host 1 sitemap-host "sed -i 's#https://example.test/posts#https://staging.example.test/posts#' sitemap.xml"
expect sitemap-missing 1 sitemap-missing "rm sitemap.xml"
expect canonical-host 1 canonical-host "sed -i 's#https://example.test/about/#https://test-blog.example.test/about/#' about/index.html"
expect post-canonical-missing 1 canonical-missing "sed -i 's#<link rel=canonical[^>]*>##' posts/one/index.html"
expect title-missing 1 title-missing "sed -i 's#<title>About</title>#<title></title>#' about/index.html"
expect title-duplicate 1 title-duplicate "sed -i 's#<title>About</title>#<title>Home</title>#' about/index.html"
expect description-missing 1 description-missing "sed -i 's#<meta name=description[^>]*>##' about/index.html"
expect description-duplicate 1 description-duplicate "sed -i 's#About the author.#The home page.#' about/index.html"
expect redirects-missing 1 redirects-missing "rm _redirects"
# X-Robots-Tag in _headers (issue 318): the header applies to the response, so a noindex there
# makes the page invisible even when the HTML and robots.txt are clean. Checked per path block;
# a bot-prefixed value ("googlebot: noindex") counts too. A header without noindex is fine.
expect header-noindex 1 header-noindex "printf '/*\n  X-Robots-Tag: noindex, nofollow\n' >_headers"
expect header-noindex-indented 1 header-noindex "printf '/*\n  Content-Type: text/html\n  x-robots-tag: googlebot: noindex\n' >_headers"
expect header-none 1 header-noindex "printf '/posts/*\n  X-Robots-Tag: none\n' >_headers"
# A valued directive whose value is "none" does not block indexing (issue 318 review).
expect header-max-image-preview-none 0 - "printf '/*\n  X-Robots-Tag: max-image-preview: none\n' >_headers"
expect header-valued-then-noindex 1 header-noindex "printf '/*\n  X-Robots-Tag: max-image-preview: none, noindex\n' >_headers"
expect header-bot-valued-none 0 - "printf '/*\n  X-Robots-Tag: googlebot: max-snippet: 0, max-image-preview: none\n' >_headers"
expect meta-max-image-preview-none 0 - "sed -i 's#</head>#<meta name=robots content=\"max-image-preview:none\"></head>#' about/index.html"
expect header-harmless 0 - "printf '/*\n  X-Robots-Tag: max-snippet:-1\n  X-Content-Type-Options: nosniff\n' >_headers"
expect header-comment-ignored 0 - "printf '# X-Robots-Tag: noindex\n/*\n  X-Content-Type-Options: nosniff\n' >_headers"
# A meta robots of "none" means noindex, nofollow; a Googlebot-specific meta or robots group counts.
expect meta-none 1 noindex "sed -i 's#</head>#<meta name=robots content=\"none\"></head>#' about/index.html"
expect meta-googlebot-noindex 1 noindex "sed -i 's#</head>#<meta name=googlebot content=\"noindex\"></head>#' about/index.html"
expect robots-googlebot-disallow-all 1 robots-disallow-all "printf 'User-agent: *\nAllow: /\n\nUser-agent: Googlebot\nDisallow: /\nSitemap: https://example.test/sitemap.xml\n' >robots.txt"
expect redirects-no-feed 1 redirects-missing "printf '/a /b 301\n' >_redirects"
expect alias-stub-ignored 0 - "mkdir -p stub && printf '<meta http-equiv=refresh content=\"0; url=/\">' >stub/index.html"

# usage errors
rc=0
run "$work/nonexistent" "$host" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then ok "a missing directory is a usage error (exit 2)"; else bad "missing directory exit $rc"; fi
rc=0
run "$work/good" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then ok "no host is a usage error (exit 2)"; else bad "no host exit $rc"; fi

if [[ $fail -ne 0 ]]; then
    echo "check-launch-seo tests failed"
    exit 1
fi
echo "all check-launch-seo tests passed"
