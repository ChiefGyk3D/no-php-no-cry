#!/usr/bin/env python3
"""Check the Markdown and the bundle images that a change adds under content/ (stdlib only).

Usage: python3 -I scripts/check-content.py [options] [file ...]

  (no files)          every file under content/ changed against the base (see --base)
  file ...            exactly those files (paths relative to --root; others are ignored)
  --all               every file under content/ (existing posts may have findings; see docs)
  --base REF          diff base. Default: the merge base with origin/main, else HEAD^1 (CI
                      checks out a pull request as a merge commit, so HEAD^1 is its base)
  --root DIR          the repository root (default: this repository)
  --json              print one JSON object instead of text
  --terms-file FILE   guard terms, one category:term per line (the SCRUB_TERMS format in
                      docs/scrub-terms.md). The same text in the SCRUB_TERMS environment
                      variable works too. Terms are never printed.
  --max-image-bytes N size cap for one bundle image (default 5 MiB)

Errors print as "rule: path: message", then one summary line. Exit 0 clean, 1 on any error,
2 on a usage problem. No network, no YAML library: the front matter is read with a small
strict parser for the subset the repository uses (anything else is an error, never guessed).
Everything read is bounded: files over 1 MiB, front matter over 64 KiB or 400 lines, and
anything that is not a regular file (a symlink, a FIFO) are rejected before they are parsed.

Rules (the id is the first word of an error):
  encoding        the file is not UTF-8
  size            a file is over its cap
  file-type       a file under content/ that is neither Markdown nor an allowed image
  front-matter    missing, unterminated or not in the supported YAML subset
  title date description draft tags
                  required fields and their shape (description: posts only, 1 to 160 chars)
  image-alt       `image` is set on a published page without a real `imageAlt`
  inline-alt      an inline image on a published page has empty, filename or placeholder alt
  image-remote    an inline or headline image that is not a regular file inside the page folder
                  (remote, absolute, ../ and missing files all fail)
  unsafe-link     a javascript:, vbscript: or data: link
  raw-html        script, iframe, object, embed or style tags, or an on*= event handler
  guard-word      an employer-name guard word or a scrub term (the word is never printed)
  todo            a TODO or FIXME marker on a published page
  image-name      a bundle image name that is not a lowercase safe name
  image-type      a bundle image that is not WebP, JPEG, PNG or a plain SVG
  image-svg       an SVG outside the allowlist; the finding starts with a [svg-...] code (svg_findings)
  image-metadata  EXIF, GPS, XMP or IPTC data (scripts/check-image-metadata.py does the reading)
  image-size      a bundle image over the byte cap
  image-dimensions a bundle image over 10000 px a side or 64 megapixels, or one whose size cannot be read
  image-unreferenced a bundle image its page never uses (image: or an inline image)
  slug            a post or journal entry without a lowercase-hyphen slug
  brand-asset     a bundle image missing from brand/approved-assets.txt or with another sha256
                  (scripts/check-brand-assets.sh does the checking)
"""
import html
import importlib.util
import json
import os
import re
import stat
import struct
import subprocess
import sys
from datetime import date, datetime
from urllib.parse import unquote

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(HERE)

MD_MAX = 1024 * 1024
FM_MAX_BYTES = 64 * 1024
FM_MAX_LINES = 400
IMAGE_MAX = 5 * 1024 * 1024
# Decode and resize cost grows with pixels, not bytes: a small, highly compressed file can be huge.
MAX_SIDE = 10000
MAX_PIXELS = 64 * 1000 * 1000
ALLOWED_IMAGES = {".webp", ".jpg", ".jpeg", ".png", ".svg"}
DESC_MAX = 160
ALT_MAX = 2000
MAX_FILES = 5000

# Employer-name guard words the repository already holds (scripts/test-resume.sh, "guard word").
# Matched case-sensitively on word boundaries; never printed.
GUARD_WORDS = ("ITIL", "LPI", "Western Governors")

SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
IMAGE_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")
DATE_RE = re.compile(
    r"^(\d{4})-(\d{2})-(\d{2})(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?\s*(?:[Zz]|[+-]\d{2}(?::?\d{2})?)?)?$"
)
PLACEHOLDER_ALT = re.compile(
    r"^(?:todo\b.*|fixme\b.*|tbd|tba|xxx|alt|alt text|image|img|photo|picture|pic|screenshot|"
    r"placeholder\b.*|untitled|describe\b.*|n/?a|none|null|\.+|-+|_+)$",
    re.I,
)
FILENAME_ALT = re.compile(r"^\S+\.(?:png|jpe?g|webp|gif|avif|svg|bmp|tiff?|heic)$", re.I)
CAMERA_ALT = re.compile(r"^(?:img|dsc|dscn|pxl|image|screenshot|photo|pic)[-_ ]?[0-9][-_0-9a-z ]*$", re.I)
TODO_RE = re.compile(r"\b(?:TODO|FIXME)\b")
HTML_BAD = re.compile(r"<\s*/?\s*(?:script|iframe|object|embed|style)\b", re.I)
HTML_HANDLER = re.compile(r"<[a-z][^<>]{0,2000}?[\s\"'/]on[a-z]{3,}\s*=", re.I)
LINK_CTX = re.compile(
    r"(?=(?:\]\(|\]:|<|\bhref\s*=|\bsrc\s*=|\baction\s*=|\bformaction\s*=)[\s\"'<]{0,8}([^\n]{0,60}))", re.I
)
BAD_SCHEMES = ("javascript:", "vbscript:", "data:")
STRIP_CTRL = re.compile(r"[\x00-\x20\x7f-\x9f​-‏  ⁠﻿]")


