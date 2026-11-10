#!/usr/bin/env bash
# Tests for scripts/check-live-headers-workflow.py: the real workflow passes,
# and each mutation of it (negative case per rule) is rejected.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-live-headers-workflow.py"
wf="$root/.github/workflows/live-headers.yml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

run() { python3 -I "$checker" "$1" >/dev/null 2>&1 && echo 0 || echo $?; }

[[ -s "$wf" ]] || { echo "FAIL: $wf missing or empty"; exit 1; }

# mutate <label> <sed-expression>: the mutated copy must fail with exit 1.
mutate() {
    local label="$1" expr="$2" rc
    sed -E "$expr" "$wf" > "$tmp/m.yml"
    if cmp -s "$wf" "$tmp/m.yml"; then
        echo "FAIL: $label (mutation changed nothing)"; failures=$((failures + 1)); return
    fi
    rc="$(run "$tmp/m.yml")"
    if [[ "$rc" == 1 ]]; then echo "ok: $label"; else echo "FAIL: $label (exit $rc)"; failures=$((failures + 1)); fi
}

rc="$(run "$wf")"
if [[ "$rc" == 0 ]]; then echo "ok: real workflow passes"; else echo "FAIL: real workflow (exit $rc)"; failures=$((failures + 1)); fi

mutate "no cron" "s/- cron:/- nocron:/"
mutate "no manual trigger" "s/^(\s+)workflow_dispatch:/\1workflow_dispatchx:/"
mutate "pull_request trigger added" "s/^(\s+)workflow_dispatch:/\1pull_request:\n\1workflow_dispatch:/"
mutate "write permission" "s/^(\s+)contents: read/\1contents: write/"
mutate "unpinned action" "0,/@[0-9a-f]{40}/s//@v4/"
mutate "pin without version comment" "0,/(@[0-9a-f]{40}) # v[0-9.]+/s//\1/"
mutate "dev check dropped" "s/--env staging/--env nothing/"
mutate "apex check dropped" "s/--env production/--env nothing/"
mutate "failure tolerated" "s/^(\s+)runs-on:/\1continue-on-error: true\n\1runs-on:/"
mutate "secret read" "s/^(\s+)runs-on:/\1env: { X: \${{ secrets.X }} }\n\1runs-on:/"

if [[ "$(run "$tmp/absent.yml")" == 2 ]]; then echo "ok: unreadable file exits 2"; else echo "FAIL: unreadable file"; failures=$((failures + 1)); fi

if [[ $failures -gt 0 ]]; then echo "$failures test(s) failed"; exit 1; fi
echo "all live-headers workflow guard tests passed"
