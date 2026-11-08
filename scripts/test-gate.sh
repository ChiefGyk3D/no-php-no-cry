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

for t in hugo shellcheck shfmt google-chrome node; do
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
# Shared libraries and the scripts that source them (verify-live is not a gate step
# itself; only its test is).
for lib in artifact-rules robots-wildcard verify-live; do
    printf '%s\n' "$stub_body" >"$repo/scripts/$lib.sh"
done
echo 'source "$(dirname "$0")/artifact-rules.sh"' >>"$repo/scripts/check-output.sh"
echo 'source "$(dirname "$0")/artifact-rules.sh"' >>"$repo/scripts/check-site-artifact.sh"
echo '. "$(dirname "$0")/robots-wildcard.sh"' >>"$repo/scripts/verify-live.sh"
echo '. "$(dirname "$0")/robots-wildcard.sh"' >>"$repo/scripts/check-output.sh"
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
check "plan lists the offline drift test" grep -qx 'test-check-reach-around-drift: .*' <<<"$out"
check "plan leaves out the live drift check" bash -c '! grep -q "^check-reach-around-drift:" <<<"$1"' _ "$out"
check "plan says the live drift check is skipped" has "$out" "skipped check-reach-around-drift"
gate --plan --with-drift
check "--with-drift plans the live drift check" grep -q '^check-reach-around-drift: ' <<<"$out"
check "--with-drift prints no skip message" lacks "$out" "skipped check-reach-around-drift"
gate --plan --only check-reach-around-drift
check "--only plans the live drift check" grep -q '^check-reach-around-drift: ' <<<"$out"
check "--only plans nothing else" lacks "$out" "test-pages"

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

# --- the drift check: offline always, live only on request ------------------
gate
check "full run ran the offline drift test" has "$calls" "test-check-reach-around-drift.sh"
check "full run did not run the live drift check" bash -c '! grep -q "^check-reach-around-drift.sh" <<<"$1"' _ "$calls"
gate --with-drift
check "--with-drift runs the live check" grep -q '^check-reach-around-drift.sh' <<<"$calls"
gate --only check-reach-around-drift
check "--only runs the live check" grep -q '^check-reach-around-drift.sh' <<<"$calls"
check "--only runs it alone" lacks "$calls" "test-check"
STUB_FAIL="check-reach-around-drift.sh" gate --with-drift
check "a failing live check fails the gate" test "$rc" -ne 0

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
echo "# edit" >>"$repo/scripts/artifact-rules.sh"
gate --fast --plan
check "a changed library plans its consumer check-output" has "$out" "check-output-production"
check "a changed library plans its consumer check-site-artifact" has "$out" "check-site-artifact-staging"
check "a changed library plans the consumer's test" has "$out" "test-check-output"
check "a changed library plans the other consumer's test" has "$out" "test-check-site-artifact"
check "a changed library skips the browser gate" lacks "$out" "browser-gate"

reset_repo
echo "# edit" >>"$repo/scripts/robots-wildcard.sh"
gate --fast --plan
check "robots library plans its direct test" has "$out" "test-robots-wildcard"
check "robots library plans check-output (sourced by it)" has "$out" "check-output-production"
check "robots library plans test-verify-live (consumer verify-live)" has "$out" "test-verify-live"

reset_repo
echo "# edit" >>"$repo/scripts/test-pages.sh"
gate --fast --plan
check "a leaf script does not drag in the library consumers" lacks "$out" "check-output-production"

reset_repo
mkdir -p "$repo/tools/wxr2hugo"
echo "pillow==1" >"$repo/tools/wxr2hugo/requirements-webp.txt"
gate --fast --plan
check "webp requirements plan test-wxr2hugo-webp" has "$out" "test-wxr2hugo-webp"
check "webp requirements skip the browser gate" lacks "$out" "browser-gate"

reset_repo
mkdir -p "$repo/data"
echo "x: 1" >"$repo/data/support.yaml"
gate --fast --plan
check "support.yaml plans the QR check" has "$out" "gen-support-qr"
reset_repo
echo new >"$repo/content/new.md"
gate --fast --plan
check "other content does not plan the QR check" lacks "$out" "gen-support-qr"

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

for f in brand/tokens.json scripts/gen-tokens.py docs/token-drift.md scripts/check-reach-around-drift.sh; do
    reset_repo
    mkdir -p "$repo/$(dirname "$f")"
    echo "x" >>"$repo/$f"
    gate --fast --plan
    check "fast: $f plans the offline drift test" grep -q '^test-check-reach-around-drift: ' <<<"$out"
    check "fast: $f leaves out the live check" bash -c '! grep -q "^check-reach-around-drift:" <<<"$1"' _ "$out"
    gate --fast --plan --with-drift
    check "fast: $f with the flag plans the live check" grep -q '^check-reach-around-drift: ' <<<"$out"
done
reset_repo
echo new >"$repo/content/new.md"
gate --fast --plan --with-drift
check "fast: unrelated change with the flag skips the live check" bash -c '! grep -q "^check-reach-around-drift:" <<<"$1"' _ "$out"
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

mkdir -p "$work/stubs-no-node"
for t in hugo shellcheck shfmt google-chrome python3; do ln -sf "$stubs/$t" "$work/stubs-no-node/$t"; done
rc=0
out="$(cd "$repo" && PATH="$work/stubs-no-node:$bare" GATE_TOOLS='' GATE_TMP="$work/gt" \
    scripts/gate.sh --only test-analytics 2>&1)" || rc=$?
check "a missing node exits 2" test "$rc" -eq 2
check "the missing node names the step" has "$out" "node for test-analytics"

if [[ $failures -gt 0 ]]; then
    echo "$failures gate test(s) failed"
    exit 1
fi
echo "all gate tests passed"
