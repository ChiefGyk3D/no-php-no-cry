#!/usr/bin/env bash
# Mutation tests for the scheduled ASN refresh workflow guard.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-refresh-asns-workflow.py"
workflow="$root/.github/workflows/refresh-asns.yml"
fetcher="$root/scripts/fetch-asn-sources.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

check() { python3 -I "$checker" "$1" "${2:-$fetcher}" >/dev/null 2>&1; }

if check "$workflow"; then
    echo "ok: real workflow passes"
else
    echo "FAIL: real workflow"
    failures=$((failures + 1))
fi

mutate() {
    local label="$1" expression="$2"
    sed -E "$expression" "$workflow" >"$tmp/mutated.yml"
    if cmp -s "$workflow" "$tmp/mutated.yml"; then
        echo "FAIL: $label mutation changed nothing"
        failures=$((failures + 1))
    elif check "$tmp/mutated.yml"; then
        echo "FAIL: $label mutation passed"
        failures=$((failures + 1))
    else
        echo "ok: $label"
    fi
}

mutate_fetcher() {
    local label="$1" expression="$2"
    sed -E "$expression" "$fetcher" >"$tmp/mutated-fetcher.sh"
    if cmp -s "$fetcher" "$tmp/mutated-fetcher.sh"; then
        echo "FAIL: $label mutation changed nothing"
        failures=$((failures + 1))
    elif check "$workflow" "$tmp/mutated-fetcher.sh"; then
        echo "FAIL: $label mutation passed"
        failures=$((failures + 1))
    else
        echo "ok: $label"
    fi
}

mutate "monthly schedule required" "/cron:/d"
mutate "manual trigger required" "/workflow_dispatch:/d"
mutate "no pull request trigger" "s/^  workflow_dispatch:/  pull_request:\n  workflow_dispatch:/"
mutate "actions pinned" "0,/@[0-9a-f]{40}/s//@v4/"
mutate "pin version comments" "0,/@[0-9a-f]{40} # v[0-9.]+/s/ # v[0-9.]+//"
mutate "blocked egress" "s/egress-policy: block/egress-policy: audit/"
mutate "raw endpoint allowlisted" "s/            raw.githubusercontent.com:443//"
mutate "API endpoint allowlisted" "s/            api.github.com:443//"
mutate_fetcher "VPN source pinned" "s#X4BNet/lists_vpn/main/input/vpn/ASN.txt#example.invalid/vpn.txt#"
mutate_fetcher "datacenter source pinned" "s#X4BNet/lists_vpn/main/input/datacenter/ASN.txt#example.invalid/datacenter.txt#"
mutate_fetcher "ipverse source pinned" "s#ipverse/as-metadata/master/as.json#example.invalid/as.json#"
mutate "generator must run" "s#node analytics/refresh-asns.mjs#echo skipped#"
mutate "PR remains owner gated" "s/vars.ASN_REFRESH_PR_ENABLED == 'true'/true/"
mutate "default branch avoids shell template injection" "/DEFAULT_BRANCH:/d; s/\"\$DEFAULT_BRANCH\"/\"\${{ github.event.repository.default_branch }}\"/"
mutate "never auto merge" "s/gh pr create/gh pr create \&\& gh pr merge --auto/"

if [[ $failures -ne 0 ]]; then
    echo "$failures workflow guard test(s) failed"
    exit 1
fi
echo "all ASN refresh workflow guard tests passed"
