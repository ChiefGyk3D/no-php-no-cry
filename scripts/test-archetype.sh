#!/usr/bin/env bash
# Test the post and journal archetypes (issue #103): `hugo new content` makes a
# page bundle from each; the result is a draft that stays out of the build; the
# same page, published with a description and an image with real alt text,
# builds and passes scripts/check-output.sh; and a published page whose image
# has no alt text, or the "TODO alt text" placeholder, fails the build.
#
# Everything happens in a throwaway site under the repository's gitignored tmp/,
# so no content/ file of the repository is touched. Needs the pinned Hugo; a
# missing Hugo is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/archetype.XXXXXX")"
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

# new_site <dir>: layouts, assets, static, config and archetypes from the
# repository, plus the two section index pages. No other content.
new_site() {
    local site="$1"
    mkdir -p "$site/content/posts" "$site/content/journal"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$root/archetypes" "$root/data" "$site/"
    cp "$root/hugo.toml" "$site/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$site/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$site/content/posts/_index.md"
    printf -- '---\ntitle: "Journal"\n---\n' >"$site/content/journal/_index.md"
}

# publish <index.md> <alt text>: turn the archetype output into a finished page.
# Every description must be unique (check-output.sh enforces it), and the post
# gets one alias, which the checker then expects as a 301 line.
publish() {
    local f="$1" alt="$2" slug
    slug="$(basename "$(dirname "$f")")"
    sed -i \
        -e 's/^draft: true$/draft: false/' \
        -e "s/^description: \"\"\$/description: \"A synthetic page made from the archetype for a test: $slug.\"/" \
        -e 's/^categories: \[\]$/categories: ["Sample"]/' \
        -e 's/^tags: \[\]$/tags: ["archetype"]/' "$f"
    case "$f" in
        */posts/*) sed -i -e 's#^slug: \(.*\)$#slug: \1\naliases: ["/2026/11/06/example-post/"]#' "$f" ;;
    esac
    printf '\n![%s](pic.png)\n' "$alt" >>"$f"
    cp "$root/content/posts/sample-post/sample-image.png" "$(dirname "$f")/pic.png"
}

site="$work/site"
new_site "$site"
for kind in posts/example-post journal/example-entry; do
    if (cd "$site" && hugo new content "$kind" >"$work/new.log" 2>&1) && [[ -f "$site/content/$kind/index.md" ]]; then
        pass "hugo new content $kind made a page bundle"
    else
        fail "hugo new content $kind failed: $(tail -n 3 "$work/new.log")"
    fi
done

post="$site/content/posts/example-post/index.md"
entry="$site/content/journal/example-entry/index.md"

# Safe defaults the guide promises.
for f in "$post" "$entry"; do
    name="${f#"$site"/content/}"
    grep -qx 'draft: true' "$f" && pass "$name starts as a draft" || fail "$name is not a draft"
    grep -qx 'syndicate: false' "$f" && pass "$name does not syndicate by default" || fail "$name syndicates by default"
    grep -qx '<!--more-->' "$f" && pass "$name has the summary marker" || fail "$name has no summary marker"
done
grep -q 'Alt text prompts' "$post" && pass "the post archetype carries alt text prompts" || fail "no alt text prompts in the post archetype"

# As a draft: builds, and the page is not in the output.
if (cd "$site" && hugo --destination "$site/public-draft" >"$work/draft.log" 2>&1); then
    if [[ ! -e "$site/public-draft/posts/example-post" && ! -e "$site/public-draft/journal/example-entry" ]]; then
        pass "the draft site builds and the drafts are not published"
    else
        fail "a draft page was published"
    fi
else
    fail "the draft site did not build: $(tail -n 3 "$work/draft.log")"
fi

# Published with real alt text: builds and passes the output checks.
publish "$post" "A striped test pattern used as a stand-in image"
publish "$entry" "A striped test pattern used as a stand-in image"
if (cd "$site" && hugo --minify --destination "$site/public" >"$work/pub.log" 2>&1); then
    pass "the published site builds"
    if [[ -f "$site/public/posts/example-post/index.html" && -f "$site/public/journal/example-entry/index.html" ]]; then
        pass "both pages are in the output"
    else
        fail "a published page is missing from the output"
    fi
    if EXPECT_ENV=production EXPECT_ALIAS=/2026/11/06/example-post/ "$root/scripts/check-output.sh" "$site/public" >"$work/check.log" 2>&1; then
        pass "scripts/check-output.sh passes on the published site"
    else
        fail "check-output.sh failed: $(tail -n 5 "$work/check.log")"
    fi
    if "$root/scripts/check-wording.sh" "$site" >"$work/wording.log" 2>&1; then
        pass "scripts/check-wording.sh passes on the new pages"
    else
        fail "check-wording.sh failed: $(tail -n 3 "$work/wording.log")"
    fi
else
    fail "the published site did not build: $(tail -n 5 "$work/pub.log")"
fi

# Negative cases: the build must refuse a published image without real alt text.
# The first case also proves the harness reports a failing build as a failure.
neg() { # neg <name> <alt text> <expected message>
    local s="$work/neg-$1"
    new_site "$s"
    (cd "$s" && hugo new content posts/example-post >/dev/null 2>&1)
    publish "$s/content/posts/example-post/index.md" "$2"
    if (cd "$s" && hugo --destination "$s/public" >"$s/build.log" 2>&1); then
        fail "guard: a published page with $1 alt text built"
    elif grep -q "$3" "$s/build.log"; then
        pass "a published page with $1 alt text fails the build"
    else
        fail "the $1 alt build failed for another reason: $(tail -n 3 "$s/build.log")"
    fi
}
neg missing "" "has no alt text"
neg placeholder "TODO alt text" "placeholder alt text"

# The same missing-alt page is fine while it is a draft (nothing is rendered).
s="$work/neg-missing"
sed -i 's/^draft: false$/draft: true/' "$s/content/posts/example-post/index.md"
if (cd "$s" && hugo --destination "$s/public-d" >"$s/build-d.log" 2>&1); then
    pass "the same page builds again as a draft"
else
    fail "a draft with missing alt text should build: $(tail -n 3 "$s/build-d.log")"
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all archetype checks passed"
