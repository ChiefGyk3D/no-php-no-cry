#!/usr/bin/env bash
# Test scripts/check-budget.py with a small fixture site (no Hugo, no browser):
# the good tree passes, and each budget rule fails on a tree that breaks only it.
# Run from CI; the real build is checked by the "size budget" step.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/budget.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# make_site <dir>: a tree that is within every limit.
make_site() {
    local d="$1"
    mkdir -p "$d/css" "$d/fonts" "$d/brand" "$d/posts/hello"
    printf '%s' 'body{background:url(../brand/icon.svg)}@font-face{font-family:J;src:url(../fonts/j.woff2)}' >"$d/css/site.css"
    head -c 20000 /dev/urandom >"$d/fonts/j.woff2"
    head -c 30000 /dev/urandom >"$d/brand/pic.webp"
    printf '<svg xmlns="http://www.w3.org/2000/svg"></svg>' >"$d/brand/icon.svg"
    local page='<!doctype html><title>t</title><link rel=stylesheet href=/css/site.css><img src=/brand/pic.webp width=1 height=1 alt=x>'
    printf '%s' "$page" >"$d/index.html"
    printf '%s' "$page" >"$d/posts/hello/index.html"
}

# expect_fail <name> <rule> <dir>: the checker must exit 1 and name the rule.
expect_fail() {
    local out rc=0
    out="$(python3 -I "$root/scripts/check-budget.py" "$3" 2>&1)" || rc=$?
    if [[ $rc -eq 1 && "$out" == *"[$2]"* ]]; then
        pass "$1 -> $2"
    else
        fail "$1: expected exit 1 with [$2], got exit $rc: $out"
    fi
}

good="$work/good"
make_site "$good"
if python3 -I "$root/scripts/check-budget.py" "$good" >"$work/good.out" 2>&1; then
    pass "within-budget fixture passes"
else
    fail "within-budget fixture failed: $(cat "$work/good.out")"
fi

# Collected loosely, asserted strictly: the guard must see pages.
if grep -q 'budget: ok (2 pages' "$work/good.out"; then pass "the checker counted the fixture pages"; else fail "page count missing: $(cat "$work/good.out")"; fi

mutate() { # mutate <name> <rule> <command run inside a copy of the good tree>
    local d="$work/m-$1"
    cp -r "$good" "$d"
    (cd "$d" && eval "$3")
    expect_fail "$1" "$2" "$d"
}

mutate second-js js-name 'printf x > other.js'
mutate stray-mjs js-name 'printf x > other.mjs'
mutate stray-cjs js-name 'printf x > other.cjs'
mutate stray-upper-js js-name 'printf x > OTHER.JS'
mutate wrong-js-name js-name 'printf x > app.js; sed -i "s#<img#<script src=/app.js></script><img#" index.html'
mutate theme-js-retired js-name 'printf x > theme.js'
mutate copy-js-elsewhere js-page 'printf x > copy.js; sed -i "s#<img#<script src=/copy.js></script><img#" index.html'
mutate two-js-files js-count 'printf x > copy.js; printf x > other.js'
mutate big-js js-size 'head -c 20000 /dev/urandom | base64 > copy.js'
mutate big-mjs js-size 'head -c 20000 /dev/urandom | base64 > copy.mjs'
mutate big-cjs js-size 'head -c 20000 /dev/urandom | base64 > copy.cjs'
mutate big-css css-size 'head -c 60000 /dev/urandom | base64 > css/site.css'
mutate two-stylesheets css-count 'cp css/site.css css/two.css; sed -i "s#<img#<link rel=stylesheet href=/css/two.css><img#" index.html'
mutate big-font font-size 'head -c 40000 /dev/urandom > fonts/j.woff2'
mutate three-fonts font-count 'for n in a b c; do head -c 100 /dev/urandom > fonts/$n.woff2; done; printf "%s" "@font-face{src:url(../fonts/a.woff2)}@font-face{src:url(../fonts/b.woff2)}@font-face{src:url(../fonts/c.woff2)}" > css/site.css'
mutate big-html html-size 'head -c 60000 /dev/urandom | base64 >> index.html'
mutate big-image image-size 'head -c 130000 /dev/urandom > brand/pic.webp'
mutate huge-image-file image-file-size 'head -c 310000 /dev/urandom > brand/og.png'
mutate huge-svg-file image-file-size 'head -c 400000 /dev/urandom | base64 > brand/unreferenced.svg'
mutate page-over-total page-total 'head -c 100000 /dev/urandom > brand/pic.webp; head -c 29000 /dev/urandom > fonts/j.woff2; printf "%s" "@font-face{src:url(../fonts/j.woff2)}@font-face{src:url(../fonts/k.woff2)}" > css/site.css; head -c 29000 /dev/urandom > fonts/k.woff2'
mutate post-text-heavy post-no-images 'head -c 28000 /dev/urandom > fonts/j.woff2; head -c 29000 /dev/urandom > fonts/k.woff2; head -c 29000 /dev/urandom > brand/x.bin; printf "%s" "body{background:url(../brand/x.bin)}@font-face{src:url(../fonts/j.woff2)}@font-face{src:url(../fonts/k.woff2)}" > css/site.css'
mutate missing-file missing-asset 'rm brand/pic.webp'

# The pinned copy script is allowed, on the support page only.
ok_copy="$work/ok-copy"
cp -r "$good" "$ok_copy"
mkdir -p "$ok_copy/support"
printf 'x' >"$ok_copy/copy.js"
printf '%s' '<!doctype html><title>t</title><link rel=stylesheet href=/css/site.css><script src=/copy.js></script>' >"$ok_copy/support/index.html"
if python3 -I "$root/scripts/check-budget.py" "$ok_copy" >"$work/ok-copy.out" 2>&1; then
    pass "/copy.js on /support/ passes"
else
    fail "/copy.js on /support/ failed: $(cat "$work/ok-copy.out")"
fi

empty="$work/empty"
mkdir -p "$empty"
expect_fail "empty tree" no-pages "$empty"

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all budget checks passed"
