#!/usr/bin/env bash
# Test for scripts/check-deploy-sparse.py: every file a sparse-checkout job of the
# deploy workflow needs (scripts it runs, scripts they source, the headers file,
# the theme hash file) must be in that job's sparse list. The real workflow must
# pass; fixtures that drop an entry, or add a script that sources an unlisted
# one, must fail naming the file.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="$root/scripts/check-deploy-sparse.py"
wf="$root/.github/workflows/deploy.yml"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/deploy-sparse.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
run() { python3 -I "$tool" "$1" "${2:-$root}" 2>&1; }

rc=0
out="$(run "$wf")" || rc=$?
if [[ $rc -eq 0 ]]; then
    echo "ok: the deploy workflow's sparse lists cover what its jobs need"
else
    echo "FAIL: the deploy workflow is missing files in a sparse list (rc=$rc)"
    echo "$out"
    failures=$((failures + 1))
fi

# expect_missing <name> <workflow> <root> <job: path>
expect_missing() {
    local rc=0 out
    out="$(run "$2" "$3")" || rc=$?
    if [[ $rc -eq 1 && "$out" == *"$4"* ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1 (rc=$rc, wanted rc=1 naming '$4')"
        echo "$out"
        failures=$((failures + 1))
    fi
}

# The sparse list of the deploy job, minus one entry at a time.
for entry in /scripts/artifact-rules.sh /theme.js.sha256 /static/_headers /scripts/check-site-artifact.sh /scripts/ensure-pages-project.sh; do
    grep -vxF "            $entry" "$wf" >"$work/wf.yml"
    if cmp -s "$work/wf.yml" "$wf"; then
        echo "FAIL: the entry $entry is not in the workflow's sparse list"
        failures=$((failures + 1))
        continue
    fi
    expect_missing "deploy without $entry" "$work/wf.yml" "$root" "deploy: ${entry#/}"
done

# A script that sources a file nobody listed.
fake="$work/root"
mkdir -p "$fake/scripts" "$fake/static"
printf '#!/usr/bin/env bash\nsource "$(dirname "$0")/extra-lib.sh"\n' >"$fake/scripts/check-site-artifact.sh"
printf 'x=1\n' >"$fake/scripts/extra-lib.sh"
printf 'x\n' >"$fake/scripts/ensure-pages-project.sh"
expect_missing "a sourced script that is not listed" "$wf" "$fake" "deploy: scripts/extra-lib.sh"

# A step added to the deploy job that runs another script.
sed 's#^        run: scripts/ensure-pages-project.sh$#        run: scripts/ensure-pages-project.sh \&\& scripts/wait-for-ci-green.sh#' "$wf" >"$work/wf2.yml"
expect_missing "a newly run script that is not listed" "$work/wf2.yml" "$root" "deploy: scripts/wait-for-ci-green.sh"

# A workflow with no sparse list at all is a failure of the check, not a pass.
printf 'jobs:\n  a:\n    steps:\n      - run: echo\n' >"$work/none.yml"
rc=0
run "$work/none.yml" >/dev/null || rc=$?
if [[ $rc -eq 1 ]]; then
    echo "ok: a workflow with no sparse list is reported"
else
    echo "FAIL: no sparse list gave rc=$rc, wanted 1"
    failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all deploy-sparse tests passed"