class FMError(Exception):
    pass


# --- front matter: a strict subset of YAML --------------------------------------------------

MAP = {"__opaque__": "map"}  # marker for a nested map the checks do not read
SPECIALS = ("&", "*", "!", "@", "`", "%")


def _strip_comment(s):
    """Drop a trailing ` # comment` from a plain scalar."""
    m = re.search(r"\s#", s)
    return s[: m.start()] if m else s


def _quoted(s):
    """Parse a leading quoted scalar; return (value, rest). Raise FMError when unterminated."""
    q = s[0]
    i = 1
    n = len(s)
    if q == '"':
        while i < n:
            if s[i] == "\\":
                i += 2
                continue
            if s[i] == '"':
                break
            i += 1
        if i >= n:
            raise FMError("unterminated double quote")
        try:
            val = json.loads(s[: i + 1])
        except ValueError:
            raise FMError("unsupported escape in double-quoted text") from None
        return val, s[i + 1 :]
    out = []
    while i < n:
        if s[i] == "'":
            if i + 1 < n and s[i + 1] == "'":
                out.append("'")
                i += 2
                continue
            return "".join(out), s[i + 1 :]
        out.append(s[i])
        i += 1
    raise FMError("unterminated single quote")


def _tail_ok(rest):
    rest = rest.strip()
    return rest == "" or rest.startswith("#")


def _scalar(s):
    s = s.strip()
    if s == "":
        return ""
    c = s[0]
    if c in SPECIALS:
        raise FMError("anchors, aliases, tags and directives are not allowed")
    if c in "\"'":
        val, rest = _quoted(s)
        if not _tail_ok(rest):
            raise FMError("text after a closing quote")
        return val
    s = _strip_comment(s).strip()
    low = s.lower()
    if low in ("true", "false"):
        return low == "true"
    if low in ("null", "~", ""):
        return None
    return s


def _flow_list(s):
    """Parse [a, "b", 'c'] into a list of scalars. Nested flow collections are opaque errors."""
    s = s.strip()
    body = s
    # drop a trailing comment after the closing bracket
    depth_end = None
    i, n, q = 1, len(s), None
    items, cur = [], []
    while i < n:
        ch = s[i]
        if q:
            cur.append(ch)
            if q == '"' and ch == "\\" and i + 1 < n:
                cur.append(s[i + 1])
                i += 1
            elif ch == q:
                q = None
        elif ch in "\"'":
            q = ch
            cur.append(ch)
        elif ch in "[{":
            raise FMError("nested flow collections are not supported")
        elif ch == ",":
            items.append("".join(cur))
            cur = []
        elif ch == "]":
            depth_end = i
            break
        else:
            cur.append(ch)
        i += 1
    if depth_end is None:
        raise FMError("unterminated [ list (lists must close on the same line)")
    if not _tail_ok(body[depth_end + 1 :]):
        raise FMError("text after a closing ]")
    last = "".join(cur)
    if last.strip() != "" or items:
        items.append(last)
    out = []
    for it in items:
        if it.strip() == "":
            raise FMError("empty list item")
        out.append(_scalar(it))
    return out


