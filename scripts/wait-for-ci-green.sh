#!/usr/bin/env bash
# Usage: scripts/wait-for-ci-green.sh <owner/repo> <commit-sha>
#
# Waits for the check run named `CI green` (the gate job of ci.yml) on a commit
# to conclude, so a deploy never publishes a commit CI has not passed.
# Only check runs of the GitHub Actions app count (a success posted by another
# app under the same name is ignored). Each such run's check suite
# (check_suite.id, fetched once per distinct id from the check-suites endpoint)
# must be bound to this gate: head_branch is the default branch, pull_requests
# is empty, and head_sha starts with this commit. A run whose suite is not
# bound is untrusted and IGNORED: it is never decisive in either direction, so
# a newer run from a pull request or another ref can neither deny nor rescue
# the gate. Suites are looked up for runs in any state, because an untrusted
# run that is still running must not make the gate wait. Of the trusted runs,
# the NEWEST decides, by started_at and then id (no start time yet counts as
# newest):
#   newest succeeded         exit 0
#   newest ended any other   exit 1 at once (failure, cancelled, skipped, ...)
#   newest queued/running    keep waiting
#   none, or never finishes  exit 1 after the bounded wait
# So a stale success never beats a newer failure, and a rerun that is still
# running is waited for rather than judged by the run before it. The timeout
# message names only the rule, never run content.
#
# Environment:
#   WAIT_TIMEOUT_SECONDS   total wait (default 1500, 25 minutes)
#   POLL_INTERVAL_SECONDS  delay between polls (default 20)
#   DEFAULT_BRANCH         branch the suite must belong to (default main)
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

# One "started_at<TAB>id<TAB>status<TAB>suite-id<TAB>conclusion" line per check
# run with this exact name that belongs to the GitHub Actions app (app.slug, as returned
# by the check-runs endpoint). A missing started_at sorts as the newest.
query() {
    "$gh_bin" api --paginate "repos/${repo}/commits/${sha}/check-runs?per_page=100" \
        --jq ".check_runs[] | select(.name == \"${name}\" and .app.slug == \"github-actions\") | [(.started_at // \"9999-12-31T23:59:59Z\"), (.id | tostring), .status, (.check_suite.id | tostring), (.conclusion // \"\")] | @tsv"
}

# "head_branch<TAB>head_sha<TAB>pull-request-count" for one check suite.
suite() {
    "$gh_bin" api "repos/${repo}/check-suites/${1}" \
        --jq '[(.head_branch // ""), (.head_sha // ""), (.pull_requests | length | tostring)] | @tsv'
}

# trust[<suite id>] = "trusted" or "untrusted"; one lookup per distinct suite.
declare -A trust=()

# resolve <suite-id>: fills trust[] or returns 1 when the lookup failed.
resolve() {
    local id="$1" info s_branch s_sha s_prs
    [[ -z "${trust[$id]:-}" ]] || return 0
    [[ "$id" =~ ^[0-9]+$ ]] || {
        trust[$id]=untrusted
        return 0
    }
    info="$(suite "$id" 2>&1)" || return 1
    IFS=$'\t' read -r s_branch s_sha s_prs <<<"$info"
    if [[ "$s_prs" != 0 ]]; then
        trust[$id]=untrusted
    elif [[ "$s_branch" != "$default_branch" ]]; then
        trust[$id]=untrusted
    elif [[ -z "$s_sha" || "$s_sha" != "$sha"* ]]; then
        trust[$id]=untrusted
    else
        trust[$id]=trusted
    fi
}

start=$SECONDS
while :; do
    runs=""
    if ! runs="$(query 2>&1)"; then
        echo "poll: the check-runs call failed, will retry"
        runs=""
    fi

    # Keep the runs whose suite is trusted. If any suite cannot be resolved
    # this poll, decide nothing yet (an unresolved run could be the newest).
    trusted="" unresolved=0
    while IFS=$'\t' read -r started id status suite_id conclusion; do
        [[ -n "$id" ]] || continue
        if ! resolve "$suite_id"; then
            unresolved=1
            continue
        fi
        if [[ "${trust[$suite_id]}" == trusted ]]; then
            trusted+="${started}"$'\t'"${id}"$'\t'"${status}"$'\t'"${conclusion}"$'\n'
        fi
    done <<<"$runs"
    if [[ $unresolved -eq 1 ]]; then
        echo "poll: a check-suite call failed, will retry"
        trusted=""
    fi

    # Newest trusted run last: oldest start first, then lowest id first.
    status="" conclusion=""
    if [[ -n "$trusted" ]]; then
        newest="$(printf '%s' "$trusted" | sort -t$'\t' -k1,1 -k2,2n | tail -n 1)"
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
        if [[ -n "$status" ]]; then
            echo "gate: timed out after ${timeout} s waiting for '${name}' on ${sha}"
        else
            echo "gate: timed out after ${timeout} s with no trusted '${name}' run on ${sha}"
        fi
        exit 1
    fi
    if [[ -n "$status" ]]; then
        echo "wait: the newest trusted '${name}' run is still ${status} on ${sha}"
    else
        echo "wait: no trusted '${name}' run on ${sha} yet"
    fi
    sleep "$interval"
done
