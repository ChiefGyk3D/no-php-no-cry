"""WCAG contrast check for the design tokens in assets/css/tokens.css.

Usage: python3 -I scripts/check-contrast.py [tokens.css]

tokens.css is generated from brand/tokens.json (scripts/gen-tokens.py). Dark
only (brand kit decision L): the one :root block is checked. Text pairs need
4.5:1 (WCAG AA); the focus ring and non-text accents need 3:1. Highlight colors
(--code-*) are text on --surface. Prints one line per pair; exits 1 on any
failure, missing token or missing block. A leftover light or data-theme block
also fails, so light mode cannot come back unnoticed.
"""
import re
import sys

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
    ("focus", "surface", 3.0),
    # Kit gray: text on the ground, a 3:1 accent on the charcoal surface.
    ("gray", "bg", 4.5),
    ("gray", "surface", 3.0),
    # Carbon and plate surfaces (brief section 6).
    ("focus", "carbon-base", 3.0),
    ("focus", "carbon-line", 3.0),
    ("focus", "plate", 3.0),
    ("text", "carbon-base", 4.5),
    ("text", "carbon-line", 4.5),
    ("text", "plate", 4.5),
    ("muted", "carbon-base", 4.5),
    ("muted", "carbon-line", 4.5),
    ("muted", "plate", 4.5),
    # Syntax highlighting is drawn on the code-block background (--surface).
    ("code-keyword", "surface", 4.5),
    ("code-string", "surface", 4.5),
    ("code-number", "surface", 4.5),
    ("code-function", "surface", 4.5),
    ("code-comment", "surface", 4.5),
    ("code-deleted", "surface", 4.5),
    ("code-inserted", "surface", 4.5),
]

REQUIRED = sorted({name for pair in PAIRS for name in pair[:2]})

DARK_BASE = ":root"


def strip_comments(css):
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def blocks(css):
    """Return {selector path: body} for every leaf rule; comments never count."""
    css = strip_comments(css)
    found = {}
    stack = []
    start = 0
    for i, ch in enumerate(css):
        if ch == "{":
            stack.append((" ".join(css[start:i].split()), i + 1))
            start = i + 1
        elif ch == "}" and stack:
            sel, body_start = stack.pop()
            path = " ".join([s for s, _ in stack] + [sel])
            found[path] = css[body_start:i]
            start = i + 1
        elif ch == ";" and not stack:
            start = i + 1
    return found


def parse(css):
    """Return {token: '#RRGGBB'} for a block of CSS; comments never count."""
    css = strip_comments(css)
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
    found = blocks(css)
    failed = False
    if DARK_BASE not in found:
        print("FAIL block missing: expected '%s'" % DARK_BASE)
        return 1
    for sel in found:
        if sel != DARK_BASE and not sel.startswith("@font-face"):
            print("FAIL unexpected block '%s': the brand is dark only" % sel)
            failed = True
    tokens = parse(found[DARK_BASE])
    for name in REQUIRED:
        if name not in tokens:
            print("FAIL dark: token --%s missing" % name)
            failed = True
    for fg, bg, need in PAIRS:
        if fg not in tokens or bg not in tokens:
            continue
        got = ratio(tokens[fg], tokens[bg])
        status = "ok  " if got >= need else "FAIL"
        if got < need:
            failed = True
        print(
            "%s dark: %s on %s %s on %s = %.2f:1 (need %.1f)"
            % (status, fg, bg, tokens[fg], tokens[bg], got, need)
        )
    return 1 if failed else 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "assets/css/tokens.css"
    sys.exit(main(target))
