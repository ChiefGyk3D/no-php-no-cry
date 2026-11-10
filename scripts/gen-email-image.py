#!/usr/bin/env python3
"""Render the business email address as a PNG for the optional image variant (issue 329).

The About page shows the address as text by default. Set params.emailAsImage = true
(or HUGO_PARAMS_EMAILASIMAGE=true for one build) to show this image instead, inside a
mailto link whose accessible name is the fixed alt text, not the address.

Usage: python3 -I scripts/gen-email-image.py [--check]

Reads the address from scripts/about-email.sh, draws it in the display font
(static/fonts/orbitron-wght.ttf, OFL) in the --text color on a transparent
background (dark mode only), and writes assets/contact/email-address.png with no
metadata, plus email-address.stamp (the hashes scripts/check-email-image.sh checks). Needs Pillow (a dev-time tool; the output is committed, the build does
not run this). --check redraws and fails when the committed file differs.
"""
import hashlib
import io
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "contact" / "email-address.png"
STAMP = ROOT / "assets" / "contact" / "email-address.stamp"
FONT = ROOT / "static" / "fonts" / "orbitron-wght.ttf"
COLOR = (0xF0, 0xF0, 0xF0, 255)  # --text in brand/tokens.json
SIZE = 44  # px; the page shows it at half this width (2x for sharp text)


def render(text: str) -> bytes:
    font = ImageFont.truetype(str(FONT), SIZE)
    left, top, right, bottom = font.getbbox(text)
    pad = 6
    img = Image.new("RGBA", (right - left + 2 * pad, bottom - top + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((pad - left, pad - top), text, font=font, fill=COLOR)
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def stamp(mail: str, png: bytes) -> str:
    """The sha256 of the address, the font and the PNG: scripts/check-email-image.sh (issue 331)
    compares these without Pillow, so CI fails when the address changes but the image does not."""
    h = lambda b: hashlib.sha256(b).hexdigest()
    return "email %s\nfont %s\npng %s\n" % (h(mail.encode()), h(FONT.read_bytes()), h(png))


def main() -> int:
    mail = subprocess.run([str(ROOT / "scripts" / "about-email.sh")], capture_output=True, text=True, check=True).stdout.strip()
    if not mail:
        print("no address: the contact config is incomplete", file=sys.stderr)
        return 1
    data = render(mail)
    if "--check" in sys.argv:
        ok = OUT.exists() and OUT.read_bytes() == data
        print("ok" if ok else "assets/contact/email-address.png is out of date; run scripts/gen-email-image.py")
        return 0 if ok else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    STAMP.write_text(stamp(mail, data))
    w, h = Image.open(io.BytesIO(data)).size
    print("wrote %s (%dx%d)" % (OUT.relative_to(ROOT), w, h))
    return 0


if __name__ == "__main__":
    sys.exit(main())
