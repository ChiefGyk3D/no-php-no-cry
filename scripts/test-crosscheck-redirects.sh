#!/usr/bin/env bash
# Test scripts/crosscheck-redirects.sh against a fixture _redirects and output tree.
# Cases: a redirect that lands on an existing page (pass), a redirect to a missing
# page (fail), a path with no rule and no file (reported gap), an alias stub page
# (pass), a splat rule, a redirect chain, a loop, a non-301 status, and a rule that
# wins over a file. Builds under the repository's gitignored tmp/, never /tmp. No
# network.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="$root/scripts/crosscheck-redirects.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/crosscheck-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

out="$work/public"
mkdir -p "$out/posts/hello" "$out/feed" "$out/old-alias" "$out/dead-alias" "$out/about"
echo '<html>hello</html>' >"$out/posts/hello/index.html"
echo '<html>posts</html>' >"$out/posts/index.html"
echo '<html>about</html>' >"$out/about/index.html"
echo '<rss/>' >"$out/feed/index.xml"
echo '<html><head><meta http-equiv="refresh" content="0; url=https://example.test/posts/hello/"></head></html>' >"$out/old-alias/index.html"
echo '<html><head><meta http-equiv="refresh" content="0; url=https://example.test/posts/gone/"></head></html>' >"$out/dead-alias/index.html"
cat >"$out/_redirects" <<'RULES'
# fixture
/old-post/ /posts/hello/ 301
/old-post /posts/hello/ 301
/lost/ /posts/missing/ 301
/hop1/ /hop2/ 301
/hop2/ /posts/hello/ 301
/loop-a/ /loop-b/ 301
/loop-b/ /loop-a/ 301
/temp/ /posts/hello/ 302
/about/ /posts/hello/ 301
/category/* /posts/ 301
RULES

list="$work/list.txt"
cat >"$list" <<'LIST'
# legacy paths
/old-post/
https://example.test/old-post?x=1
/lost/
/nowhere/
/old-alias/
/dead-alias/
/hop1/
/loop-a/
/temp/
/category/anything/deep/
/feed/index.xml
/posts/hello/
LIST

res="$work/res.txt"
rc=0
"$tool" --allow-gaps "$list" "$out" >"$res" 2>&1 || rc=$?

expect() { # expect <path> <verdict>
    if grep -qxF "$(printf '%s\t%s' "$1" "$2")" "$res"; then
        pass "$1 -> $2"
    else
        fail "$1 should report '$2'; got: $(grep -F "$1" "$res" || echo none)"
    fi
}
expect /old-post/ "ok redirect -> /posts/hello/"
expect /old-post "ok redirect -> /posts/hello/"
expect /lost/ "FAIL redirect to missing /posts/missing/"
expect /nowhere/ "GAP no rule"
expect /old-alias/ "ok alias -> /posts/hello/"
expect /dead-alias/ "FAIL alias to missing /posts/gone/"
expect /hop1/ "ok redirect -> /posts/hello/"
expect /loop-a/ "FAIL redirect loop"
expect /temp/ "FAIL status 302 on /temp/"
expect /category/anything/deep/ "ok redirect -> /posts/"
expect /feed/index.xml "ok served"
expect /posts/hello/ "ok served"
if grep -qx 'crosscheck: ok 7, gap 1, fail 4' "$res"; then
    pass "counts: ok 7, gap 1, fail 4"
else
    fail "counts: $(tail -n 1 "$res")"
fi
if [[ $rc -eq 1 ]]; then pass "a failure exits 1"; else fail "failure exit code was $rc"; fi

# A gap alone: fatal by default, tolerated with --allow-gaps.
printf '/old-post/\n/nowhere/\n' >"$work/gap.txt"
rc=0
"$tool" "$work/gap.txt" "$out" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then pass "a gap exits 1 by default"; else fail "gap exit code was $rc"; fi
rc=0
"$tool" --allow-gaps "$work/gap.txt" "$out" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then pass "--allow-gaps tolerates a gap"; else fail "--allow-gaps exit code was $rc"; fi
printf '/old-post/\n/about/\n' >"$work/clean.txt"
rc=0
"$tool" "$work/clean.txt" "$out" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then pass "an all-ok list exits 0 (a rule wins over a file)"; else fail "clean exit code was $rc"; fi

# Usage errors exit 2.
rc=0
"$tool" "$work/nope.txt" "$out" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then pass "a missing list exits 2"; else fail "missing list exit code was $rc"; fi
mkdir "$work/bare"
rc=0
"$tool" "$list" "$work/bare" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then pass "an output dir without _redirects exits 2"; else fail "bare dir exit code was $rc"; fi

if [[ $failures -gt 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all crosscheck-redirects tests passed"
