#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat >"$work/model.json" <<'JSON'
{
  "detail": {
    "diagrams": [
      {"title": "Publishing", "cells": [{"position": {"x": 0, "y": 0}, "size": {"width": 10, "height": 10}, "data": {"threats": [
        {"status": "Open"}, {"status": "Mitigated"}
      ]}}]},
      {"title": "Reading", "cells": [{"data": {"threats": [
        {"status": "Accepted"}, {"status": "NotApplicable"}
      ]}}]}
    ]
  }
}
JSON

cat >"$work/RISKS.md" <<'MD'
# Risks

<!-- threat-summary:start -->
old summary
<!-- threat-summary:end -->

<!-- threat-register:start -->
old register
<!-- threat-register:end -->
MD

python3 -I "$root/scripts/render-threat-summary.py" "$work/model.json" "$work/RISKS.md"

grep -Fq '| Diagram | Total | Mitigated | Open | Accepted | NotApplicable |' "$work/RISKS.md"
grep -Fq '| All diagrams | 4 | 1 | 1 | 1 | 1 |' "$work/RISKS.md"
grep -Fq '| Publishing | 2 | 1 | 1 | 0 | 0 |' "$work/RISKS.md"
grep -Fq '| Reading | 2 | 0 | 0 | 1 | 1 |' "$work/RISKS.md"
grep -Fq '## Publishing' "$work/RISKS.md"
grep -Fq '### Outside named boundaries' "$work/RISKS.md"
grep -Fq -- '- Open: Untitled threat' "$work/RISKS.md"
python3 -I "$root/scripts/render-threat-summary.py" --check "$work/model.json" "$work/RISKS.md"

sed -i 's/| 4 |/| 99 |/' "$work/RISKS.md"
if python3 -I "$root/scripts/render-threat-summary.py" --check "$work/model.json" "$work/RISKS.md"; then
    echo "FAIL: --check accepted a stale summary" >&2
    exit 1
fi

python3 -I "$root/scripts/render-threat-summary.py" "$work/model.json" "$work/RISKS.md"
sed -i 's/^- Open: Untitled threat/- Open: Stale threat title/' "$work/RISKS.md"
if python3 -I "$root/scripts/render-threat-summary.py" --check "$work/model.json" "$work/RISKS.md"; then
    echo "FAIL: --check accepted a stale register entry" >&2
    exit 1
fi

echo "all threat summary tests passed"
