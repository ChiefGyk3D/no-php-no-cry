#!/usr/bin/env python3
"""Drafts belong on the dev host only.

Usage: python3 -I scripts/check-drafts.py <site-dir> <absent|present> [content-dir]

  absent   a production build: no page whose front matter says `draft: true` may be in
           the output ([draft-in-production] <page>).
  present  the dev (staging) build: every such page must be in the output, so the owner
           can review it there ([draft-missing] <page>); the dev host is noindex.

A draft is a content file whose front matter has an unquoted `draft: true` (the rule of
scripts/check-content.py). Its output page is <section>/<slug or name>/index.html (a
bundle's directory name or the file name, replaced by `slug:` when set). Page content is
never printed. scripts/check-output.sh runs the `absent` check on every production tree,
so the private production pipeline, which runs that script, gets it too.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DRAFT = re.compile(r"^draft:[ \t]*true[ \t]*$", re.M)
SLUG = re.compile(r"^slug:[ \t]*[\"']?([^\"'\s]+)[\"']?[ \t]*$", re.M)


def front_matter(text):
    if not text.startswith("---"):
        return ""
    end = text.find("\n---", 3)
    return text[3:end] if end > 0 else ""


def draft_pages(content):
    """Yield the output path (relative to the site dir) of every draft page."""
    for root, _dirs, files in os.walk(content):
        for name in sorted(files):
            if not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            with open(path, encoding="utf-8") as fh:
                fm = front_matter(fh.read())
            if not DRAFT.search(fm):
                continue
            rel = os.path.relpath(root, content)
            parts = [] if rel == "." else rel.split(os.sep)
            if name not in ("index.md", "_index.md"):
                parts.append(name[:-3])
            m = SLUG.search(fm)
            if m and parts and name != "_index.md":
                parts[-1] = m.group(1)
            yield "/".join(parts + ["index.html"])


def main(argv):
    if len(argv) not in (3, 4) or argv[2] not in ("absent", "present"):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    site, mode = argv[1], argv[2]
    content = argv[3] if len(argv) == 4 else os.path.join(HERE, "..", "content")
    if not os.path.isdir(site) or not os.path.isdir(content):
        print("[missing-output] site or content directory not found")
        return 1
    pages = sorted(set(draft_pages(content)))
    findings = 0
    for page in pages:
        exists = os.path.isfile(os.path.join(site, page))
        if mode == "absent" and exists:
            print("[draft-in-production] %s" % page)
            findings += 1
        elif mode == "present" and not exists:
            print("[draft-missing] %s" % page)
            findings += 1
    if findings:
        return 1
    print("check-drafts: ok (%d draft page(s), %s in %s)" % (len(pages), mode, site))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
