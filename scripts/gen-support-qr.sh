#!/usr/bin/env bash
# Usage: scripts/gen-support-qr.sh [--check]
#
# Regenerates static/support/qr-<coin>.svg from the addresses in
# data/support.yaml with the pinned segno release (scripts/requirements-qr.txt,
# installed with --require-hashes into a throwaway venv under tmp/). --check
# regenerates into tmp/ and exits 1 if a committed file differs. Run it whenever
# an address changes; CI does not (test-pages.sh checks that each SVG records
# the address in data/support.yaml).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
venv="$(mktemp -d "$root/tmp/qr-venv.XXXXXX")"
trap 'rm -rf "$venv"' EXIT
python3 -m venv "$venv"
"$venv/bin/pip" install --quiet --require-hashes -r "$root/scripts/requirements-qr.txt"
"$venv/bin/python" -I "$root/scripts/gen-support-qr.py" "$@"
