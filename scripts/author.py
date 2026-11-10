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
  preview [--port N] [--no-drafts] [--hugo PATH]
                           hugo server (drafts shown unless --no-drafts) bound to 127.0.0.1 only (any other
                           --host is refused); prints the URL, opens no browser. Needs the pinned standard
                           Hugo from .hugo-version.
  check PATH [--require-published] [--build] [--hugo PATH]
                           run the named steps on a page (an index.md, a bundle folder, or a slug path under
                           content/): content (scripts/check-content.py), images (metadata), dashes, wording,
                           draft state; with --build also the production build and scripts/check-output.sh.
                           Exit 0 only if every step passes.
  publish BUNDLE --issue N [--set-draft-false] [--dry-run] [--remote R] [--base B] [--gh PATH]
                           check, commit the bundle on the current branch, push that branch and open a pull
                           request through gh. Never merges, never pushes main, never forces.

The slug comes from the title: ASCII letters and digits joined by single hyphens, at most 80
characters. A new page is always draft: true (a draft is never built or announced). The helper never overwrites anything and follows no
symlink. new and img add write only under content/ and use no network, git or browser; only publish runs
git and gh. --root DIR names the repository root (default: this repository; tests use it).

Exit codes: 0 ok, 1 validation error (bad input, collision, check findings), 2 usage error.
"""
import argparse
import datetime
import hashlib
import importlib.util
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
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


PNG_DEPTHS = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
PNG_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
ADAM7 = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))


def png_raw_size(w, h, depth, ctype, interlace):
    """Bytes of filtered scanline data the IDAT stream must inflate to (PNG spec, sections 7 and 9)."""
    bits = depth * PNG_CHANNELS[ctype]
    if not interlace:
        return h * (1 + (w * bits + 7) // 8)
    total = 0
    for x0, y0, dx, dy in ADAM7:
        pw, ph = (w - x0 + dx - 1) // dx, (h - y0 + dy - 1) // dy
        if pw > 0 and ph > 0:
            total += ph * (1 + (pw * bits + 7) // 8)
    return total


PNG_KEEP = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND", b"gAMA", b"cHRM", b"sRGB"}


def strip_png(b):
    bad = Refuse("the PNG is truncated or malformed (chunk checksum or structure)")
    out = bytearray(PNG_SIG)
    i, n = 8, len(b)
    dims = None
    idat = 0
    first = True
    z = []
    palette = False
    last = b""
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
            depth, ctype, comp, filt, interlace = data[8:13]
            if ctype not in PNG_DEPTHS or depth not in PNG_DEPTHS[ctype] or comp != 0 or filt != 0 or interlace > 1:
                raise Refuse("the PNG header has an invalid bit depth, color type, or method (malformed)")
            dims = (w, h)
            first = False
        elif kind == b"IHDR":
            raise bad
        if kind == b"eXIf":
            refuse_rotated(exif_orientation(data))
        if kind == b"PLTE":
            if idat or palette or ctype in (0, 4) or length % 3 or not 3 <= length <= 3 * (1 << depth):
                raise bad
            palette = True
        if kind == b"IDAT":
            if idat and last != b"IDAT":
                raise bad  # IDAT chunks must be consecutive
            if ctype == 3 and not palette:
                raise bad
            idat += 1
            z.append(data)
        last = kind
        if kind in PNG_KEEP:
            out += b[i : i + 12 + length]
        i += 12 + length
        if kind == b"IEND":
            break
    if i != n:
        raise Refuse("the PNG has %d bytes after the end of the image; refused" % (n - i))
    if idat == 0:
        raise bad
    # inflate the image data (bounded) and require exactly the scanline bytes the header implies
    want = png_raw_size(dims[0], dims[1], depth, ctype, interlace)
    d = zlib.decompressobj()
    try:
        got = d.decompress(b"".join(z), want + 1)
        if len(got) != want or d.unconsumed_tail or not d.eof or d.unused_data:
            raise bad
    except zlib.error:
        raise bad from None
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


# --- preview ------------------------------------------------------------------------------------

LOOPBACK = "127.0.0.1"


def free_port():
    import socket  # only to find a free loopback port; nothing listens beyond 127.0.0.1

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((LOOPBACK, 0))
        return s.getsockname()[1]


def find_hugo(root, hugo_arg):
    """The Hugo binary (--hugo or the first one on PATH), confirmed to be the pinned standard edition."""
    import shutil

    path = hugo_arg if hugo_arg else shutil.which("hugo")
    if not path or not os.path.isfile(path) or not os.access(path, os.X_OK):
        raise Refuse(
            "hugo is not installed (%s). Install the release named in .hugo-version "
            "(standard edition) as the README describes, or pass --hugo PATH"
            % ("%s is not an executable file" % hugo_arg if hugo_arg else "none was found on PATH")
        )
    pin_file = os.path.join(os.path.realpath(root), ".hugo-version")
    try:
        with open(pin_file, encoding="utf-8") as f:
            pin = f.read().strip()
    except OSError:
        raise Refuse(".hugo-version is missing; cannot tell which Hugo release is pinned") from None
    try:
        v = subprocess.run([path, "version"], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Refuse("could not run %s version: %s" % (path, e)) from None
    version_out = (v.stdout or "").strip()
    gate = subprocess.run(
        ["bash", os.path.join(HERE, "check-hugo-version.sh"), pin, version_out],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if v.returncode != 0 or gate.returncode != 0:
        raise Refuse(
            "wrong Hugo version: %r found, the pinned standard edition v%s is required (%s)"
            % (version_out[:80], pin, (gate.stdout.strip().splitlines() or ["no version output"])[-1])
        )
    return path


def preview(root, host, port, hugo_arg, drafts=True):
    if host != LOOPBACK:
        raise Refuse("preview binds %s only; refusing host %r" % (LOOPBACK, host))
    if port is not None and not 1024 <= port <= 65535:
        raise Refuse("port must be between 1024 and 65535")
    hugo = find_hugo(root, hugo_arg)
    port = port or free_port()
    url = "http://%s:%d/" % (LOOPBACK, port)
    print("preview (%s): %s  (Ctrl-C stops it; nothing else can reach it)" % ("drafts shown" if drafts else "drafts hidden", url), flush=True)
    argv = [hugo, "server"] + (["-D"] if drafts else []) + ["--bind", LOOPBACK, "--port", str(port), "--baseURL", url, "--source", os.path.realpath(root)]
    try:
        return subprocess.call(argv, stdin=subprocess.DEVNULL)
    except KeyboardInterrupt:
        return 0


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


# --- check (all steps) -----------------------------------------------------------------------------

PAGE_MAX = 1024 * 1024  # the content check's cap for one Markdown file
TEMPLATE_MAX = 64 * 1024
DASHES = {chr(0x2014): "em dash", chr(0x2013): "en dash"}
SHORT_FORM_RE = re.compile(r"\bcry" + r"pto(?!graph|system)\b", re.IGNORECASE)  # brand/README.md, "Wording"
IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp")
CHECK_STEPS = ("content", "images", "dashes", "wording", "draft")


def read_page(root, rel):
    """The text of one Markdown file, read through no symlink with a hard size cap."""
    p = os.path.join(os.path.realpath(root), rel)
    st = os.lstat(p)
    if not stat.S_ISREG(st.st_mode):
        raise Refuse("%s is not a regular file (a symlink or special file)" % rel)
    if st.st_size > PAGE_MAX:
        raise Refuse("%s is %d bytes; the limit for a page is %d bytes" % (rel, st.st_size, PAGE_MAX))
    fd = os.open(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    with os.fdopen(fd, "rb") as f:
        data = f.read(PAGE_MAX + 1)
    if len(data) > PAGE_MAX:
        raise Refuse("%s is over %d bytes" % (rel, PAGE_MAX))
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise Refuse("%s is not UTF-8" % rel) from None


def front_matter_end(lines):
    """Index of the closing --- line of the front matter, or None when there is no front matter."""
    if not lines or lines[0].rstrip("\r\n") != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\r\n") == "---":
            return i
    return None


def draft_lines(lines):
    """(index, value) of every draft: line inside the front matter."""
    end = front_matter_end(lines)
    if end is None:
        return []
    out = []
    for i in range(1, end):
        m = re.match(r"^draft:[ \t]*(\S*)[ \t]*$", lines[i].rstrip("\r\n"))
        if m:
            out.append((i, m.group(1).strip("\"'")))
        elif lines[i].startswith("draft:"):
            out.append((i, "?"))
    return out


def flip_draft(text):
    """The text with the front matter's single draft: true line set to draft: false; Refuse otherwise."""
    lines = text.splitlines(keepends=True)
    found = draft_lines(lines)
    if len(found) != 1:
        raise Refuse("expected exactly one draft: line in the front matter, found %d" % len(found))
    i, value = found[0]
    if value == "false":
        return text
    if value != "true":
        raise Refuse("the front matter has draft: %s; --set-draft-false only flips draft: true" % (value or "(empty)"))
    ending = lines[i][len(lines[i].rstrip("\r\n")):]
    lines[i] = "draft: false" + ending
    return "".join(lines)


