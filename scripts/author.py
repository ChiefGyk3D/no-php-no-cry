#!/usr/bin/env python3
"""Authoring helper: make a new post or journal entry that passes the content check (stdlib only).

Usage: python3 -I scripts/author.py [--root DIR] new (post|journal) TITLE [options]
       python3 -I scripts/author.py [--root DIR] check PATH

  new post|journal TITLE   create content/posts/<slug>/index.md (or content/journal/<slug>/index.md)
      --description TEXT   required, 1 to 160 characters. Asked for on a terminal when missing;
                           without a terminal a missing description is an error.
      --date YYYY-MM-DD    a real calendar date (default: now, Eastern time with its offset). A future date is refused
                           unless --allow-future is given.
      --tag SLUG           a lowercase slug (a-z, 0-9, single hyphens); repeat for more, at most 10
      --allow-future       accept a date after today
  check PATH               run scripts/check-content.py on PATH: an index.md, a bundle folder, or
                           a slug path under content/. Prints its result and passes its exit code.

The slug comes from the title: ASCII letters and digits joined by single hyphens, at most 80
characters. A new page is always draft: true (a draft is never built or announced). The helper never overwrites anything, follows no
symlink, writes only a new folder and index.md under content/, and does no network, git or
browser work. --root DIR names the repository root (default: this repository; tests use it).

Exit codes: 0 ok, 1 validation error (bad input, collision, check findings), 2 usage error.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys
import unicodedata
import zoneinfo

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(HERE)
CHECKER = os.path.join(HERE, "check-content.py")

SECTIONS = {"post": "posts", "journal": "journal"}
TITLE_MAX = 200
DESC_MAX = 160  # the same cap as scripts/check-content.py
SLUG_MAX = 80
TAG_MAX = 40
TAGS_MAX = 10
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
DATE_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")
# C0 and C1 controls plus the Unicode line and paragraph separators
CTRL_RE = re.compile("[" + chr(0) + "-" + chr(31) + chr(127) + "-" + chr(159) + chr(0x2028) + chr(0x2029) + "]")


class Refuse(Exception):
    """A validation error: printed, exit 1."""


def make_slug(title):
    text = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if len(slug) > SLUG_MAX:
        cut = slug[:SLUG_MAX]
        # cut at a word boundary when one is near, never leave a trailing hyphen
        if slug[SLUG_MAX] != "-" and "-" in cut:
            cut = cut.rsplit("-", 1)[0]
        slug = cut.strip("-")
    if not slug or not SLUG_RE.match(slug):
        raise Refuse("the title has no ASCII letters or digits to build a slug from")
    return slug


def clean_text(name, value, maxlen):
    value = unicodedata.normalize("NFC", value).strip()
    if not value:
        raise Refuse("%s must not be empty" % name)
    if len(value) > maxlen:
        raise Refuse("%s is %d characters, at most %d" % (name, len(value), maxlen))
    if CTRL_RE.search(value):
        raise Refuse("%s must be one line of plain text (no control characters)" % name)
    return value


def eastern_now():
    try:
        return datetime.datetime.now(zoneinfo.ZoneInfo("America/New_York")).replace(microsecond=0)
    except zoneinfo.ZoneInfoNotFoundError:
        raise Refuse("the America/New_York time zone data is missing; pass --date YYYY-MM-DD") from None


def parse_date(value, allow_future):
    """The date line: now with the Eastern offset, or a given calendar date as written."""
    if value is None:
        return eastern_now().isoformat()
    today = eastern_now().date()
    m = DATE_RE.match(value)
    if not m:
        raise Refuse("date must look like 2026-11-08")
    try:
        d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        raise Refuse("date %s is not a real calendar date" % value) from None
    if d > today and not allow_future:
        raise Refuse("date %s is in the future (today is %s Eastern); use --allow-future to keep it" % (d, today))
    return d.isoformat()


def check_tags(tags):
    if len(tags) > TAGS_MAX:
        raise Refuse("at most %d tags" % TAGS_MAX)
    seen = []
    for t in tags:
        if len(t) > TAG_MAX or not SLUG_RE.match(t):
            raise Refuse(
                "tag %r is not a lowercase slug (a-z, 0-9, single hyphens, at most %d characters)" % (t[:60], TAG_MAX)
            )
        if t not in seen:
            seen.append(t)
    return seen


def quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(kind, title, when, description, slug, tags):
    lines = [
        "---",
        "title: " + quote(title),
        "date: " + when,
        "draft: true",
        "description: " + quote(description),
        "slug: " + quote(slug),
        "categories: []",
        "tags: [" + ", ".join(quote(t) for t in tags) + "]",
        "syndicate: true",
    ]
    if kind == "post":
        lines.append("affiliate: false")
    lines += [
        "---",
        "",
        "Write the opening paragraph here. Keep it short: it can become the summary.",
        "",
        "<!--more-->",
        "",
        "Write the rest here.",
        "",
    ]
    return "\n".join(lines)


def real_dir(path, what):
    """path must be an existing real directory: not a symlink, not a file."""
    if not os.path.lexists(path):
        raise Refuse("%s does not exist: %s" % (what, path))
    if os.path.islink(path) or not os.path.isdir(path):
        raise Refuse("%s must be a real directory, not a symlink or file: %s" % (what, path))


def section_dir(root, section):
    """The real content/<section> directory, created when absent; every step checked."""
    root = os.path.realpath(root)
    real_dir(root, "repository root")
    content = os.path.join(root, "content")
    real_dir(content, "content directory")
    sec = os.path.join(content, section)
    if not os.path.lexists(sec):
        os.mkdir(sec)
    real_dir(sec, "content/" + section)
    if os.path.realpath(sec) != sec:
        raise Refuse("content/%s resolves outside content/" % section)
    return sec


def create(root, kind, title, description, when_arg, tags, allow_future):
    title = clean_text("title", title, TITLE_MAX)
    description = clean_text("description", description, DESC_MAX)
    when = parse_date(when_arg, allow_future)
    tags = check_tags(tags)
    slug = make_slug(title)
    sec = section_dir(root, SECTIONS[kind])
    bundle = os.path.join(sec, slug)
    # belt and braces: the target stays inside the section directory
    if os.path.dirname(bundle) != sec or os.path.commonpath([bundle, sec]) != sec:
        raise Refuse("the slug resolves outside content/")
    if os.path.lexists(bundle):
        raise Refuse("content/%s/%s already exists; nothing was changed" % (SECTIONS[kind], slug))
    text = render(kind, title, when, description, slug, tags)
    os.mkdir(bundle)  # fails if it appeared since the check above
    index = os.path.join(bundle, "index.md")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(index, flags, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return "content/%s/%s/index.md" % (SECTIONS[kind], slug)


def resolve_target(root, arg):
    """Turn PATH into a content/... Markdown path relative to root, inside content/ only."""
    root = os.path.realpath(root)
    p = arg if os.path.isabs(arg) else os.path.join(root, arg)
    p = os.path.normpath(p)
    content = os.path.join(root, "content")
    if os.path.islink(content):
        raise Refuse("content/ is a symlink")
    if p == content or os.path.commonpath([p, content]) != content:
        raise Refuse("%s is not inside content/" % arg)
    # no component below content/ may be a symlink
    cur = content
    for part in os.path.relpath(p, content).split(os.sep):
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            raise Refuse("%s goes through a symlink" % arg)
    if os.path.isdir(p):
        p = os.path.join(p, "index.md")
    if os.path.islink(p) or not os.path.isfile(p):
        raise Refuse("%s is not a regular file" % os.path.relpath(p, root))
    rel = os.path.relpath(p, root).replace(os.sep, "/")
    if not rel.endswith(".md"):
        raise Refuse("%s is not a Markdown file" % rel)
    return rel


def ask_description():
    if not (sys.stdin.isatty() and sys.stderr.isatty()):
        return None
    sys.stderr.write("Description (1 to %d characters, one or two plain sentences): " % DESC_MAX)
    sys.stderr.flush()
    line = sys.stdin.readline()
    return line.strip() if line else None


def build_parser():
    p = argparse.ArgumentParser(prog="author", description="Authoring helper for content/.")
    p.add_argument("--root", default=DEFAULT_ROOT, help="repository root (default: this repository)")
    sub = p.add_subparsers(dest="cmd", required=True)
    n = sub.add_parser("new", help="create a draft post or journal entry")
    n.add_argument("kind", choices=sorted(SECTIONS))
    n.add_argument("title")
    n.add_argument("--description")
    n.add_argument("--date")
    n.add_argument("--tag", action="append", default=[], dest="tags")
    n.add_argument("--allow-future", action="store_true")
    c = sub.add_parser("check", help="run the content check on a file or bundle")
    c.add_argument("path")
    return p


def main(argv):
    try:
        args = build_parser().parse_args(argv)
    except SystemExit as e:
        return 0 if e.code in (0, None) else 2
    try:
        if args.cmd == "new":
            description = args.description if args.description is not None else ask_description()
            if description is None or not description.strip():
                raise Refuse("a description is required (1 to %d characters): pass --description TEXT" % DESC_MAX)
            rel = create(args.root, args.kind, args.title, description, args.date, args.tags, args.allow_future)
            print("created %s (draft: true)" % rel)
            print("next: python3 -I scripts/author.py check %s" % rel)
            return 0
        rel = resolve_target(args.root, args.path)
        proc = subprocess.run(
            [sys.executable, "-I", CHECKER, "--root", os.path.realpath(args.root), rel],
            stdin=subprocess.DEVNULL,
            timeout=120,
        )
        return proc.returncode
    except Refuse as e:
        print("author: %s" % e, file=sys.stderr)
        return 1
    except subprocess.TimeoutExpired:
        print("author: the content check timed out", file=sys.stderr)
        return 1
    except OSError as e:
        print("author: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
