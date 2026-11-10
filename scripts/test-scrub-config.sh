#!/usr/bin/env bash
# The scrub term list lives in the owner-only secrets config stg_scrub. Any
# tracked file that names a secrets config for SCRUB_TERMS must name stg_scrub,
# and the docs must say the CI deploy identity cannot read it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
fail=0
bad() {
    echo "FAIL: $*" >&2
    fail=1
}

# 1. Every command line that touches SCRUB_TERMS in the secret manager uses
#    --config stg_scrub.
while IFS=: read -r f n line; do
    if [[ "$line" == *"--config"* && "$line" != *"--config stg_scrub"* ]]; then
        bad "$f:$n names a config other than stg_scrub for SCRUB_TERMS"
    fi
done < <(git grep -nI 'SCRUB_TERMS' -- . ':!scripts/test-scrub-config.sh' | grep -E -- '--config' || true)

# 2. The prose names no dev, prd or stg config for the term list.
if grep -nE 'config `(dev|prd|stg)`' docs/scrub-terms.md >&2; then
    bad "docs/scrub-terms.md names a config other than stg_scrub"
fi
grep -q 'config `stg_scrub`' docs/scrub-terms.md || bad "docs/scrub-terms.md does not name config stg_scrub"
grep -q 'owner-only environment that the CI deploy identity cannot read' docs/scrub-terms.md ||
    bad "docs/scrub-terms.md lacks the owner-only sentence"

[[ $fail -eq 0 ]] && echo "ok: scrub terms config is stg_scrub everywhere"
exit $fail
