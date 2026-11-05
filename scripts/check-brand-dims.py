#!/usr/bin/env python3
"""Check the pixel sizes of the generated brand images (no Pillow needed).

Usage: python3 -I scripts/check-brand-dims.py [static/brand dir]

Mascot WebP files are exactly their names (128, 256, 512) and no WebP is past
the 900 px master; the OG card is 1200x630; favicons match their names.
Exit 1 with one line per problem.
"""

import pathlib
import struct
import sys

PNG_SIG = bytes([0x89]) + b"PNG\r\n" + bytes([0x1A, 0x0A])


def png(p):
    b = p.read_bytes()
    if b[:8] != PNG_SIG:
        raise ValueError("not a PNG")
    return struct.unpack(">II", b[16:24])


def webp(p):
    b = p.read_bytes()
    if b[:4] != b"RIFF" or b[8:12] != b"WEBP":
        raise ValueError("not a WebP")
    kind = b[12:16]
    if kind == b"VP8 ":
        w, h = struct.unpack("<HH", b[26:30])
        return w & 0x3FFF, h & 0x3FFF
    if kind == b"VP8L":
        v = struct.unpack("<I", b[21:25])[0]
        return (v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1
    if kind == b"VP8X":
        return (
            int.from_bytes(b[24:27], "little") + 1,
            int.from_bytes(b[27:30], "little") + 1,
        )
    raise ValueError("unknown WebP chunk")


def main():
    d = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "static/brand")
    problems = []
    expect = [(f"mascot-{n}.webp", webp, (n, n)) for n in (128, 256, 512)]
    expect += [("og-card.png", png, (1200, 630))]
    expect += [(f"favicon-{n}.png", png, (n, n)) for n in (32, 192, 512)]
    expect += [("apple-touch-icon-180.png", png, (180, 180))]
    for name, fn, want in expect:
        try:
            got = fn(d / name)
        except (OSError, ValueError, struct.error) as e:
            problems.append(f"{name}: {e}")
            continue
        if got != want:
            problems.append(f"{name}: size {got}, expected {want}")
    found = 0
    for p in sorted(d.glob("*.webp")):
        found += 1
        try:
            if max(webp(p)) > 900:
                problems.append(f"{p.name}: larger than the 900 px master")
        except (OSError, ValueError, struct.error) as e:
            problems.append(f"{p.name}: {e}")
    if found == 0:
        problems.append("no WebP files found")
    for line in problems:
        print(line)
    if problems:
        sys.exit(1)
    print("brand image dimensions ok")


if __name__ == "__main__":
    main()
