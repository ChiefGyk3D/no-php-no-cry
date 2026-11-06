#!/usr/bin/env python3
"""Write static/support/qr-<coin>.svg for every cryptocurrency entry in data/support.yaml.

Usage (through scripts/gen-support-qr.sh, which installs the pinned packages):
    gen-support-qr.py [--check] [--decode] [--dir DIR]

--dir names the directory to write to or check (default static/support). The
page tests use it to compare the built site's copies with a fresh encoding.
--decode also renders every SVG in a headless browser (CHROME names the binary;
google-chrome, chromium and chromium-browser are tried) and decodes the picture
with OpenCV's QR detector: the decoded text must equal the address exactly.

The data file is read with a small line parser (the Python standard library has
no YAML reader); it understands only the "- key: value" list that
data/support.yaml documents. Each SVG is a black-on-white code at error
correction level H with a four-module quiet zone (a scanner needs the light
ground, so it does not use the site tokens), no script, no external reference,
and a <desc> holding the encoded text, which scripts/test-pages.sh compares with
data/support.yaml. The coin mark from static/support/coin-<coin>.svg (sources and
licenses in brand/ICONS.md) sits in the center on a light square cleared on the
module grid; that square covers at most MAX_PLATE of the code area, well inside
what level H can lose (about 30 percent), and the mark fills 78 percent of it.
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

import segno

root = pathlib.Path(__file__).resolve().parent.parent


def entries(path):
    out, cur = [], None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].rstrip() if raw.lstrip().startswith("#") else raw.rstrip()
        if not line.strip():
            continue
        text = line.lstrip()
        if text.startswith("- "):
            cur = {}
            out.append(cur)
            text = text[2:]
        key, _, val = text.partition(":")
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        cur[key.strip()] = val
    return out


MAX_PLATE = 0.12  # cleared center as a share of the code area (level H repairs about 0.30)
BORDER = 4        # quiet zone, in modules
SCALE = 5         # pixels per module in the SVG's width and height
LOGO_FILL = 0.78  # mark diameter as a share of the cleared square


def num(x):
    out = ("%.3f" % x).rstrip("0").rstrip(".")
    return out or "0"


def logo_parts(coin):
    """Return (viewbox size, inner markup) of static/support/coin-<coin>.svg."""
    raw = (root / "static" / "support" / ("coin-%s.svg" % coin)).read_text(encoding="utf-8")
    m = re.fullmatch(r'<svg xmlns="http://www\.w3\.org/2000/svg" viewBox="0 0 (\d+) \1">(.*)</svg>\s*', raw, re.S)
    if not m or re.search(r"<script|on[a-z]+=|javascript:|href=|<image|<style", m.group(2), re.I):
        raise SystemExit("static/support/coin-%s.svg is not a plain square-viewBox SVG without script or links" % coin)
    return int(m.group(1)), m.group(2)


def render(text, coin):
    code = segno.make(text, error="h", micro=False)
    n = code.symbol_size(border=0)[0]
    plate = int(MAX_PLATE ** 0.5 * n)
    if plate % 2 == 0:
        plate -= 1  # odd, so the square centers on the module grid
    assert plate >= 7 and (plate / n) ** 2 <= MAX_PLATE, (n, plate)
    lo = (n - plate) // 2
    rows = []
    for y, row in enumerate(code.matrix):
        x = 0
        while x < n:
            if not row[x] or (lo <= x < lo + plate and lo <= y < lo + plate):
                x += 1
                continue
            start = x
            while x < n and row[x] and not (lo <= x < lo + plate and lo <= y < lo + plate):
                x += 1
            rows.append("M%d %dh%dv1h-%dz" % (start + BORDER, y + BORDER, x - start, x - start))
    size = n + 2 * BORDER
    box, inner = logo_parts(coin)
    diam = plate * LOGO_FILL
    scale = diam / box
    origin = BORDER + lo + (plate - diam) / 2
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">'
        "<desc>%s</desc>"
        '<rect width="%d" height="%d" fill="#ffffff"/>'
        '<path fill="#000000" d="%s"/>'
        '<g transform="translate(%s %s) scale(%s)">%s</g>'
        "</svg>\n"
        % (size, size, size * SCALE, size * SCALE, text, size, size, "".join(rows),
           num(origin), num(origin), num(scale), inner)
    ).encode("utf-8")


def find_chrome():
    for name in (os.environ.get("CHROME"), "google-chrome", "chromium", "chromium-browser"):
        if name and shutil.which(name):
            return shutil.which(name)
    raise SystemExit("no headless Chrome or Chromium found (set CHROME)")


def decode_svg(svg_path, tmp):
    """Render an SVG in headless Chrome and decode the picture with OpenCV."""
    import cv2

    head = svg_path.read_bytes()[:200].decode("ascii", "replace")
    w, h = [int(v) for v in re.search(r'width="(\d+)" height="(\d+)"', head).groups()]
    png = tmp / (svg_path.stem + ".png")
    subprocess.run(
        [find_chrome(), "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
         "--force-device-scale-factor=3", "--window-size=%d,%d" % (w, h),
         "--user-data-dir=%s" % (tmp / "profile"), "--screenshot=%s" % png, svg_path.resolve().as_uri()],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    img = cv2.imread(str(png))
    if img is None:
        return None
    text, _, _ = cv2.QRCodeDetector().detectAndDecode(img)
    return text


def main():
    args = sys.argv[1:]
    check = "--check" in args
    decode = "--decode" in args
    out_dir = root / "static" / "support"
    if "--dir" in args:
        out_dir = pathlib.Path(args[args.index("--dir") + 1]).resolve()
    if not check:
        out_dir.mkdir(parents=True, exist_ok=True)
    bad = 0
    n = 0
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="qr-decode."))
    try:
        for e in entries(root / "data" / "support.yaml"):
            if e.get("kind") != "cryptocurrency":
                continue
            n += 1
            data = render(e["address"], e["coin"])
            target = out_dir / ("qr-%s.svg" % e["coin"])
            if check:
                if not target.exists() or target.read_bytes() != data:
                    print("differs: %s" % target)
                    bad = 1
            if not check:
                target.write_bytes(data)
                print("wrote %s" % target)
            if decode:
                got = decode_svg(target, tmp)
                if got != e["address"]:
                    print("decode FAILED: %s gave %r" % (target.name, got))
                    bad = 1
                else:
                    print("decoded %s: exact address" % target.name)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if n != 4:
        print("expected 4 cryptocurrency entries, found %d" % n)
        return 1
    return bad


sys.exit(main())
