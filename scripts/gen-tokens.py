#!/usr/bin/env python3
"""Generate assets/css/tokens.css from brand/tokens.json (stdlib only).

Usage: python3 -I scripts/gen-tokens.py [--check] [--source FILE] [--out FILE]

Output is deterministic (no dates, stable order). The light palette is emitted
twice from one source: under @media (prefers-color-scheme: light) for
:root:not([data-theme]), and under :root[data-theme="light"]. The color tokens
of the dark palette are emitted again under :root[data-theme="dark"], which
pins dark. --check writes nothing and exits 1 if the file on disk differs from
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
 * Design tokens. Dark first: :root is the dark palette, the light palette is
 * the override below, emitted for the system preference and for
 * :root[data-theme="light"]; :root[data-theme="dark"] pins dark. Brand amber
 * #FBB03B, text on amber #1A1A1A, off-white #F0F0F0, near-black page.
 *
 * Every color pair is checked for WCAG AA (4.5:1 text, 3:1 focus ring) in
 * every block by scripts/check-contrast.py; colors are 6-digit hex so the
 * check can read them. Nothing else in the CSS hard-codes a color or a font.
 * Specification: brand/README.md.
 *
 * Jost is self-hosted from /fonts (SIL OFL 1.1, license text beside it); no
 * font host is contacted. The wordmark font is undecided: the wordmark is only
 * ever used as an image, never typeset.
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
    for mode in ("dark", "light"):
        for group in data.get(mode) or []:
            for name, value in group.get("tokens", {}).items():
                if not NAME.match(name):
                    raise SourceError("%s: bad token name %r" % (path, name))
                if value.startswith("#") and not HEX.match(value):
                    raise SourceError(
                        "%s: --%s: %r is not a 6-digit uppercase hex color" % (path, name, value)
                    )
    if not data.get("dark") or not data.get("light") or "fontFace" not in data:
        raise SourceError("%s: needs dark, light and fontFace" % path)
    return data


def block(selector, groups, level, only_themed=False, extra=()):
    """One rule; level 0 is top level, level 1 sits inside an @media block."""
    outer = "  " * level
    pad = outer + "  "
    lines = ["%s%s {" % (outer, selector)]
    first = True
    for line in extra:
        lines.append(pad + line)
        first = False
    for group in groups:
        if only_themed and not group.get("themed"):
            continue
        if not first:
            lines.append("")
        first = False
        lines.append("%s/* %s */" % (pad, group["comment"]))
        for name, value in group["tokens"].items():
            lines.append("%s--%s: %s;" % (pad, name, value))
    lines.append(outer + "}")
    return "\n".join(lines)


def generate(data):
    face = data["fontFace"]
    out = [HEADER]
    out.append(
        "@font-face {\n"
        "  font-family: %s;\n"
        "  font-style: normal;\n"
        "  font-weight: %s;\n"
        "  font-display: swap;\n"
        '  src: url("%s") format("woff2");\n'
        "}\n" % (face["family"], face["weight"], face["src"])
    )
    out.append(block(":root", data["dark"], 0, extra=["color-scheme: dark light;"]) + "\n")
    out.append(
        "@media (prefers-color-scheme: light) {\n"
        + block(":root:not([data-theme])", data["light"], 1)
        + "\n}\n"
    )
    out.append(block(':root[data-theme="light"]', data["light"], 0, extra=["color-scheme: light;"]) + "\n")
    out.append(
        block(':root[data-theme="dark"]', data["dark"], 0, only_themed=True, extra=["color-scheme: dark;"])
    )
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
