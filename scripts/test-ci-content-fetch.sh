#!/usr/bin/env bash
# Guard: the "content checks" job in ci.yml must fetch the checked-out commit at
# depth 2. A depth-1 pull-request merge commit loses its parents, and
# `git fetch --deepen=1 origin` does not bring them back, so check-content.py
# finds no diff base. Includes a self-check that the old line makes it fail.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

check() { # check <ci.yml path>; prints nothing, returns 0 when the command is right
    python3 -I - "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'\{"name": "content checks", "command": "((?:[^"\\]|\\.)*)"', text)
if not m:
    sys.exit("content checks job not found")
cmd = m.group(1).replace('\\"', '"').replace("\\n", "\n")
if "--deepen" in cmd:
    sys.exit("content checks still uses --deepen")
if 'git fetch --no-tags --depth=2 origin "$(git rev-parse HEAD)"' not in cmd.splitlines():
    sys.exit("content checks does not fetch HEAD at depth 2")
PY
}

if check "$root/.github/workflows/ci.yml" 2>"$work/err"; then
    echo "ok: content checks fetches HEAD at depth 2"
else
    echo "FAIL: $(cat "$work/err")"
    fail=1
fi

# negative case: put the old line back and the guard must bite
sed 's|git fetch --no-tags --depth=2 origin \\"$(git rev-parse HEAD)\\"|git fetch --no-tags --deepen=1 origin|' \
    "$root/.github/workflows/ci.yml" >"$work/old.yml"
if check "$work/old.yml" 2>/dev/null; then
    echo "FAIL: guard did not bite on the old --deepen=1 line"
    fail=1
else
    echo "ok: guard bites on the old line"
fi
exit "$fail"
