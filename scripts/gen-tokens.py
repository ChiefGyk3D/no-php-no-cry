#!/usr/bin/env python3
"""Generate assets/css/tokens.css from brand/tokens.json (stdlib only).

Usage: python3 -I scripts/gen-tokens.py [--check] [--source FILE] [--out FILE]

Output is deterministic (no dates, stable order). Dark only (brand kit decision
L): one :root block, no light palette, no data-theme selectors. --check writes nothing and exits 1 if the file on disk differs from
what the source generates, or if the source is malformed.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEX = re.compile(r"^#[0-9A-F]{6}$")
NAME = re.compile(r"^[a-z0-9-]+$")

HEADER = """\
/*
 * GENERATED FILE. Do not edit: change brand/tokens.json and run
 * python3 -I scripts/gen-tokens.py (CI runs it with --check).
 *
 * Design tokens. Dark only (brand kit decision L): :root is the one palette,
 * there is no light mode. Brand amber #FBB03B, ground #0F0F0F, charcoal
 * #202020, gray #808080; text on amber #1A1A1A, off-white #F0F0F0.
 *
 * Every color pair is checked for WCAG AA (4.5:1 text, 3:1 focus ring) by
 * scripts/check-contrast.py; colors are 6-digit hex so the
 * check can read them. Nothing else in the CSS hard-codes a color or a font.
 * Specification: brand/README.md.
 *
 * Jost and Orbitron are self-hosted from /fonts (SIL OFL 1.1, license text
 * beside each); no font host is contacted. Orbitron is the display face for
 * headings only (--font-display, kit decision X1), never body text. Cyber City
 * is the logo, wordmark and display font only (--font-display); TODO: its
 * file is not bundled (license document not seen here), so the stack falls
 * through to Orbitron, then Jost. The wordmark is used as an
 * image, never typeset.
 */
"""


class SourceError(Exception):
    pass


def _no_duplicates(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise SourceError("duplicate key %r" % key)
        seen[key] = value
    return seen


def load(path):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle, object_pairs_hook=_no_duplicates)
    except (OSError, ValueError, SourceError) as exc:
        raise SourceError("%s: %s" % (path, exc))
    if "light" in data or "dark" in data:
        raise SourceError("%s: dark only, no light/dark palettes; use groups" % path)
    for group in data.get("groups") or []:
        for name, value in group.get("tokens", {}).items():
            if not NAME.match(name):
                raise SourceError("%s: bad token name %r" % (path, name))
            if value.startswith("#") and not HEX.match(value):
                raise SourceError(
                    "%s: --%s: %r is not a 6-digit uppercase hex color" % (path, name, value)
                )
    faces = data.get("fontFace")
    if not data.get("groups") or not isinstance(faces, list) or not faces:
        raise SourceError("%s: needs groups and a fontFace list" % path)
    for face in faces:
        if not isinstance(face, dict) or set(face) != {"family", "weight", "src", "format"}:
            raise SourceError("%s: each fontFace needs family, weight, src and format" % path)
        if not all(isinstance(v, str) and re.match(r"^[A-Za-z0-9 ./_-]+$", v) for v in face.values()):
            raise SourceError("%s: fontFace values may only hold letters, digits and ./_- " % path)
    return data


def block(selector, groups, level, extra=()):
    """One rule; level 0 is top level."""
    outer = "  " * level
    pad = outer + "  "
    lines = ["%s%s {" % (outer, selector)]
    first = True
    for line in extra:
        lines.append(pad + line)
        first = False
    for group in groups:
        if not first:
            lines.append("")
        first = False
        lines.append("%s/* %s */" % (pad, group["comment"]))
        for name, value in group["tokens"].items():
            lines.append("%s--%s: %s;" % (pad, name, value))
    lines.append(outer + "}")
    return "\n".join(lines)


def generate(data):
    out = [HEADER]
    for face in data["fontFace"]:
        out.append(
            "@font-face {\n"
            "  font-family: %s;\n"
            "  font-style: normal;\n"
            "  font-weight: %s;\n"
            "  font-display: swap;\n"
            '  src: url("%s") format("%s");\n'
            "}\n" % (face["family"], face["weight"], face["src"], face["format"])
        )
    out.append(block(":root", data["groups"], 0, extra=["color-scheme: dark;"]))
    return "\n".join(out) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="fail if the output file would change")
    parser.add_argument("--source", default=os.path.join(ROOT, "brand", "tokens.json"))
    parser.add_argument("--out", default=os.path.join(ROOT, "assets", "css", "tokens.css"))
    args = parser.parse_args(argv)
    try:
        text = generate(load(args.source))
    except SourceError as exc:
        print("FAIL tokens.json: %s" % exc)
        return 1
    if args.check:
        try:
            with open(args.out, encoding="utf-8") as handle:
                current = handle.read()
        except OSError as exc:
            print("FAIL cannot read %s: %s" % (args.out, exc))
            return 1
        if current != text:
            print("FAIL drift: %s differs from what %s generates; run scripts/gen-tokens.py" % (args.out, args.source))
            return 1
        print("ok   %s is current" % args.out)
        return 0
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
