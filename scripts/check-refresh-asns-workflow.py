#!/usr/bin/env python3
"""Structural guard for the credential-sensitive ASN refresh workflow."""
import re
import sys
from pathlib import Path


def check(text, fetcher_text):
    findings = []
    required = {
        "monthly schedule": r"cron:\s*['\"]17 8 1 \* \*['\"]",
        "manual trigger": r"(?m)^  workflow_dispatch:",
        "blocked egress": r"egress-policy:\s*block",
        "raw endpoint": r"raw\.githubusercontent\.com:443",
        "API endpoint": r"api\.github\.com:443",
        "GitHub endpoint": r"github\.com:443",
        "generator": r"node analytics/refresh-asns\.mjs",
        "owner gate": r"if:\s*vars\.ASN_REFRESH_PR_ENABLED == 'true'",
        "default branch environment handoff": r"DEFAULT_BRANCH:\s*\$\{\{ github\.event\.repository\.default_branch \}\}",
        "safe default branch use": r"--base\s+[\"']?\$DEFAULT_BRANCH[\"']?",
        "PR creation": r"gh pr create",
        "read permission": r"(?m)^permissions:\n  contents: read$",
    }
    for label, pattern in required.items():
        if not re.search(pattern, text):
            findings.append(f"missing {label}")
    source_patterns = {
        "VPN source": r"https://raw\.githubusercontent\.com/X4BNet/lists_vpn/main/input/vpn/ASN\.txt",
        "datacenter source": r"https://raw\.githubusercontent\.com/X4BNet/lists_vpn/main/input/datacenter/ASN\.txt",
        "ipverse source": r"https://raw\.githubusercontent\.com/ipverse/as-metadata/master/as\.json",
        "commit API": r"https://api\.github\.com/repos/X4BNet/lists_vpn/commits/main",
    }
    for label, pattern in source_patterns.items():
        if not re.search(pattern, fetcher_text):
            findings.append(f"missing {label}")
    for trigger in ("pull_request", "pull_request_target", "push", "workflow_run"):
        if re.search(rf"(?m)^  {trigger}:", text):
            findings.append(f"unexpected trigger {trigger}")
    if re.search(r"\bgh\s+pr\s+merge\b|\bmerge-pull-request\b|\bauto-merge\b", text, re.I):
        findings.append("workflow must never merge")
    uses = re.findall(r"(?m)^\s*(?:-\s*)?uses:\s*([^\s#]+)(?:\s+#\s*(\S+))?", text)
    if not uses:
        findings.append("no actions found")
    for reference, version in uses:
        if not re.search(r"@[0-9a-f]{40}$", reference):
            findings.append(f"action is not pinned: {reference}")
        if not version or not re.fullmatch(r"v[0-9]+(?:\.[0-9]+)*", version):
            findings.append(f"action pin lacks version comment: {reference}")
    if re.search(r"(?m)^\s*(?:contents|pull-requests): write\s*$", text):
        findings.append("workflow grants repository write permission")
    if re.search(r"\bsecrets\.", text):
        findings.append("workflow reads a GitHub Actions secret")
    if re.search(r"--base[^\n]*\$\{\{\s*github\.event\.repository\.default_branch\s*\}\}", text):
        findings.append("default branch is interpolated directly into a shell script")
    return findings


def main():
    if len(sys.argv) not in (2, 3):
        print("usage: check-refresh-asns-workflow.py WORKFLOW [FETCHER]", file=sys.stderr)
        return 2
    try:
        workflow_path = Path(sys.argv[1])
        text = workflow_path.read_text(encoding="utf-8")
        fetcher_path = Path(sys.argv[2]) if len(sys.argv) == 3 else workflow_path.parents[2] / "scripts/fetch-asn-sources.sh"
        fetcher_text = fetcher_path.read_text(encoding="utf-8")
    except OSError as error:
        print(error, file=sys.stderr)
        return 2
    findings = check(text, fetcher_text)
    for finding in findings:
        print(f"[refresh-asns-workflow] {finding}", file=sys.stderr)
    if findings:
        return 1
    print("ok: ASN refresh workflow structure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
