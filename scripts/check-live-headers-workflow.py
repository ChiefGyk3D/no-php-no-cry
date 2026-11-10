#!/usr/bin/env python3
"""Guard for .github/workflows/live-headers.yml, the scheduled live header check.

The workflow runs scripts/verify-live.sh (which compares the deployed headers
with static/_headers) against the dev host and, read only, the apex. This guard
fails when the workflow stops doing that safely.

Usage: python3 -I scripts/check-live-headers-workflow.py [FILE]
Exit 0 clean, 1 on a finding, 2 on a usage error.
"""
import pathlib
import re
import sys

DEFAULT = pathlib.Path(__file__).resolve().parent.parent / ".github/workflows/live-headers.yml"
DEV_HOST = "test-blog.chiefgyk3d.com"
APEX_HOST = "chiefgyk3d.com"


def check(text):
    out = []
    lines = [ln for ln in text.splitlines() if not ln.lstrip().startswith("#")]
    body = "\n".join(lines)
    if not re.search(r"^\s+schedule:\s*$", body, re.M) or not re.search(r"-\s*cron:\s*'[^']+'", body):
        out.append("no schedule with a cron entry")
    if not re.search(r"^\s+workflow_dispatch:", body, re.M):
        out.append("no workflow_dispatch trigger")
    for bad in ("pull_request", "pull_request_target", "push", "workflow_run"):
        if re.search(rf"^\s+{bad}:", body, re.M):
            out.append(f"unexpected trigger {bad}")
    if not re.search(r"^permissions:\s*\n\s+contents:\s*read\s*$", body, re.M):
        out.append("top-level permissions are not exactly contents: read")
    if re.search(r"^\s+(?:[a-z-]+):\s*write\s*$", body, re.M):
        out.append("a write permission is granted")
    if re.search(r"\bsecrets\b", body, re.I):
        out.append("reads the secrets context")
    for m in re.finditer(r"^\s*-?\s*uses:\s*(\S+)(.*)$", text, re.M):
        ref, rest = m.group(1), m.group(2)
        if not re.search(r"@[0-9a-f]{40}$", ref) or not re.search(r"#\s*v\d", rest):
            out.append(f"action not pinned by commit with a version comment: {ref}")
    calls = re.findall(r"scripts/verify-live\.sh\s+(.*)", body)
    dev = [c for c in calls if re.match(rf"\"?{re.escape(DEV_HOST)}\b", c.strip())]
    apex = [c for c in calls if re.match(rf"\"?{re.escape(APEX_HOST)}\b", c.strip())]
    if not any("--env staging" in c and "--public" in c for c in dev):
        out.append("dev host is not verified with --public and --env staging")
    if not any("--env production" in c and "--public" in c for c in apex):
        out.append("apex is not verified with --public and --env production")
    if re.search(r"continue-on-error|\|\|\s*true", body):
        out.append("the check is allowed to fail")
    return out


def main(argv):
    if len(argv) > 2:
        print(__doc__)
        return 2
    path = pathlib.Path(argv[1]) if len(argv) == 2 else DEFAULT
    try:
        text = path.read_text()
    except OSError as e:
        print(f"cannot read {path}: {e}")
        return 2
    findings = check(text)
    for f in findings:
        print(f"FAIL: {f}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
