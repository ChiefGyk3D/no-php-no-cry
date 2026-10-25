#!/usr/bin/env python3
"""WCAG contrast check for the design tokens in assets/css/tokens.css.

Usage: python3 -I scripts/check-contrast.py [tokens.css]

Reads the hex colors from the dark base (:root) and the light override
(@media (prefers-color-scheme: light)), then checks each pair below in both
modes. Text pairs need 4.5:1 (WCAG AA); the focus ring needs 3:1
(non-text contrast). Prints one line per pair; exits 1 on any failure or any
missing token.
"""
import re
import sys

LIGHT_MARKER = "@media (prefers-color-scheme: light)"

# (foreground, background, minimum ratio)
PAIRS = [
    ("text", "bg", 4.5),
    ("text", "surface", 4.5),
    ("muted", "bg", 4.5),
    ("muted", "surface", 4.5),
    ("link", "bg", 4.5),
    ("link", "surface", 4.5),
    ("on-accent", "accent", 4.5),
    ("focus", "bg", 3.0),
]

REQUIRED = sorted({name for pair in PAIRS for name in pair[:2]})


def parse(css):
    """Return {token: '#RRGGBB'} for a block of CSS."""
    return {
        m.group(1): m.group(2).upper()
        for m in re.finditer(r"--([a-z0-9-]+)\s*:\s*(#[0-9a-fA-F]{6})\s*;", css)
    }


def luminance(hexcolor):
    channels = [int(hexcolor[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def main(path):
    with open(path, encoding="utf-8") as handle:
        css = handle.read()
    if LIGHT_MARKER not in css:
        print("FAIL no light-mode block found: expected '%s'" % LIGHT_MARKER)
        return 1
    dark_css, light_css = css.split(LIGHT_MARKER, 1)
    dark = parse(dark_css)
    light = dict(dark)
    light.update(parse(light_css))

    failed = False
    for mode, tokens in (("dark", dark), ("light", light)):
        for name in REQUIRED:
            if name not in tokens:
                print("FAIL %s: token --%s missing" % (mode, name))
                failed = True
        for fg, bg, need in PAIRS:
            if fg not in tokens or bg not in tokens:
                continue
            got = ratio(tokens[fg], tokens[bg])
            status = "ok  " if got >= need else "FAIL"
            if got < need:
                failed = True
            print(
                "%s %s: %s on %s %s on %s = %.2f:1 (need %.1f)"
                % (status, mode, fg, bg, tokens[fg], tokens[bg], got, need)
            )
    return 1 if failed else 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "assets/css/tokens.css"
    sys.exit(main(target))
