#!/usr/bin/env bash
# Run the WebP step's tests (tools/wxr2hugo/webp_tests) with the pinned Pillow
# release (tools/wxr2hugo/requirements-webp.txt, installed with --require-hashes
# and --only-binary into a throwaway venv under tmp/). Needs network access to
# the Python package index for that one package, the same as gen-support-qr.sh.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
venv="$(mktemp -d "$root/tmp/webp-venv.XXXXXX")"
trap 'rm -rf "$venv"' EXIT
python3 -m venv "$venv"
"$venv/bin/pip" install --quiet --require-hashes --only-binary=:all: -r "$root/tools/wxr2hugo/requirements-webp.txt"
tests="$root/tools/wxr2hugo/webp_tests"
"$venv/bin/python" -I -m unittest discover -s "$tests" -t "$tests" -v
