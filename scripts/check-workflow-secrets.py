#!/usr/bin/env python3
"""Fail when a workflow reads a GitHub repository secret.

Credentials live in the secret manager (Doppler) and nowhere else. A workflow
must not read `secrets.NAME`, `secrets['NAME']` or the whole `secrets` context.
The one allowed name is GITHUB_TOKEN: GitHub creates it for each run, it is not
a stored repository secret.

Usage: python3 -I scripts/check-workflow-secrets.py [DIR ...]
Default DIR is .github. Scans every .yml and .yaml file under each DIR.
Lines that are whole-line comments are ignored. Exit 0 clean, 1 on a finding,
2 on a usage error.
"""
import pathlib
import re
import sys

ALLOWED = {"GITHUB_TOKEN"}

NAMED = re.compile(r"""(?<![\w./-])secrets\s*(?:\.\s*([A-Za-z_][A-Za-z0-9_-]*)|\[\s*['"]([^'"]*)['"]\s*\])""")
# The whole context passed on or serialized, or indexed dynamically.
WHOLE = re.compile(r"""\(\s*secrets\s*[,)]|(?<![\w./-])secrets\s*\[\s*[^'"\s]""")
# A bare `secrets` token inside ${{ ... }}, not followed by `.` or `[`.
EXPR = re.compile(r"\$\{\{(.*?)\}\}")
BARE = re.compile(r"(?<![\w./-])secrets(?![\w-])(?!\s*[.\[])")
INHERIT = re.compile(r"^\s*secrets\s*:\s*inherit\b")


def scan(path):
    problems = []
    text = path.read_text(encoding="utf-8", errors="replace")
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        for m in NAMED.finditer(line):
            name = m.group(1) or m.group(2)
            if name not in ALLOWED:
                problems.append((n, "secrets.%s is not allowed" % name))
        if WHOLE.search(line) or any(BARE.search(m.group(1)) for m in EXPR.finditer(line)):
            problems.append((n, "the whole secrets context is not allowed"))
        if INHERIT.match(line):
            problems.append((n, "secrets: inherit is not allowed"))
    return problems


def main(argv):
    roots = [pathlib.Path(a) for a in argv] or [pathlib.Path(".github")]
    files = []
    for root in roots:
        if not root.is_dir():
            print("check-workflow-secrets: not a directory: %s" % root, file=sys.stderr)
            return 2
        files += sorted(p for p in root.rglob("*") if p.suffix in (".yml", ".yaml") and p.is_file())
    if not files:
        print("check-workflow-secrets: no workflow files found", file=sys.stderr)
        return 2
    bad = 0
    for f in files:
        for n, msg in scan(f):
            print("%s:%d: %s (credentials come from the secret manager only)" % (f, n, msg))
            bad += 1
    if bad:
        return 1
    print("check-workflow-secrets: %d file(s), no repository secret reads" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
