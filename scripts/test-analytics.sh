#!/usr/bin/env bash
# Tests for the blog page-view collector (issue 84): the Pages Function and its
# helpers (node --test, Node 20 or newer, no packages) and the SQL (python3
# sqlite3: schema guard, k-threshold views, rollup, retention). Local only; no
# Cloudflare call is made and none is possible (the D1 binding is a fake).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

command -v node >/dev/null || {
    echo "test-analytics: node is required (20 or newer)" >&2
    exit 2
}
major="$(node -p 'process.versions.node.split(".")[0]')"
if ((major < 20)); then
    echo "test-analytics: node 20 or newer is required, found $major" >&2
    exit 2
fi

# Files are listed, not the directory: Node 22 reads a directory argument as a
# module path (the CI runner failed on it); Node 20 accepted it. A shell glob
# works on both. The check below keeps an empty glob from passing as no tests.
tests=(analytics/test/*.test.mjs)
[[ -e "${tests[0]}" ]] || {
    echo "test-analytics: no analytics/test/*.test.mjs files found" >&2
    exit 2
}
node --test "${tests[@]}"
python3 -I -W ignore scripts/test-analytics-sql.py
python3 -I scripts/test-analytics-reconciliation.py
echo "test-analytics: ok"
