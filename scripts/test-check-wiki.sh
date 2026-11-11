#!/usr/bin/env bash
# Tests for scripts/check-wiki.py: the repository's README and wiki pages are clean
# (and the check really read them), and the check bites on each kind of broken
# reference, a missing page, an empty wiki and the house-style rules, while good
# input of the same shapes passes.
#
# Fixtures are throwaway repositories under the repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/check-wiki.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}
check_py() { python3 -I "$root/scripts/check-wiki.py" "$@"; }

# --- the repository itself ------------------------------------------------------
rc=0
check_py "$root" >"$work/repo.log" 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then
    ok "the repository README and wiki are clean"
else
    bad "the repository has findings: $(cat "$work/repo.log")"
fi
# Collect loosely, assert strictly: the real wiki must hold every required page and
# the check must have read the README plus all of them.
n="$(find "$root/docs/wiki" -maxdepth 1 -name '*.md' | wc -l)"
if [[ "$n" -ge 17 ]]; then ok "the wiki holds $n pages"; else bad "the wiki holds only $n pages"; fi
if grep -q "check-wiki: ok ($((n + 1)) files)" "$work/repo.log"; then
    ok "the check read the README and all $n pages"
else
    bad "the check did not read every file: $(cat "$work/repo.log")"
fi

# The public analytics how-to is a wiki source and points readers to the longer
# repository copy. Each acceptance item has its own check so removing one part
# of the guide makes this test fail.
howto="$root/docs/wiki/Privacy-first-analytics-for-Hugo.md"
repo_howto="$root/docs/privacy-first-analytics-for-hugo.md"
if [[ -f "$howto" && -f "$repo_howto" ]]; then
    ok "the analytics how-to has repository and wiki copies"
else
    bad "the analytics how-to is missing a repository or wiki copy"
fi
for requirement in \
    '## Site configuration' \
    '## Hugo render hook' \
    '## Cloudflare Pages routes' \
    '## Response headers' \
    '## Privacy text from the same configuration' \
    '## Preview-first deployment order' \
    '## Owner-only account checklist'; do
    if [[ -f "$howto" ]] && grep -qF "$requirement" "$howto"; then
        ok "analytics how-to includes $requirement"
    else
        bad "analytics how-to is missing $requirement"
    fi
done
for requirement in \
    'Optional, less private: city' \
    'Optional, less private: per-domain clicks' \
    'Optional, less private: daily visitor code' \
    'not live in no-php-no-cry'; do
    if [[ -f "$howto" ]] && grep -qiF "$requirement" "$howto"; then
        ok "analytics how-to marks $requirement"
    else
        bad "analytics how-to does not mark $requirement"
    fi
done

# --- fixtures -------------------------------------------------------------------
# fixture <name> <page text>: a repository with a real file, a real folder, a second
# wiki page and one wiki page holding the text under test.
fixture() {
    local d="$work/$1"
    mkdir -p "$d/docs/wiki" "$d/scripts" "$d/layouts"
    : >"$d/scripts/real.sh"
    : >"$d/layouts/baseof.html"
    printf '# Real\n' >"$d/docs/wiki/Other.md"
    printf '# A heading\n\n## Second heading\n\n%s\n' "$2" >"$d/docs/wiki/Page.md"
    printf '# Readme\n' >"$d/README.md"
    : >"$d/LICENSE"
    echo "$d"
}
# expect <name> <exit 0|1> <rule or -> <page text>
expect() {
    local d out rc=0
    d="$(fixture "$1" "$4")"
    out="$(check_py --no-require-set "$d" 2>&1)" || rc=$?
    if [[ $rc -ne "$2" ]]; then
        bad "$1 (exit $rc, want $2): $out"
    elif [[ "$3" != "-" ]] && ! grep -q "^\[$3\]" <<<"$out"; then
        bad "$1 (exit ok but rule [$3] not reported): $out"
    else
        ok "$1"
    fi
}

fence='```'
tick='`'
emdash="$(printf '\342\200\224')"

expect good-wiki-link 0 - "See [other](Other.md) and [file](../../scripts/real.sh)."
expect good-anchor 0 - "See [x](Other.md#real) and [y](#a-heading) and [z](#second-heading)."
expect good-repo-url 0 - "See [x](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/scripts/real.sh)."
expect good-external-url 0 - "See [x](https://example.com/nothing-here)."
expect good-code-path 0 - "Run ${tick}scripts/real.sh${tick} or look in ${tick}layouts/${tick} and ${tick}LICENSE${tick}."
expect good-placeholder-path 0 - "Make ${tick}content/posts/<slug>/index.md${tick} and ${tick}scripts/test-*.sh${tick} and ${tick}docs/wiki/\$NAME.md${tick}."
expect good-fence 0 - "${fence}sh
scripts/real.sh --flag
ls layouts/baseof.html
${fence}"

expect bad-wiki-link 1 bad-link "See [gone](Missing.md)."
expect bad-repo-relative-link 1 bad-link "See [gone](../../scripts/missing.sh)."
expect bad-repo-url 1 bad-link "See [x](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/scripts/missing.sh)."
expect bad-escape-link 1 bad-link "See [x](../../../outside.md)."
expect bad-anchor-same-page 1 bad-anchor "See [y](#no-such-heading)."
expect bad-anchor-other-page 1 bad-anchor "See [y](Other.md#no-such-heading)."
expect bad-code-path 1 bad-path "Run ${tick}scripts/missing.sh${tick} first."
expect bad-second-word-in-span 1 bad-path "Run ${tick}bash scripts/missing.sh --flag${tick} first."
expect good-second-word-in-span 0 - "Run ${tick}bash scripts/real.sh --flag${tick} first."
expect bad-code-dir 1 bad-path "Look in ${tick}layouts/nothing/${tick}."
expect bad-root-file 1 bad-path "Read ${tick}MISSING.md${tick}."
expect bad-fence-path 1 bad-path "${fence}sh
scripts/missing.sh --flag
${fence}"
expect bad-fence-path-quoted 1 bad-path "${fence}sh
bash \"scripts/missing.sh\"
${fence}"
expect http-link 1 http-link "See http://example.com/x for more."
expect private-home-path 1 private-path "It lives in /home/someone/project."
expect private-dev-folder 1 private-path "Use ~/.local/share/no-php-no-cry-dev/hugo."
expect em-dash 1 em-dash "A sentence ${emdash} with a dash."

# A path in plain prose, outside backticks and fences, is not judged, so ordinary
# words never trip the check.
expect plain-prose-not-checked 0 - "The scripts/missing.sh name in plain prose is not a checked span."

# --- the whole set --------------------------------------------------------------
d="$(fixture required-set "Text.")"
rc=0
out="$(check_py "$d" 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^\[missing-page\] docs/wiki/Home.md' <<<"$out"; then
    ok "a wiki missing required pages fails"
else
    bad "missing required pages not reported (exit $rc): $out"
fi

mkdir -p "$work/empty/docs/wiki"
printf '# Readme\n' >"$work/empty/README.md"
rc=0
out="$(check_py --no-require-set "$work/empty" 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^\[no-pages\]' <<<"$out"; then
    ok "an empty wiki fails"
else
    bad "an empty wiki passed (exit $rc): $out"
fi

rc=0
check_py --bogus "$root" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then ok "an unknown option is a usage error"; else bad "unknown option exit $rc, want 2"; fi

exit "$fail"
