#!/usr/bin/env python3
"""Fixture site for scripts/test-browser-gate.sh. Not part of the build.

Usage: fixture-site.py DIR              write the good fixture into DIR
       fixture-site.py DIR MUTATION     break one rule in an existing copy

The good fixture passes every browser-gate rule; each mutation breaks one.
"""
import os
import struct
import sys
import zlib

GOOD_HTML = """<!doctype html>
<html lang="en-us"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Fixture</title><link rel="icon" href="/pic.png"><link rel="stylesheet" href="/site.css"></head>
<body><a class="skip" href="#main">Skip to main content</a>
<header><nav aria-label="Main"><div class="nav-menu"><button class="nav-toggle" type="button" popovertarget="nav-list">Menu</button><ul id="nav-list" popover><li><a href="/a/">One</a></li><li><a href="/b/">Two</a></li></ul></div></nav></header>
<main id="main"><h1>Fixture</h1><p>Some text with an <a href="/inline/">inline link</a> in it.</p><img src="/pic.png" width="64" height="64" alt="A gray square"><ul class="tiles"><li class="tile"><span class="handle">@someone<wbr><span class="part">@host.example.org</span></span></li></ul></main>
<footer><a href="/c/">Three</a></footer></body></html>
"""
GOOD_CSS = (
    "body{margin:0;background:#101010;color:#eee;font:16px/1.5 sans-serif}"
    "a{color:#fbb03b}a:focus{outline:3px solid #fbb03b;outline-offset:2px}"
    ".skip{position:absolute;left:-999px}.skip:focus{left:0;background:#000;padding:12px}"
    "nav a,footer a{display:inline-flex;align-items:center;min-height:44px;min-width:44px}"
    ".nav-toggle{min-height:44px;min-width:44px;font:inherit}"
    ".nav-menu ul{position:absolute;top:60px;left:0;right:0;margin:0;padding:0;list-style:none;background:#222;border:0}"
    "@media(min-width:64rem){.nav-menu .nav-toggle{display:none}.nav-menu ul{position:static;display:flex;gap:8px;background:none}}"
    "main{padding:16px}"
    ".tiles{list-style:none;margin:0;padding:0}.tile{width:12rem;border:1px solid #888;padding:8px;box-sizing:border-box}.part{white-space:nowrap}"
    ".wide{width:3000px;height:1px;background:#fff}"
    ".small{display:block;width:30px;height:20px;min-width:0;min-height:0}"
)


def png(path, w, h, stored):
    row = b"\0" + (os.urandom(w * 3) if stored else b"\x20" * (w * 3))
    raw = row * h

    def chunk(t, data):
        return struct.pack(">I", len(data)) + t + data + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 0 if stored else 9)) + chunk(b"IEND", b""))


def edit(d, name, old, new):
    p = os.path.join(d, name)
    with open(p, "r", encoding="utf-8") as f:
        s = f.read()
    if old not in s:
        raise SystemExit("fixture-site: %r not found in %s" % (old, name))
    with open(p, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new, 1))


def write(d, name, text):
    with open(os.path.join(d, name), "w", encoding="utf-8") as f:
        f.write(text)


