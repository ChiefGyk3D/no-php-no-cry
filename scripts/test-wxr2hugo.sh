#!/usr/bin/env bash
# Run the wxr2hugo unit tests (Python 3 stdlib only, synthetic fixtures).
# Isolated mode (-I) matches how the tool itself is run.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests="$root/tools/wxr2hugo/tests"

python3 -I -m unittest discover -s "$tests" -t "$tests" -v
