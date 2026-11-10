"""Reads a page, svg or xml file the way a browser reads its tags.

Usage: python3 -I scripts/scan-markup.py [--markup] [--scripts none|pinned] [--known /a.js,/b.js] [--allow /a.js] [--allow-email ADDRESS] [--cloudflare-beacon] <site-host> <file>

Prints one rule name per line, never page content. Attributes are read from real
attributes by a quote-aware parser (a ">" or "=" inside a quoted value is just
text). Character references in values are decoded; tabs and newlines are dropped
from a URL and leading control characters and spaces trimmed, as a browser does.

Rules, for any file: event-handler (an on* attribute), javascript-url.
HTML mode (default) also: base-element, http-reference, external-asset (an
http:, https:, scheme-relative or backslash URL to another host on a tag that
loads something). --markup (svg, xml, xhtml) also: script-not-allowed for any
script element. HTML mode also email-shaped-text: a text node (outside
script and style) holding user@host, or a mailto: URL (except the exact share link shape: mailto:?subject=V&body=V, V percent-encoded with no email-shaped text once decoded; issue 220). Cloudflare Email
Obfuscation rewrites those to "[email protected]" and injects a script; render
a handle with the @ in its own element instead. --scripts none|pinned (HTML
only, used on served pages) also judges script elements: with "none" any script
element is script-not-allowed;
with "pinned" the pinned scripts are the ones named by --known (the allowlist
of scripts/artifact-rules.sh, as /name paths), and --allow names the one that
belongs on THIS page: <script src=/NAME></script> for that name is allowed once
(a second is script-count); the same tag for any other known script is
script-wrong-page; any other form, attribute or body is script-not-allowed.
A <script type="application/ld+json"> data block (that one attribute, nothing
else) is not a script in either mode: a browser never runs it and script-src
does not apply. Its body is judged by scripts/check-seo.py. In --markup mode
every script element is still refused.
--cloudflare-beacon requires exactly one Cloudflare Web Analytics tag with a
versioned Insights URL and a nonempty public token. It permits only that remote
script; every other script rule remains active.
--allow-email ADDRESS (HTML mode) exempts that one address, as page text and as a
mailto: link to exactly that address, from email-shaped-text. The caller passes it
only for the page that publishes the owner-approved business address (About);
any other address on that page, or on any other page, is still a finding.
"""
import json
import re
import sys
from urllib.parse import unquote
from html.parser import HTMLParser

LOADS = {"img", "script", "iframe", "frame", "source", "link", "video", "audio",
         "embed", "object", "form", "input", "track", "base"}
URL_ATTRS = {"src", "href", "poster", "action", "data", "formaction", "xlink:href",
             "background", "ping", "manifest", "codebase"}


EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]")


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


# The Email share link (layouts/_partials/share.html, issue 220) is exactly
# mailto:?subject=V&body=V with V made of unreserved characters and uppercase %XX
# escapes. Anything else (another key, another order, another case, a raw space or
# a raw "@", an address) stays a finding, and so does a V that decodes to
# something email-shaped (a %40 smuggled in).
SHARE_MAILTO = re.compile(r"^mailto:\?subject=((?:[A-Za-z0-9._~-]|%[0-9A-F]{2})*)&body=((?:[A-Za-z0-9._~-]|%[0-9A-F]{2})*)$")


def share_mailto_ok(v):
    m = SHARE_MAILTO.match(v)
    return bool(m) and not any(re.search(r"[^\s@]+@[^\s@]+", unquote(g, errors="replace")) for g in m.groups())


