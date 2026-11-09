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
  img add BUNDLE FILE --alt TEXT [--name NAME] [--featured]
                           copy a JPEG or PNG into a page bundle with every metadata block removed
                           (EXIF with GPS, XMP, IPTC, comments, thumbnails). See docs/authoring-helper.md.
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
import hashlib
import importlib.util
import os
import re
import stat
import struct
import subprocess
import sys
import unicodedata
import zlib
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


IMAGE_MAX = 5 * 1024 * 1024  # the same cap as scripts/check-content.py
IMAGE_SIDE_MAX = 10000  # pixels a side, the same cap as scripts/check-content.py
IMAGE_PIXELS_MAX = 64 * 1000 * 1000
ALT_CAP = 300  # characters of alt text this helper accepts (the content check allows more)
NAME_MAX = 60
PNG_SIG = bytes([0x89]) + b"PNG\r\n" + bytes([0x1A, 0x0A])


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


# --- img add ------------------------------------------------------------------------------------

_checker = None


def checker():
    """scripts/check-content.py loaded as a module, so the alt text rules have one source."""
    global _checker
    if _checker is None:
        spec = importlib.util.spec_from_file_location("check_content", CHECKER)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _checker = mod
    return _checker


def exif_orientation(tiff):
    """The EXIF Orientation value (1 to 8) from a TIFF block, or None when absent or unreadable."""
    try:
        order = {b"II": "<", b"MM": ">"}[tiff[:2]]
        off = struct.unpack(order + "I", tiff[4:8])[0]
        count = struct.unpack(order + "H", tiff[off : off + 2])[0]
        for k in range(min(count, 256)):
            e = off + 2 + k * 12
            tag, typ, num = struct.unpack(order + "HHI", tiff[e : e + 8])
            if tag == 0x0112 and typ == 3 and num == 1:
                return struct.unpack(order + "H", tiff[e + 8 : e + 10])[0]
    except (KeyError, struct.error):
        return None
    return None


def refuse_rotated(orientation):
    if orientation is not None and orientation != 1:
        raise Refuse(
            "the image carries EXIF orientation %d (it is displayed rotated or mirrored). This helper cannot "
            "rotate pixels, and dropping the tag would show it sideways. Rotate it in an image editor, "
            "save it with orientation normal, and add it again" % orientation
        )


def check_dims(w, h):
    if w < 1 or h < 1 or w > IMAGE_SIDE_MAX or h > IMAGE_SIDE_MAX or w * h > IMAGE_PIXELS_MAX:
        raise Refuse(
            "image dimensions %dx%d are out of range (at most %d pixels a side and %d megapixels)"
            % (w, h, IMAGE_SIDE_MAX, IMAGE_PIXELS_MAX // 1000000)
        )


def sniff(data):
    """'jpeg' or 'png' from the first bytes, never from the file name."""
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:8] == PNG_SIG:
        return "png"
    raise Refuse("the file is not a JPEG or PNG (its first bytes are not an image of either type)")


# JPEG segments that are kept: tables, frame and scan headers and the restart interval, plus the Adobe
# colour marker. Everything else is dropped: JFIF thumbnails, EXIF, XMP, IPTC, ICC, comments, other APPn.
JPEG_KEEP = {0xDB, 0xC4, 0xCC, 0xDD, 0xDC, 0xDA} | {m for m in range(0xC0, 0xD0) if m not in (0xC4, 0xC8, 0xCC)}


