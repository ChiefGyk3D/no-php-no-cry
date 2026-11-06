"""SEO checks for scripts/check-output.sh. Prints findings, never page content.

Usage:
  python3 -I scripts/check-seo.py jsonld <home|article|other> <file>
      JSON-LD data blocks (<script type="application/ld+json">) in a page.
      Prints "bad-jsonld" when a block is not JSON, has another @context than
      https://schema.org, carries a personal-detail key (employer, first or last
      name, job title, email...), names a Person other than the display name,
      has a non-https sameAs; or, for a home page, lacks the Person, or, for an
      article, lacks the Article with headline, datePublished and the author.
  python3 -I scripts/check-seo.py site <dir> <site-host> <staging|production|"">
      "<rule>\t<path>" lines for: duplicate-description (two pages of the
      build share a description), bad-feed (index.xml lacks the atom self link
      on the site host), and, in production, missing-sitemap and bad-sitemap
      (sitemap.xml does not parse, lists a url off the host, a url with no
      lastmod, a redirect alias stub, a noindex page or a url with no page, or
      leaves out a post or journal entry).
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from xml.parsers import expat
from html.parser import HTMLParser

NAME = "ChiefGyk3D"
FORBIDDEN = {"givenName", "familyName", "additionalName", "worksFor", "jobTitle",
             "affiliation", "email", "telephone", "address", "birthDate", "alumniOf"}


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks, self.desc, self.robots, self.refresh = [], [], [], False
        self._ld = None

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "script" and a.get("type", "").lower() == "application/ld+json":
            self._ld = []
        elif tag == "meta":
            if a.get("name", "").lower() == "description":
                self.desc.append(a.get("content", ""))
            if a.get("name", "").lower() == "robots":
                self.robots.append(a.get("content", ""))
            if a.get("http-equiv", "").lower() == "refresh":
                self.refresh = True

    def handle_data(self, data):
        if self._ld is not None:
            self._ld.append(data)

    def handle_endtag(self, tag):
        if tag == "script" and self._ld is not None:
            self.blocks.append("".join(self._ld))
            self._ld = None


def parse(path):
    p = Page()
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            p.feed(f.read())
        p.close()
    except Exception:
        pass
    return p


def walk(x, bad):
    if isinstance(x, dict):
        for k, v in x.items():
            if k in FORBIDDEN:
                bad.add("forbidden key")
            if k == "sameAs":
                urls = v if isinstance(v, list) else [v]
                if not all(isinstance(u, str) and u.startswith("https://") for u in urls):
                    bad.add("sameAs not https")
            walk(v, bad)
        if x.get("@type") == "Person" and x.get("name") != NAME:
            bad.add("person name")
    elif isinstance(x, list):
        for v in x:
            walk(v, bad)


def jsonld(kind, path):
    p = parse(path)
    bad, nodes = set(), []
    for raw in p.blocks:
        try:
            d = json.loads(raw)
        except ValueError:
            bad.add("not json")
            continue
        if not isinstance(d, dict) or d.get("@context") != "https://schema.org":
            bad.add("context")
            continue
        nodes.extend(d["@graph"] if isinstance(d.get("@graph"), list) else [d])
        walk(d, bad)
    nodes = [n for n in nodes if isinstance(n, dict)]
    if kind == "home" and not [n for n in nodes if n.get("@type") == "Person"]:
        bad.add("home without Person")
    if kind == "article":
        arts = [n for n in nodes if n.get("@type") == "Article"]
        ok = len(arts) == 1 and arts[0].get("headline") and arts[0].get("datePublished") \
            and isinstance(arts[0].get("author"), dict) and arts[0]["author"].get("name") == NAME
        if not ok:
            bad.add("article incomplete")
    if bad:
        print("bad-jsonld")
    return 0


def pages(root):
    for dp, _, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith(".html"):
                yield os.path.join(dp, f)


def url_file(root, host, loc):
    m = re.match(r"^https://%s(/[^?#]*)$" % re.escape(host), loc)
    if not m:
        return None
    rel = m.group(1)
    cand = os.path.join(root, rel.lstrip("/"))
    if rel.endswith("/"):
        cand = os.path.join(cand, "index.html")
    return cand if os.path.isfile(cand) else ""


def site(root, host, env):
    out = []
    descs = {}
    for f in pages(root):
        p = parse(f)
        if p.refresh:
            continue
        rel = os.path.relpath(f, root)
        if len(p.desc) == 1 and p.desc[0].strip():
            descs.setdefault(p.desc[0].strip(), []).append(rel)
    for d, rels in sorted(descs.items()):
        if len(rels) > 1:
            out.append(("duplicate-description", ", ".join(sorted(rels))))
    # /index.xml needs the atom self link on the site host; the site feed
    # must name exactly its own address.
    for name, want in (("index.xml", None), ("feed/index.xml", "https://%s/feed/index.xml" % host)):
        feed = os.path.join(root, name)
        if not os.path.isfile(feed):
            continue
        ok = False
        try:
            atom = "{http://www.w3.org/2005/Atom}"
            ls = [l for l in load_xml(feed).iter(atom + "link") if l.get("rel") == "self"]
            href = (ls[0].get("href") or "") if len(ls) == 1 else ""
            ok = href == want if want else href.startswith("https://%s/" % host)
        except (ET.ParseError, OSError):
            pass
        if not ok:
            out.append(("bad-feed", "%s (needs one atom:link rel=self on %s)" % (name, want or "https://%s/" % host)))
    if env == "production":
        sm = os.path.join(root, "sitemap.xml")
        if not os.path.isfile(sm) or os.path.getsize(sm) == 0:
            out.append(("missing-sitemap", "sitemap.xml"))
        else:
            out.extend(("bad-sitemap", m) for m in sitemap(root, host, sm))
    for rule, where in out:
        print("%s\t%s" % (rule, where))
    return 0


def load_xml(path):
    """Root element of an XML file; a DOCTYPE or entity declaration is a parse error.

    The standard library tree parser would expand declared entities, and this
    checker takes no third-party packages, so a first expat pass refuses those
    declarations before the tree is built. Built output never carries one.
    """
    def refuse(*_):
        raise ET.ParseError("DTD and entity declarations are not allowed")

    with open(path, "rb") as fh:
        data = fh.read()
    scan = expat.ParserCreate()
    scan.StartDoctypeDeclHandler = refuse
    scan.EntityDeclHandler = refuse
    try:
        scan.Parse(data, True)
    except expat.ExpatError as exc:
        raise ET.ParseError(str(exc)) from exc
    return ET.fromstring(data)


def sitemap(root, host, path):
    ns = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
    try:
        tree = load_xml(path)
    except (ET.ParseError, OSError):
        return ["sitemap.xml (does not parse)"]
    bad, locs = [], set()
    for u in tree.iter(ns + "url"):
        loc = (u.findtext(ns + "loc") or "").strip()
        lm = (u.findtext(ns + "lastmod") or "").strip()
        locs.add(loc)
        f = url_file(root, host, loc)
        if f is None:
            bad.append("sitemap.xml (url off the site host)")
            continue
        if not lm or not re.match(r"^\d{4}-\d{2}-\d{2}(T|$)", lm):
            bad.append("sitemap.xml (url with no lastmod: %s)" % loc[len("https://" + host):])
        if f == "":
            bad.append("sitemap.xml (url with no page: %s)" % loc[len("https://" + host):])
            continue
        p = parse(f)
        if p.refresh:
            bad.append("sitemap.xml (lists a redirect alias: %s)" % loc[len("https://" + host):])
        if any("noindex" in r.lower() for r in p.robots) or os.path.basename(f) == "404.html":
            bad.append("sitemap.xml (lists a noindex page: %s)" % loc[len("https://" + host):])
    if not locs:
        bad.append("sitemap.xml (no urls)")
    for sec in ("posts", "journal"):
        d = os.path.join(root, sec)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            f = os.path.join(d, name, "index.html")
            if os.path.isfile(f) and not parse(f).refresh and \
                    "https://%s/%s/%s/" % (host, sec, name) not in locs:
                bad.append("sitemap.xml (leaves out /%s/%s/)" % (sec, name))
    return bad


def main(argv):
    if len(argv) == 3 and argv[0] == "jsonld":
        return jsonld(argv[1], argv[2])
    if len(argv) == 4 and argv[0] == "site":
        return site(argv[1], argv[2].lower(), argv[3])
    return 2


sys.exit(main(sys.argv[1:]))