class Scan(HTMLParser):
    def __init__(self, host, markup, scripts, known=(), allow="", allow_email="", cloudflare_beacon=False):
        super().__init__(convert_charrefs=True)
        self.allow_email = allow_email.lower()
        self.host, self.markup, self.scripts = host, markup, scripts
        self.known, self.allow = set(known), allow
        self.cloudflare_beacon = cloudflare_beacon
        self.cloudflare_beacons = 0
        self.found = set()
        self.pinned_tags = 0
        self.in_script = False
        self.in_style = False

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_data(self, data):
        if self.allow_email:
            data = re.sub(re.escape(self.allow_email), "", data, flags=re.I)
        if not self.markup and not self.in_script and not self.in_style and EMAIL.search(data):
            self.found.add("email-shaped-text")
        if self.in_script and data.strip():
            self.found.add("script-not-allowed")

    def handle_endtag(self, tag):
        if tag.lower() == "script":
            self.in_script = False
        if tag.lower() == "style":
            self.in_style = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        is_cloudflare_beacon = False
        if tag == "style":
            self.in_style = True
        if tag == "script":
            plain = [(n.lower(), clean(v)) for n, v in attrs]
            names = [n for n, _ in plain]
            values = dict(plain)
            beacon_src = values.get("src", "")
            beacon_data = values.get("data-cf-beacon", "")
            try:
                beacon_config = json.loads(beacon_data)
            except (json.JSONDecodeError, TypeError):
                beacon_config = {}
            if (self.cloudflare_beacon and not self.markup
                    and len(names) == len(set(names))
                    and set(names) <= {"defer", "src", "integrity", "data-cf-beacon", "crossorigin"}
                    and re.fullmatch(r"https://static\.cloudflareinsights\.com/beacon\.min\.js/v[A-Za-z0-9._-]+", beacon_src)
                    and isinstance(beacon_config, dict) and isinstance(beacon_config.get("token"), str)
                    and beacon_config["token"]):
                is_cloudflare_beacon = True
                self.cloudflare_beacons += 1
                self.in_script = True
                if self.cloudflare_beacons > 1:
                    self.found.add("script-count")
            elif not self.markup and [(n.lower(), clean(v).lower()) for n, v in attrs] == [("type", "application/ld+json")]:
                # A JSON-LD data block: never run, not subject to script-src.
                # Its body is judged by scripts/check-seo.py.
                self.in_script = False
            elif self.markup or self.scripts == "none":
                self.found.add("script-not-allowed")
            elif self.scripts == "pinned":
                self.in_script = True
                if len(plain) == 1 and plain[0][0] == "src" and plain[0][1] in self.known:
                    if plain[0][1] != self.allow:
                        self.found.add("script-wrong-page")
                    else:
                        self.pinned_tags += 1
                        if self.pinned_tags > 1:
                            self.found.add("script-count")
                else:
                    self.found.add("script-not-allowed")
        if tag == "base" and not self.markup:
            self.found.add("base-element")
        for name, value in attrs:
            name = name.lower()
            v = clean(value)
            if not self.markup and re.match(r"^mailto:", v, re.I) and not share_mailto_ok(v) and not (self.allow_email and v.lower() == "mailto:" + self.allow_email):
                self.found.add("email-shaped-text")
            if re.match(r"^on[a-z]", name):
                self.found.add("event-handler")
            if re.match(r"^javascript:", v, re.I) or re.search(r"url\s*=\s*['\"]?\s*javascript:", v, re.I):
                self.found.add("javascript-url")
            if self.markup or tag not in LOADS:
                continue
            if is_cloudflare_beacon and name == "src":
                continue
            # <link rel=me> is an identity claim (Mastodon, GitHub read it); nothing is fetched.
            if tag == "link" and clean(dict(attrs).get("rel")).lower().split() == ["me"]:
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
    markup, scripts, known, allow, allow_email, cloudflare_beacon = False, "", [], "", "", False
    args = list(argv)
    while args and args[0].startswith("--"):
        opt = args.pop(0)
        if opt == "--markup":
            markup = True
        elif opt == "--cloudflare-beacon":
            cloudflare_beacon = True
        elif opt == "--scripts" and args:
            scripts = args.pop(0)
        elif opt == "--known" and args:
            known = [k for k in args.pop(0).split(",") if k]
        elif opt == "--allow" and args:
            allow = args.pop(0)
        elif opt == "--allow-email" and args:
            allow_email = args.pop(0)
        else:
            return 2
    if len(args) != 2:
        return 2
    host, path = args[0].lower(), args[1]
    scan = Scan(host, markup, scripts, known, allow, allow_email, cloudflare_beacon)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            scan.feed(f.read())
        scan.close()
    except Exception:
        scan.found.add("unparseable-html")
    if cloudflare_beacon and scan.cloudflare_beacons == 0:
        scan.found.add("missing-beacon")
    for rule in sorted(scan.found):
        print(rule)
    return 0


sys.exit(main(sys.argv[1:]))
