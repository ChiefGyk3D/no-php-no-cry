#!/usr/bin/env python3
"""Drafts belong on the dev host only.

Usage: python3 -I scripts/check-drafts.py <site-dir> <absent|present> [content-dir]

  absent   a production build: no page whose front matter says `draft: true` may be in
           the output ([draft-in-production] <page>).
  present  the dev (staging) build: every such page must be in the output, so the owner
           can review it there ([draft-missing] <page>); the dev host is noindex.

A draft is a content file whose front matter has an unquoted `draft: true`, read with the
parser of scripts/check-content.py. Its output page is <section>/<slug or name>/index.html (a
bundle's directory name or the file name, replaced by `slug:` when set). Page content is
never printed. scripts/check-output.sh runs the `absent` check on every production tree,
so the private production pipeline, which runs that script, gets it too.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# The front matter is read with the content check's own parser (scripts/check-content.py), so
# `draft: true # note`, CRLF lines, a `...` closing fence and a quoted slug mean here what they
# mean there. A file that parser rejects is read with the lenient patterns below instead: it
# counts as a draft when any line says draft: true, so a malformed page is never waved through.
LENIENT_DRAFT = re.compile(r"^draft:[ \t]*true\b", re.M | re.I)
LENIENT_SLUG = re.compile(r"^slug:[ \t]*[\"']?([^\"'\s#]+)", re.M)


def _load_content_check():
    spec = importlib.util.spec_from_file_location("check_content", os.path.join(HERE, "check-content.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_front_matter(cc, text):
    """Return (is_draft, slug or None) for one content file."""
    try:
        lines, _body, _n = cc.split_front_matter(text)
        fm = cc.parse_front_matter(lines)
        slug = fm.get("slug")
        return fm.get("draft") is True, slug if isinstance(slug, str) and slug else None
    except Exception:  # FMError or anything odd: fall back to the lenient reading
        flat = text.replace("\r\n", "\n").replace("\r", "\n")
        m = LENIENT_SLUG.search(flat)
        return bool(LENIENT_DRAFT.search(flat)), m.group(1) if m else None


def draft_pages(content):
    """Yield the output path (relative to the site dir) of every draft page."""
    cc = _load_content_check()
    for root, _dirs, files in os.walk(content):
        for name in sorted(files):
            if not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            with open(path, encoding="utf-8") as fh:
                is_draft, slug = read_front_matter(cc, fh.read())
            if not is_draft:
                continue
            rel = os.path.relpath(root, content)
            parts = [] if rel == "." else rel.split(os.sep)
            if name not in ("index.md", "_index.md"):
                parts.append(name[:-3])
            if slug and parts and name != "_index.md":
                parts[-1] = slug
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
