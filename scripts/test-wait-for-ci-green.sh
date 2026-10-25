#!/usr/bin/env bash
# Test for scripts/wait-for-ci-green.sh. No network: GH_BIN points at a stub
# that replays one canned check-runs answer per call from a sequence file (the
# last line repeats).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/wait-for-ci-green.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/wait-ci.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# The stub answers like `gh api --paginate <check-runs url> [--jq FILTER]`: it
# builds the check-runs JSON from a spec line and, when --jq is given, applies
# that filter with jq -r, so the real script's filter is what gets tested.
# Field names (name, app.slug, started_at, id, status, conclusion) are those of
# the GitHub check-runs endpoint.
cat >"$work/gh-stub" <<'STUB'
#!/usr/bin/env bash
# Replays line N of $STUB_SEQ on call N (the last line repeats). A line is
# check runs separated by "|", each "name~app-slug~id~started_at~status~conclusion"
# ("G" stands for the name `CI green`). "ERR" makes the call fail; an empty
# line means no check runs.
n=0
[[ -f "$STUB_COUNT" ]] && n="$(cat "$STUB_COUNT")"
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
total="$(wc -l <"$STUB_SEQ")"
((n > total)) && n="$total"
line="$(sed -n "${n}p" "$STUB_SEQ")"
[[ "$line" == ERR ]] && exit 1
filter=""
while [[ $# -gt 0 ]]; do
    [[ "$1" == --jq ]] && filter="$2"
    shift
done
json="$(printf '%s\n' "$line" | tr '|' '\n' | jq -R -s '
  {check_runs: [split("\n")[] | select(length > 0) | split("~") | {
    name: (if .[0] == "G" then "CI green" else .[0] end),
    app: {slug: .[1]},
    id: (.[2] | tonumber),
    started_at: (if .[3] == "" then null else .[3] end),
    status: .[4],
    conclusion: (if .[5] == "" then null else .[5] end)}]}')"
if [[ -n "$filter" ]]; then
    printf '%s\n' "$json" | jq -r "$filter"
else
    printf '%s\n' "$json"
fi
STUB
chmod +x "$work/gh-stub"

failures=0

# run_case <name> <want-rc> <want-text> <timeout> <seq-line>...
run_case() {
    local name="$1" want_rc="$2" want_text="$3" timeout="$4" out rc=0
    shift 4
    printf '%s\n' "$@" >"$work/seq"
    rm -f "$work/count"
    out="$(GH_BIN="$work/gh-stub" STUB_SEQ="$work/seq" STUB_COUNT="$work/count" \
        WAIT_TIMEOUT_SECONDS="$timeout" POLL_INTERVAL_SECONDS=1 \
        "$script" owner/repo 0123abc 2>&1)" || rc=$?
    if [[ $rc -eq $want_rc && "$out" == *"$want_text"* ]]; then
        echo "ok: $name"
    else
        echo "FAIL: $name (rc=$rc, wanted rc=$want_rc and text '$want_text')"
        echo "$out"
        failures=$((failures + 1))
    fi
}

# Shorthand: a run by the GitHub Actions app, named `CI green`.
ga="G~github-actions"
t1="2026-10-25T10:00:00Z"
t2="2026-10-25T10:05:00Z"

run_case success 0 "is green" 5 "$ga~1~$t1~completed~success"
run_case failure 1 "concluded failure" 5 "$ga~1~$t1~completed~failure"
run_case cancelled 1 "concluded cancelled" 5 "$ga~1~$t1~completed~cancelled"
run_case timeout 1 "timed out" 2 "$ga~1~$t1~queued~" "$ga~1~$t1~in_progress~"
run_case never-appears 1 "timed out" 2 ""
run_case appears-later 0 "is green" 10 "" "" "$ga~1~$t1~in_progress~" "$ga~1~$t1~completed~success"
run_case transient-error 0 "is green" 10 "ERR" "$ga~1~$t1~completed~success"
# The newest run decides, not any historical success.
run_case older-success-newer-failure 1 "concluded failure" 5 \
    "$ga~1~$t1~completed~success|$ga~2~$t2~completed~failure"
run_case older-failure-newer-success 0 "is green" 5 \
    "$ga~1~$t1~completed~failure|$ga~2~$t2~completed~success"
# Order in the response does not matter.
run_case newest-listed-first 1 "concluded failure" 5 \
    "$ga~2~$t2~completed~failure|$ga~1~$t1~completed~success"
# Same start time: the higher id is newer.
run_case tie-broken-by-id 1 "concluded failure" 5 \
    "$ga~7~$t1~completed~success|$ga~9~$t1~completed~failure"
# A newest run still running keeps waiting, even over an older success.
run_case newest-in-progress-waits 1 "timed out" 2 \
    "$ga~1~$t1~completed~success|$ga~2~$t2~in_progress~"
run_case newest-queued-waits 1 "timed out" 2 \
    "$ga~1~$t1~completed~failure|$ga~2~$t2~queued~"
run_case newest-in-progress-then-green 0 "is green" 10 \
    "$ga~1~$t1~completed~failure|$ga~2~$t2~in_progress~" \
    "$ga~1~$t1~completed~failure|$ga~2~$t2~in_progress~" \
    "$ga~1~$t1~completed~failure|$ga~2~$t2~completed~success"
# A queued run with no start time yet counts as the newest.
run_case unstarted-is-newest 1 "timed out" 2 \
    "$ga~1~$t1~completed~success|$ga~2~~queued~"
# Only the GitHub Actions app counts: a success from another app does not.
run_case other-app-only 1 "timed out" 2 "$ga~1~$t1~queued~|X~some-other-app~3~$t2~completed~success"
run_case other-app-success-alone 1 "timed out" 2 "G~some-other-app~3~$t1~completed~success"
# A newer other-app run neither hides nor replaces the Actions result.
run_case other-app-newer-success-ignored 1 "concluded failure" 5 \
    "$ga~1~$t1~completed~failure|G~some-other-app~3~$t2~completed~success"
# A differently named check run is ignored.
run_case other-name-ignored 1 "timed out" 2 "Other~github-actions~4~$t1~completed~success"

# A concluded failure must return at once, not after the timeout.
printf '%s\n' "$ga~1~$t1~completed~failure" >"$work/seq"
rm -f "$work/count"
start=$SECONDS
GH_BIN="$work/gh-stub" STUB_SEQ="$work/seq" STUB_COUNT="$work/count" \
    WAIT_TIMEOUT_SECONDS=30 POLL_INTERVAL_SECONDS=5 "$script" owner/repo 0123abc >/dev/null 2>&1 || true
if ((SECONDS - start < 4)); then
    echo "ok: failure is immediate"
else
    echo "FAIL: failure waited $((SECONDS - start)) s"
    failures=$((failures + 1))
fi

# Bad input is refused.
rc=0
"$script" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then
    echo "ok: usage refused"
else
    echo "FAIL: no arguments gave rc=$rc, wanted 2"
    failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all wait-for-ci-green tests passed"
