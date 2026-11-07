#!/usr/bin/env python3
"""Size budget for the built site (docs/performance-gates.md, redesign brief section 10).

Usage: python3 -I scripts/check-budget.py [site-dir]        (default: public)

Static: nothing is fetched or run. For every HTML page it works out what a
browser downloads cold (the page, its stylesheets, every url() inside those
stylesheets, the <img> files, scripts) and compares sizes with the limits
below. Text types are measured gzip -9 (the host compresses them); files that
are already compressed (woff2, webp, png, jpeg, gif) are measured as stored.
The upper bound is used wherever the browser chooses: all url() references in
CSS count, and an <img srcset> counts its largest candidate.

Findings print as "[rule] path detail" and the exit status is 1; page content
is never printed. Rules: js-count, js-name, js-page, js-size, css-count, css-size,
font-count, font-size, html-size, image-size, image-file-size, page-total,
post-no-images, missing-asset, no-pages.

Limits (bytes; KB = 1024). Change one only with a reviewed edit to this file
and to docs/performance-gates.md.
"""
import gzip
import os
import re
import sys
from html.parser import HTMLParser

KB = 1024
# Pinned scripts (docs/pinned-script.md; scripts/check-site-artifact.sh pins their
# hashes) and the one page each may load on. Adding a pinned script is a reviewed
# edit here plus the docs and artifact rules; /theme.js was retired (issue 82).
PAGE_SCRIPTS = {"/copy.js": "/support/index.html"}
LIMITS = {
    # Same-origin scripts only, each under 1 KB gzip, and only the hash-pinned
    # ones in PAGE_SCRIPTS (the file count limit is the size of that table).
    "js_files": len(PAGE_SCRIPTS),
    "js_gzip": 1 * KB,
    # One stylesheet per page, 20 KB gzip (brief target 12 KB; today 4.1 KB).
    "css_files_per_page": 1,
    "css_gzip": 20 * KB,
    # Brief says 1 font under 30 KB; the brand kit ships two (Jost body, Orbitron
    # display), so: at most 2 font files per page, each under 30 KB transferred.
    "font_files_per_page": 2,
    "font_each": 30 * KB,
    "html_gzip": 15 * KB,
    # Largest image an <img> loads on any page; and any image file in the build
    # (the 1200x630 Open Graph card is the biggest and is never loaded by a page).
    "image_displayed": 120 * KB,
    "image_any": 300 * KB,
    "page_total": 150 * KB,
    # A post page without the images inside the post body.
    "post_no_images": 80 * KB,
}
SCRIPT_EXT = {"js", "mjs", "cjs"}
TEXT_EXT = {"html", "css", "svg", "xml", "txt", "ttf", "webmanifest"} | SCRIPT_EXT
IMAGE_EXT = {"png", "jpg", "jpeg", "gif", "webp", "avif", "ico", "svg"}
FONT_EXT = {"woff", "woff2", "ttf"}


def ext(path):
    return path.rsplit(".", 1)[-1].lower() if "." in path.rsplit("/", 1)[-1] else ""


def size(fs_path):
    """Transfer size: gzip -9 for text types, stored size otherwise."""
    with open(fs_path, "rb") as f:
        data = f.read()
    if ext(fs_path) in TEXT_EXT:
        return len(gzip.compress(data, 9, mtime=0))
    return len(data)