def run_tool(argv, timeout, env=None):
    return subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout, env=env)


def emit(proc):
    for stream in (proc.stdout, proc.stderr):
        if stream:
            print(stream.rstrip("\n")[:6000])


def check_page(root, rel, require_published=False, build=False, hugo_arg=None):
    """Run every check step on one page, print one [ok] or [FAIL] line per step; return the failed step names."""
    real = os.path.realpath(root)
    failed = []

    def verdict(name, good, why=""):
        if good:
            print("[ok] %s%s" % (name, (" (" + why + ")") if why else ""))
        else:
            failed.append(name)
            print("[FAIL] %s%s" % (name, (": " + why) if why else ""))

    proc = run_tool([sys.executable, "-I", CHECKER, "--root", real, rel], 120)
    emit(proc)
    verdict("content", proc.returncode == 0)

    bundle = os.path.dirname(os.path.join(real, rel))
    pics = sorted(n for n in os.listdir(bundle) if n.lower().endswith(IMAGE_EXTS))
    if pics:
        proc = run_tool([sys.executable, "-I", os.path.join(HERE, "check-image-metadata.py"), bundle], 120)
        emit(proc)
        verdict("images", proc.returncode == 0, "" if proc.returncode == 0 else "metadata found or unreadable image")
    else:
        verdict("images", True, "no images in the bundle")

    text = read_page(root, rel)
    lines = text.splitlines()
    bad_dash = [(n, DASHES[c]) for n, line in enumerate(lines, 1) for c in line if c in DASHES]
    for n, kind in bad_dash[:20]:
        print("dashes: %s:%d: %s; write a comma, a colon, parentheses or a plain hyphen" % (rel, n, kind))
    verdict("dashes", not bad_dash, "%d dash character(s)" % len(bad_dash) if bad_dash else "")
    bad_word = [n for n, line in enumerate(lines, 1) if SHORT_FORM_RE.search(line)]
    for n in bad_word[:20]:
        print("wording: %s:%d: use the full word, never the short form" % (rel, n))
    verdict("wording", not bad_word, "%d line(s)" % len(bad_word) if bad_word else "")

    drafts = draft_lines(text.splitlines(keepends=True))
    is_draft = any(v != "false" for _, v in drafts)
    if is_draft:
        print("note: draft: true (the production build skips it; publish --set-draft-false makes it public)")
    verdict("draft", not (is_draft and require_published), "draft: true, but a published page is required" if is_draft and require_published else "")

    if build:
        hugo = find_hugo(root, hugo_arg)
        tmp = os.path.join(real, "tmp")
        os.makedirs(tmp, exist_ok=True)
        dest = tempfile.mkdtemp(prefix="author-build.", dir=tmp)
        try:
            env = {k: v for k, v in os.environ.items() if k != "HUGO_PARAMS_ENVIRONMENT"}
            proc = run_tool([hugo, "--minify", "--gc", "--destination", dest, "--source", real], 600, env)
            if proc.returncode != 0:
                print((proc.stdout + proc.stderr)[-2000:].rstrip())
            verdict("build", proc.returncode == 0, "" if proc.returncode == 0 else "hugo exited %d" % proc.returncode)
            if proc.returncode == 0:
                env["EXPECT_ENV"] = "production"
                proc = run_tool(["bash", os.path.join(HERE, "check-output.sh"), dest], 600, env)
                emit(proc)
                verdict("check-output", proc.returncode == 0)
        finally:
            shutil.rmtree(dest, ignore_errors=True)
    if failed:
        print("check: FAILED step(s): %s" % ", ".join(failed))
    else:
        print("check: all steps passed")
    return failed