def parse_front_matter(lines):
    """Parse the front matter lines (no fences) into a dict. Raise FMError on anything odd."""
    data = {}
    i, n = 0, len(lines)
    for k, ln in enumerate(lines, 1):
        if "\t" in ln[: len(ln) - len(ln.lstrip())]:
            raise FMError("line %d: tab indentation" % k)
    while i < n:
        raw = lines[i]
        i += 1
        if raw.strip() == "" or raw.lstrip().startswith("#"):
            continue
        if raw[0] in " -":
            raise FMError("line %d: unexpected indented text" % i)
        key, sep, val = raw.partition(":")
        if not sep or not KEY.match(key):
            raise FMError("line %d: expected key: value" % i)
        if key in data:
            raise FMError("line %d: duplicate key %s" % (i, key))
        if len(data) >= 200:
            raise FMError("too many keys")
        if val.strip() != "" and not val.startswith(" "):
            raise FMError("line %d: a space is needed after the colon" % i)
        v = val.strip()
        # Continuation lines: indented lines, or `- ` items at column 0 for a block list.
        cont = []
        while i < n and (lines[i].strip() == "" or lines[i][0] in " \t" or lines[i].startswith("- ") or lines[i] == "-"):
            cont.append(lines[i])
            i += 1
        while cont and cont[-1].strip() == "":
            cont.pop()
        nonblank = [c for c in cont if c.strip() != "" and not c.lstrip().startswith("#")]
        if v[:1] in ("|", ">"):
            if not re.match(r"^[|>][+-]?\d?\s*(#.*)?$", v):
                raise FMError("line %d: unsupported block scalar header" % i)
            data[key] = (" " if v[0] == ">" else "\n").join(c.strip() for c in nonblank)
        elif v[:1] == "[":
            if nonblank:
                raise FMError("line %d: text after a one-line list" % i)
            data[key] = _flow_list(v)
        elif v[:1] == "{":
            if not re.search(r"\}\s*(#.*)?$", v) or nonblank:
                raise FMError("line %d: unterminated { map" % i)
            data[key] = MAP
        elif v == "" or v.startswith("#"):
            if not nonblank:
                data[key] = None
            elif nonblank[0].lstrip().startswith("- "):
                items = []
                for c in nonblank:
                    t = c.strip()
                    if t.startswith("- "):
                        body = t[2:].strip()
                        if re.match(r"^[A-Za-z_][\w-]*:\s", body + " ") and body[:1] not in "\"'":
                            items.append(MAP)
                        else:
                            items.append(_scalar(body))
                    elif t == "-":
                        raise FMError("line %d: empty list item" % i)
                    elif c[0] in " \t" and items:
                        items.append(MAP)  # a map item continued on its own lines
                data[key] = items
            else:
                data[key] = MAP
        else:
            if nonblank:
                # a plain scalar continued on the next lines
                if v[:1] in "\"'":
                    raise FMError("line %d: a quoted value must close on its own line" % i)
                v = v + " " + " ".join(c.strip() for c in nonblank)
            data[key] = _scalar(v)
    return data


def split_front_matter(text):
    """Return (front matter lines, body text, body first line number)."""
    if text.startswith("﻿"):
        text = text[1:]
    lines = text.split("\n")
    if lines and lines[0].rstrip("\r") == "+++":
        raise FMError("TOML front matter (+++) is not supported; use YAML between --- lines")
    if not lines or lines[0].rstrip("\r") != "---":
        raise FMError("the file must start with a --- line")
    fm = []
    for idx in range(1, len(lines)):
        ln = lines[idx].rstrip("\r")
        if ln in ("---", "..."):
            body = "\n".join(lines[idx + 1 :])
            return fm, body, idx + 2
        fm.append(ln)
        if len(fm) > FM_MAX_LINES:
            raise FMError("front matter is over %d lines" % FM_MAX_LINES)
        if sum(len(x) for x in fm) > FM_MAX_BYTES:
            raise FMError("front matter is over %d bytes" % FM_MAX_BYTES)
    raise FMError("the front matter is not closed by a --- line")


# --- body helpers -------------------------------------------------------------------------


def strip_fences(body):
    """Remove fenced code blocks (``` or ~~~). An unclosed fence runs to the end, as in CommonMark."""
    out, fence = [], None
    for ln in body.split("\n"):
        m = re.match(r"^ {0,3}(`{3,}|~{3,})", ln)
        if fence is None:
            if m:
                fence = m.group(1)[0] * len(m.group(1))
                out.append("")
                continue
            out.append(ln)
        else:
            out.append("")
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and ln.strip().strip(fence[0]) == "":
                fence = None
    return "\n".join(out)


def strip_code_spans(text):
    # Runs of 1 to 10 backticks; a longer run is left alone. Bounded: no quadratic backtracking.
    return re.sub(r"(?<!`)(`{1,10})(?!`)[^`\n]{0,2000}?(?<!`)\1(?!`)", " ", text)


def strip_comments(text):
    """Remove terminated <!-- --> comments in one linear pass; an unterminated one is kept (stricter)."""
    out, pos = [], 0
    while True:
        i = text.find("<!--", pos)
        if i < 0:
            break
        j = text.find("-->", i + 4)
        if j < 0:
            break
        out.append(text[pos:i])
        pos = j + 3
    out.append(text[pos:])
    return "".join(out)


def scan_images(text):
    """Yield (alt, destination or None) for every inline or reference image. Bounded, bracket aware."""
    refs = {}
    for m in re.finditer(r"(?m)^ {0,3}\[([^\]\n]{1,200})\]:[ \t]*<?([^\s>]{1,2000})", text):
        refs.setdefault(m.group(1).strip().lower(), m.group(2))
    pos, n, seen = 0, len(text), 0
    while True:
        i = text.find("![", pos)
        if i < 0:
            return
        seen += 1
        if seen > 5000:
            yield "", None  # bounded: more image markers than any real page
            return
        j, depth = i + 2, 1
        limit = min(n, i + 2 + ALT_MAX)
        while j < limit and depth:
            ch = text[j]
            if ch == "\\":
                j += 2
                continue
            if ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
            j += 1
        if depth:
            yield text[i + 2 : limit], None  # no closing bracket within bounds
            pos = i + 2
            continue
        alt = text[i + 2 : j - 1]
        rest = text[j : j + ALT_MAX]
        dest = None
        if rest.startswith("("):
            m = re.match(r"\(\s*<?([^\s)>]*)", rest)
            dest = m.group(1) if m else ""
        elif rest.startswith("["):
            m = re.match(r"\[([^\]\n]*)\]", rest)
            label = (m.group(1) if m and m.group(1) else alt).strip().lower()
            dest = refs.get(label, "")
        else:
            dest = refs.get(alt.strip().lower())
        yield alt, dest
        pos = j


