#!/usr/bin/env python3
"""Structural offline test for the scheduled Public Suffix List refresh."""

import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
workflow = (root / ".github/workflows/refresh-public-suffix-list.yml").read_text()
assert "schedule:" in workflow and "workflow_dispatch:" in workflow
assert "publicsuffix.org/list/public_suffix_list.dat" in workflow
assert "scripts/build-outbound-domains.py" in workflow
assert "BEGIN PRIVATE DOMAINS" in workflow
assert "git diff --exit-code" in workflow
psl = (root / "analytics/public_suffix_list.dat").read_text()
assert re.search(r"^// VERSION: \d{4}-\d{2}-\d{2}$", psl, re.MULTILINE)
assert "===BEGIN ICANN DOMAINS===" in psl
assert "===BEGIN PRIVATE DOMAINS===" in psl
print("test-psl-refresh-workflow: ok")