# --- publish ---------------------------------------------------------------------------------------

ISSUE_RE = re.compile(r"^(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#?[1-9][0-9]{0,8}$")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
BASE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,100}$")


def git(root, *args, timeout=120):
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
    env["GIT_LITERAL_PATHSPECS"] = "1"
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        return subprocess.run(["git", "-C", os.path.realpath(root)] + list(args), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout, env=env)
    except FileNotFoundError:
        raise Refuse("git is not installed") from None


def git_ok(root, *args):
    proc = git(root, *args)
    if proc.returncode != 0:
        raise Refuse("git %s failed: %s" % (args[0], (proc.stderr or proc.stdout).strip()[:300]))
    return proc.stdout


def pr_body(root, issue, summary):
    ref = "Refs " + (issue if "#" in issue else "#" + issue)
    template = os.path.join(os.path.realpath(root), ".github", "PULL_REQUEST_TEMPLATE.md")
    text = None
    try:
        st = os.lstat(template)
        if stat.S_ISREG(st.st_mode) and st.st_size <= TEMPLATE_MAX:
            with open(template, encoding="utf-8") as f:
                text = f.read()
    except (OSError, UnicodeDecodeError):
        text = None
    if text is None:
        return summary + "\n\n" + ref + "\n"
    if re.search(r"(?m)^Refs #[ \t]*$", text):
        text = re.sub(r"(?m)^Refs #[ \t]*$", lambda _m: ref, text, count=1)
    else:
        text = text.rstrip("\n") + "\n\n" + ref + "\n"
    comment = "<!-- One or two sentences. -->"
    text = text.replace(comment, summary, 1) if comment in text else summary + "\n\n" + text
    return text


