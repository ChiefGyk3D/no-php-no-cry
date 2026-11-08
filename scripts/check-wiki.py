#!/usr/bin/env python3
"""Check the README and the wiki pages under docs/wiki/ for broken references.

Usage: python3 -I scripts/check-wiki.py [--no-require-set] [repo-root]

Scans README.md and docs/wiki/*.md (Python standard library only). Findings print
as "[rule] file:line detail" and the exit status is 1. Page text is not echoed
beyond the offending target. Rules:

  no-pages      the wiki directory holds no page (a check that finds nothing fails)
  missing-page  a page of REQUIRED_PAGES is absent (skipped by --no-require-set)
  bad-link      a Markdown link whose relative target, or whose github.com blob or
                tree URL for this repository, names a file or folder that does not exist
  bad-anchor    a link to #heading that the target page does not have
  bad-path      a word in a backtick span or in a fenced block that looks like a path
                in this repository (it starts with a known top-level folder, or is a
                known top-level file) and does not exist. Words with a glob, a
                placeholder or a variable ($, *, <, {) are not checked.
  http-link     a plain http:// URL
  private-path  a home-folder path (/home/..., /Users/...) or the private dev folder
  em-dash       an em dash (the house style never uses one)

Exit codes: 0 clean, 1 a finding, 2 usage.
"""

import os
import re
import sys

REPO_URL = "https://github.com/ChiefGyk3D/no-php-no-cry"

REQUIRED_PAGES = [
    "Home",
    "Getting-started",
    "Architecture",
    "Writing-a-post",
    "Journal-entries",
    "Images-and-alt-text",
    "Headline-images",
    "Share-links",
    "Search-and-tags",
    "Build-checks-and-budgets",
    "Deploy-overview",
    "Migrating-from-WordPress",
    "Performance",
    "Accessibility",
    "Contributing",
    "FAQ",
    "_Sidebar",
]

TOP_DIRS = (
    "scripts",
    "docs",
    "layouts",
    "assets",
    "data",
    "content",
    "archetypes",
    "static",
    "tools",
    "brand",
    "functions",
    "analytics",
    "deploy",
    ".github",
)
# A word that names a repository path: a known folder first, then path characters only.
PATH_RE = re.compile(r"^(?:%s)/[A-Za-z0-9_./-]*$" % "|".join(re.escape(d) for d in TOP_DIRS))
ROOT_FILE_RE = re.compile(r"^(?:[A-Z][A-Z0-9_-]*\.md|hugo\.toml|\.hugo-version|board\.yaml|[a-z]+\.js\.sha256)$")

LINK_RE = re.compile(r"(?<!\\)\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
FENCE_RE = re.compile(r"^\s{0,3}(```+|~~~+)")
CODE_SPAN_RE = re.compile(r"(`+)(.+?)\1")
HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$")


def slug(text):
    """The anchor GitHub makes from a heading."""
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = text.strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def read_lines(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read().splitlines()


def anchors_of(path, cache):
    if path not in cache:
        found = set()
        seen = {}
        in_fence = False
        for line in read_lines(path):
            if FENCE_RE.match(line):
                in_fence = not in_fence
                continue
            m = None if in_fence else HEADING_RE.match(line)
            if m:
                s = slug(m.group(1))
                n = seen.get(s, 0)
                seen[s] = n + 1
                found.add(s if n == 0 else "%s-%d" % (s, n))
        cache[path] = found
    return cache[path]


def inside(root, path):
    root = os.path.realpath(root)
    path = os.path.realpath(path)
    return path == root or path.startswith(root + os.sep)


def path_word_ok(root, word):
    """True when word is not a checked repository path, or names one that exists."""
    word = word.strip("\"'.,;:()[]")
    word = re.sub(r":\d+$", "", word)
    if not word or any(c in word for c in "$*<>{}"):
        return True
    if not (PATH_RE.match(word) or ROOT_FILE_RE.match(word)):
        return True
    full = os.path.join(root, word)
    return os.path.exists(full) and inside(root, full)


def check_file(root, path, rel, findings, cache, wiki_dir):
    in_fence = False
    for no, line in enumerate(read_lines(path), 1):
        def add(rule, detail):
            findings.append("[%s] %s:%d %s" % (rule, rel, no, detail))

        if chr(0x2014) in line:  # the em dash, spelled so this file has none
            add("em-dash", "em dash")
        if re.search(r"/(?:home|Users)/[A-Za-z0-9_.-]+|no-php-no-cry-dev", line):
            add("private-path", "home-folder or private dev path")
        if re.search(r"\bhttp://", line):
            add("http-link", "plain http:// URL")

        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            for word in re.split(r"[\s=|;&]+", line):
                if not path_word_ok(root, word):
                    add("bad-path", word.strip("\"'.,;:()[]"))
            continue

        for m in CODE_SPAN_RE.finditer(line):
            for word in re.split(r"[\s=|;&]+", m.group(2).strip()):
                if not path_word_ok(root, word):
                    add("bad-path", word.strip("\"'.,;:()[]"))
        prose = CODE_SPAN_RE.sub("", line)
        for m in LINK_RE.finditer(line):
            target = m.group(1)
            if target.startswith("mailto:") or target.startswith("http://"):
                continue
            frag = ""
            if "#" in target:
                target, frag = target.split("#", 1)
            if target.startswith("https://"):
                if not target.startswith(REPO_URL + "/"):
                    continue
                rest = target[len(REPO_URL) + 1 :]
                m2 = re.match(r"(?:blob|tree)/main/(.*)$", rest)
                if not m2:
                    continue
                full = os.path.join(root, m2.group(1))
            elif target == "":
                full = path
            elif re.match(r"^[a-z][a-z0-9+.-]*:", target):
                continue
            else:
                full = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not inside(root, full) or not os.path.exists(full):
                add("bad-link", target or "(this page)")
                continue
            if frag and os.path.isfile(full) and full.endswith(".md"):
                if frag.lower() not in anchors_of(full, cache):
                    add("bad-anchor", "%s#%s" % (target, frag))
        del prose


def main(argv):
    require = True
    args = []
    for a in argv:
        if a == "--no-require-set":
            require = False
        elif a.startswith("-"):
            print("usage: check-wiki.py [--no-require-set] [repo-root]", file=sys.stderr)
            return 2
        else:
            args.append(a)
    if len(args) > 1:
        print("usage: check-wiki.py [--no-require-set] [repo-root]", file=sys.stderr)
        return 2
    root = os.path.abspath(args[0] if args else os.path.join(os.path.dirname(__file__), ".."))
    if not os.path.isdir(root):
        print("usage: check-wiki.py [--no-require-set] [repo-root]", file=sys.stderr)
        return 2

    wiki_dir = os.path.join(root, "docs", "wiki")
    pages = []
    if os.path.isdir(wiki_dir):
        pages = sorted(f for f in os.listdir(wiki_dir) if f.endswith(".md"))
    findings = []
    if not pages:
        findings.append("[no-pages] docs/wiki: no page found")
    if require and pages:
        for name in REQUIRED_PAGES:
            if name + ".md" not in pages:
                findings.append("[missing-page] docs/wiki/%s.md: required page is absent" % name)

    cache = {}
    files = [("README.md", os.path.join(root, "README.md"))] if os.path.isfile(os.path.join(root, "README.md")) else []
    files += [("docs/wiki/" + p, os.path.join(wiki_dir, p)) for p in pages]
    for rel, path in files:
        check_file(root, path, rel, findings, cache, wiki_dir)

    if findings:
        print("\n".join(findings))
        return 1
    print("check-wiki: ok (%d files)" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
