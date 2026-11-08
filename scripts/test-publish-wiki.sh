#!/usr/bin/env bash
# Tests for scripts/publish-wiki.sh: page links become full wiki addresses, anchors
# survive, code and external links are untouched, and a missing page or a relative
# path exits non-zero without writing anything. The real docs/wiki must publish clean.
#
# Fixtures are throwaway directories under the repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/publish-wiki.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}
b="https://example.test/wiki"
tick='`'
fence='```'

# case <name> <want rc> <page text>: Page.md holds the text, Other.md exists.
mk() {
    mkdir -p "$work/$1/src" "$work/$1/dest"
    printf '# Other\n' >"$work/$1/src/Other.md"
    printf '%s\n' "$2" >"$work/$1/src/Page.md"
}
run() { WIKI_BASE="$b" "$root/scripts/publish-wiki.sh" "$work/$1/dest" "$work/$1/src" 2>&1; }

mk plain 'See [o](Other.md) and [a](Other.md#sec) and [x](https://x.test/a.md) and [h](#here).'
rc=0
out="$(run plain)" || rc=$?
page="$work/plain/dest/Page.md"
if [[ $rc -eq 0 ]] && grep -qF "[o]($b/Other)" "$page" && grep -qF "[a]($b/Other#sec)" "$page" &&
    grep -qF '(https://x.test/a.md)' "$page" && grep -qF '(#here)' "$page" &&
    [[ -f "$work/plain/dest/Other.md" ]]; then ok "page links and anchors rewritten, others kept"; else bad "plain: rc=$rc $out"; fi

mk code "Run ${tick}[o](Other.md)${tick} here.
${fence}md
![alt](pic.webp) and [o](Other.md)
${fence}"
rc=0
out="$(run code)" || rc=$?
if [[ $rc -eq 0 ]] && grep -qF "${tick}[o](Other.md)${tick}" "$work/code/dest/Page.md" &&
    grep -qF '![alt](pic.webp) and [o](Other.md)' "$work/code/dest/Page.md"; then ok "code spans and fences untouched"; else bad "code: rc=$rc $out"; fi

mk missing 'See [m](Nope.md).'
rc=0
out="$(run missing)" || rc=$?
if [[ $rc -ne 0 ]] && grep -q 'missing page Nope.md' <<<"$out" && [[ ! -e "$work/missing/dest/Page.md" ]]; then ok "missing page fails, nothing written"; else bad "missing: rc=$rc $out"; fi

mk rel 'See ![i](pic.webp).'
rc=0
out="$(run rel)" || rc=$?
if [[ $rc -ne 0 ]] && grep -q 'relative link not valid' <<<"$out" && [[ ! -e "$work/rel/dest/Other.md" ]]; then ok "relative path fails, nothing written"; else bad "rel: rc=$rc $out"; fi

mk title 'See [o](Other.md "A title") and [p](<Other.md#x> '"'"'t'"'"') and \\[no](Other.md) and plain ](Other.md) text.'
rc=0
out="$(run title)" || rc=$?
page="$work/title/dest/Page.md"
if [[ $rc -eq 0 ]] && grep -qF "[o]($b/Other \"A title\")" "$page" && grep -qF "[p](<$b/Other#x> 't')" "$page" &&
    grep -qF '\\[no](Other.md)' "$page" && grep -qF 'plain ](Other.md) text' "$page"; then ok "titles and angle brackets handled, escaped and bare text untouched"; else bad "title: rc=$rc $out"; fi

mk fences "$(printf '%s\n' '````' '[o](Other.md)' '```' '[o](Other.md)' '````' '[o](Other.md)' '~~~' '```' '[o](Other.md)' '~~~')"
rc=0
out="$(run fences)" || rc=$?
page="$work/fences/dest/Page.md"
if [[ $rc -eq 0 ]] && [[ "$(grep -cF "[o](Other.md)" "$page")" -eq 3 ]] && [[ "$(grep -cF "[o]($b/Other)" "$page")" -eq 1 ]]; then ok "fence closes only on a matching marker and length"; else bad "fences: rc=$rc $out"; fi

mk stale 'See [o](Other.md).'
printf 'old\n' >"$work/stale/dest/Gone.md"
printf 'img\n' >"$work/stale/dest/keep.png"
rc=0
out="$(run stale)" || rc=$?
if [[ $rc -eq 0 ]] && [[ ! -e "$work/stale/dest/Gone.md" ]] && [[ -f "$work/stale/dest/keep.png" ]]; then ok "stale pages removed, other files kept"; else bad "stale: rc=$rc $out"; fi

mkdir -p "$work/real"
rc=0
out="$("$root/scripts/publish-wiki.sh" "$work/real" 2>&1)" || rc=$?
n="$(find "$root/docs/wiki" -maxdepth 1 -name '*.md' | wc -l)"
if [[ $rc -eq 0 ]] && grep -q "ok ($n pages" <<<"$out" && ! grep -qE '\]\([A-Za-z_-]+\.md[)#]' "$work/real/Home.md" &&
    ! grep -qE '\]\([A-Za-z_-]+\.md[)#]' "$work/real/_Sidebar.md"; then ok "the real wiki publishes clean ($n pages)"; else bad "real: rc=$rc $out"; fi

exit "$fail"
