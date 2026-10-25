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
# Once the newest run has completed, its check suite (check_suite.id, fetched
# from the check-suites endpoint) must be bound to this gate: head_branch is the
# default branch, pull_requests is empty, and head_sha is this commit. If not,
# the result is "not green" at once (the rule name is printed, nothing else);
# the script never falls back to an older run.
#
# Environment:
#   WAIT_TIMEOUT_SECONDS   total wait (default 1500, 25 minutes)
#   POLL_INTERVAL_SECONDS  delay between polls (default 20)
#   DEFAULT_BRANCH        branch the suite must belong to (default main)
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
default_branch="${DEFAULT_BRANCH:-main}"

for v in "$timeout" "$interval"; do
    [[ "$v" =~ ^[0-9]+$ ]] || {
        echo "input: wait settings must be whole numbers of seconds (got '${v}')"
        exit 2
    }
done
[[ "$default_branch" =~ ^[A-Za-z0-9._/-]{1,100}$ ]] || {
    echo "input: DEFAULT_BRANCH has unexpected characters"
    exit 2
}
[[ "$sha" =~ ^[0-9a-f]{7,64}$ ]] || {
    echo "input: not a commit sha: ${sha}"
    exit 2
}

# One "started_at<TAB>id<TAB>status<TAB>conclusion<TAB>suite-id" line per check run with
# this exact name that belongs to the GitHub Actions app (app.slug, as returned
# by the check-runs endpoint). A missing started_at sorts as the newest.
query() {
    "$gh_bin" api --paginate "repos/${repo}/commits/${sha}/check-runs?per_page=100" \
        --jq ".check_runs[] | select(.name == \"${name}\" and .app.slug == \"github-actions\") | [(.started_at // \"9999-12-31T23:59:59Z\"), (.id | tostring), .status, (.conclusion // \"\"), (.check_suite.id | tostring)] | @tsv"
}

# "head_branch<TAB>head_sha<TAB>pull-request-count" for one check suite.
suite() {
    "$gh_bin" api "repos/${repo}/check-suites/${1}" \
        --jq '[(.head_branch // ""), (.head_sha // ""), (.pull_requests | length | tostring)] | @tsv'
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

    status="" conclusion="" suite_id=""
    if [[ -n "$newest" ]]; then
        IFS=$'\t' read -r _ _ status conclusion suite_id <<<"$newest"
    fi

    if [[ "$status" == completed ]]; then
        # Bind the newest run to the default branch's own suite for this commit.
        info=""
        if [[ "$suite_id" =~ ^[0-9]+$ ]] && info="$(suite "$suite_id" 2>&1)"; then
            IFS=$'\t' read -r s_branch s_sha s_prs <<<"$info"
            rule=""
            if [[ "$s_prs" != 0 ]]; then
                rule="pull-request"
            elif [[ "$s_branch" != "$default_branch" ]]; then
                rule="branch"
            elif [[ -z "$s_sha" || "$s_sha" != "$sha"* ]]; then
                rule="sha"
            fi
            if [[ -n "$rule" ]]; then
                echo "gate: the newest '${name}' run failed the suite binding (${rule}); not deploying"
                exit 1
            fi
        else
            echo "poll: the check-suite call failed, will retry"
            if ((SECONDS - start >= timeout)); then
                echo "gate: timed out after ${timeout} s waiting for '${name}' on ${sha}"
                exit 1
            fi
            sleep "$interval"
            continue
        fi
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
