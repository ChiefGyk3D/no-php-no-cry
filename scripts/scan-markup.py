"""Reads a page, svg or xml file the way a browser reads its tags.

Usage: python3 -I scripts/scan-markup.py [--markup] [--scripts none|theme] <site-host> <file>

Prints one rule name per line, never page content. Attributes are read from real
attributes by a quote-aware parser (a ">" or "=" inside a quoted value is just
text). Character references in values are decoded; tabs and newlines are dropped
from a URL and leading control characters and spaces trimmed, as a browser does.

Rules, for any file: event-handler (an on* attribute), javascript-url.
HTML mode (default) also: base-element, http-reference, external-asset (an
http:, https:, scheme-relative or backslash URL to another host on a tag that
loads something). --markup (svg, xml, xhtml) also: script-not-allowed for any
script element. --scripts none|theme (HTML only, used on served pages) also
judges script elements: with "none" any script element is script-not-allowed;
with "theme" only one <script src=/theme.js></script> is allowed (a second is
script-count, any other form, attribute or body is script-not-allowed).
"""
import re
import sys
from html.parser import HTMLParser

LOADS = {"img", "script", "iframe", "frame", "source", "link", "video", "audio",
         "embed", "object", "form", "input", "track", "base"}
URL_ATTRS = {"src", "href", "poster", "action", "data", "formaction", "xlink:href",
             "background", "ping", "manifest", "codebase"}


def clean(value):
    value = re.sub(r"[\t\n\r]", "", value or "")
    return re.sub(r"^[\x00-\x20]+", "", value)


def judge(url, host):
    url = url.replace("\\", "/")
    m = re.match(r"^(https?:)?//([^/?#]*)", url, re.I)
    if not m:
        return ""
    netloc = m.group(2).lower().rsplit("@", 1)[-1]
    name = netloc.rsplit(":", 1)[0] if re.search(r":\d*$", netloc) else netloc
    rule = "http" if m.group(1) and m.group(1).lower() == "http:" else ""
    if name != host:
        return "external" if not rule else "external-http"
    return rule


class Scan(HTMLParser):
    def __init__(self, host, markup, scripts):
        super().__init__(convert_charrefs=True)
        self.host, self.markup, self.scripts = host, markup, scripts
        self.found = set()
        self.theme_tags = 0
        self.in_script = False

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_data(self, data):
        if self.in_script and data.strip():
            self.found.add("script-not-allowed")

    def handle_endtag(self, tag):
        if tag.lower() == "script":
            self.in_script = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag == "script":
            if self.markup or self.scripts == "none":
                self.found.add("script-not-allowed")
            elif self.scripts == "theme":
                self.in_script = True
                plain = [(n.lower(), clean(v)) for n, v in attrs]
                if plain == [("src", "/theme.js")]:
                    self.theme_tags += 1
                    if self.theme_tags > 1:
                        self.found.add("script-count")
                else:
                    self.found.add("script-not-allowed")
        if tag == "base" and not self.markup:
            self.found.add("base-element")
        for name, value in attrs:
            name = name.lower()
            v = clean(value)
            if re.match(r"^on[a-z]", name):
                self.found.add("event-handler")
            if re.match(r"^javascript:", v, re.I) or re.search(r"url\s*=\s*['\"]?\s*javascript:", v, re.I):
                self.found.add("javascript-url")
            if self.markup or tag not in LOADS:
                continue
            urls = []
            if name in URL_ATTRS:
                urls = [v]
            elif name in ("srcset", "imagesrcset"):
                urls = [clean(part.strip().split(" ")[0]) for part in (value or "").split(",")]
            for u in urls:
                kind = judge(u, self.host)
                if kind in ("http", "external-http"):
                    self.found.add("http-reference")
                if kind in ("external", "external-http"):
                    self.found.add("external-asset")


def main(argv):
    markup, scripts = False, ""
    args = list(argv)
    while args and args[0].startswith("--"):
        opt = args.pop(0)
        if opt == "--markup":
            markup = True
        elif opt == "--scripts" and args:
            scripts = args.pop(0)
        else:
            return 2
    if len(args) != 2:
        return 2
    host, path = args[0].lower(), args[1]
    scan = Scan(host, markup, scripts)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            scan.feed(f.read())
        scan.close()
    except Exception:
        scan.found.add("unparseable-html")
    for rule in sorted(scan.found):
        print(rule)
    return 0


sys.exit(main(sys.argv[1:]))
