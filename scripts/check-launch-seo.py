"""Launch SEO check for an already built, production-mode output directory.

Usage:
  python3 -I scripts/check-launch-seo.py <output-dir> <production-host>

Run it before the apex cutover on a build made for the apex, for example:
  HUGO_PARAMS_ENVIRONMENT=production hugo --minify --baseURL https://chiefgyk3d.com/ -d out
  python3 -I scripts/check-launch-seo.py out chiefgyk3d.com

Prints "<rule>\\t<detail>" lines and exits 1 when there are findings, 0 when the
build is ready to be indexed. The rules:
  noindex             a page carries a robots meta that says noindex or none (404.html is
                      noindex on purpose and is skipped)
  robots-missing      no robots.txt
  robots-disallow-all robots.txt disallows everything for all agents, Googlebot or Bingbot
  header-noindex      _headers sets an X-Robots-Tag with noindex or none (any path block)
  robots-no-sitemap   robots.txt has no Sitemap line
  robots-host         the Sitemap line is not on the production host
  sitemap-missing     no sitemap.xml, or it does not parse or lists no url
  sitemap-host        a sitemap url is not https on the production host
  canonical-missing   an indexable page has no canonical link
  canonical-host      a canonical is not an absolute https url on the production host
  title-missing       a page has no title or an empty one
  title-duplicate     two pages share a title
  description-missing a page has no meta description or an empty one
  description-duplicate two pages share a description
  redirects-missing   no _redirects file, or no 301 rule, or no rule for /feed
                      (the old WordPress feed address)
Standard library only. Prints paths and rule names, never page content.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

SM = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
# robots.txt groups whose Disallow: / makes the site invisible to the search engines that matter
SEARCH_AGENTS = ("*", "googlebot", "bingbot")


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title, self.in_title, self.has_title = "", False, False
        self.desc, self.robots, self.canon, self.refresh = [], [], [], False

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "title":
            self.in_title, self.has_title = True, True
        elif tag == "meta":
            name = a.get("name", "").lower()
            if name == "description":
                self.desc.append(a.get("content", ""))
            elif name in ("robots", "googlebot"):
                self.robots.append(a.get("content", ""))
            elif a.get("http-equiv", "").lower() == "refresh":
                self.refresh = True
        elif tag == "link" and "canonical" in a.get("rel", "").lower().split():
            self.canon.append(a.get("href", ""))

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title += data


def parse(path):
    p = Page()
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            p.feed(f.read())
        p.close()
    except (OSError, ValueError):
        pass
    return p


def html_files(root):
    for dp, _, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith(".html"):
                yield os.path.join(dp, f)


def host_of(url):
    m = re.match(r"^https://([^/?#:@]+)(?:[/?#]|$)", url or "")
    return m.group(1).lower() if m else None


def robots_findings(root, host):
    out = []
    path = os.path.join(root, "robots.txt")
    if not os.path.isfile(path):
        return [("robots-missing", "robots.txt")]
    agents, sitemaps = [], []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if ":" not in line:
                continue
            k, v = (s.strip() for s in line.split(":", 1))
            k = k.lower()
            if k == "user-agent":
                if agents and agents[-1][1]:
                    agents = []
                agents.append((v, False))
            elif k == "disallow" and v == "/" and any(a.lower() in SEARCH_AGENTS for a, _ in agents):
                out.append(("robots-disallow-all", "robots.txt"))
            elif k == "sitemap":
                sitemaps.append(v)
            if k != "user-agent" and agents:
                agents = [(a, True) for a, _ in agents]
    if not sitemaps:
        out.append(("robots-no-sitemap", "robots.txt"))
    for s in sitemaps:
        if host_of(s) != host:
            out.append(("robots-host", "robots.txt"))
            break
    return sorted(set(out))


def sitemap_findings(root, host):
    path = os.path.join(root, "sitemap.xml")
    try:
        with open(path, "rb") as f:
            data = f.read()
        if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
            return [("sitemap-missing", "sitemap.xml (DTD or entity declaration)")]
        tree = ET.fromstring(data)
    except (OSError, ET.ParseError):
        return [("sitemap-missing", "sitemap.xml")]
    locs = [(u.findtext(SM + "loc") or "").strip() for u in tree.iter(SM + "url")]
    if not locs:
        return [("sitemap-missing", "sitemap.xml lists no url")]
    return [("sitemap-host", loc) for loc in locs if host_of(loc) != host]


def redirects_findings(root):
    path = os.path.join(root, "_redirects")
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            rules = [l.split() for l in f if l.strip() and not l.lstrip().startswith("#")]
    except OSError:
        return [("redirects-missing", "_redirects")]
    rules = [r for r in rules if len(r) == 3 and r[2] == "301"]
    if not rules:
        return [("redirects-missing", "_redirects has no 301 rule")]
    if not any(r[0].rstrip("/") == "/feed" for r in rules):
        return [("redirects-missing", "_redirects has no rule for /feed")]
    return []


def headers_findings(root):
    """An X-Robots-Tag with noindex (or none) in _headers, in any path block, blocks indexing."""
    try:
        with open(os.path.join(root, "_headers"), encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return []  # no header file, no header
    out = []
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if line.startswith("#") or ":" not in line:
            continue
        k, v = (x.strip() for x in line.split(":", 1))
        if k.lower() == "x-robots-tag" and re.search(r"\b(noindex|none)\b", v.lower()):
            out.append(("header-noindex", "_headers line %d" % n))
    return out


def page_findings(root, host):
    out, titles, descs = [], {}, {}
    for f in html_files(root):
        rel = os.path.relpath(f, root)
        p = parse(f)
        if p.refresh:  # an alias redirect stub, not a page
            continue
        is404 = rel == "404.html"
        if any(re.search(r"\b(noindex|none)\b", r.lower()) for r in p.robots) and not is404:
            out.append(("noindex", rel))
        t = p.title.strip()
        if not t:
            out.append(("title-missing", rel))
        elif not is404:
            titles.setdefault(t, []).append(rel)
        d = p.desc[0].strip() if p.desc else ""
        if not d:
            out.append(("description-missing", rel))
        elif not is404:
            descs.setdefault(d, []).append(rel)
        if not is404:
            if not p.canon:
                out.append(("canonical-missing", rel))
            elif len(p.canon) != 1 or host_of(p.canon[0]) != host:
                out.append(("canonical-host", rel))
    for rule, seen in (("title-duplicate", titles), ("description-duplicate", descs)):
        for rels in seen.values():
            if len(rels) > 1:
                out.append((rule, ", ".join(sorted(rels))))
    return out


def main(argv):
    if len(argv) != 3 or not re.fullmatch(r"[A-Za-z0-9.-]+", argv[2]):
        print("usage: check-launch-seo.py <output-dir> <production-host>", file=sys.stderr)
        return 2
    root, host = argv[1], argv[2].lower()
    if not os.path.isdir(root):
        print("input: %s is not a directory" % root, file=sys.stderr)
        return 2
    found = robots_findings(root, host) + sitemap_findings(root, host) \
        + redirects_findings(root) + headers_findings(root) + page_findings(root, host)
    for rule, where in sorted(found):
        print("%s\t%s" % (rule, where))
    if found:
        print("check-launch-seo: %d finding(s)" % len(found))
        return 1
    print("check-launch-seo: ok (%s)" % host)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
