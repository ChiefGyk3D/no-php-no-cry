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
# internal paths (same grammar as scripts/test-redirects.sh).
check_lines() {
    awk '
        /^#/ { next }
        {
            if (NF != 3) { print "line " NR ": " NF " fields"; bad = 1; next }
            if ($1 !~ /^\/[A-Za-z0-9._~\/%-]*$/) { print "line " NR ": bad source"; bad = 1 }
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
    if [[ "$(grep -vc '^#' "$work/plain/public/_redirects" || true)" == "0" ]]; then
        pass "no redirect rule is published while the pages are drafts"
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
    if [[ "$(grep -vc '^#' "$r")" == "3" ]] && out="$(check_lines "$r" 2>&1)"; then
        pass "exactly three well-formed rules for the two aliased posts"
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

# --- guard self-test: the line checker must reject bad lines -------------------
i=0
for bad in '/a /b' '/a /b 301 extra' '/a /b 200' '/a https://evil.example/ 301' '/a /b#c%20d 301' '/a /b 308'; do
    i=$((i + 1))
    printf '# header\n%s\n' "$bad" >"$work/line$i"
    if check_lines "$work/line$i" >/dev/null 2>&1; then
        fail "guard: line '$bad' was accepted"
    fi
done
printf '# header\n/a /b 301\n/c/ /d/#ok 301\n' >"$work/ok"
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
