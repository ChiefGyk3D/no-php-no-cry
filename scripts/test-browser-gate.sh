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
if [[ $rc -eq 0 && "$out" == *"browser gate: ok (2 runs"* ]]; then pass "good fixture passes (one width run plus the 1920x930 fit run)"; else fail "good fixture: exit $rc: $out"; fi

mutate overflow overflow overflow
mutate tile-overflow tile tile-overflow
mutate tile-overflow-vertical tile tile-overflow-vertical
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
# Standing rule (issue 123): a page taller than 1920x930 fails [fit] unless it is allow-listed.
mutate tall-page fit tall
d="$work/m-tall-page"
out="$(run_gate "$d" --fit-allow home || true)"
if [[ "$out" != *"[fit]"* && "$out" == *"browser gate: ok"* ]]; then pass "an allow-listed tall page is exempt"; else fail "allow-listed tall page: $out"; fi
allow_ok="$(
    python3 -I - "$root/scripts/browser-gate.py" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("bg", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
names = {n for n, _ in m.PAGES}
print(all(k in names and v.strip() for k, v in m.FIT_ALLOW.items()) and not {"home", "social", "support", "privacy", "404"} & set(m.FIT_ALLOW))
PY
)"
if [[ "$allow_ok" == "True" ]]; then pass "FIT_ALLOW names real templates with reasons and leaves Home, Social, Support, Privacy and 404 checked"; else fail "FIT_ALLOW is stale or exempts a page that must fit"; fi

# The popover Menu button (phones, 390 px): the good fixture passes the keyboard
# pass there, and a manual popover (Escape does not close it) fails it.
rc=0
out="$(run_gate "$work/good" --widths 390)" || rc=$?
if [[ $rc -eq 0 ]]; then pass "good fixture passes at 390 (popover menu exercised)"; else fail "good fixture at 390: exit $rc: $out"; fi
mutate menu-escape tab menu-escape --widths 390
d="$work/m-menu-escape"
out="$(run_gate "$d" --widths 390 || true)"
if [[ "$out" == *"Escape does not close the menu"* ]]; then pass "menu-escape fails on the Escape assertion"; else fail "menu-escape: wrong failure: $out"; fi

# The pinned axe-core: a tampered copy must be refused.
cp "$root/tools/axe/axe.min.js" "$work/axe-bad.js"
echo "/* tampered */" >>"$work/axe-bad.js"
rc=0
out="$(run_gate "$work/good" --axe "$work/axe-bad.js")" || rc=$?
if [[ $rc -ne 0 && "$out" == *"[setup]"* ]]; then pass "a tampered axe-core is refused"; else fail "tampered axe-core: exit $rc: $out"; fi
if (cd "$root/tools/axe" && sha256sum -c axe.min.js.sha256 >/dev/null 2>&1); then pass "vendored axe-core matches its pinned hash"; else fail "vendored axe-core does not match axe.min.js.sha256"; fi

# The origin check compares parsed scheme/host/port, not a string prefix: a
# request to port 123451 is not the site at port 12345.
rc=0
out="$(
    python3 -I - "$root/scripts/browser-gate.py" <<'PY' 2>&1
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("browser_gate", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
base = "http://127.0.0.1:12345"
same = [base, base + "/", base + "/a/b?x=1#f", base + "?q"]
other = [base + "1/x", base + "1", "http://127.0.0.1:1234/", "https://127.0.0.1:12345/",
         "http://127.0.0.1.evil.test:12345/", "http://127.0.0.1:12345@evil.test/", "ws://127.0.0.1:12345/"]
bad = [u for u in same if not mod.same_origin(u, base)] + [u for u in other if mod.same_origin(u, base)]
if bad:
    print("wrong origin verdict for:", bad)
    sys.exit(1)
PY
)" || rc=$?
if [[ $rc -eq 0 ]]; then pass "origin check compares scheme/host/port (port-prefix collision refused)"; else fail "origin check: $out"; fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all browser gate checks passed"