def strip_jpeg(b):
    bad = Refuse("the JPEG is truncated or malformed")
    out = bytearray(b"\xff\xd8")
    i, n = 2, len(b)
    frames = scans = 0
    dims = None
    while True:
        if i >= n or b[i] != 0xFF:
            raise bad
        while i < n and b[i] == 0xFF:
            i += 1
        if i >= n:
            raise bad
        m = b[i]
        i += 1
        if m == 0xD9:
            if i != n:
                raise Refuse("the JPEG has %d bytes after the end of the image marker; refused" % (n - i))
            out += b"\xff\xd9"
            break
        if m in (0x00, 0x01, 0xD8) or 0xD0 <= m <= 0xD7:
            raise bad
        if i + 2 > n:
            raise bad
        length = struct.unpack(">H", b[i : i + 2])[0]
        if length < 2 or i + length > n:
            raise bad
        seg = b[i + 2 : i + length]
        i += length
        if 0xE0 <= m <= 0xEF:
            if m == 0xE1 and seg[:6] == b"Exif\0\0":
                refuse_rotated(exif_orientation(seg[6:]))
            if m == 0xEE and seg[:5] == b"Adobe" and len(seg) == 12:
                out += bytes([0xFF, m]) + struct.pack(">H", length) + seg
            continue
        if m not in JPEG_KEEP:
            continue
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xCC):
            if len(seg) < 6:
                raise bad
            h, w = struct.unpack(">HH", seg[1:5])
            check_dims(w, h)
            dims = (w, h)
            frames += 1
        out += bytes([0xFF, m]) + struct.pack(">H", length) + seg
        if m == 0xDA:
            scans += 1
            j = i
            while True:
                if j >= n:
                    raise bad
                if b[j] == 0xFF:
                    if j + 1 >= n:
                        raise bad
                    nxt = b[j + 1]
                    if nxt == 0 or 0xD0 <= nxt <= 0xD7:
                        j += 2
                        continue
                    if nxt == 0xFF:
                        j += 1
                        continue
                    break
                j += 1
            out += b[i:j]
            i = j
    if frames != 1 or scans < 1 or dims is None:
        raise bad
    return bytes(out), dims


PNG_KEEP = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND", b"gAMA", b"cHRM", b"sRGB"}


def strip_png(b):
    bad = Refuse("the PNG is truncated or malformed (chunk checksum or structure)")
    out = bytearray(PNG_SIG)
    i, n = 8, len(b)
    dims = None
    idat = 0
    first = True
    while True:
        if i + 12 > n:
            raise bad
        length = struct.unpack(">I", b[i : i + 4])[0]
        kind = b[i + 4 : i + 8]
        if length > n or i + 12 + length > n or not re.fullmatch(rb"[A-Za-z]{4}", kind):
            raise bad
        data = b[i + 8 : i + 8 + length]
        if zlib.crc32(kind + data) != struct.unpack(">I", b[i + 8 + length : i + 12 + length])[0]:
            raise bad
        if first:
            if kind != b"IHDR" or length != 13:
                raise bad
            w, h = struct.unpack(">II", data[:8])
            check_dims(w, h)
            dims = (w, h)
            first = False
        elif kind == b"IHDR":
            raise bad
        if kind == b"eXIf":
            refuse_rotated(exif_orientation(data))
        if kind == b"IDAT":
            idat += 1
        if kind in PNG_KEEP:
            out += b[i : i + 12 + length]
        i += 12 + length
        if kind == b"IEND":
            break
    if i != n:
        raise Refuse("the PNG has %d bytes after the end of the image; refused" % (n - i))
    if idat == 0:
        raise bad
    return bytes(out), dims


def strip_image(kind, data):
    return strip_jpeg(data) if kind == "jpeg" else strip_png(data)


def clean_file_name(name):
    text = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:NAME_MAX].strip("-")
    return text or "image"


def resolve_bundle(root, arg):
    """PATH to a leaf page bundle (a real folder with a real index.md) inside content/."""
    root = os.path.realpath(root)
    p = arg if os.path.isabs(arg) else os.path.join(root, arg)
    p = os.path.normpath(p)
    content = os.path.join(root, "content")
    if os.path.islink(content):
        raise Refuse("content/ is a symlink")
    if p == content or os.path.commonpath([p, content]) != content:
        raise Refuse("%s is not inside content/" % arg)
    cur = content
    for part in os.path.relpath(p, content).split(os.sep):
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            raise Refuse("%s goes through a symlink" % arg)
    if not os.path.lexists(p):
        raise Refuse("bundle %s does not exist" % arg)
    if not os.path.isdir(p):
        raise Refuse("bundle %s is not a folder" % arg)
    index = os.path.join(p, "index.md")
    if os.path.islink(index) or not os.path.isfile(index):
        raise Refuse("%s has no index.md of its own; it is not a page bundle" % arg)
    return p, os.path.relpath(p, root).replace(os.sep, "/")


