#!/usr/bin/env bash
# Test the content migration end to end (issue #63): the converter's output
# builds with this repository's layouts, drafts stay out of the build, every
# old permalink becomes a well-formed _redirects rule (only the drafts build
# emits them), the archive banner and forward link render, and placeholder alt
# text stops a published page.
#
# Converter inputs and outputs live under the system temp directory (the
# converter refuses paths inside the repository); the throwaway Hugo sites live
# under the repository's gitignored tmp/. Needs the pinned Hugo; a missing Hugo
# is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/migration.XXXXXX")"
conv="$(mktemp -d)"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work" "$conv"' EXIT

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

# check_lines <file>: every line is a '#' comment or "/from /to 301" with
# internal paths (same grammar as scripts/test-redirects.sh; a source may end in
# a '*' splat, as the legacy WordPress rules do).
check_lines() {
    awk '
        /^#/ { next }
        {
            if (NF != 3) { print "line " NR ": " NF " fields"; bad = 1; next }
            if ($1 !~ /^\/[A-Za-z0-9._~\/%-]*\*?$/) { print "line " NR ": bad source"; bad = 1 }
            if ($2 !~ /^\/[A-Za-z0-9._~\/%-]*(#[A-Za-z0-9._~-]+)?$/) { print "line " NR ": bad target"; bad = 1 }
            if ($3 != "301") { print "line " NR ": status " $3; bad = 1 }
        }
        END { exit bad }
    ' "$1"
}

# A 1x1 PNG for the fixture's attachment.
png_b64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=='
mkdir -p "$conv/media/uploads/2023/02"
printf '%s' "$png_b64" | base64 -d >"$conv/media/uploads/2023/02/pic.png"

fixture="$root/tools/wxr2hugo/tests/fixtures/basic.xml"

convert() { # convert <name> <wxr> [converter args...]
    local name="$1" wxr="$2"
    shift 2
    cp "$wxr" "$conv/$name.xml"
    python3 -I "$root/tools/wxr2hugo/convert.py" --wxr "$conv/$name.xml" --out "$conv/$name" \
        --media "$conv/media/uploads" "$@" >"$conv/$name.log" 2>&1
}

build_site() { # build_site <dir> <converted-dir> [hugo args...]
    local site="$1" src="$2"
    shift 2
    mkdir -p "$site/content/posts"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$site/"
    cp "$root/hugo.toml" "$site/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$site/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$site/content/posts/_index.md"
    cp -r "$src/posts/." "$site/content/posts/"
    local page
    for page in "$src"/*/; do
        [[ -f "$page/index.md" ]] && cp -r "$page" "$site/content/$(basename "$page")"
    done
    (cd "$site" && hugo "$@" --destination "$site/public" >"$site/build.log" 2>&1)
}

# --- a draft-all migration builds, and publishes nothing ----------------------
if convert drafts "$fixture" --draft-all; then
    pass "the converter ran with --draft-all"
else
    fail "the converter failed: $(cat "$conv/drafts.log")"
fi
if build_site "$work/plain" "$conv/drafts"; then
    if [[ ! -e "$work/plain/public/posts/first-post" && ! -e "$work/plain/public/posts/second-post" ]]; then
        pass "draft-all pages are not built"
    else
        fail "a draft-all page was built"
    fi
    # What remains is the fixed set of legacy WordPress rules (feed, sitemap,
    # uncategorized category, paging): no alias, date archive or category line of a draft.
    cat >"$work/legacy-baseline" <<'RULES'
/category/uncategorized /posts/ 301
/category/uncategorized/ /posts/ 301
/comments/feed /feed/index.xml 301
/comments/feed/ /feed/index.xml 301
/feed /feed/index.xml 301
/feed/ /feed/index.xml 301
/feed/atom /feed/index.xml 301
/feed/atom/ /feed/index.xml 301
/wp-sitemap.xml /sitemap.xml 301
/category/* /posts/ 301
/page/* /posts/ 301
RULES
    if [[ "$(grep -v '^#' "$work/plain/public/_redirects")" == "$(cat "$work/legacy-baseline")" ]]; then
        pass "no alias, date or category rule is published while the pages are drafts"
    else
        fail "drafts leaked redirect rules: $(cat "$work/plain/public/_redirects")"
    fi
else
    fail "the draft-all site did not build: $(tail -n 3 "$work/plain/build.log")"
fi

# --- with drafts shown, every old permalink is a well-formed rule -------------
if build_site "$work/drafts" "$conv/drafts" --buildDrafts; then
    r="$work/drafts/public/_redirects"
    for want in \
        "/2023/02/10/first-post /posts/first-post/ 301" \
        "/2023/02/10/first-post/ /posts/first-post/ 301" \
        "/second-post.html /posts/second-post/ 301"; do
        if grep -qxF "$want" "$r"; then
            pass "rule present: $want"
        else
            fail "rule missing: $want"
        fi
    done
    # Alias rules are every line that is not a legacy WordPress rule (feeds,
    # sitemap, categories, tags, paging, date archives).
    aliases_only="$(grep -vE '^(#|/[0-9]{4}(/[0-9]{2})?/? /posts/ 301$|/feed|/comments/feed|/wp-sitemap\.xml |/category/|/tag/|/page/)' "$r" || true)"
    if [[ "$(grep -c '' <<<"$aliases_only")" == "3" ]] && out="$(check_lines "$r" 2>&1)"; then
        pass "exactly three alias rules for the two aliased posts, all well formed"
    else
        fail "unexpected _redirects: ${out:-$(cat "$r")}"
    fi
else
    fail "the drafts site did not build: $(tail -n 3 "$work/drafts/build.log")"
fi

# --- archive banner and forward link render -----------------------------------
printf '{"first-post": {"archive": "Kept as written.", "supersededBy": "/posts/second-post/"}}\n' >"$conv/annotations.json"
if convert annotated "$fixture" --draft-all --annotations "$conv/annotations.json" &&
    build_site "$work/annotated" "$conv/annotated" --buildDrafts; then
    html="$work/annotated/public/posts/first-post/index.html"
    if grep -q 'class="archive-banner' "$html" && grep -q 'Kept as written\.' "$html"; then
        pass "the archive banner renders"
    else
        fail "no archive banner in the built post"
    fi
    if grep -q 'class="superseded-note' "$html" && grep -Eq 'href="?/posts/second-post/' "$html"; then
        pass "the forward link renders"
    else
        fail "no forward link in the built post"
    fi
else
    fail "the annotated site did not build"
fi

# --- placeholder alt text stops a published page ------------------------------
sed 's/A striped test pattern//' "$fixture" >"$conv/noalt-src.xml"
if convert noalt "$conv/noalt-src.xml"; then
    if build_site "$work/noalt" "$conv/noalt"; then
        fail "a published page with placeholder alt text built"
    elif grep -q 'placeholder alt text' "$work/noalt/build.log"; then
        pass "a published page with placeholder alt text fails the build"
    else
        fail "the placeholder-alt build failed for another reason: $(tail -n 3 "$work/noalt/build.log")"
    fi
    if build_site "$work/noalt-draft" "$conv/noalt" --buildDrafts; then
        fail "guard: --buildDrafts rendered placeholder alt text without failing"
    fi
else
    fail "the no-alt conversion failed: $(cat "$conv/noalt.log")"
fi
if convert noalt-drafts "$conv/noalt-src.xml" --draft-all && build_site "$work/noalt-ok" "$conv/noalt-drafts"; then
    pass "the same page as a draft builds (it is not published)"
else
    fail "the draft version should build"
fi

# --- the legacy WordPress URLs that are not posts are redirected by the site ---
# 10 posts (once their drafts are published) plus these five make the 15 aliases
# of docs/redesign-brief.md section 12 item 16.
if hugo --quiet --source "$root" --destination "$work/real" >"$work/real.log" 2>&1; then
    for want in \
        "/blog /posts/ 301" "/blog/ /posts/ 301" \
        "/contact /about/#contact 301" "/contact/ /about/#contact 301" \
        "/support-me /support/ 301" "/support-me/ /support/ 301" \
        "/social-media /social/ 301" "/social-media/ /social/ 301" \
        "/sample-page / 301" "/sample-page/ / 301"; do
        if grep -qxF "$want" "$work/real/_redirects"; then
            pass "site rule present: $want"
        else
            fail "site rule missing: $want"
        fi
    done
    if out="$(check_lines "$work/real/_redirects" 2>&1)"; then
        pass "the site's own _redirects has only well-formed lines"
    else
        fail "the site's own _redirects: $out"
    fi
else
    fail "the site did not build: $(tail -n 3 "$work/real.log")"
fi

# --- the four batch-1 posts are published (issue #178) -------------------------
# Each is built (not a draft) at its permalink, keeps its original date, carries
# the archive note, and the Twitch and Toot post and page hold no wallet address.
wallet_re='bc1[a-z0-9]{20,}|0x[0-9a-fA-F]{30,}|\b[48][0-9A-Za-z]{94}\b|\b[1-9A-HJ-NP-Za-km-z]{32,44}\b'
wallet_scan() { # wallet_scan <file>: succeeds when the file holds a wallet-shaped string
    grep -Eq "$wallet_re" "$1"
}
note='This is a record, not a current view.'
if [[ -d "$work/real/posts" ]]; then
    for entry in \
        "stream-daemon-the-secure-open-source-stream-automation-engine-for-modern-creators 2025-11-05" \
        "introducing-twitch-and-toot-the-open-source-solution-for-mastodon-stream-alerts 2023-02-06" \
        "boosting-your-mastodon-servers-visibility-a-guide-to-federation-and-relays 2023-02-08" \
        "discovering-the-magic-of-mastodon-a-journey-into-the-decentralized-social-networking-world 2023-02-06"; do
        slug="${entry% *}"
        day="${entry#* }"
        page="$work/real/posts/$slug/index.html"
        src="$root/content/posts/$slug/index.md"
        if [[ -f "$page" ]]; then
            pass "published: $slug"
        else
            fail "not built (still a draft?): $slug"
            continue
        fi
        if grep -q "^draft:" "$src"; then fail "$slug still has a draft flag"; fi
        if grep -Eq "datetime=\"?$day" "$page" && grep -Eq "^date: $day" "$src"; then
            pass "original date kept: $slug $day"
        else
            fail "date is not $day: $slug"
        fi
        if [[ "$(grep -o 'class="\?archive-banner' "$page" | wc -l)" -eq 1 ]] && grep -Fq "$note" "$page"; then
            pass "one archive notice renders: $slug"
        else
            fail "archive notice missing or repeated: $slug"
        fi
        if grep -Fq "/$slug/ /posts/$slug/ 301" "$work/real/_redirects"; then
            pass "old permalink redirects: $slug"
        else
            fail "no redirect for the old permalink: $slug"
        fi
    done
    tt="introducing-twitch-and-toot-the-open-source-solution-for-mastodon-stream-alerts"
    if wallet_scan "$root/content/posts/$tt/index.md" || wallet_scan "$work/real/posts/$tt/index.html"; then
        fail "a wallet address string remains in the Twitch and Toot post"
    else
        pass "no wallet address string in the Twitch and Toot post"
    fi
    if grep -Fq 'href=/support/' "$work/real/posts/$tt/index.html" || grep -Fq 'href="/support/"' "$work/real/posts/$tt/index.html"; then
        pass "the Twitch and Toot post points to the Support page"
    else
        fail "the Twitch and Toot post has no link to /support/"
    fi
    # Guard: the scanner must bite on each address shape.
    for sample in \
        "bc1q$(printf 'a%.0s' {1..30})" \
        "0x$(printf 'b%.0s' {1..40})" \
        "4$(printf 'c%.0s' {1..94})" \
        "$(printf 'D%.0s' {1..44})"; do
        printf 'Tip: %s\n' "$sample" >"$work/wallet-sample"
        if wallet_scan "$work/wallet-sample"; then
            pass "guard: the wallet scan flags a sample of ${#sample} characters"
        else
            fail "guard: the wallet scan missed a sample of ${#sample} characters"
        fi
    done
    printf 'Tips go through the Support page now.\n' >"$work/wallet-sample"
    if wallet_scan "$work/wallet-sample"; then
        fail "guard: the wallet scan flagged plain prose"
    else
        pass "guard: the wallet scan passes plain prose"
    fi
fi

# --- guard self-test: the line checker must reject bad lines -------------------
i=0
for bad in '/a /b' '/a /b 301 extra' '/a /b 200' '/a https://evil.example/ 301' '/a /b#c%20d 301' '/a /b 308' '/a*b /b 301'; do
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
echo "all migration checks passed"
