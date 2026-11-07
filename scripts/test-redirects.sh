#!/usr/bin/env bash
# Test the generated _redirects file (layouts/home.redirects).
#
# Builds throwaway sites (this repository's layouts, assets and static files,
# plus pages written here) under the repository's gitignored tmp/, never /tmp.
# Asserts that an alias_fragment outside the narrow fragment grammar (letters,
# digits, '.', '_', '~', '-') fails the build, that a valid one builds, and that
# every generated _redirects line is a comment or exactly "/from /to 301" with
# an allowed status and internal paths. A guard self-test feeds the line checker
# bad lines and requires a failure. Needs the pinned Hugo; a missing Hugo is a
# failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/redirects.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

if ! command -v hugo >/dev/null 2>&1; then
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
fi

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# check_lines <file>: every line is a '#' comment or exactly three fields:
# an internal source path (a trailing '*' splat is allowed), an internal target
# path (with an optional fragment from the allowed grammar), and the status
# 301. Prints each violation.
check_lines() {
    awk '
        /^#/ { next }
        {
            n = NF
            if (n != 3) { print "line " NR ": " n " fields"; bad = 1; next }
            if ($1 !~ /^\/[A-Za-z0-9._~\/%-]*\*?$/) { print "line " NR ": bad source"; bad = 1 }
            if ($2 !~ /^\/[A-Za-z0-9._~\/%-]*(#[A-Za-z0-9._~-]+)?$/) { print "line " NR ": bad target"; bad = 1 }
            if ($3 != "301") { print "line " NR ": status " $3; bad = 1 }
        }
        END { exit bad }
    ' "$1"
}

build_site() { # build_site <dir> <fragment-yaml-or-empty>
    local site="$1" frag="$2"
    mkdir -p "$site/content/posts/x"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$site/"
    cp "$root/hugo.toml" "$site/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$site/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$site/content/posts/_index.md"
    {
        printf -- '---\ntitle: "X"\ndate: 2024-01-02T03:04:05-05:00\naliases:\n  - /old-x/\n'
        [[ -n "$frag" ]] && printf 'alias_fragment: %s\n' "$frag"
        printf -- '---\n\nBody.\n'
    } >"$site/content/posts/x/index.md"
    (cd "$site" && hugo --destination "$site/public" >"$site/build.log" 2>&1)
}

# --- a valid fragment builds, and every line is well formed ------------------
for good in 'contact' 'a.b_c~d-9'; do
    s="$work/good-$RANDOM"
    if build_site "$s" "\"$good\""; then
        if grep -q "^/old-x/ /posts/x/#$good 301\$" "$s/public/_redirects" && out="$(check_lines "$s/public/_redirects" 2>&1)"; then
            pass "fragment '$good' builds and every _redirects line is well formed"
        else
            fail "fragment '$good': unexpected _redirects: ${out:-no matching line}"
        fi
    else
        fail "fragment '$good' should build: $(tail -n 3 "$s/build.log")"
    fi
done

# --- rejected fragments fail the build ----------------------------------------
reject() { # reject <label> <yaml value>
    local s="$work/bad-$RANDOM"
    if build_site "$s" "$2"; then
        fail "$1: the build should have failed"
    elif grep -q 'alias_fragment' "$s/build.log"; then
        pass "$1: the build fails and names alias_fragment"
    else
        fail "$1: the build failed for another reason: $(tail -n 3 "$s/build.log")"
    fi
}
reject "newline" '"a\nb"'
reject "space" '"a b"'
reject "hash" '"a#b"'
reject "percent-encoded newline" '"a%0Ab"'
reject "redirect-like text" '"x\n/evil /elsewhere 301"'
reject "redirect-like text on one line" '"x /evil 301"'
reject "slash" '"a/b"'

# --- the real site's file is well formed --------------------------------------
if hugo --quiet --source "$root" --destination "$work/real" >"$work/real.log" 2>&1; then
    if out="$(check_lines "$work/real/_redirects" 2>&1)"; then
        pass "the site's own _redirects has only well-formed lines"
    else
        fail "the site's own _redirects: $out"
    fi
else
    fail "the site did not build: $(tail -n 3 "$work/real.log")"
fi

# --- feed and legacy WordPress URLs -------------------------------------------
# A site with known posts: x (2024-01, Home Lab, an alias), z (2024-01, Security,
# same month as x), y (2023-05, Security) and a draft d (2022-09) that must leave
# no date rule. uploads is the data/legacy_uploads.json content ("" for none).
build_legacy() { # build_legacy <dir> <uploads-json-or-empty>
    local site="$1" uploads="$2"
    mkdir -p "$site/content/posts" "$site/data"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$site/"
    cp "$root/hugo.toml" "$site/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$site/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$site/content/posts/_index.md"
    mkpost() { # mkpost <slug> <date> <categories-yaml> <extra front matter lines>
        mkdir -p "$site/content/posts/$1"
        printf -- '---\ntitle: "Post %s"\ndate: %s\ncategories: %s\n%s---\n\nFULLBODY-%s paragraph.\n' "$1" "$2" "$3" "$4" "$1" >"$site/content/posts/$1/index.md"
    }
    # TAGS=1 gives post x two tags and the draft one of its own (a tag only a
    # draft uses has no term page, so it must leave no rule).
    local xtags="" dtags=""
    if [[ -n "${TAGS:-}" ]]; then
        xtags='tags: ["Foo Bar", "zeta"]
'
        dtags='tags: ["Draft Tag"]
'
    fi
    mkpost x 2024-01-02T03:04:05-05:00 '["Home Lab"]' "aliases:
  - /old-x/
$xtags"
    mkpost z 2024-01-20T10:00:00-05:00 '["Security"]' ''
    mkpost y 2023-05-17T10:00:00-04:00 '["Security"]' ''
    # Post y shows a 2000 px wide image, so the page serves resized copies; the
    # original must still be published, it is the target of the upload redirect.
    # A flat gray PNG written with the standard library (no image tools needed).
    python3 -I -c '
import struct, sys, zlib
w, h = 2000, 4
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
raw = b"".join(b"\x00" + b"\x80" * w for _ in range(h))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
' "$site/content/posts/y/pic.png"
    printf '\n![A test pattern](pic.png)\n' >>"$site/content/posts/y/index.md"
    mkpost d 2022-09-09T10:00:00-04:00 '["Draft Only"]' "draft: true
$dtags"
    # UNCAT=1 adds a published post in the Uncategorized category (same month as
    # y, so no new date rule): the legacy mapping must still send it to /posts/.
    [[ -z "${UNCAT:-}" ]] || mkpost u 2023-05-18T10:00:00-04:00 '["Uncategorized"]' ''
    [[ -n "$uploads" ]] && printf '%s\n' "$uploads" >"$site/data/legacy_uploads.json"
    (cd "$site" && hugo --destination "$site/public" >"$site/build.log" 2>&1)
}

legacy_uploads='[{"from": "/wp-content/uploads/2023/05/pic-300x200.jpg", "to": "/posts/y/pic.png"}]'
legacy="$work/legacy"
if build_legacy "$legacy" "$legacy_uploads"; then
    # Exact text: static rules in byte order (without and with the trailing
    # slash), then the two dynamic rules last. Nothing else, so a rule for the
    # draft's month or category, or for a category that has no posts, would fail.
    cat >"$work/legacy.want" <<'RULES'
/2023 /posts/ 301
/2023/ /posts/ 301
/2023/05 /posts/ 301
/2023/05/ /posts/ 301
/2024 /posts/ 301
/2024/ /posts/ 301
/2024/01 /posts/ 301
/2024/01/ /posts/ 301
/category/home-lab /categories/home-lab/ 301
/category/home-lab/ /categories/home-lab/ 301
/category/security /categories/security/ 301
/category/security/ /categories/security/ 301
/category/uncategorized /posts/ 301
/category/uncategorized/ /posts/ 301
/comments/feed /feed/index.xml 301
/comments/feed/ /feed/index.xml 301
/feed /feed/index.xml 301
/feed/ /feed/index.xml 301
/feed/atom /feed/index.xml 301
/feed/atom/ /feed/index.xml 301
/old-x /posts/x/ 301
/old-x/ /posts/x/ 301
/wp-content/uploads/2023/05/pic-300x200.jpg /posts/y/pic.png 301
/category/* /posts/ 301
/page/* /posts/ 301
RULES
    grep -v '^#' "$legacy/public/_redirects" >"$work/legacy.got" || true
    if diff -u "$work/legacy.want" "$work/legacy.got" >"$work/legacy.diff"; then
        pass "legacy rules: the exact expected _redirects lines, static before dynamic"
    else
        fail "legacy rules differ from the expected lines: $(cat "$work/legacy.diff")"
    fi
    if out="$(check_lines "$legacy/public/_redirects" 2>&1)"; then
        pass "legacy rules: every line is well formed"
    else
        fail "legacy rules: $out"
    fi
    # Cloudflare Pages: 2000 static and 100 dynamic rules per file.
    static="$(grep -v '^#' "$legacy/public/_redirects" | grep -vc '\*' || true)"
    dynamic="$(grep -v '^#' "$legacy/public/_redirects" | grep -c '\*' || true)"
    if ((static >= 1 && dynamic >= 1 && static <= 2000 && dynamic <= 100)); then
        pass "legacy rules: $static static and $dynamic dynamic, within the Pages limits"
    else
        fail "legacy rules: $static static and $dynamic dynamic are outside 2000 and 100"
    fi
    # No static rule may follow a dynamic one (the top-most matching rule wins).
    if grep -v '^#' "$legacy/public/_redirects" | awk '/\*/ { dyn = 1; next } dyn { bad = 1 } END { exit bad }'; then
        pass "legacy rules: no static rule follows a dynamic one"
    else
        fail "legacy rules: a static rule follows a dynamic one"
    fi
    # Every redirect to a file must land on a file the build
    # publishes: the feed, and the upload targets (a 2000 px image is shown
    # resized, so its original is published only on purpose, see render-image).
    missing_targets() { # missing_targets <public-dir>
        awk '!/^#/ && $3 == "301" && $2 ~ /\.[a-z0-9]+$/ { print $2 }' "$1/_redirects" | while read -r t; do
            [[ -f "$1$t" ]] || echo "$t"
        done
    }
    if [[ -z "$(missing_targets "$legacy/public")" ]] && grep -q 'pic.png 301' "$legacy/public/_redirects"; then
        pass "legacy rules: every upload redirect lands on a published file"
    else
        fail "legacy rules: upload redirect targets missing from the build: $(missing_targets "$legacy/public")"
    fi
    cp -r "$legacy/public" "$work/tgt"
    rm "$work/tgt/posts/y/pic.png"
    if [[ -n "$(missing_targets "$work/tgt")" ]]; then
        pass "guard: an upload redirect to a file that is not published is caught"
    else
        fail "guard: a missing upload target was not caught"
    fi

    # The feed is a real file at /feed/index.xml, with the atom self link on that
    # address and full bodies; every page names it, and _headers is untouched.
    host="https://test-blog.chiefgyk3d.com"
    # feed_check <feed-file> <index.html> <post.html> <_headers>: prints each failure.
    feed_check() {
        python3 -I - "$1" "$host" 2>/dev/null <<'PY' || echo "feed: not a valid RSS 2.0 feed with the self link on /feed/index.xml and full bodies"
import sys
import xml.etree.ElementTree as ET

path, host = sys.argv[1:3]
root = ET.parse(path).getroot()
atom = "{http://www.w3.org/2005/Atom}"
assert root.tag == "rss" and root.get("version") == "2.0"
selfs = [l for l in root.iter(atom + "link") if l.get("rel") == "self"]
assert len(selfs) == 1 and selfs[0].get("href") == host + "/feed/index.xml", selfs
items = root.findall("./channel/item")
assert len(items) == 3, len(items)
assert all("FULLBODY-" in (i.findtext("description") or "") for i in items)
PY
        # The site minifies its HTML, which drops the attribute quotes.
        local link="<link rel=\"?alternate\"? type=\"?application/rss\\+xml\"? title=\"?ChiefGyk3D\"? href=\"?$host"
        local page
        for page in "$2" "$3"; do
            grep -qE "$link/feed/index.xml\"?>" "$page" || echo "feed: $page lacks the auto-discovery link to /feed/index.xml"
            ! grep -qE "$link/index.xml" "$page" || echo "feed: $page still advertises /index.xml as the site feed"
        done
        grep -qE 'href="?/feed/index.xml"?>RSS</a>' "$2" || echo "feed: the footer RSS link does not point at /feed/index.xml"
        # _headers stays the one pinned /* block (scripts/check-site-artifact.sh):
        # byte for byte the repository's file, one CSP line, no other rule block.
        cmp -s "$4" "$root/static/_headers" || echo "feed: _headers differs from static/_headers"
        [[ "$(grep -c 'Content-Security-Policy' "$4")" == 1 ]] || echo "feed: _headers must keep exactly one CSP line"
        [[ "$(grep -c '^/' "$4")" == 1 ]] || echo "feed: _headers must stay a single /* block"
    }
    run_feed_check() { feed_check "$1/feed/index.xml" "$1/index.html" "$1/posts/x/index.html" "$1/_headers"; }
    out="$(run_feed_check "$legacy/public")"
    if [[ -s "$legacy/public/feed/index.xml" && -z "$out" ]]; then
        pass "feed: /feed/index.xml is RSS with the self link, full bodies, discovery links and headers"
    else
        fail "feed: ${out:-/feed/index.xml missing}"
    fi
    # Negative cases: the feed check must bite.
    mut="$work/mut"
    cp -r "$legacy/public" "$mut"
    sed -i "s#$host/feed/index.xml#$host/index.xml#" "$mut/index.html"
    if [[ -n "$(run_feed_check "$mut")" ]]; then
        pass "guard: a head that advertises /index.xml is caught"
    else
        fail "guard: a head advertising /index.xml was accepted"
    fi
    cp "$legacy/public/index.html" "$mut/index.html"
    sed -i 's#rel="self"#rel="alternate"#' "$mut/feed/index.xml"
    if [[ -n "$(run_feed_check "$mut")" ]]; then
        pass "guard: a feed without the self link is caught"
    else
        fail "guard: a feed without the self link was accepted"
    fi
    cp "$legacy/public/feed/index.xml" "$mut/feed/index.xml"
    printf '/feed/\n  Content-Type: application/rss+xml\n' >>"$mut/_headers"
    if [[ -n "$(run_feed_check "$mut")" ]]; then
        pass "guard: an extra _headers rule block is caught"
    else
        fail "guard: an extra _headers rule block was accepted"
    fi
else
    fail "the legacy site did not build: $(tail -n 3 "$legacy/build.log")"
fi

# With no upload data file the site builds and holds no upload rule.
if build_legacy "$work/legacy-empty" ""; then
    if grep -q 'wp-content' "$work/legacy-empty/public/_redirects"; then
        fail "no upload data, yet an upload rule exists"
    else
        pass "no upload data: no wp-content rule"
    fi
else
    fail "the site without upload data did not build: $(tail -n 3 "$work/legacy-empty/build.log")"
fi

# A bad upload entry fails the build and names legacy_uploads.
reject_upload() { # reject_upload <label> <json>
    local s="$work/up-$RANDOM"
    if build_legacy "$s" "$2"; then
        fail "upload $1: the build should have failed"
    elif grep -q 'legacy_uploads' "$s/build.log"; then
        pass "upload $1: the build fails and names legacy_uploads"
    else
        fail "upload $1: the build failed for another reason: $(tail -n 3 "$s/build.log")"
    fi
}
reject_upload "source outside uploads" '[{"from": "/evil/a.jpg", "to": "/posts/y/a.webp"}]'
reject_upload "external target" '[{"from": "/wp-content/uploads/a.jpg", "to": "https://evil.example/a.webp"}]'
reject_upload "newline in source" '[{"from": "/wp-content/uploads/a.jpg\n/evil /elsewhere 301", "to": "/posts/y/a.webp"}]'
reject_upload "space in target" '[{"from": "/wp-content/uploads/a.jpg", "to": "/posts/y/a b.webp"}]'
reject_upload "splat in source" '[{"from": "/wp-content/uploads/*", "to": "/posts/y/a.webp"}]'
reject_upload "missing target" '[{"from": "/wp-content/uploads/a.jpg"}]'
reject_upload "scheme-relative target" '[{"from": "/wp-content/uploads/a.jpg", "to": "//evil.example/image"}]'
reject_upload "scheme-relative target with a path only" '[{"from": "/wp-content/uploads/a.jpg", "to": "//posts/y/a.webp"}]'
reject_upload "backslash target" '[{"from": "/wp-content/uploads/a.jpg", "to": "/\\evil.example/image"}]'
reject_upload "backslash after the first segment" '[{"from": "/wp-content/uploads/a.jpg", "to": "/posts\\y/a.webp"}]'
reject_upload "control character in target" '[{"from": "/wp-content/uploads/a.jpg", "to": "/posts/y/a\tb.webp"}]'
reject_upload "carriage return in target" '[{"from": "/wp-content/uploads/a.jpg", "to": "/posts/y/a\rb.webp"}]'
reject_upload "backslash in source" '[{"from": "/wp-content/uploads/a\\b.jpg", "to": "/posts/y/a.webp"}]'

# --- tag redirects --------------------------------------------------------------
# /tag/<slug>/ (the WordPress tag address) goes to the tag page, only for tags a
# published post uses; the rules sit among the static ones in byte order.
tagged="$work/tagged"
if TAGS=1 build_legacy "$tagged" "$legacy_uploads"; then
    {
        grep -v '^/wp-content/' "$work/legacy.want" | grep -v '^/category/\*\|^/page/\*'
        printf '%s\n' '/tag/foo-bar /tags/foo-bar/ 301' '/tag/foo-bar/ /tags/foo-bar/ 301' '/tag/zeta /tags/zeta/ 301' '/tag/zeta/ /tags/zeta/ 301'
    } | LC_ALL=C sort >"$work/tagged.want"
    {
        grep '^/wp-content/' "$work/legacy.want"
        grep '\*' "$work/legacy.want"
    } >>"$work/tagged.want"
    if diff -u "$work/tagged.want" <(grep -v '^#' "$tagged/public/_redirects") >"$work/tagged.diff"; then
        pass "tag rules: /tag/<slug>/ goes to /tags/<slug>/ for used tags, none for a draft-only tag"
    else
        fail "tag rules differ from the expected lines: $(cat "$work/tagged.diff")"
    fi
    if out="$(check_lines "$tagged/public/_redirects" 2>&1)"; then
        pass "tag rules: every line is well formed"
    else
        fail "tag rules: $out"
    fi
    # Every tag redirect lands on a page the build publishes.
    bad_tag=""
    while read -r t; do
        [[ -f "$tagged/public${t}index.html" ]] || bad_tag="$bad_tag $t"
    done < <(awk '$1 ~ /^\/tag\// { print $2 }' "$tagged/public/_redirects")
    if [[ -z "$bad_tag" ]] && grep -q '^/tag/zeta/ ' "$tagged/public/_redirects"; then
        pass "tag rules: every target is a published tag page"
    else
        fail "tag rules: targets not published:${bad_tag:- none checked}"
    fi
else
    fail "the tagged site did not build: $(tail -n 3 "$tagged/build.log")"
fi
# With no tags there is no /tag/ rule at all (the plain legacy site above).
if grep -q '^/tag/' "$legacy/public/_redirects"; then
    fail "an untagged site has a /tag/ rule"
else
    pass "no tags: no /tag/ rule"
fi

# --- a post in the Uncategorized category -------------------------------------
# The legacy mapping sends /category/uncategorized/ to /posts/ whether or not
# Hugo makes a term page, so a post using that category must not change it.
uncat="$work/uncat"
if UNCAT=1 build_legacy "$uncat" "$legacy_uploads"; then
    if diff -u "$work/legacy.want" <(grep -v '^#' "$uncat/public/_redirects") >"$work/uncat.diff"; then
        pass "uncategorized post: /category/uncategorized/ still goes to /posts/, no term-page rule"
    else
        fail "uncategorized post changes the rules: $(cat "$work/uncat.diff")"
    fi
else
    fail "the site with an uncategorized post did not build: $(tail -n 3 "$uncat/build.log")"
fi

# --- the file-size limit counts every line ------------------------------------
# Cloudflare Pages allows 2000 static rules and 100 dynamic ones, and
# scripts/check-site-artifact.sh allows 2000 lines in all. The file always adds
# a header line and two dynamic rules, so 1997 static rules is the most that
# fits. A bare site holds 8 static rules (6 feed, 2 uncategorized); the rest
# are one-line .html aliases on one page.
build_count() { # build_count <dir> <static-rule-total> [<tags>]
    local site="$1" n="$2" ntags="${3:-0}" i base=8
    mkdir -p "$site/content/posts"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$site/"
    cp "$root/hugo.toml" "$site/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$site/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$site/content/posts/_index.md"
    if ((ntags > 0)); then
        # One dated post with the tags: 4 date rules and 2 rules per tag.
        mkdir -p "$site/content/posts/t"
        {
            printf -- '---\ntitle: "T"\ndate: 2024-01-02T03:04:05-05:00\ntags:\n'
            for ((i = 1; i <= ntags; i++)); do printf '  - tag%d\n' "$i"; done
            printf -- '---\n\nBody.\n'
        } >"$site/content/posts/t/index.md"
        base=$((8 + 4 + 2 * ntags))
    fi
    {
        printf -- '---\ntitle: "Home"\naliases:\n'
        for ((i = 1; i <= n - base; i++)); do printf '  - /a%d.html\n' "$i"; done
        printf -- '---\n'
    } >"$site/content/posts/_index.md"
    (cd "$site" && hugo --destination "$site/public" >"$site/build.log" 2>&1)
}
c="$work/count-1997"
if build_count "$c" 1997; then
    lines="$(wc -l <"$c/public/_redirects")"
    if ((lines == 2000)) && "$root/scripts/check-site-artifact.sh" "$c/public" >"$work/count.log" 2>&1; then
        pass "1997 static rules: 2000 lines in all, and the artifact check accepts it"
    else
        fail "1997 static rules: $lines lines, artifact check: $(tail -n 3 "$work/count.log")"
    fi
else
    fail "1997 static rules should build: $(tail -n 3 "$c/build.log")"
fi
for n in 1998 2000 2001; do
    c="$work/count-$n"
    if build_count "$c" "$n"; then
        fail "$n static rules: the build should have failed (the file would exceed 2000 lines)"
    elif grep -q '_redirects' "$c/build.log"; then
        pass "$n static rules: the build fails and names _redirects"
    else
        fail "$n static rules: the build failed for another reason: $(tail -n 3 "$c/build.log")"
    fi
done

# Tag rules count toward the same cap: 5 tags add 10 static rules.
c="$work/count-tags-1997"
if build_count "$c" 1997 5; then
    lines="$(wc -l <"$c/public/_redirects")"
    if ((lines == 2000)) && grep -q '^/tag/tag5/ ' "$c/public/_redirects" && "$root/scripts/check-site-artifact.sh" "$c/public" >"$work/count.log" 2>&1; then
        pass "1997 static rules including 5 tags: 2000 lines, tag rules present, artifact check accepts it"
    else
        fail "1997 static rules with tags: $lines lines, artifact check: $(tail -n 3 "$work/count.log")"
    fi
else
    fail "1997 static rules with tags should build: $(tail -n 3 "$c/build.log")"
fi
c="$work/count-tags-1998"
if build_count "$c" 1998 5; then
    fail "1998 static rules including tags: the build should have failed"
elif grep -q '_redirects' "$c/build.log"; then
    pass "1998 static rules including tags: the build fails and names _redirects"
else
    fail "1998 static rules including tags: failed for another reason: $(tail -n 3 "$c/build.log")"
fi

# --- guard self-test: the line checker must reject bad lines -------------------
i=0
for bad in '/a /b' '/a /b 301 extra' '/a /b 200' '/a https://evil.example/ 301' '/a /b#c%20d 301' '/a /b 308' \
    '/feed/ /feed/index.xml 200' '/a*b /b 301' '/a /b* 301' '/a/*/c /b 301'; do
    i=$((i + 1))
    printf '# header\n%s\n' "$bad" >"$work/line$i"
    if check_lines "$work/line$i" >/dev/null 2>&1; then
        fail "guard: line '$bad' was accepted"
    fi
done
printf '# header\n/a /b 301\n/c/ /d/#ok 301\n/e/* /f/ 301\n' >"$work/ok"
if check_lines "$work/ok" >/dev/null 2>&1; then
    pass "guard: bad lines are rejected and good lines accepted"
else
    fail "guard: a good line was rejected"
fi

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all redirect checks passed"
