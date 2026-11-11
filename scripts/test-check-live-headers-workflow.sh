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

[[ -s "$wf" ]] || {
    echo "FAIL: $wf missing or empty"
    exit 1
}

# mutate <label> <sed-expression>: the mutated copy must fail with exit 1.
mutate() {
    local label="$1" expr="$2" expected="${3:-}" output rc
    sed -E "$expr" "$wf" >"$tmp/m.yml"
    if cmp -s "$wf" "$tmp/m.yml"; then
        echo "FAIL: $label (mutation changed nothing)"
        failures=$((failures + 1))
        return
    fi
    rc=0
    output="$(python3 -I "$checker" "$tmp/m.yml" 2>&1)" || rc=$?
    if [[ "$rc" == 1 && (-z "$expected" || "$output" == *"$expected"*) ]]; then
        echo "ok: $label"
    else
        echo "FAIL: $label (exit $rc, missing finding: ${expected:-any})"
        failures=$((failures + 1))
    fi
}

rc="$(run "$wf")"
if [[ "$rc" == 0 ]]; then
    echo "ok: real workflow passes"
else
    echo "FAIL: real workflow (exit $rc)"
    failures=$((failures + 1))
fi

mutate "no cron" "s/- cron:/- nocron:/" "no schedule with a cron entry"
mutate "no manual trigger" "/^(\s+)workflow_dispatch:/d" "no workflow_dispatch trigger"
mutate "pull_request trigger added" "s/^(\s+)workflow_dispatch:/\1pull_request:\n\1workflow_dispatch:/" "unexpected trigger pull_request"
mutate "pull_request_target trigger added" "s/^(\s+)workflow_dispatch:/\1pull_request_target:\n\1workflow_dispatch:/" "unexpected trigger pull_request_target"
mutate "push trigger added" "s/^(\s+)workflow_dispatch:/\1push:\n\1workflow_dispatch:/" "unexpected trigger push"
mutate "workflow_run trigger added" "s/^(\s+)workflow_dispatch:/\1workflow_run:\n\1workflow_dispatch:/" "unexpected trigger workflow_run"
mutate "write permission" "s/^(\s+)contents: read/\1contents: write/"
mutate "top-level write-all permission" "s/^permissions:.*/permissions: write-all/; /  contents: read/d"
mutate "top-level read-all permission" "s/^permissions:.*/permissions: read-all/; /  contents: read/d"
mutate "job permission override" "s/^(  verify:)/\1\n    permissions: { contents: read }/" "job verify overrides permissions"
mutate "job write-all permission" "s/^(  verify:)/\1\n    permissions: write-all/" "job verify overrides permissions"
mutate "job read-all permission" "s/^(  verify:)/\1\n    permissions: read-all/" "job verify overrides permissions"
mutate "quoted job write-all permission" "s/^(  verify:)/\1\n    'permissions': write-all/"
mutate "quoted flow job write-all permission" "s/^(  verify:)/  hidden: { 'permissions': write-all }\n\1/"
mutate "tagged flow job write-all permission" "s/^(  verify:)/  hidden: { !!str permissions: write-all }\n\1/"
mutate "anchored job write-all permission" "s#^(  verify:)#  hidden: &hidden { permissions: write-all, uses: example/repository/.github/workflows/check.yml@main }\n\1#"
mutate "tagged job write-all permission" "s#^(  verify:)#  hidden: !!map { permissions: write-all, uses: example/repository/.github/workflows/check.yml@main }\n\1#"
mutate "verify job disabled" "s/^(  verify:)/\1\n    if: \${{ false }}/"
mutate "top-level shell swallows failures" "s/^(concurrency:)/defaults:\n  run:\n    shell: echo {0}\n\n\1/"
mutate "job shell swallows failures" "s/^(  verify:)/\1\n    defaults: { run: { shell: echo {0} } }/"
mutate "unpinned action" "0,/@[0-9a-f]{40}/s//@v4/"
mutate "quoted unpinned action key" "0,/- uses:/s//- 'uses':/; 0,/@[0-9a-f]{40}/s//@v4/"
mutate "pin without version comment" "0,/(@[0-9a-f]{40}) # v[0-9.]+/s//\1/"
mutate "unpinned reusable workflow" "s#^(  verify:)#  untrusted:\n    uses: example/repository/.github/workflows/check.yml@main\n\n\1#"
mutate "unpinned action in flow sequence" "s#^(  verify:)#  untrusted:\n    runs-on: ubuntu-24.04\n    steps: [{ uses: actions/checkout@main }]\n\n\1#"
mutate "dev check dropped" "s/--env staging/--env nothing/"
mutate "apex check dropped" "s/--env production/--env nothing/"
mutate "dev check disabled" "s/if: matrix.environment == 'staging'/if: \${{ false }}/" "Dev host headers is not the exact required verifier step"
mutate "apex check disabled" "s/if: matrix.environment == 'production'/if: \${{ false }}/" "Apex headers is not the exact required verifier step"
mutate "staging matrix row disabled" "0,/environment: staging/s//environment: disabled/" "verify matrix is not the two expected static hosts"
mutate "production matrix row disabled" "0,/environment: production/s//environment: disabled/" "verify matrix is not the two expected static hosts"
mutate "matrix row excluded" "s/^(        include:)/        exclude:\n          - environment: staging\n\1/" "verify matrix is not the two expected static hosts"
mutate "verifier replaced by echo" "s#run: scripts/verify-live.sh#run: echo scripts/verify-live.sh#" "Dev host headers is not the exact required verifier step"
mutate "verifier failure swallowed by or true" "s/--env staging/--env staging || true/" "Dev host headers is not the exact required verifier step"
mutate "verifier failure swallowed by colon" "s/--env staging/--env staging || :/" "Dev host headers is not the exact required verifier step"
mutate "verifier failure swallowed by echo" "s/--env staging/--env staging || echo ignored/" "Dev host headers is not the exact required verifier step"
mutate "failure tolerated" "s/^(\s+)runs-on:/\1continue-on-error: true\n\1runs-on:/"
mutate "setup step has failure-tolerance key" "s/^(      - name: Install Hugo.*)/\1\n        continue-on-error: false/"
mutate "quoted sequence failure tolerance" "s/^(    steps:)/\1\n      - 'continue-on-error': true\n        run: exit 1/"
mutate "setup command failure swallowed" "s/(sha256sum -c -)/\1 || true/"
mutate "secret read" "s/^(\s+)runs-on:/\1env: { X: \${{ secrets.X }} }\n\1runs-on:/"
mutate "duplicate YAML key" "s/^(permissions:)/\1\npermissions:/"

if [[ "$(run "$tmp/absent.yml")" == 2 ]]; then
    echo "ok: unreadable file exits 2"
else
    echo "FAIL: unreadable file"
    failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures test(s) failed"
    exit 1
fi
echo "all live-headers workflow guard tests passed"
