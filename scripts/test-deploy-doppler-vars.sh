#!/usr/bin/env bash
# Test for the deploy workflow's secrets step: the Doppler project and config
# come from repository variables, never a hardcoded value; the fetch is limited
# to the two Cloudflare deploy names; an empty variable fails the job. The real
# workflow must pass; fixtures with a hardcoded project or config, a missing
# names list or a missing empty-variable guard must fail.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/deploy.yml"
failures=0

# check <file>: exit 0 when the doppler-secrets step is configured correctly.
check() {
    python3 -I - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"uses: [^\n]*doppler-secrets@[^\n]*\n\s+with:\n((?:\s+[^\n]+\n)+)", text)
if not m:
    sys.exit("no doppler-secrets step")
block = m.group(1)
def val(key):
    k = re.search(rf"^\s+{key}:\s*(.+?)\s*$", block, re.M)
    return k.group(1) if k else None
errs = []
if val("project") != "${{ vars.DOPPLER_PROJECT }}":
    errs.append("project is not vars.DOPPLER_PROJECT")
if val("config") != "${{ vars.DOPPLER_CONFIG }}":
    errs.append("config is not vars.DOPPLER_CONFIG")
if val("identity-id") != "${{ vars.DOPPLER_CLOUDFLARE_IDENTITY_ID }}":
    errs.append("identity-id is not vars.DOPPLER_CLOUDFLARE_IDENTITY_ID")
names = val("names")
if names is None or sorted(re.split(r"[,\s]+", names.strip("'\""))) != ["CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN"]:
    errs.append("names is not exactly the two Cloudflare deploy names")
if "-z \"${DOPPLER_PROJECT:-}\"" not in text or "-z \"${DOPPLER_CONFIG:-}\"" not in text:
    errs.append("no empty-variable guard for project and config")
if errs:
    sys.exit("; ".join(errs))
PY
}

expect() { # expect <pass|fail> <label> <file>
    local rc=0
    check "$3" >/dev/null 2>&1 || rc=$?
    if [[ "$1" == pass && $rc -eq 0 ]] || [[ "$1" == fail && $rc -ne 0 ]]; then
        echo "ok: $2"
    else
        echo "FAIL: $2 (wanted $1, rc=$rc)"
        failures=$((failures + 1))
    fi
}

work="$(mktemp -d "${TMPDIR:-/tmp}/deploy-doppler-vars.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mutate() { # mutate <name> <sed expression>
    sed -E "$2" "$wf" >"$work/$1.yml"
}

expect pass "the real workflow reads project and config from variables" "$wf"
mutate hard-project 's/^(\s+project:).*/\1 hardcoded/'
expect fail "a hardcoded project fails" "$work/hard-project.yml"
mutate hard-config 's/^(\s+config:).*/\1 hardcoded/'
expect fail "a hardcoded config fails" "$work/hard-config.yml"
mutate no-names '/^\s+names:/d'
expect fail "a missing names list fails" "$work/no-names.yml"
mutate wide-names 's/^(\s+names:).*/\1 CLOUDFLARE_API_TOKEN,CLOUDFLARE_ACCOUNT_ID,EXTRA/'
expect fail "a wider names list fails" "$work/wide-names.yml"
mutate no-guard 's/-z "\$\{DOPPLER_PROJECT:-\}"/-n "${DOPPLER_PROJECT:-}"/'
expect fail "a missing empty-variable guard fails" "$work/no-guard.yml"

# claims_ok <file>...: the names input is an export allow-list, not a fetch
# filter (the action reads the whole config). No workflow comment, doc or
# threat-model text may say the fetch is limited to the two names.
claims_ok() {
    ! grep -n -i -E 'limits the fetch|fetch(es)? only (those|the) two|fetch is limited|workflow fetches only|exports every secret' "$@"
}
if claims_ok "$wf" "$root/docs/deploy.md" "$root/docs/threat-model/no-php-no-cry.threat-model.json" >"$work/claims.out"; then
    echo "ok: no text claims the fetch is limited to the two names"
else
    echo "FAIL: text claims the fetch is limited:"; cat "$work/claims.out"
    failures=$((failures + 1))
fi
printf 'names limits the fetch to two\n' >"$work/bad-claim.txt"
if claims_ok "$work/bad-claim.txt" >/dev/null; then
    echo "FAIL: a fetch-limited claim is not detected"; failures=$((failures + 1))
else
    echo "ok: a fetch-limited claim is detected"
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
