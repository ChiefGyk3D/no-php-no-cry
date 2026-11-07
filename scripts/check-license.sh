#!/usr/bin/env bash
# Check the license files.
#
# Usage: scripts/check-license.sh [repo-root]      (default: this repo)
#
# Fails when: LICENSE is missing or is not byte-for-byte the official Apache-2.0
# text (sha256 pinned below), LICENSE-CONTENT is missing or lacks the CC BY 4.0
# name, legal-code URL, scope section or attribution terms, or BRAND.md is missing
# or does not say "all rights reserved". Findings are printed as plain sentences.
set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# sha256 of https://www.apache.org/licenses/LICENSE-2.0.txt (fetched 2026-11-06).
apache_sha256="cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"
findings=0

report() {
    printf '%s\n' "$1"
    findings=$((findings + 1))
}

if [[ ! -f "$root/LICENSE" ]]; then
    report "LICENSE is missing"
else
    got="$(sha256sum "$root/LICENSE" | cut -d' ' -f1)"
    if [[ "$got" != "$apache_sha256" ]]; then
        report "LICENSE is not the official Apache-2.0 text (sha256 $got)"
    fi
fi

if [[ ! -f "$root/LICENSE-CONTENT" ]]; then
    report "LICENSE-CONTENT is missing"
elif ! grep -q 'creativecommons.org/licenses/by/4.0/legalcode' "$root/LICENSE-CONTENT"; then
    report "LICENSE-CONTENT does not point to the CC BY 4.0 legal code"
else
    grep -q 'Attribution 4.0 International' "$root/LICENSE-CONTENT" ||
        report "LICENSE-CONTENT does not name Attribution 4.0 International"
    grep -q '^Scope$' "$root/LICENSE-CONTENT" && grep -q '^Not covered:' "$root/LICENSE-CONTENT" ||
        report "LICENSE-CONTENT does not state its scope (Scope, Not covered)"
    grep -q '^Attribution$' "$root/LICENSE-CONTENT" && grep -q 'credit "ChiefGyk3D"' "$root/LICENSE-CONTENT" ||
        report "LICENSE-CONTENT does not state the attribution terms"
fi

if [[ ! -f "$root/BRAND.md" ]]; then
    report "BRAND.md (the brand notice) is missing"
elif ! grep -qi 'all rights reserved' "$root/BRAND.md"; then
    report "BRAND.md does not say the brand assets are all rights reserved"
fi

if [[ $findings -gt 0 ]]; then
    exit 1
fi
echo "ok: license files present, LICENSE matches the pinned Apache-2.0 text"
