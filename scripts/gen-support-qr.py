#!/usr/bin/env python3
"""Write static/support/qr-<coin>.svg for every crypto entry in data/support.yaml.

Usage (through scripts/gen-support-qr.sh, which installs the pinned segno):
    gen-support-qr.py [--check] [--dir DIR]

--dir names the directory to write to or check (default static/support). The
page tests use it to compare the built site's copies with a fresh encoding.

The data file is read with a small line parser (the Python standard library has
no YAML reader); it understands only the "- key: value" list that
data/support.yaml documents. Each SVG is a black-on-white code with a four-module
quiet zone (a scanner needs the light ground, so it does not use the site
tokens), no script, no external reference, and a <desc> holding the encoded
text, which scripts/test-pages.sh compares with data/support.yaml.
"""
import io
import pathlib
import sys

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


def render(text):
    buf = io.BytesIO()
    segno.make(text, error="m", micro=False).save(
        buf, kind="svg", scale=4, border=4, dark="#000000", light="#ffffff",
        xmldecl=False, svgns=True, nl=False, omitsize=False, title=None,
        desc=text, lineclass=None, svgid=None)
    return buf.getvalue()


def main():
    args = sys.argv[1:]
    check = "--check" in args
    out_dir = root / "static" / "support"
    if "--dir" in args:
        out_dir = pathlib.Path(args[args.index("--dir") + 1]).resolve()
    if not check:
        out_dir.mkdir(parents=True, exist_ok=True)
    bad = 0
    n = 0
    for e in entries(root / "data" / "support.yaml"):
        if e.get("kind") != "crypto":
            continue
        n += 1
        data = render(e["address"])
        target = out_dir / ("qr-%s.svg" % e["coin"])
        if check:
            if not target.exists() or target.read_bytes() != data:
                print("differs: %s" % target)
                bad = 1
        else:
            target.write_bytes(data)
            print("wrote %s" % target)
    if n != 4:
        print("expected 4 crypto entries, found %d" % n)
        return 1
    return bad


sys.exit(main())
