#!/usr/bin/env bash
# Usage: scripts/check-hugo-version.sh <expected-version> [version-output]
#
# Passes only for the pinned version of the standard edition. The version
# output is `hugo version` unless given (the tests give it). Hugo's
# build-metadata delimiter after the version is accepted as '-' or '+'.
set -euo pipefail

version="${1:?usage: check-hugo-version.sh <expected-version> [version-output]}"
if [[ $# -ge 2 ]]; then
    out="$2"
else
    out="$(hugo version)"
fi
echo "$out"

case "$out" in
    "hugo v${version}-"* | "hugo v${version}+"*) ;;
    *)
        echo "unexpected Hugo version (wanted v${version})"
        exit 1
        ;;
esac
case "$out" in
    *extended*)
        echo "extended edition is not allowed"
        exit 1
        ;;
    *) ;;
esac
