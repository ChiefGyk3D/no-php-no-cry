#!/usr/bin/env bash
# Usage: scripts/gen-support-qr.sh [--check] [--decode] [--dir DIR]
#
# Regenerates static/support/qr-<coin>.svg from the addresses in
# data/support.yaml with the pinned segno release (scripts/requirements-qr.txt,
# installed with --require-hashes into a throwaway venv under tmp/). --check
# regenerates into tmp/ and exits 1 if a committed file differs. Run it whenever
# an address changes. --decode also renders each SVG in headless Chrome and decodes
# it with OpenCV (exact address or failure); it needs Chrome or Chromium (CHROME).
# CI runs --check --decode (it compares the whole file, so the encoded
# modules are verified, not only the <desc> text) and test-pages.sh runs it
# against the built site. It needs network access to the Python package index,
# only for the hash-pinned releases in scripts/requirements-qr.txt (and, with
# --decode, scripts/requirements-qr-decode.txt).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
venv="$(mktemp -d "$root/tmp/qr-venv.XXXXXX")"
trap 'rm -rf "$venv"' EXIT
python3 -m venv "$venv"
"$venv/bin/pip" install --quiet --require-hashes -r "$root/scripts/requirements-qr.txt"
# The large decode-only wheels (OpenCV, NumPy) are installed only for --decode.
for arg in "$@"; do
    if [ "$arg" = "--decode" ]; then
        "$venv/bin/pip" install --quiet --require-hashes -r "$root/scripts/requirements-qr-decode.txt"
        break
    fi
done
"$venv/bin/python" -I "$root/scripts/gen-support-qr.py" "$@"