def publish(root, bundle_arg, issue, remote, base, gh_arg, set_draft_false, dry_run):
    if not ISSUE_RE.match(issue):
        raise Refuse("issue must look like 254, #254 or owner/repo#254, got %r" % issue[:40])
    if not NAME_RE.match(remote):
        raise Refuse("remote name %r is not a plain remote name" % remote[:40])
    if not BASE_RE.match(base):
        raise Refuse("base branch %r is not a plain branch name" % base[:40])
    gh = gh_arg if gh_arg else shutil.which("gh")
    if not gh or not os.path.isfile(gh) or not os.access(gh, os.X_OK):
        raise Refuse("gh is not installed (or %s is not executable); install the GitHub CLI and sign in, or pass --gh PATH" % (gh_arg or "none was found on PATH"))
    page = resolve_target(root, bundle_arg)
    if not page.endswith("/index.md"):
        raise Refuse("publish takes a page bundle (a folder with index.md), not %s" % page)
    bundle_rel = page[: -len("/index.md")]
    slug = bundle_rel.rsplit("/", 1)[-1]
    if not SLUG_RE.match(slug):
        raise Refuse("the bundle folder name %r is not a lowercase slug" % slug[:60])
    # git state
    top = git(root, "rev-parse", "--show-toplevel")
    if top.returncode != 0 or os.path.realpath(top.stdout.strip()) != os.path.realpath(root):
        raise Refuse("%s is not the top of a git work tree" % root)
    if remote not in git_ok(root, "remote").split():
        raise Refuse("remote %r is not configured in this repository" % remote)
    cur = git(root, "symbolic-ref", "-q", "--short", "HEAD")
    branch = cur.stdout.strip()
    if cur.returncode != 0 or not branch:
        raise Refuse("detached HEAD: switch to a branch for this change first (git switch -c post/%s)" % slug)
    new_branch = "post/" + slug
    if git(root, "rev-parse", "--verify", "-q", "refs/heads/" + new_branch).returncode == 0:
        raise Refuse("the branch %s already exists locally; delete it or pick another folder name" % new_branch)
    listed = git(root, "ls-remote", "--heads", remote, "refs/heads/" + new_branch, timeout=120)
    if listed.returncode != 0:
        raise Refuse("could not ask %s about branches: %s" % (remote, (listed.stderr or listed.stdout).strip()[:200]))
    if listed.stdout.strip():
        raise Refuse("the branch %s already exists on %s; delete it or pick another folder name" % (new_branch, remote))
    status = git_ok(root, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames")
    outside = [e[3:] for e in status.split("\0") if e and not e[3:].startswith(bundle_rel + "/")]
    if outside:
        raise Refuse("the tree is dirty outside the bundle (%s%s); commit or stash it first" % (", ".join(outside[:5]), ", ..." if len(outside) > 5 else ""))
    real_bundle = os.path.join(os.path.realpath(root), bundle_rel)
    for dirpath, dirnames, filenames in os.walk(real_bundle):
        for n in dirnames + filenames:
            m = os.lstat(os.path.join(dirpath, n)).st_mode
            if not (stat.S_ISREG(m) or stat.S_ISDIR(m)):
                raise Refuse("%s/%s is a symlink or special file; the bundle may hold regular files only" % (os.path.relpath(dirpath, os.path.realpath(root)), n))
    original = read_page(root, page)
    print("publish %s from branch %s to a new branch %s" % (bundle_rel, branch, new_branch))
    failed = check_page(root, page)
    if failed:
        raise Refuse("the check failed (%s); nothing was committed" % ", ".join(failed))
    flipped = False
    if set_draft_false:
        new_text = flip_draft(original)
        if new_text != original:
            if dry_run:
                print("dry run: would set draft: false")
            else:
                write_page(root, page, new_text)
                flipped = True
                failed = check_page(root, page, require_published=True)
                if failed:
                    write_page(root, page, original)
                    raise Refuse("the check failed after draft: false (%s); the page was restored" % ", ".join(failed))
    is_public = set_draft_false or not any(v != "false" for _, v in draft_lines(original.splitlines(keepends=True)))
    title = ("Publish %s" if is_public else "Add draft %s") % slug
    summary = "Adds %s with scripts/author.py publish. Check steps passed: %s. Draft: %s." % (
        bundle_rel, ", ".join(CHECK_STEPS), "false" if is_public else "true",
    )
    if dry_run:
        print("dry run: would create branch %s, commit %s, push it to %s and open a pull request against %s (%s). Nothing was changed." % (new_branch, bundle_rel, remote, base, title))
        return 0
    made_branch = False
    committed = False
    try:
        git_ok(root, "switch", "-q", "-c", new_branch)
        made_branch = True
        git_ok(root, "add", "--", bundle_rel)
        staged = [x for x in git_ok(root, "diff", "--cached", "--name-only", "-z").split("\0") if x]
        if not staged:
            raise Refuse("nothing to publish: %s has no changes against HEAD (if it is already committed, push the branch and open the pull request yourself)" % bundle_rel)
        if any(not x.startswith(bundle_rel + "/") for x in staged):
            raise Refuse("the index holds files outside the bundle; nothing was committed")
        git_ok(root, "commit", "-q", "-m", title)
        committed = True
        refspec = "refs/heads/%s:refs/heads/%s" % (new_branch, new_branch)
        pushed = git(root, "push", remote, refspec, timeout=300)
        if pushed.returncode != 0:
            raise Refuse("git push failed: %s" % (pushed.stderr or pushed.stdout).strip()[:300])
        argv = [gh, "pr", "create", "--base", base, "--head", new_branch, "--title", title, "--body", pr_body(root, issue, summary)]
        try:
            made = subprocess.run(argv, cwd=os.path.realpath(root), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120)
        except subprocess.TimeoutExpired:
            raise Refuse("gh timed out; the branch %s is pushed, open the pull request by hand" % new_branch) from None
        if made.returncode != 0:
            raise Refuse("gh failed (exit %d: %s); the branch %s is pushed, open the pull request by hand" % (made.returncode, (made.stderr or made.stdout).strip()[:200], new_branch))
    except BaseException:
        if made_branch:
            if committed:
                git(root, "reset", "-q", "--mixed", "HEAD~1")  # keep the files, drop the commit
            else:
                git(root, "reset", "-q", "--", bundle_rel)
            git(root, "switch", "-q", branch)
            git(root, "branch", "-q", "-D", new_branch)
        if flipped:
            write_page(root, page, original)
        raise
    back = git(root, "switch", "-q", branch)
    if back.returncode != 0:
        raise Refuse("the pull request is open, but switching back to %s failed: %s" % (branch, back.stderr.strip()[:200]))
    print("pushed branch %s to %s and returned to %s; the helper never merges" % (new_branch, remote, branch))
    print(made.stdout.strip())
    return 0


def write_page(root, rel, text):
    """Replace a page through a temporary file in its folder; the original stays until the swap."""
    dest = os.path.join(os.path.realpath(root), rel)
    tmp = dest + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp, dest)
    except BaseException:
        if os.path.lexists(tmp):
            os.unlink(tmp)
        raise



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
    pv = sub.add_parser("preview", help="serve the site with drafts on 127.0.0.1 only")
    pv.add_argument("--host", default=LOOPBACK)
    pv.add_argument("--port", type=int)
    pv.add_argument("--hugo", help="path to the pinned hugo binary (default: hugo on PATH)")
    pv.add_argument("--no-drafts", action="store_true", help="do not show drafts (default: drafts are shown)")
    c = sub.add_parser("check", help="run every check step on a file or bundle")
    c.add_argument("path")
    c.add_argument("--require-published", action="store_true", help="fail when the page is still a draft")
    c.add_argument("--build", action="store_true", help="also run the production build and scripts/check-output.sh")
    c.add_argument("--hugo", help="path to the pinned hugo binary for --build (default: hugo on PATH)")
    pb = sub.add_parser("publish", help="commit a bundle on the current branch, push it and open a pull request")
    pb.add_argument("bundle")
    pb.add_argument("--issue", required=True, help="the issue to link: 254, #254 or owner/repo#254")
    pb.add_argument("--remote", default="origin")
    pb.add_argument("--base", default="main", help="the branch the pull request targets (default: main)")
    pb.add_argument("--gh", help="path to the gh binary (default: gh on PATH)")
    pb.add_argument("--set-draft-false", action="store_true", help="set draft: false in the front matter")
    pb.add_argument("--dry-run", action="store_true", help="run the checks and print the plan; change nothing")
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
        if args.cmd == "preview":
            return preview(args.root, args.host, args.port, args.hugo, not args.no_drafts)
        if args.cmd == "img":
            print(add_image(args.root, args.bundle, args.file, args.alt, args.name, args.featured))
            return 0
        if args.cmd == "publish":
            return publish(args.root, args.bundle, args.issue, args.remote, args.base, args.gh, args.set_draft_false, args.dry_run)
        rel = resolve_target(args.root, args.path)
        return 1 if check_page(args.root, rel, args.require_published, args.build, args.hugo) else 0
    except Refuse as e:
        print("author: %s" % e, file=sys.stderr)
        return 1
    except subprocess.TimeoutExpired:
        print("author: a step timed out", file=sys.stderr)
        return 1
    except OSError as e:
        print("author: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