def alt_problem(alt, dest):
    a = re.sub(r"[*_`\[\]]", "", alt).strip()
    if a == "":
        return "alt text is empty"
    if len(a) > ALT_MAX:
        return "alt text is too long"
    if PLACEHOLDER_ALT.match(a) or re.search(r"\b(?:TODO|FIXME)\b", a):
        return "alt text is a placeholder"
    if FILENAME_ALT.match(a) or CAMERA_ALT.match(a):
        return "alt text is a file name"
    base = os.path.basename((dest or "").split("?")[0].split("#")[0])
    stem = os.path.splitext(base)[0]
    if base and a.lower() in (base.lower(), stem.lower()):
        return "alt text is the file name"
    if len(a) < 3:
        return "alt text is too short to describe an image"
    return None


def bundle_path(page_dir, dest):
    """The repository-relative path of a page-bundle file named by dest, or None when dest
    is remote, absolute, backslashed or climbs out of the page folder."""
    d = unquote((dest or "").split("#")[0].split("?")[0]).strip()
    if not d or d.startswith("/") or "\\" in d or "\x00" in d or is_remote(d):
        return None
    n = os.path.normpath(d)
    if n == "." or n == ".." or n.startswith("../"):
        return None
    return page_dir + "/" + n.replace(os.sep, "/")


def is_remote(dest):
    return bool(re.match(r"^(?:[a-z][a-z0-9+.-]*:|//)", dest or "", re.I))


