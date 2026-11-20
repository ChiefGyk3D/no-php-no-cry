"""Reads a page, svg or xml file the way a browser reads its tags.

Usage: python3 -I scripts/scan-markup.py [--markup] [--scripts none|pinned] [--known /a.js,/b.js] [--allow /a.js] [--allow-email ADDRESS] [--cloudflare-beacon] [--cloudflare-precursor] <site-host> <file>

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
--cloudflare-precursor (HTML only, used by the smoke test on served pages, never by
the build check) also permits, at most once per page, the one inline script
Cloudflare Precursor injects at the edge: a script element with no attribute
whose whole body fullmatches PRECURSOR_BODY below. A second one is script-count;
any other body, or any attribute, is script-not-allowed as before. Without --scripts
it implies --scripts none. A self-closing script tag (<script/>, <SCRIPT />) is
script-not-allowed in every mode (a browser ignores the slash, this parser does
not), and a comment, CDATA, declaration or processing instruction inside a
candidate script refuses it.
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


# The inline script Cloudflare Precursor injects at the edge (observed
# 2026-11-20, issue 410): window.__CF$cv$params={...} then a loader that appends
# <script src=/cdn-cgi/challenge-platform/scripts/precursor/main.js?ray=RAY>.
# The whole body must match this one shape, byte for byte apart from the
# per-request values, which are matched by character class and length: the ray
# (16 lowercase hex, the same in params and loader), t (base64 of a 10 digit
# timestamp), u (32 hex), ut (token characters) and i (a small integer). No
# whitespace, statement or URL may be added before, inside or after it.
PRECURSOR_BODY = re.compile(
    r"window\.__CF\$cv\$params=\{r:'(?P<ray>[0-9a-f]{16})'"
    r",t:'[A-Za-z0-9+/]{14}=='"
    r",u:'[0-9a-f]{32}'"
    r",ut:'[A-Za-z0-9._-]{40,300}'"
    r",i:[0-9]{1,4}\};"
    r"\(function\(\)\{if\(!document\.body\)return;"
    r"var l=window\.location,o;"
    r"try\{o=new URL\(l\.origin\)\.origin\}"
    r"catch\(e\)\{try\{o=new URL\(new URL\(l\.href\)\.origin\)\.origin\}catch\(e\)\{o=''\}\}"
    r"var u='/cdn-cgi/challenge-platform/scripts/precursor/main\.js\?ray=(?P<loader>[0-9a-f]{16})',"
    r"s=document\.createElement\('script'\);"
    r"s\.src=o\?new URL\(u,o\)\.href:u;"
    r"document\.head\.appendChild\(s\);\}\)\(\);"
)


def precursor_body_ok(body):
    m = PRECURSOR_BODY.fullmatch(body)
    return bool(m) and m.group("ray") == m.group("loader")


class Scan(HTMLParser):
    def __init__(self, host, markup, scripts, known=(), allow="", allow_email="", cloudflare_beacon=False, precursor=False):
        super().__init__(convert_charrefs=True)
        self.allow_email = allow_email.lower()
        self.host, self.markup, self.scripts = host, markup, scripts
        self.known, self.allow = set(known), allow
        self.cloudflare_beacon = cloudflare_beacon
        self.cloudflare_beacons = 0
        self.precursor = precursor
        self.precursors = 0
        self.precursor_body = None  # the text of an open candidate script, else None
        self.found = set()
        self.pinned_tags = 0
        self.in_script = False
        self.in_style = False

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag.lower() == "script":
            # A browser ignores the slash of <script/> and reads script text up to
            # </script>, but this parser stays in markup mode: what it sees
            # (a comment, a tag) is not what the browser runs. Refuse the tag
            # in every mode, and never let it open or satisfy an allowance.
            self.found.add("script-not-allowed")
            self.precursor_body = None
            self.in_script = False

    def poison_candidate(self, *_):
        # Anything but plain text between a candidate's tags means the scanner's
        # text is not exactly the bytes a browser would run.
        if self.precursor_body is not None:
            self.found.add("script-not-allowed")
            self.precursor_body = None

    handle_comment = unknown_decl = handle_decl = handle_pi = poison_candidate

    def handle_data(self, data):
        if self.precursor_body is not None:
            self.precursor_body.append(data)
            return
        if self.allow_email:
            data = re.sub(re.escape(self.allow_email), "", data, flags=re.I)
        if not self.markup and not self.in_script and not self.in_style and EMAIL.search(data):
            self.found.add("email-shaped-text")
        if self.in_script and data.strip():
            self.found.add("script-not-allowed")

    def handle_endtag(self, tag):
        if tag.lower() == "script":
            self.in_script = False
            if self.precursor_body is not None:
                body = "".join(self.precursor_body)
                self.precursor_body = None
                if not precursor_body_ok(body):
                    self.found.add("script-not-allowed")
                else:
                    self.precursors += 1
                    if self.precursors > 1:
                        self.found.add("script-count")
        if tag.lower() == "style":
            self.in_style = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        is_cloudflare_beacon = False
        if tag == "style":
            self.in_style = True
        if tag == "script":
            raw = [(n.lower(), v or "") for n, v in attrs]
            raw_values = dict(raw)
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
                    and set(names) <= {"defer", "src", "integrity", "data-cf-beacon", "crossorigin", "type"}
                    and "integrity" in values
                    and raw_values.get("crossorigin") == "anonymous"
                    and ("type" not in raw_values or raw_values["type"].lower() == "module")
                    and re.fullmatch(r"https://static\.cloudflareinsights\.com/beacon\.min\.js/v[A-Za-z0-9._-]+", beacon_src)
                    and isinstance(beacon_config, dict) and isinstance(beacon_config.get("token"), str)
                    and beacon_config["token"]):
                is_cloudflare_beacon = True
                self.cloudflare_beacons += 1
                self.in_script = True
                if self.cloudflare_beacons > 1:
                    self.found.add("script-count")
            elif self.precursor and not self.markup and not attrs:
                # A bare <script> with no attribute at all is a candidate for
                # the Precursor snippet; its body is judged at </script>.
                self.precursor_body = []
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
    precursor = False
    args = list(argv)
    while args and args[0].startswith("--"):
        opt = args.pop(0)
        if opt == "--markup":
            markup = True
        elif opt == "--cloudflare-precursor":
            precursor = True
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
    if (cloudflare_beacon or precursor) and not scripts:
        scripts = "none"
    host, path = args[0].lower(), args[1]
    scan = Scan(host, markup, scripts, known, allow, allow_email, cloudflare_beacon, precursor)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            scan.feed(f.read())
        scan.close()
    except Exception:
        scan.found.add("unparseable-html")
    if scan.precursor_body is not None:
        # A candidate script that never closed is not the exact snippet.
        scan.found.add("script-not-allowed")
    if cloudflare_beacon and scan.cloudflare_beacons == 0:
        scan.found.add("missing-beacon")
    for rule in sorted(scan.found):
        print(rule)
    return 0


sys.exit(main(sys.argv[1:]))
