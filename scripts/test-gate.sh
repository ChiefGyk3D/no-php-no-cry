#!/usr/bin/env bash
# Offline tests for scripts/gate.sh: plan output, fast-mode classification,
# failure propagation, --only, --keep, and the missing-tool message. The repo
# under test is a throwaway git repository whose scripts and tools are stubs
# that log their calls; nothing builds the site and nothing touches the network.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# check <label> <condition...>: the condition is a command; failure counts.
check() {
    local label="$1"
    shift
    if "$@"; then pass "$label"; else fail "$label"; fi
}
has() { grep -qF -- "$2" <<<"$1"; }
lacks() { ! grep -qF -- "$2" <<<"$1"; }

# --- the stub repository ---------------------------------------------------
stubs="$work/stubs"
repo="$work/repo"
mkdir -p "$stubs" "$repo/scripts" "$repo/content" "$repo/assets/css"

# A stub logs "<name> <args>" and fails when its name is in $STUB_FAIL.
stub_body='#!/usr/bin/env bash
name="$(basename "$0")"
echo "$name $*" >>"${STUB_LOG:-/dev/null}"
[[ " ${STUB_FAIL:-} " == *" $name "* ]] && exit 1
exit 0'

for t in hugo shellcheck shfmt google-chrome; do
    printf '%s\n' "$stub_body" >"$stubs/$t"
