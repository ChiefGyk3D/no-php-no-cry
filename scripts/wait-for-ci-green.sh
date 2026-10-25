#!/usr/bin/env bash
# Usage: scripts/wait-for-ci-green.sh <owner/repo> <commit-sha>
#
# Waits for the check run named `CI green` (the gate job of ci.yml) on a commit
# to conclude, so a deploy never publishes a commit CI has not passed.
# Only check runs of the GitHub Actions app count (a success posted by another
# app under the same name is ignored). Of those, the NEWEST decides, by
# started_at and then id; a run with no start time yet counts as newest.
#   newest succeeded         exit 0
#   newest ended any other   exit 1 at once (failure, cancelled, skipped, ...)
#   newest queued/running    keep waiting
#   none, or never finishes  exit 1 after the bounded wait
# So a stale success never beats a newer failure, and a rerun that is still
# running is waited for rather than judged by the run before it.
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

# One "started_at<TAB>id<TAB>status<TAB>conclusion" line per check run with
# this exact name that belongs to the GitHub Actions app (app.slug, as returned
# by the check-runs endpoint). A missing started_at sorts as the newest.
query() {
    "$gh_bin" api --paginate "repos/${repo}/commits/${sha}/check-runs?per_page=100" \
        --jq ".check_runs[] | select(.name == \"${name}\" and .app.slug == \"github-actions\") | [(.started_at // \"9999-12-31T23:59:59Z\"), (.id | tostring), .status, (.conclusion // \"\")] | @tsv"
}

start=$SECONDS
while :; do
    runs=""
    if ! runs="$(query 2>&1)"; then
        echo "poll: the check-runs call failed, will retry"
        runs=""
    fi

    # Newest run last: oldest start first, then lowest id first.
    newest=""
    if [[ -n "$runs" ]]; then
        newest="$(printf '%s\n' "$runs" | sort -t$'\t' -k1,1 -k2,2n | tail -n 1)"
    fi

    status="" conclusion=""
    if [[ -n "$newest" ]]; then
        IFS=$'\t' read -r _ _ status conclusion <<<"$newest"
    fi

    if [[ "$status" == completed ]]; then
        if [[ "$conclusion" == success ]]; then
            echo "ok: '${name}' is green on ${sha}"
            exit 0
        fi
        echo "gate: '${name}' concluded ${conclusion:-unknown} on ${sha}; not deploying"
        exit 1
    fi

    if ((SECONDS - start >= timeout)); then
        echo "gate: timed out after ${timeout} s waiting for '${name}' on ${sha}"
        exit 1
    fi
    if [[ -n "$status" ]]; then
        echo "wait: the newest '${name}' run is still ${status} on ${sha}"
    else
        echo "wait: no '${name}' check run on ${sha} yet"
    fi
    sleep "$interval"
done