class Refs(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.css, self.js, self.img = [], [], []

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag == "link" and "stylesheet" in a.get("rel", "").lower().split():
            self.css.append(a.get("href", ""))
        elif tag == "script" and a.get("src"):
            self.js.append(a["src"])
        elif tag == "img":
            cands = [a.get("src", "")]
            for part in a.get("srcset", "").split(","):
                if part.strip():
                    cands.append(part.split()[0])
            self.img.append([c for c in cands if c])


def local(ref, page_url):
    """Site-relative path of a same-origin reference, or None when off-origin."""
    ref = ref.split("#", 1)[0].split("?", 1)[0]
    if not ref or re.match(r"^[a-z][a-z0-9+.-]*:|^//", ref, re.I):
        return None
    if ref.startswith("/"):
        return ref
    base = page_url.rsplit("/", 1)[0] + "/"
    parts = []
    for seg in (base + ref).split("/"):
        if seg == "..":
            if parts:
                parts.pop()
        elif seg and seg != ".":
            parts.append(seg)
    return "/" + "/".join(parts)


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "public")
    findings = []

    def bad(rule, path, detail=""):
        findings.append("[%s] %s%s" % (rule, path, (" " + detail) if detail else ""))

    def fs(url):
        return os.path.join(root, url.lstrip("/"))

    allfiles = []
    for d, _, names in os.walk(root):
        for n in names:
            allfiles.append("/" + os.path.relpath(os.path.join(d, n), root).replace(os.sep, "/"))
    pages = sorted(f for f in allfiles if f.endswith(".html"))
    if not pages:
        bad("no-pages", "/", "no HTML in the site directory")

    # Whole-build rules.
    js = [f for f in allfiles if ext(f) in SCRIPT_EXT]
    if len(js) > LIMITS["js_files"]:
        bad("js-count", "/", "%d script files, at most %d" % (len(js), LIMITS["js_files"]))
    for f in js:
        if f not in PAGE_SCRIPTS:
            bad("js-name", f, "only %s may ship" % " and ".join(PAGE_SCRIPTS))
        if size(fs(f)) > LIMITS["js_gzip"]:
            bad("js-size", f, "%d bytes gzip, limit %d" % (size(fs(f)), LIMITS["js_gzip"]))
    for f in allfiles:
        if ext(f) in IMAGE_EXT and size(fs(f)) > LIMITS["image_any"]:
            bad("image-file-size", f, "%d bytes, limit %d" % (size(fs(f)), LIMITS["image_any"]))

    css_cache = {}

    def css_urls(css_url):
        if css_url not in css_cache:
            with open(fs(css_url), "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            css_cache[css_url] = [
                u for u in (local(m.strip("\"' "), css_url) for m in re.findall(r"url\(([^)]*)\)", text)) if u
            ]
        return css_cache[css_url]

    for page in pages:
        # Alias stubs and tiny redirect pages are pages too; they pass trivially.
        refs = Refs()
        with open(fs(page), "r", encoding="utf-8", errors="replace") as fh:
            refs.feed(fh.read())
        total = size(fs(page))
        if total > LIMITS["html_gzip"]:
            bad("html-size", page, "%d bytes gzip, limit %d" % (total, LIMITS["html_gzip"]))
        no_images = total
        seen = set()

        def count(url, kind, page=page):
            nonlocal total, no_images
            if url in seen:
                return
            seen.add(url)
            if not os.path.isfile(fs(url)):
                bad("missing-asset", page, url)
                return
            n = size(fs(url))
            total += n
            if kind != "img":
                no_images += n
            return n

        css_list = [local(c, page) for c in refs.css]
        css_list = [c for c in css_list if c]
        if len(css_list) > LIMITS["css_files_per_page"]:
            bad("css-count", page, "%d stylesheets, at most %d" % (len(css_list), LIMITS["css_files_per_page"]))
        fonts = 0
        for c in css_list:
            n = count(c, "css")
            if n is None:
                continue
            if n > LIMITS["css_gzip"]:
                bad("css-size", c, "%d bytes gzip, limit %d" % (n, LIMITS["css_gzip"]))
            for u in css_urls(c):
                k = "font" if ext(u) in FONT_EXT else "asset"
                m = count(u, k)
                if k == "font":
                    fonts += 1
                    if m is not None and m > LIMITS["font_each"]:
                        bad("font-size", u, "%d bytes, limit %d" % (m, LIMITS["font_each"]))
        if fonts > LIMITS["font_files_per_page"]:
            bad("font-count", page, "%d font files, at most %d" % (fonts, LIMITS["font_files_per_page"]))
        for s in refs.js:
            u = local(s, page)
            if u:
                count(u, "js")
                if u in PAGE_SCRIPTS and page != PAGE_SCRIPTS[u]:
                    bad("js-page", page, "%s may load only on %s" % (u, PAGE_SCRIPTS[u]))
        for cands in refs.img:
            urls = [u for u in (local(c, page) for c in cands) if u]
            sizes = []
            for u in urls:
                if not os.path.isfile(fs(u)):
                    bad("missing-asset", page, u)
                    continue
                sizes.append((size(fs(u)), u))
            if not sizes:
                continue
            for n, u in sizes:
                if n > LIMITS["image_displayed"]:
                    bad("image-size", u, "%d bytes, limit %d" % (n, LIMITS["image_displayed"]))
            # Upper bound: the largest candidate. Count it once per page.
            n, u = max(sizes)
            if u not in seen:
                seen.add(u)
                total += n
        if total > LIMITS["page_total"]:
            bad("page-total", page, "%d bytes, limit %d" % (total, LIMITS["page_total"]))
        if page.startswith("/posts/") and page != "/posts/index.html" and no_images > LIMITS["post_no_images"]:
            bad("post-no-images", page, "%d bytes, limit %d" % (no_images, LIMITS["post_no_images"]))

    if findings:
        print("\n".join(findings))
        print("budget: %d finding(s) in %d page(s)" % (len(findings), len(pages)))
        return 1
    print("budget: ok (%d pages, %d files)" % (len(pages), len(allfiles)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
