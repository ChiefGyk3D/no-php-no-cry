#!/usr/bin/env bash
# Workflow-only fetcher for the ASN refresh inputs. It verifies X4BNet main did
# not move while the two files were downloaded, so the recorded SHA identifies
# the exact review window.
set -euo pipefail

out="${1:?usage: fetch-asn-sources.sh OUT_DIR}"
mkdir -p "$out"

read_sha() {
    curl -fsSL --retry 3 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        https://api.github.com/repos/X4BNet/lists_vpn/commits/main |
        python3 -c 'import json, sys; print(json.load(sys.stdin)["sha"])'
}

before="$(read_sha)"
curl -fsSL --retry 3 -o "$out/vpn.txt" \
    https://raw.githubusercontent.com/X4BNet/lists_vpn/main/input/vpn/ASN.txt
curl -fsSL --retry 3 -o "$out/datacenter.txt" \
    https://raw.githubusercontent.com/X4BNet/lists_vpn/main/input/datacenter/ASN.txt
curl -fsSL --retry 3 -o "$out/ipverse-as.json" \
    https://raw.githubusercontent.com/ipverse/as-metadata/master/as.json
after="$(read_sha)"

if [[ "$before" != "$after" ]]; then
    echo "X4BNet main changed during download; rerun the workflow" >&2
    exit 1
fi
printf '%s\n' "$before" >"$out/source-sha"
