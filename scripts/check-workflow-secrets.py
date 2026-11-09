#!/usr/bin/env python3
"""Fail when a workflow reads a GitHub repository secret.

Credentials live in the secret manager (Doppler) and nowhere else. A workflow
must not read `secrets.NAME`, `secrets['NAME']` or the whole `secrets` context.
The one allowed name is GITHUB_TOKEN: GitHub creates it for each run, it is not
a stored repository secret.

Usage: python3 -I scripts/check-workflow-secrets.py [DIR ...]
Default DIR is .github. Scans every .yml and .yaml file under each DIR.
Whole-line comments are ignored. Names are case-insensitive; an expression
may span lines. Exit 0 clean, 1 on a finding,
2 on a usage error.
"""
import pathlib
import re
import sys

ALLOWED = {"GITHUB_TOKEN"}

# GitHub expression context names are case-insensitive, so everything here is.
EXPR = re.compile(r"\$\{\{(.*?)\}\}", re.DOTALL)
IF_LINE = re.compile(r"^[ \t]*(?:-[ \t]+)?if[ \t]*:[ \t]*(?!.*\$\{\{)(.*)$", re.MULTILINE | re.IGNORECASE)
INHERIT = re.compile(r"^[ \t]*secrets[ \t]*:[ \t]*inherit\b", re.MULTILINE | re.IGNORECASE)
TOKEN = re.compile(r"(?<![\w./-])secrets(?![\w-])", re.IGNORECASE)
DOT_NAME = re.compile(r"\s*\.\s*([A-Za-z_][A-Za-z0-9_-]*)(?![\w*-])", re.IGNORECASE)
BRACKET_NAME = re.compile(r"""\s*\[\s*(['"])([A-Za-z_][A-Za-z0-9_-]*)\1\s*\]""", re.IGNORECASE)
ALLOWED_FOLDED = {n.lower() for n in ALLOWED}


def strip_comments(text):
    """Blank whole-line comments, keeping line numbers."""
    return "\n".join("" if ln.lstrip().startswith("#") else ln for ln in text.split("\n"))


def check_expr(expr):
    """Return a list of messages for one expression body."""
    msgs = []
    for m in TOKEN.finditer(expr):
        rest = expr[m.end() :]
        hit = DOT_NAME.match(rest) or BRACKET_NAME.match(rest)
        if hit:
            name = hit.group(1) if hit.re is DOT_NAME else hit.group(2)
            if name.lower() not in ALLOWED_FOLDED:
                msgs.append("secrets.%s is not allowed" % name)
        else:
            msgs.append("the whole secrets context (bare, object filter, wildcard or dynamic index) is not allowed")
    return msgs


def scan(path):
    problems = []
    text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    line_of = lambda off: text.count("\n", 0, off) + 1  # noqa: E731
    for m in EXPR.finditer(text):
        for msg in check_expr(m.group(1)):
            problems.append((line_of(m.start()), msg))
    for m in IF_LINE.finditer(text):
        for msg in check_expr(m.group(1)):
            problems.append((line_of(m.start(1)), msg))
    for m in INHERIT.finditer(text):
        problems.append((line_of(m.start()), "secrets: inherit is not allowed"))
    return sorted(set(problems))


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
