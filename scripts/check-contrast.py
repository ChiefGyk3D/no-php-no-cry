"""WCAG contrast check for the design tokens in assets/css/tokens.css.

Usage: python3 -I scripts/check-contrast.py [tokens.css]

tokens.css is generated from brand/tokens.json (scripts/gen-tokens.py). The
check reads every block the generator emits, so a hand-edited copy cannot
drift:
  dark                  :root (the dark base)
  light                 @media (prefers-color-scheme: light) :root:not([data-theme])
  light[data-theme]     :root[data-theme="light"]
  dark[data-theme]      :root[data-theme="dark"]
Each light block is the dark base plus its overrides; the three light sets
must be identical, and the pinned dark set must equal the base. Text pairs
need 4.5:1 (WCAG AA); the focus ring and the theme-toggle border need 3:1
(non-text contrast). Highlight colors (--code-*) are text on --surface.
Carbon, plate and ghost are dark-mode surfaces, so their pairs run in the dark
blocks only. Prints one line per pair; exits 1 on any failure, missing token,
missing block or drift between blocks.
"""
import re
import sys

# (foreground, background, minimum ratio[, modes]); modes defaults to both.
DARK = ("dark",)
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
    # Theme toggle: control border and icon (link color) on the page, both modes.
    ("link", "bg", 3.0),
    # Carbon, plate and ghost surfaces (dark mode only, brief section 6).
    ("focus", "carbon-base", 3.0, DARK),
    ("focus", "carbon-line", 3.0, DARK),
    ("focus", "plate", 3.0, DARK),
    ("focus", "ghost", 3.0, DARK),
    ("text", "carbon-base", 4.5, DARK),
    ("text", "carbon-line", 4.5, DARK),
    ("text", "plate", 4.5, DARK),
    ("muted", "carbon-base", 4.5, DARK),
    ("muted", "carbon-line", 4.5, DARK),
    ("muted", "plate", 4.5, DARK),
    # Cream plate: same in both modes; focus ring and link text use #8A5A00.
    ("focus-on-plate", "plate-light", 3.0),
    ("focus-on-plate", "plate-light", 4.5),
    ("on-accent", "plate-light", 4.5),
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

# Block selectors, as they appear after whitespace is collapsed. A leading
# "@media (...)" is part of the path for nested rules.
DARK_BASE = ":root"
LIGHT_MEDIA = "@media (prefers-color-scheme: light) :root:not([data-theme])"
LIGHT_FORCED = ':root[data-theme="light"]'
DARK_FORCED = ':root[data-theme="dark"]'


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
    for sel in (DARK_BASE, LIGHT_MEDIA, LIGHT_FORCED, DARK_FORCED):
        if sel not in found:
            print("FAIL block missing: expected '%s'" % sel)
            failed = True
    if failed:
        return 1

    dark = parse(found[DARK_BASE])
    light = dict(dark)
    light.update(parse(found[LIGHT_MEDIA]))
    light_forced = dict(dark)
    light_forced.update(parse(found[LIGHT_FORCED]))
    dark_forced = dict(dark)
    dark_forced.update(parse(found[DARK_FORCED]))

    for label, other, ref in (
        ("light[data-theme] differs from light", light_forced, light),
        ("dark[data-theme] differs from dark", dark_forced, dark),
    ):
        diff = sorted(k for k in set(other) | set(ref) if other.get(k) != ref.get(k))
        if diff:
            print("FAIL drift: %s in --%s" % (label, ", --".join(diff)))
            failed = True

    modes = (
        ("dark", "dark", dark),
        ("light", "light", light),
        ("dark[data-theme]", "dark", dark_forced),
        ("light[data-theme]", "light", light_forced),
    )
    for mode, kind, tokens in modes:
        for name in REQUIRED:
            if name not in tokens:
                print("FAIL %s: token --%s missing" % (mode, name))
                failed = True
        for pair in PAIRS:
            fg, bg, need = pair[:3]
            if kind not in (pair[3] if len(pair) > 3 else ("dark", "light")):
                continue
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