done
cat >"$stubs/python3" <<'PY'
#!/usr/bin/env bash
# python3 -I scripts/<x>.py ...: log and fail by the script name.
name="$(basename "$2")"
echo "$name ${*:3}" >>"${STUB_LOG:-/dev/null}"
[[ " ${STUB_FAIL:-} " == *" $name "* ]] && exit 1
exit 0
PY
chmod +x "$stubs"/*

cp "$root/scripts/gate.sh" "$repo/scripts/gate.sh"
# Every script gate.sh names gets a stub, so the list cannot drift from the test.
while read -r s; do
    [[ "$s" == scripts/gate.sh ]] && continue
    printf '%s\n' "$stub_body" >"$repo/$s"
    chmod +x "$repo/$s"
done < <(grep -oE 'scripts/[A-Za-z0-9._-]+\.(sh|py)' "$root/scripts/gate.sh" | sort -u)
echo "0.168.0" >"$repo/.hugo-version"
echo seed >"$repo/content/seed.md"
echo seed >"$repo/assets/css/site.css"

git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.invalid
git -C "$repo" config user.name t
git -C "$repo" add -A
git -C "$repo" commit -q -m seed
git -C "$repo" update-ref refs/remotes/origin/main HEAD

# gate [args...]: runs the stub repo's gate.sh; sets $out, $rc and $calls.
gate() {
    : >"$work/calls.log"
    rc=0
    out="$(cd "$repo" && PATH="$stubs:$PATH" GATE_TOOLS='' GATE_TMP="$work/gt" \
        STUB_LOG="$work/calls.log" STUB_FAIL="${STUB_FAIL:-}" \
        scripts/gate.sh "$@" 2>&1)" || rc=$?
    calls="$(cat "$work/calls.log")"
}
reset_repo() {
    git -C "$repo" reset -q --hard origin/main
    git -C "$repo" clean -qfd
}
mkdir -p "$work/gt"

# --- plan ------------------------------------------------------------------
gate --plan
check "plan exits 0" test "$rc" -eq 0
for n in check-hugo-version build-production check-output-staging test-pages gen-tokens \
    check-contrast check-brand-assets gen-support-qr check-wording check-license \
    check-budget test-check-budget browser-gate test-browser-gate shfmt shellcheck test-gate; do
    check "plan lists $n" has "$out" "$n"
done
check "plan runs nothing" test -z "$calls"

# --- full run, all green ---------------------------------------------------
gate
check "full run exits 0" test "$rc" -eq 0
check "full run reports 0 failed" has "$out" "0 failed"
check "full run ran hugo" has "$calls" "hugo --minify --gc"
check "full run ran shellcheck" has "$calls" "shellcheck -S warning"
check "full run ran shfmt" has "$calls" "shfmt -d -i 4 -ci"
check "full run ran the browser gate" has "$calls" "browser-gate.py"
check "temp dir removed without --keep" test -z "$(ls -A "$work/gt")"

# --- failure propagation: later steps still run ----------------------------
STUB_FAIL="test-pages.sh" gate
check "one failing step exits non-zero" test "$rc" -ne 0
check "summary names the failed step" has "$out" "failed: test-pages"
check "steps after a failure still ran" has "$calls" "shellcheck -S warning"
check "only the failing step is listed" lacks "$out" "failed: test-pages test-"

STUB_FAIL="hugo" gate
check "failing build exits non-zero" test "$rc" -ne 0
check "dependents of a failed build are not run" lacks "$calls" "browser-gate.py"
check "dependents of a failed build count as failed" has "$out" "browser-gate"

STUB_FAIL="shfmt" gate
check "failing lint step exits non-zero" test "$rc" -ne 0
check "failing step prints its exit code" has "$out" "shfmt"

# --- --only ----------------------------------------------------------------
gate --only browser-gate
check "--only exits 0 when the step passes" test "$rc" -eq 0
check "--only runs the step" has "$calls" "browser-gate.py"
check "--only runs the build it needs" has "$calls" "hugo --minify --gc"
check "--only skips unrelated steps" lacks "$calls" "test-pages.sh"
check "--only skips lint" lacks "$calls" "shellcheck"
STUB_FAIL="browser-gate.py" gate --only browser-gate
check "--only reports a failing step" test "$rc" -ne 0
check "failed browser gate hints at --only" has "$out" "--only browser-gate"
gate --only no-such-step
check "--only with an unknown step exits 2" test "$rc" -eq 2

# --- --keep ----------------------------------------------------------------
gate --keep --only check-wording
kept="$(grep -oE "$work/gt/[^ ]+" <<<"$out" | head -n 1 || true)"
check "--keep prints the kept directory" test -n "$kept"
check "--keep leaves it on disk" test -d "$kept"
rm -rf "$kept"

# --- fast mode -------------------------------------------------------------
reset_repo
gate --fast --plan
check "fast with no changes exits 0" test "$rc" -eq 0
check "fast with no changes runs nothing" has "$out" "nothing to run"

reset_repo
echo new >"$repo/content/new.md"
gate --fast --plan
check "content change plans the build" has "$out" "build-production"
check "content change plans test-pages" has "$out" "test-pages"
check "content change skips shellcheck" lacks "$out" "shellcheck"
check "content change skips the browser gate" lacks "$out" "browser-gate"
check "content change skips the budget" lacks "$out" "check-budget"

reset_repo
echo "# edit" >>"$repo/scripts/check-wording.sh"
git -C "$repo" commit -q -am "edit a script" # committed, not pushed: still counts
gate --fast --plan
check "script change plans its own test" has "$out" "test-check-wording"
check "script change plans shfmt" has "$out" "shfmt"
check "script change plans shellcheck" has "$out" "shellcheck"
check "script change skips the build" lacks "$out" "build-production"
check "script change skips the browser gate" lacks "$out" "browser-gate"

reset_repo
echo "/* edit */" >>"$repo/assets/css/site.css"
gate --fast --plan
check "css change plans the build" has "$out" "build-production"
check "css change plans contrast" has "$out" "check-contrast"
check "css change plans the budget" has "$out" "check-budget"
check "css change plans the browser gate" has "$out" "browser-gate"
check "css change skips shellcheck" lacks "$out" "shellcheck"

reset_repo
echo "# edit" >>"$repo/scripts/gate.sh"
gate --fast --plan
check "an edit to gate.sh plans test-gate" has "$out" "test-gate"
reset_repo

# --- missing tool ----------------------------------------------------------
bare="$work/bare"
mkdir -p "$bare"
for u in bash git mktemp rm mkdir date cat tr grep sort sed dirname basename head tail wc cut env uname id ls seq tee; do
    p="$(command -v "$u" 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p" ]]; then ln -sf "$p" "$bare/$u"; fi
done
mkdir -p "$work/stubs-no-shfmt"
for t in hugo shellcheck google-chrome python3; do ln -sf "$stubs/$t" "$work/stubs-no-shfmt/$t"; done
rc=0
out="$(cd "$repo" && PATH="$work/stubs-no-shfmt:$bare" GATE_TOOLS='' GATE_TMP="$work/gt" \
    scripts/gate.sh --only shfmt 2>&1)" || rc=$?
check "a missing tool exits 2" test "$rc" -eq 2
check "a missing tool is named" has "$out" "shfmt"

if [[ $failures -gt 0 ]]; then
    echo "$failures gate test(s) failed"
    exit 1
fi
echo "all gate tests passed"
