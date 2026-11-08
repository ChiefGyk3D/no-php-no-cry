#!/usr/bin/env python3
"""Fail when a published image carries EXIF, XMP, IPTC or GPS metadata (no dependencies).

Usage: python3 -I scripts/check-image-metadata.py <dir>

Walks <dir> for .webp, .jpg, .jpeg and .png files and reads their container
structure directly (Python stdlib only; no ExifTool or Pillow needed):

  WebP  an EXIF or XMP  RIFF chunk
  JPEG  an APP1 segment (Exif or XMP), an APP13 segment (IPTC) or a COM segment
  PNG   an eXIf chunk, or a tEXt/zTXt/iTXt chunk with an XMP, IPTC, APP13 or raw EXIF/XMP profile keyword

GPS tags live inside the EXIF block, so an EXIF finding covers them. Findings
print as "[image-metadata] path: what" and the exit status is 1. The portrait
of the owner (static/brand/portrait-*.webp) is published only as a stripped
copy; the original is never committed (docs/redesign-brief.md, "Portrait"). A
file that cannot be parsed is a finding too (fail closed), and a directory with
no image files is an error, so the walk cannot pass by finding nothing.
"""
import os
import struct
import sys

EXTS = {".webp", ".jpg", ".jpeg", ".png"}
JPEG_SOI = bytes([0xFF, 0xD8])
# Textual PNG metadata keywords (lower case): XMP, and the ImageMagick/ExifTool "raw profile"
# forms of IPTC, APP13, EXIF and XMP.
PNG_META_KEYS = {
    "xml:com.adobe.xmp",
    "iptc",
    "raw profile type iptc",
    "raw profile type app13",
    "raw profile type exif",
    "raw profile type xmp",
}
PNG_SIG = bytes([0x89]) + b"PNG\r\n" + bytes([0x1A, 0x0A])


EXIF_PREFIX = b"Exif" + bytes(2)


MAX_IFDS = 16


def exif_finding(blob):
    """EXIF is a finding when ANY IFD in its TIFF block holds a tag, or when the block
    cannot be read. GPS, camera, date, serial and thumbnail data live in IFD0, the linked
    IFD1 (thumbnail) or sub-IFDs reached through a pointer tag (Exif 0x8769, GPS 0x8825,
    Interop 0xA005); a pointer is itself a tag, so an IFD that points anywhere is non-empty
    and is a finding. The IFD chain (IFD0 -> IFD1 -> ...) is walked with a cycle guard and
    a cap of MAX_IFDS. A structure with zero tags in every IFD, which some encoders write,
    holds nothing and passes."""
    if blob[:6] == EXIF_PREFIX:
        blob = blob[6:]
    try:
        order = {b"II": "<", b"MM": ">"}[blob[:2]]
        off = struct.unpack(order + "I", blob[4:8])[0]
        seen = set()
        while off:
            if off in seen or len(seen) >= MAX_IFDS:
                return "EXIF IFD chain loops or is too long"
            seen.add(off)
            count = struct.unpack(order + "H", blob[off : off + 2])[0]
            end = off + 2 + 12 * count
            if end + 4 > len(blob):
                return "EXIF block that cannot be read"
            if count:
                return "EXIF block with %d tags" % count
            off = struct.unpack(order + "I", blob[end : end + 4])[0]
    except (KeyError, struct.error):
        return "EXIF block that cannot be read"
    return None


def webp_findings(b):
    if b[:4] != b"RIFF" or b[8:12] != b"WEBP":
        return ["not a WebP file"]
    out, i = [], 12
    while i + 8 <= len(b):
        kind = b[i : i + 4]
        size = struct.unpack("<I", b[i + 4 : i + 8])[0]
        if kind == b"EXIF":
            out.append(exif_finding(b[i + 8 : i + 8 + size]))
        elif kind == b"XMP ":
            out.append("XMP chunk")
        i += 8 + size + (size & 1)
    return [x for x in out if x]


def jpeg_findings(b):
    if b[:2] != JPEG_SOI:
        return ["not a JPEG file"]
    out, i = [], 2
    while i + 4 <= len(b):
        if b[i] != 0xFF:
            return out + ["bad JPEG marker structure"]
        m = b[i + 1]
        if m == 0xFF:
            i += 1
            continue
        if m in (0xDA, 0xD9):  # start of scan or end of image: no more headers
            break
        if 0xD0 <= m <= 0xD8 or m == 0x01:
            i += 2
            continue
        n = struct.unpack(">H", b[i + 2 : i + 4])[0]
        seg = b[i + 4 : i + 2 + n]
        if m == 0xE1:
            out.append("XMP segment" if seg.startswith(b"http://ns.adobe.com/xap") else exif_finding(seg))
        elif m == 0xED:
            out.append("IPTC segment")
        elif m == 0xFE:
            out.append("comment segment")
        i += 2 + n
    return [x for x in out if x]


def png_findings(b):
    if b[:8] != PNG_SIG:
        return ["not a PNG file"]
    out, i = [], 8
    while i + 8 <= len(b):
        n = struct.unpack(">I", b[i : i + 4])[0]
        kind = b[i + 4 : i + 8]
        body = b[i + 8 : i + 8 + n]
        if kind == b"eXIf":
            out.append(exif_finding(body))
        elif kind in (b"tEXt", b"zTXt", b"iTXt"):
            key = body.split(bytes(1), 1)[0].decode("latin-1").lower()
            if key in PNG_META_KEYS:
                out.append("%s metadata chunk" % key)
        i += 12 + n
    return [x for x in out if x]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check-image-metadata.py <dir>")
    root = sys.argv[1]
    parsers = {".webp": webp_findings, ".png": png_findings, ".jpg": jpeg_findings, ".jpeg": jpeg_findings}
    bad, seen = 0, 0
    for d, _, files in sorted(os.walk(root)):
        for f in sorted(files):
            ext = os.path.splitext(f)[1].lower()
            if ext not in EXTS:
                continue
            p = os.path.join(d, f)
            seen += 1
            try:
                with open(p, "rb") as fh:
                    found = parsers[ext](fh.read())
            except (OSError, struct.error) as e:
                found = ["unreadable: %s" % type(e).__name__]
            for what in found:
                print("[image-metadata] %s: %s" % (os.path.relpath(p, root), what))
                bad += 1
    if seen == 0:
        print("[image-metadata] no image files found under %s" % root)
        sys.exit(1)
    if bad:
        sys.exit(1)
    print("no EXIF, XMP or IPTC metadata in %d image files" % seen)


if __name__ == "__main__":
    main()
