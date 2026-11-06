#!/usr/bin/env bash
# Test scripts/browser-gate.py against small fixture sites (no Hugo): a good page
# passes, and each rule fails on a page that breaks only it. Needs Chrome or
# Chromium (CHROME names it); a missing browser is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/bgate.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# make_site <dir>: one page with the skip link, header, nav, main and footer, a
# stylesheet, a declared-size image, and the real _headers.
make_site() {
    local d="$1"
    mkdir -p "$d"
    cp "$root/static/_headers" "$d/_headers"
    python3 -I "$root/scripts/fixture-site.py" "$d"
}

run_gate() { # run_gate <site> [extra args]; prints output, returns the exit code
    local site="$1"
    shift
    python3 -I "$root/scripts/browser-gate.py" "$site" --pages home --widths 1440 --no-zoom "$@" 2>&1
}

expect_fail() { # expect_fail <name> <rule> <site> [extra args]
    local name="$1" rule="$2" site="$3" out rc=0
    shift 3
    out="$(run_gate "$site" "$@")" || rc=$?
    if [[ $rc -eq 1 && "$out" == *"[$rule]"* ]]; then
        pass "$name -> $rule"
    else
        fail "$name: expected exit 1 with [$rule], got exit $rc: $out"
    fi
}

# mutate <name> <rule> <fixture-site.py mutation name> [extra gate args]
mutate() {
    local name="$1" rule="$2" mutation="$3" d="$work/m-$1"
    shift 3
    cp -r "$work/good" "$d"
    python3 -I "$root/scripts/fixture-site.py" "$d" "$mutation"
    expect_fail "$name" "$rule" "$d" "$@"
}

make_site "$work/good"
rc=0
out="$(run_gate "$work/good")" || rc=$?
if [[ $rc -eq 0 && "$out" == *"browser gate: ok (1 runs"* ]]; then pass "good fixture passes (and one run was measured)"; else fail "good fixture: exit $rc: $out"; fi

mutate overflow overflow overflow
mutate console console console
mutate missing-file network missing-file
mutate off-site network off-site
mutate axe axe no-alt
mutate small-target target small-target
mutate tab-order tab tab-order
mutate no-focus-ring tab no-focus-ring
mutate no-skip-link tab no-skip-link
mutate layout-shift cls layout-shift
mutate slow-lcp lcp slow-lcp
mutate toggle-missing toggle toggle-missing

# The pinned axe-core: a tampered copy must be refused.
cp "$root/tools/axe/axe.min.js" "$work/axe-bad.js"
echo "/* tampered */" >>"$work/axe-bad.js"
rc=0
out="$(run_gate "$work/good" --axe "$work/axe-bad.js")" || rc=$?
if [[ $rc -ne 0 && "$out" == *"[setup]"* ]]; then pass "a tampered axe-core is refused"; else fail "tampered axe-core: exit $rc: $out"; fi
if (cd "$root/tools/axe" && sha256sum -c axe.min.js.sha256 >/dev/null 2>&1); then pass "vendored axe-core matches its pinned hash"; else fail "vendored axe-core does not match axe.min.js.sha256"; fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all browser gate checks passed"
