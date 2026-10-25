#!/usr/bin/env bash
# Test for scripts/wait-for-ci-green.sh. No network: GH_BIN points at a stub
# that replays one canned answer per call from a sequence file (the last line
# repeats). Each answer is zero or more "status<TAB>conclusion" lines, as the
# real script's jq filter would print for check runs named `CI green`.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/wait-for-ci-green.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/wait-ci.XXXXXX")"
trap 'rm -rf "$work"' EXIT

cat >"$work/gh-stub" <<'STUB'
#!/usr/bin/env bash
# Replays line N of $STUB_SEQ on call N (the last line repeats). In a line,
# "|" separates check runs and "~" stands for a tab; "ERR" makes the call fail.
n=0
[[ -f "$STUB_COUNT" ]] && n="$(cat "$STUB_COUNT")"
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
total="$(wc -l <"$STUB_SEQ")"
((n > total)) && n="$total"
line="$(sed -n "${n}p" "$STUB_SEQ")"
[[ "$line" == ERR ]] && exit 1
[[ -z "$line" ]] && exit 0
printf '%s\n' "$line" | tr '|~' '\n\t'
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

run_case success 0 "is green" 5 "completed~success"
run_case failure 1 "concluded failure" 5 "completed~failure"
run_case cancelled 1 "concluded cancelled" 5 "completed~cancelled"
run_case timeout 1 "timed out" 2 "queued~" "in_progress~"
run_case never-appears 1 "timed out" 2 ""
run_case appears-later 0 "is green" 10 "" "" "in_progress~" "completed~success"
run_case transient-error 0 "is green" 10 "ERR" "completed~success"
# An older failed run on the same SHA does not hide a later green one.
run_case rerun-green 0 "is green" 5 "completed~failure|completed~success"
# A failure while a rerun is still pending fails at once, not after the wait.
run_case fails-fast 1 "concluded failure" 30 "completed~failure|in_progress~"

# A concluded failure must return at once, not after the timeout.
printf '%s\n' "completed~failure" >"$work/seq"
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
