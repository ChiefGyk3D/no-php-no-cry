#!/usr/bin/env bash
# Usage: scripts/wait-for-ci-green.sh <owner/repo> <commit-sha>
#
# Waits for the check run named `CI green` (the gate job of ci.yml) on a commit
# to conclude, so a deploy never publishes a commit CI has not passed.
#   success         exit 0
#   any other       exit 1 at once (failure, cancelled, skipped, ...)
#   never finishes  exit 1 after the bounded wait
# A success wins over an older failed run of the same name on the same commit
# (a rerun); a failure with no success fails at once even if a rerun is pending.
#
# Environment:
#   WAIT_TIMEOUT_SECONDS   total wait (default 1500, 25 minutes)
#   POLL_INTERVAL_SECONDS  delay between polls (default 20)
#   CI_CHECK_NAME          check run name (default "CI green")
#   GH_BIN                 the gh command (default gh); tests point it at a stub
#   GH_TOKEN               read by gh; needs checks: read
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: wait-for-ci-green.sh <owner/repo> <commit-sha>"
    exit 2
fi
repo="$1"
sha="$2"
timeout="${WAIT_TIMEOUT_SECONDS:-1500}"
interval="${POLL_INTERVAL_SECONDS:-20}"
name="${CI_CHECK_NAME:-CI green}"
gh_bin="${GH_BIN:-gh}"

for v in "$timeout" "$interval"; do
    [[ "$v" =~ ^[0-9]+$ ]] || {
        echo "input: wait settings must be whole numbers of seconds (got '${v}')"
        exit 2
    }
done
[[ "$sha" =~ ^[0-9a-f]{7,64}$ ]] || {
    echo "input: not a commit sha: ${sha}"
    exit 2
}

# One "status<TAB>conclusion" line per check run with this exact name.
query() {
    "$gh_bin" api --paginate "repos/${repo}/commits/${sha}/check-runs?per_page=100" \
        --jq ".check_runs[] | select(.name == \"${name}\") | [.status, (.conclusion // \"\")] | @tsv"
}

start=$SECONDS
while :; do
    runs=""
    if ! runs="$(query 2>&1)"; then
        echo "poll: the check-runs call failed, will retry"
        runs=""
    fi

    success=0 failed="" pending=0
    while IFS=$'\t' read -r status conclusion; do
        [[ -n "$status" ]] || continue
        if [[ "$status" != completed ]]; then
            pending=1
        elif [[ "$conclusion" == success ]]; then
            success=1
        else
            failed="${conclusion:-unknown}"
        fi
    done <<<"$runs"

    if [[ $success -eq 1 ]]; then
        echo "ok: '${name}' is green on ${sha}"
        exit 0
    fi
    if [[ -n "$failed" ]]; then
        echo "gate: '${name}' concluded ${failed} on ${sha}; not deploying"
        exit 1
    fi

    if ((SECONDS - start >= timeout)); then
        echo "gate: timed out after ${timeout} s waiting for '${name}' on ${sha}"
        exit 1
    fi
    if [[ $pending -eq 1 ]]; then
        echo "wait: '${name}' is still running on ${sha}"
    else
        echo "wait: no '${name}' check run on ${sha} yet"
    fi
    sleep "$interval"
done
