#!/usr/bin/env bash
# Tests the offline outbound-link build step and Hugo render-hook inputs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/content" "$tmp/data" "$tmp/static" "$tmp/analytics"
cat >"$tmp/content/index.md" <<'EOF'
---
title: N0CALL
---
[one](https://www.n0call.test/path?grid=FN31pr#part)
[two](https://n0tst.github.io/path)
[plain HTTP](http://radio.n0http.test/path)
[IPv4](https://127.0.0.1/path)
[local](/inside/)
EOF

python3 -I "$root/scripts/build-outbound-domains.py" --root "$tmp" --psl "$root/analytics/public_suffix_list.dat"

python3 -I - "$tmp" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
hosts = json.loads((root / "data/analytics_hosts.json").read_text())
domains = (root / "static/analytics-domains.txt").read_text().splitlines()
module = (root / "analytics/site-domains.mjs").read_text()
assert hosts == {
    "n0tst.github.io": "n0tst.github.io",
    "radio.n0http.test": "n0http.test",
    "www.n0call.test": "n0call.test",
}
assert domains == ["n0call.test", "n0http.test", "n0tst.github.io"]
assert "n0call.test" in module and "n0tst.github.io" in module
assert "n0http.test" in module
assert "0.1" not in module
assert "path" not in module and "FN31pr" not in module
PY

grep -q 'printf "/e/c/%s"' "$root/layouts/_markup/render-link.html"
grep -q 'site.Data.analytics_hosts' "$root/layouts/_markup/render-link.html"
grep -q 'relURL' "$root/layouts/_markup/render-link.html"

echo "test-outbound-clicks: ok"
