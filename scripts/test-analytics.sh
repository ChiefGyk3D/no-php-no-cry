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

node --test analytics/test/
python3 -I -W ignore scripts/test-analytics-sql.py
echo "test-analytics: ok"