def image_dimensions(b, ext):
    """(width, height) from the header of a PNG, JPEG or WebP, or None. Reads headers only."""
    try:
        if ext == ".png" and b[:8] == bytes([0x89]) + b"PNG\r\n" + bytes([0x1A, 0x0A]) and b[12:16] == b"IHDR":
            return struct.unpack(">II", b[16:24])
        if ext in (".jpg", ".jpeg") and b[:2] == bytes([0xFF, 0xD8]):
            i = 2
            while i + 4 <= len(b):
                if b[i] != 0xFF:
                    return None
                m = b[i + 1]
                if m == 0xFF:
                    i += 1
                    continue
                if 0xD0 <= m <= 0xD8 or m == 0x01:
                    i += 2
                    continue
                n = struct.unpack(">H", b[i + 2 : i + 4])[0]
                if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    h, w = struct.unpack(">HH", b[i + 5 : i + 9])
                    return (w, h)
                if m in (0xDA, 0xD9):
                    return None
                i += 2 + n
        if ext == ".webp" and b[:4] == b"RIFF" and b[8:12] == b"WEBP":
            i = 12
            while i + 8 <= len(b):
                kind = b[i : i + 4]
                size = struct.unpack("<I", b[i + 4 : i + 8])[0]
                body = b[i + 8 : i + 8 + size]
                if kind == b"VP8X" and len(body) >= 10:
                    return (1 + int.from_bytes(body[4:7], "little"), 1 + int.from_bytes(body[7:10], "little"))
                if kind == b"VP8L" and len(body) >= 5 and body[0] == 0x2F:
                    v = int.from_bytes(body[1:5], "little")
                    return ((v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1)
                if kind == b"VP8 " and len(body) >= 10 and body[3:6] == bytes([0x9D, 0x01, 0x2A]):
                    return (struct.unpack("<H", body[6:8])[0] & 0x3FFF, struct.unpack("<H", body[8:10])[0] & 0x3FFF)
                i += 8 + size + (size & 1)
    except (struct.error, IndexError):
        return None
    return None


# --- terms -----------------------------------------------------------------------------------


def load_terms(path):
    """Return a list of (category, casefolded term). Never raises with term content."""
    text = None
    if path:
        try:
            with open(path, "rb") as fh:
                text = fh.read(256 * 1024).decode("utf-8")
        except (OSError, UnicodeDecodeError):
            raise SystemExit("check-content: cannot read the terms file")
    elif os.environ.get("SCRUB_TERMS"):
        text = os.environ["SCRUB_TERMS"]
    out = []
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        cat, sep, term = line.partition(":")
        if sep and term.strip() and cat.strip().lower() in ("employer", "hostname", "serial"):
            out.append((cat.strip().lower(), term.strip().casefold()))
    return out


def guard_hits(text, terms):
    cats = []
    for w in GUARD_WORDS:
        if re.search(r"\b" + re.escape(w) + r"\b", text):
            cats.append("employer")
    low = text.casefold()
    for cat, term in terms:
        if term in low:
            cats.append(cat)
    return sorted(set(cats))


# --- the checker ---------------------------------------------------------------------------------


SVG_NS = "http://www.w3.org/2000/svg"
SVG_ELEMENTS = {
    "svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan", "title", "desc",
    "defs", "marker", "linearGradient", "radialGradient", "stop",
}
SVG_ATTRIBUTES = {
    "id", "viewBox", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry", "d", "points",
    "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-dasharray", "stroke-linecap",
    "stroke-linejoin", "stroke-opacity", "opacity", "transform", "font-family", "font-size", "font-weight",
    "font-style", "text-anchor", "dominant-baseline", "letter-spacing", "paint-order", "role", "aria-label",
    "aria-labelledby", "aria-hidden", "marker-start", "marker-mid", "marker-end", "markerWidth", "markerHeight",
    "markerUnits", "refX", "refY", "orient", "offset", "stop-color", "stop-opacity", "gradientUnits",
    "gradientTransform", "fx", "fy", "preserveAspectRatio", "style", "version",
}
SVG_VALUE_BAD = re.compile(r"(?i)\b(?:javascript|vbscript|data):|https?:|//|@import|expression\s*\(|" + re.escape(chr(92)))
SVG_URL_FUNC = re.compile(r"(?i)url\s*\(\s*([^)]*)\)")
SVG_LOCAL_REF = re.compile(r"^['\"]?#[A-Za-z_][A-Za-z0-9_.-]*['\"]?$")
SVG_TEXT_BAD = re.compile(r"(?i)\b[a-z][a-z0-9+.-]*:[^\s]|//[a-z0-9]|\bwww\.")
SVG_XML_DECL = re.compile(r"^<\?xml\s[^>]*\?>")
SVG_BOMS = (b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff", b"\x00\x00\xfe\xff")


def svg_findings(data):
    """Reasons an SVG is not a plain, inert picture (issue 352), each as "[code] detail".

    An allowlist: UTF-8 only; no DOCTYPE, entity, comment, CDATA or processing
    instruction other than a leading xml declaration; SVG-namespace elements from a
    fixed set; attributes from a fixed set; no href of any spelling, event handler or
    external reference in an attribute, a style or a text node. The byte and text scans
    run before the parser, and stop the check at the first failing stage, so a parser
    difference cannot hide content from them.
    """
    import xml.etree.ElementTree as ET

    if data.startswith(SVG_BOMS) or b"\x00" in data:
        return ["[svg-encoding] has a byte order mark or a NUL byte (UTF-8 without a mark only)"]
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return ["[svg-encoding] is not valid UTF-8"]
    found = []
    m = SVG_XML_DECL.match(text)
    decl = m.group(0) if m else ""
    enc = re.search(r"encoding\s*=\s*[\"']([^\"']*)", decl)
    if enc and enc.group(1).lower() not in ("utf-8", "utf8"):
        return ["[svg-encoding] declares the encoding %s" % enc.group(1)]
    body = text[len(decl) :]
    if "<?" in body:
        found.append("[svg-pi] has a processing instruction other than the leading xml declaration")
    if "<!--" in text:
        found.append("[svg-comment] has a comment")
    if "<![CDATA[" in text:
        found.append("[svg-cdata] has a CDATA section")
    if re.search(r"(?i)<!(doctype|entity)", text):
        found.append("[svg-doctype] has a DOCTYPE or entity declaration")
    for _prefix, uri in re.findall(r"xmlns(?::([\w.-]+))?\s*=\s*[\"']([^\"']*)[\"']", text):
        if uri != SVG_NS:
            found.append("[svg-namespace] declares the namespace %s" % uri)
    if found:
        return sorted(set(found))
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return ["[svg-parse] is not well-formed XML"]
    if root.tag != "{%s}svg" % SVG_NS:
        found.append("[svg-element] the root element is not an SVG-namespace svg")
    for el in root.iter():
        if el.tag.startswith("{"):
            ns, _, name = el.tag[1:].partition("}")
        else:
            ns, name = "", el.tag
        if ns != SVG_NS:
            found.append("[svg-namespace] element <%s> is not in the SVG namespace" % name)
        elif name not in SVG_ELEMENTS:
            found.append("[svg-element] <%s> is not an allowed element" % name)
        for k, v in el.attrib.items():
            if k.startswith("{"):
                kns, _, kname = k[1:].partition("}")
            else:
                kns, kname = "", k
            low = kname.lower()
            if low == "href":
                found.append("[svg-href] has a href attribute")
            elif low.startswith("on"):
                found.append("[svg-event-handler] has the %s attribute" % kname)
            elif kns or kname not in SVG_ATTRIBUTES:
                found.append("[svg-attribute] %s is not an allowed attribute" % kname)
            if SVG_VALUE_BAD.search(v):
                found.append("[svg-external-ref] attribute %s has an external or script reference" % kname)
            for ref in SVG_URL_FUNC.findall(v):
                if not SVG_LOCAL_REF.match(ref.strip()):
                    found.append("[svg-external-ref] attribute %s has a url() that is not a local #id" % kname)
        for t in (el.text, el.tail):
            if t and SVG_TEXT_BAD.search(t):
                found.append("[svg-external-ref] text has a URL, a scheme or a protocol-relative reference")
    if "viewBox" not in root.attrib:
        found.append("[svg-viewbox] has no viewBox")
    return sorted(set(found))


class Checker:
    def __init__(self, root, max_image, terms):
        self.root = root
        self.max_image = max_image
        self.terms = terms
        self.errors = []
        self.md = 0
        self.images = []
        self.refs = {}
        spec = importlib.util.spec_from_file_location("check_image_metadata", os.path.join(HERE, "check-image-metadata.py"))
        self.meta = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.meta)

    def err(self, rule, path, msg):
        self.errors.append({"rule": rule, "path": path, "message": msg})

    def read(self, rel, cap, size_rule="size"):
        """Bytes of a regular, non-symlink file within the cap, else None (an error is recorded)."""
        full = os.path.join(self.root, rel)
        try:
            st = os.lstat(full)
        except OSError:
            self.err("file-type", rel, "cannot be read")
            return None
        if stat.S_ISLNK(st.st_mode):
            self.err("file-type", rel, "is a symbolic link")
            return None
        if not stat.S_ISREG(st.st_mode):
            self.err("file-type", rel, "is not a regular file")
            return None
        if st.st_size > cap:
            self.err(size_rule, rel, "%d bytes, limit %d" % (st.st_size, cap))
            return None
        try:
            with open(full, "rb") as fh:
                return fh.read(cap + 1)[:cap]
        except OSError:
            self.err("file-type", rel, "cannot be read")
            return None

    def check_file(self, rel):
        ext = os.path.splitext(rel)[1].lower()
        if ext == ".md":
            self.check_markdown(rel)
        elif ext in ALLOWED_IMAGES or ext in (".gif", ".avif", ".heic", ".bmp", ".tif", ".tiff"):
            self.check_image(rel, ext)
        else:
            self.err("file-type", rel, "only Markdown and WebP, JPEG, PNG or SVG images belong under content/")

    # -- Markdown --
    def check_markdown(self, rel, count=True):
        if count:
            self.md += 1
        raw = self.read(rel, MD_MAX)
        if raw is None:
            return
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            self.err("encoding", rel, "is not valid UTF-8")
            return
        if "\x00" in text:
            self.err("encoding", rel, "contains a NUL byte")
            return
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        try:
            fm_lines, body, _ = split_front_matter(text)
            fm = parse_front_matter(fm_lines)
        except FMError as e:
            self.err("front-matter", rel, str(e))
            return
        is_index = os.path.basename(rel) == "_index.md"
        parts = rel.split("/")
        is_post = len(parts) >= 3 and parts[1] == "posts" and not is_index
        draft = fm.get("draft")
        if "draft" in fm and not isinstance(draft, bool):
            self.err("draft", rel, "draft must be true or false (unquoted)")
        published = draft is not True

        # required fields
        title = fm.get("title")
        if not is_index and (not isinstance(title, str) or not title.strip()):
            self.err("title", rel, "title is required and must be non-empty text")
        if len(parts) >= 3 and parts[1] in ("posts", "journal") and not is_index:
            self.check_date(rel, fm.get("date"))
            slug = fm.get("slug")
            if not isinstance(slug, str) or not SLUG.match(slug):
                self.err("slug", rel, "slug is required: lowercase words joined by single hyphens (a-z, 0-9)")
        if is_post:
            d = fm.get("description")
            if not isinstance(d, str) or not d.strip():
                self.err("description", rel, "description is required and must be non-empty text")
            elif len(d.strip()) > DESC_MAX:
                self.err("description", rel, "description is %d characters, at most %d" % (len(d.strip()), DESC_MAX))
        if "tags" in fm:
            tags = fm["tags"]
            if tags is None:
                pass
            elif not isinstance(tags, list) or any(not isinstance(t, str) for t in tags):
                self.err("tags", rel, "tags must be a list of text values")
            else:
                for t in tags:
                    if not SLUG.match(t):
                        self.err("tags", rel, "tag %r is not a lowercase slug (a-z, 0-9, single hyphens)" % t[:60])
        # headline image
        img = fm.get("image")
        if img not in (None, "") and published:
            alt = fm.get("imageAlt")
            if not isinstance(alt, str) or not alt.strip():
                self.err("image-alt", rel, "image is set but imageAlt is missing or empty")
            else:
                prob = alt_problem(alt, img if isinstance(img, str) else "")
                if prob:
                    self.err("image-alt", rel, "imageAlt: " + prob)
        page_dir = os.path.dirname(rel)
        refs = self.refs.setdefault(page_dir, set())
        if isinstance(img, str) and img.strip():
            bp = bundle_path(page_dir, img)
            if bp:
                refs.add(bp)
            if published and not (bp and self.is_bundle_file(bp)):
                self.err("image-remote", rel, "image must name a file inside the page folder")

        # body rules
        whole = text
        hits = guard_hits(whole, self.terms) + guard_hits(rel, self.terms)
        for cat in sorted(set(hits)):
            self.err("guard-word", rel, "contains a %s guard term (not shown)" % cat)

        nofence = strip_fences(body)
        if published and TODO_RE.search(strip_fences(text)):
            self.err("todo", rel, "a TODO or FIXME marker is still in a published page")
        visible = strip_comments(nofence).replace("\x00", "")
        visible = strip_code_spans(visible)
        if HTML_BAD.search(visible) or HTML_HANDLER.search(visible):
            self.err("raw-html", rel, "raw script, embed or event-handler HTML is not allowed")
        norm = html.unescape(visible)
        for m in LINK_CTX.finditer(norm):
            tgt = STRIP_CTRL.sub("", m.group(1)).lower()
            if tgt.startswith(BAD_SCHEMES):
                self.err("unsafe-link", rel, "a %s link is not allowed" % tgt.split(":")[0])
                break
        for alt, dest in scan_images(visible):
            bp = bundle_path(page_dir, dest) if dest else None
            if bp:
                refs.add(bp)
            if not published:
                continue
            if dest is None or dest == "":
                prob = alt_problem(alt, "") or "image has no destination"
            else:
                prob = alt_problem(alt, dest)
            if prob:
                self.err("inline-alt", rel, prob)
            if dest and not (bp and self.is_bundle_file(bp)):
                self.err("image-remote", rel, "an image must be a file inside the page folder (no links, absolute or ../ paths)")

    def is_bundle_file(self, rel):
        full = os.path.join(self.root, rel)
        return os.path.isfile(full) and not os.path.islink(full)

    def check_date(self, rel, v):
        if not isinstance(v, str) or not v.strip():
            self.err("date", rel, "date is required")
            return
        m = DATE_RE.match(v.strip())
        if not m:
            self.err("date", rel, "date must look like 2026-11-08 or 2026-11-08T09:30:00-05:00")
            return
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        try:
            date(y, mo, d)
            if m.group(4):
                datetime(y, mo, d, int(m.group(4)), int(m.group(5)), int(m.group(6) or 0))
        except ValueError:
            self.err("date", rel, "date is not a real calendar date or time")

    # -- images --
    def check_image(self, rel, ext):
        name = os.path.basename(rel)
        self.images.append(rel)
        if not IMAGE_NAME.match(name) or name != name.lower():
            self.err("image-name", rel, "use a lowercase name of a-z, 0-9, dot, hyphen and underscore, no spaces")
        if ext not in ALLOWED_IMAGES:
            self.err("image-type", rel, "only WebP, JPEG and PNG are allowed")
            return
        data = self.read(rel, self.max_image, "image-size")
        if data is None:
            return
        if ext == ".svg":
            for what in svg_findings(data):
                self.err("image-svg", rel, what)
            return
        if ext == ".webp":
            parser = self.meta.webp_findings
        elif ext == ".png":
            parser = self.meta.png_findings
        else:
            parser = self.meta.jpeg_findings
        try:
            found = parser(data)
        except (struct.error, IndexError, ValueError):
            found = ["unreadable image structure"]
        for what in found:
            self.err("image-metadata", rel, what)
        dims = image_dimensions(data, ext)
        if dims is None:
            self.err("image-dimensions", rel, "the image width and height could not be read")
        elif dims[0] > MAX_SIDE or dims[1] > MAX_SIDE or dims[0] * dims[1] > MAX_PIXELS:
            self.err(
                "image-dimensions",
                rel,
                "%dx%d pixels, limit %d per side and %d megapixels" % (dims[0], dims[1], MAX_SIDE, MAX_PIXELS // 1000000),
            )

    def load_refs(self, page_dir):
        """References of a page whose Markdown is not in this run: parsed with its errors dropped."""
        if page_dir in self.refs:
            return
        self.refs[page_dir] = set()
        if not os.path.isfile(os.path.join(self.root, page_dir, "index.md")):
            return
        saved = self.errors
        self.errors = []
        try:
            self.check_markdown(page_dir + "/index.md", count=False)
        finally:
            self.errors = saved

    def check_unreferenced(self):
        for rel in self.images:
            page_dir = os.path.dirname(rel)
            self.load_refs(page_dir)
            if rel not in self.refs.get(page_dir, ()):
                self.err(
                    "image-unreferenced",
                    rel,
                    "no page uses this image: reference it from index.md (image: or ![alt](name)) or remove it",
                )

    def check_brand(self):
        if not self.images:
            return
        script = os.path.join(HERE, "check-brand-assets.sh")
        try:
            r = subprocess.run(
                ["bash", script, self.root], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60, check=False
            )
        except (OSError, subprocess.TimeoutExpired):
            self.err("brand-asset", "brand/approved-assets.txt", "the brand asset check could not run")
            return
        out = (r.stdout or "") + (r.stderr or "")
        if r.returncode == 0:
            return
        scoped = set(self.images)
        hit = False
        for line in out.splitlines():
            for p in scoped:
                if line.startswith(p + " ") or line.startswith(p + ":"):
                    self.err("brand-asset", p, line[len(p) :].lstrip(": ").strip() or "not approved")
                    hit = True
        if not hit and "approved-assets.txt is missing" in out:
            self.err("brand-asset", "brand/approved-assets.txt", "is missing")


# --- file selection --------------------------------------------------------------------------------


def git(root, *args):
    r = subprocess.run(
        ["git", "-C", root] + list(args), capture_output=True, stdin=subprocess.DEVNULL, timeout=60, check=False
    )
    return r.returncode, r.stdout


def all_content(root):
    out = []
    base = os.path.join(root, "content")
    for d, dirs, files in os.walk(base):
        dirs.sort()
        for f in sorted(files):
            out.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/"))
            if len(out) > MAX_FILES:
                raise SystemExit("check-content: more than %d files under content/" % MAX_FILES)
    return out


def changed_content(root, base):
    if not base:
        rc, _ = git(root, "rev-parse", "--verify", "-q", "origin/main")
        if rc == 0:
            rc2, mb = git(root, "merge-base", "origin/main", "HEAD")
            if rc2 == 0 and mb.strip():
                base = mb.decode().strip()
        if not base:
            rc, _ = git(root, "rev-parse", "--verify", "-q", "HEAD^1")
            if rc == 0:
                base = "HEAD^1"
    if not base:
        raise SystemExit("check-content: no diff base (use --base REF, --all, or name files)")
    rc, out = git(root, "diff", "--no-renames", "--name-only", "--diff-filter=d", "-z", base, "--", "content")
    if rc != 0:
        raise SystemExit("check-content: git diff against %s failed" % base)
    names = set(out.decode("utf-8", "replace").split("\0"))
    rc, out = git(root, "ls-files", "-z", "--others", "--exclude-standard", "--", "content")
    if rc == 0:
        names |= set(out.decode("utf-8", "replace").split("\0"))
    names.discard("")
    return sorted(names)


def main(argv):
    root, base, as_json, terms_file = DEFAULT_ROOT, None, False, None
    use_all, max_image, files = False, IMAGE_MAX, []
    it = iter(argv)
    for a in it:
        if a == "--all":
            use_all = True
        elif a == "--json":
            as_json = True
        elif a in ("--root", "--base", "--terms-file", "--max-image-bytes"):
            v = next(it, None)
            if v is None:
                print("check-content: %s needs a value" % a, file=sys.stderr)
                return 2
            if a == "--root":
                root = os.path.abspath(v)
            elif a == "--base":
                base = v
            elif a == "--terms-file":
                terms_file = v
            else:
                try:
                    max_image = int(v)
                except ValueError:
                    print("check-content: --max-image-bytes needs a number", file=sys.stderr)
                    return 2
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        elif a.startswith("-"):
            print("check-content: unknown option %s" % a, file=sys.stderr)
            return 2
        else:
            files.append(a)
    if not os.path.isdir(os.path.join(root, "content")) and not files:
        print("check-content: no content/ directory under %s" % root, file=sys.stderr)
        return 2

    if files:
        sel = [f.replace(os.sep, "/").lstrip("./") if f.startswith("./") else f.replace(os.sep, "/") for f in files]
    elif use_all:
        sel = all_content(root)
    else:
        sel = changed_content(root, base)
    sel = sorted({f for f in sel if f.startswith("content/") and ".." not in f.split("/")})
    if len(sel) > MAX_FILES:
        print("check-content: more than %d files" % MAX_FILES, file=sys.stderr)
        return 2

    ck = Checker(root, max_image, load_terms(terms_file))
    for rel in sel:
        ck.check_file(rel)
    ck.check_unreferenced()
    ck.check_brand()
    ck.errors.sort(key=lambda e: (e["path"], e["rule"], e["message"]))
    nfiles = len(sel)
    bad_files = len({e["path"] for e in ck.errors})
    if as_json:
        print(
            json.dumps(
                {
                    "ok": not ck.errors,
                    "files": nfiles,
                    "markdown": ck.md,
                    "images": len(ck.images),
                    "errors": ck.errors,
                },
                indent=2,
            )
        )
    else:
        for e in ck.errors:
            msg = " ".join(e["message"].split())
            print("%s: %s: %s" % (e["rule"], e["path"], msg))
        if ck.errors:
            print(
                "check-content: %d error(s) in %d file(s); checked %d (%d Markdown, %d images)"
                % (len(ck.errors), bad_files, nfiles, ck.md, len(ck.images))
            )
        else:
            print("check-content: ok (%d files: %d Markdown, %d images)" % (nfiles, ck.md, len(ck.images)))
    return 1 if ck.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