def mutate(d, m):
    if m == "overflow":
        edit(d, "index.html", "<h1>", '<div class="wide"></div><h1>')
    elif m == "tile-overflow":
        # A part that cannot wrap and is wider than its tile.
        edit(d, "index.html", "@host.example.org", "@a-very-long-host-name-that-cannot-wrap.example.org")
    elif m == "tile-overflow-vertical":
        # A child that protrudes below its tile (absolutely placed, inside the
        # tile's width): only a vertical comparison catches it.
        edit(d, "site.css", ".part{", ".tile{position:relative}.tile .drop{position:absolute;left:8px;top:100%;margin-top:20px;width:40px;height:20px;background:#888}.part{")
        edit(d, "index.html", '<li class="tile">', '<li class="tile"><span class="drop"></span>')
    elif m == "console":
        write(d, "theme.js", "console.error('boom');")
        edit(d, "index.html", "</head>", '<script src="/theme.js"></script></head>')
    elif m == "missing-file":
        edit(d, "index.html", "<footer>", '<img src="/gone.png" width="1" height="1" alt=""><footer>')
    elif m == "off-site":
        os.remove(os.path.join(d, "_headers"))  # no CSP, so the request is attempted
        edit(d, "index.html", "<footer>", '<img src="http://127.0.0.2:9/x.png" width="1" height="1" alt=""><footer>')
    elif m == "no-alt":
        edit(d, "index.html", ' alt="A gray square"', "")
    elif m == "small-target":
        edit(d, "index.html", "<footer>", '<footer><a class="small" href="/d/">x</a>')
    elif m == "tab-order":
        edit(d, "index.html", '<a href="/b/">', '<a href="/b/" tabindex="3">')
    elif m == "no-focus-ring":
        edit(d, "site.css", "main{", "a:focus{outline:none !important}main{")
    elif m == "no-skip-link":
        edit(d, "index.html", '<a class="skip" href="#main">Skip to main content</a>', "")
    elif m == "layout-shift":
        # Deterministic: a block is inserted above the heading 400 ms after the
        # script runs, long after first paint and inside the gate's 700 ms window.
        # (An image that arrives late shifts only if its size is learned after
        # first paint, which is a race that a fast runner can win.)
        write(d, "shift.js", "setTimeout(function () { var b = document.createElement('div'); b.style.height = '300px'; document.body.insertBefore(b, document.body.firstChild); }, 400);")
        edit(d, "index.html", "</head>", '<script src="/shift.js"></script></head>')
    elif m == "slow-lcp":
        edit(d, "index.html", '<img src="/pic.png" width="64" height="64"', '<img src="/big.png" width="512" height="512"')
    elif m == "low-res-image":
        # The 64 px file is drawn 128 px wide (a class, not a style attribute: the CSP forbids inline style).
        edit(d, "site.css", "main{", ".up{width:128px;height:128px}main{")
        edit(d, "index.html", '<img src="/pic.png" width="64" height="64"', '<img class="up" src="/pic.png" width="64" height="64"')
    elif m == "menu-escape":
        # A manual popover has no light dismiss: Escape no longer closes it.
        edit(d, "index.html", '<ul id="nav-list" popover>', '<ul id="nav-list" popover="manual">')
    elif m == "overflow-393":
        # Overflows only at exactly 393 x 852 (the iPhone 15 viewport), not at 390 x 844.
        edit(d, "site.css", "main{", "@media(min-width:393px) and (max-width:393px) and (min-height:852px) and (max-height:852px){main{width:3000px}}main{")
    elif m == "tall":
        edit(d, "site.css", "main{", ".tall{height:2000px}main{")  # a class, not a style attribute: the CSP forbids inline style
        edit(d, "index.html", "<footer>", '<div class="tall"></div><footer>')
    elif m in ("hero-wrap", "hero-ok"):
        # Issue 308: three wide hero buttons wrap at 1878 and 1366; narrow ones share a row.
        width = "700px" if m == "hero-wrap" else "100px"
        edit(d, "site.css", "main{", ".hero-actions{display:flex;flex-wrap:wrap;gap:8px}.hero-actions a{display:inline-flex;align-items:center;justify-content:center;min-height:44px;width:%s}main{" % width)
        edit(d, "index.html", "</main>", '<p class="hero-actions"><a href="/x/">One</a><a href="/y/">Two</a><a href="/z/">Three</a></p></main>')
    elif m in ("box-dead", "box-ok"):
        # Issue 308: a wide bordered box whose text keeps a narrow column leaves its right side empty.
        mx = "40ch" if m == "box-dead" else "none"
        edit(d, "site.css", "main{", ".panel{border:1px solid #888;padding:16px}.panel p{max-width:%s}main{" % mx)
        text = "Long running text that wraps over several lines inside a wide box. " * 6
        edit(d, "index.html", "</main>", '<div class="panel"><p>%s</p></div></main>' % text)
    elif m == "toggle-missing":
        write(d, "theme.js", "document.title = 'x';")
        edit(d, "index.html", "</head>", '<script src="/theme.js"></script></head>')
    else:
        raise SystemExit("fixture-site: unknown mutation " + m)


def main():
    d = sys.argv[1]
    if len(sys.argv) > 2:
        mutate(d, sys.argv[2])
        return
    os.makedirs(d, exist_ok=True)
    png(d + "/pic.png", 64, 64, False)
    png(d + "/big.png", 512, 512, True)  # about 780 KB, stored: seconds on a 1.6 Mbps link
    write(d, "site.css", GOOD_CSS)
    write(d, "index.html", GOOD_HTML)


if __name__ == "__main__":
    main()