def read_source(arg):
    """The bytes of a regular file reached through no symlink, read with a hard size cap."""
    p = os.path.abspath(arg)
    cur = os.sep
    for part in [x for x in p.split(os.sep) if x]:
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            raise Refuse("%s goes through a symlink; pass the real path" % arg)
    if not os.path.lexists(p):
        raise Refuse("%s does not exist" % arg)
    if not stat.S_ISREG(os.lstat(p).st_mode):
        raise Refuse("%s is not a regular file" % arg)
    fd = os.open(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    with os.fdopen(fd, "rb") as f:
        st = os.fstat(f.fileno())
        if not stat.S_ISREG(st.st_mode):
            raise Refuse("%s is not a regular file" % arg)
        if st.st_size > IMAGE_MAX:
            raise Refuse(
                "%s is %d bytes; the limit is %d bytes (5 MiB). Hugo resizes at build, "
                "but the file kept in the repository must stay small" % (arg, st.st_size, IMAGE_MAX)
            )
        data = f.read(IMAGE_MAX + 1)
    if len(data) > IMAGE_MAX:
        raise Refuse("%s is over the 5 MiB limit" % arg)
    if not data:
        raise Refuse("%s is empty (not a JPEG or PNG)" % arg)
    return data


def md_escape(text):
    return re.sub(r"([\\\[\]])", r"\\\1", text)


def add_image(root, bundle_arg, file_arg, alt, name, featured):
    alt = clean_text("alt text", alt, ALT_CAP)
    bundle, bundle_rel = resolve_bundle(root, bundle_arg)
    data = read_source(file_arg)
    kind = sniff(data)
    ext = ".jpg" if kind == "jpeg" else ".png"
    stem = clean_file_name(name if name is not None else os.path.splitext(os.path.basename(file_arg))[0])
    fname = stem + ext
    problem = checker().alt_problem(alt, fname)
    if problem:
        raise Refuse("%s: write a short description of what the image shows" % problem)
    clean, dims = strip_image(kind, data)  # validates structure and dimensions; refuses rotated images
    dest = os.path.join(bundle, fname)
    if os.path.dirname(dest) != bundle:
        raise Refuse("the file name resolves outside the bundle")
    if os.path.lexists(dest):
        raise Refuse("%s/%s already exists; nothing was changed (pick another name with --name)" % (bundle_rel, fname))
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(dest, flags, 0o644)
    except FileExistsError:
        raise Refuse("%s/%s already exists; nothing was changed" % (bundle_rel, fname)) from None
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(clean)
    except BaseException:
        os.unlink(dest)
        raise
    digest = hashlib.sha256(clean).hexdigest()
    lines = [
        "added %s/%s (%s %dx%d, %d bytes; EXIF, GPS, XMP, IPTC, comments and thumbnails removed)"
        % (bundle_rel, fname, kind.upper(), dims[0], dims[1], len(clean)),
        "paste into the page:",
    ]
    if featured:
        lines += ["  image: " + quote(fname), "  imageAlt: " + quote(alt)]
    else:
        lines.append("  ![%s](%s)" % (md_escape(alt), fname))
    lines += [
        "before the check can pass, look at the image, then add this line to brand/approved-assets.txt:",
        "  %s/%s | %s | <where the image came from> | <what you checked>" % (bundle_rel, fname, digest),
    ]
    return "\n".join(lines)


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
    im = sub.add_parser("img", help="add an image to a page bundle")
    imsub = im.add_subparsers(dest="img_cmd", required=True)
    ia = imsub.add_parser("add", help="copy a JPEG or PNG into a bundle with its metadata removed")
    ia.add_argument("bundle")
    ia.add_argument("file")
    ia.add_argument("--alt", required=True)
    ia.add_argument("--name")
    ia.add_argument("--featured", action="store_true")
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
        if args.cmd == "img":
            print(add_image(args.root, args.bundle, args.file, args.alt, args.name, args.featured))
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
