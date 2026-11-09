#!/usr/bin/env bash
# Tests for scripts/check-workflow-secrets.py: clean workflows pass; any
# secrets.NAME other than GITHUB_TOKEN, the bracket form, a dynamic index, the
# whole context and `secrets: inherit` fail; and the real .github tree passes.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-workflow-secrets.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

# expect <pass|fail> <label>; the workflow text arrives on stdin.
expect() {
    local want="$1" label="$2" rc=0
    rm -rf "$tmp/w"
    mkdir -p "$tmp/w"
    cat >"$tmp/w/t.yml"
    python3 -I "$checker" "$tmp/w" >/dev/null 2>&1 || rc=$?
    if [[ "$want" == pass && $rc -eq 0 ]] || [[ "$want" == fail && $rc -eq 1 ]]; then
        echo "ok: $label"
    else
        echo "FAIL: $label (wanted $want, exit $rc)"
        failures=$((failures + 1))
    fi
}

expect pass "no secrets at all" <<'YML'
jobs:
  a:
    steps:
      - run: echo hi
YML
expect pass "GITHUB_TOKEN is allowed" <<'YML'
env:
  T: ${{ secrets.GITHUB_TOKEN }}
YML
expect pass "whole-line comment is ignored" <<'YML'
# secrets.CLOUDFLARE_API_TOKEN was removed
YML
expect pass "vars context is not secrets" <<'YML'
env:
  I: ${{ vars.DOPPLER_CLOUDFLARE_IDENTITY_ID }}
YML
expect fail "fallback to a named secret" <<'YML'
env:
  T: ${{ env.T || secrets.CLOUDFLARE_API_TOKEN }}
YML
expect fail "plain named secret" <<'YML'
with:
  token: ${{ secrets.DOPPLER_CLOUDFLARE_TOKEN }}
YML
expect fail "bracket form" <<'YML'
env:
  T: ${{ secrets['X_TOKEN'] }}
YML
expect fail "bracket form, double quotes" <<'YML'
env:
  T: ${{ secrets["X_TOKEN"] }}
YML
expect fail "dynamic index" <<'YML'
env:
  T: ${{ secrets[matrix.name] }}
YML
expect fail "whole context" <<'YML'
env:
  T: ${{ toJSON(secrets) }}
YML
expect fail "secrets inherit" <<'YML'
jobs:
  a:
    uses: o/r/.github/workflows/x.yml@main
    secrets: inherit
YML
expect fail "allowed name plus a bad one" <<'YML'
env:
  A: ${{ secrets.GITHUB_TOKEN }}
  B: ${{ secrets.OTHER }}
YML
expect fail "bare whole context" <<'YML'
env:
  T: ${{ secrets }}
YML
expect fail "bare whole context in a function" <<'YML'
env:
  T: ${{ format('{0}', secrets) }}
YML
expect pass "word secrets in plain text is fine" <<'YML'
name: no secrets here
YML
expect fail "trailing comment does not hide it" <<'YML'
env:
  T: ${{ secrets.OTHER }} # ok
YML

# The real tree is clean; a missing directory is a usage error (exit 2).
if python3 -I "$checker" "$root/.github" >/dev/null 2>&1; then
    echo "ok: repository .github is clean"
else
    echo "FAIL: repository .github has a secret read"
    failures=$((failures + 1))
fi
rc=0
python3 -I "$checker" "$tmp/nope" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then
    echo "ok: missing directory is a usage error"
else
    echo "FAIL: missing directory exit $rc"
    failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures workflow secret check test(s) failed"
    exit 1
fi
echo "all workflow secret check tests passed"
