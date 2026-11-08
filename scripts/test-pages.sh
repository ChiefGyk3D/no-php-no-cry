#!/usr/bin/env bash
# Test the Support, About and Privacy pages (issue 62) against the built site.
#
# Builds the site into the repository's gitignored tmp/ (never /tmp) and asserts,
# with Python's stdlib HTML parser, the approved layout and wording of /support/,
# /about/ and /privacy/, the /contact/ redirect, the wallet addresses and their
# pre-generated QR files, and that the CSP gained no frame-src. Needs the pinned
# Hugo; a missing Hugo is a failure, not a skip. A guard self-test feeds the
# asserter a page that breaks each rule and requires a failure.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/pages.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

if ! command -v hugo >/dev/null 2>&1; then
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
fi

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

asserter="$work/assert_pages.py"
cat >"$asserter" <<'PY'
import html
import os
import re
import sys
from html.parser import HTMLParser

# The authoritative wallet addresses: github.com/ChiefGyk3D/support-me
# SIGNATURE.md (read 2026-11-04). A second copy lives here on purpose: a change
# to data/support.yaml must be a reviewed change to this test too.
ADDRESSES = {
    "btc": "bc1qztdzcy2wyavj2tsuandu4p0tcklzttvdnzalla",
    "xmr": "84Y34QubRwQYK2HNviezeH9r6aRcPvgWmKtDkN3EwiuVbp6sNLhm9ffRgs6BA9X1n9jY7wEN16ZEpiEngZbecXseUrW8SeQ",
    "eth": "0x554f18cfB684889c3A60219BDBE7b050C39335ED",
    "sol": "5T8h3HbyvHgLxwXgchRYbHSqRjZyAr8J7uwjLN9Fh8Jh",
}
BUTTONS = {
    "StreamElements": "https://streamelements.com/chiefgyk3d/tip",
    "Ko-fi": "https://ko-fi.com/chiefgyk3d",
    "Patreon": "https://patreon.com/chiefgyk3d",
    "Shop merch": "https://shop.chiefgyk3d.com/",
}
PRIVACY = [
    "The code of this site sets no cookies and embeds nothing from other sites. "
    "Following a link takes you to another site, which has its own policies.",
    "The site is hosted on Cloudflare Pages, and Cloudflare Web Analytics is turned on for it. "
    "The content security policy on this site allows that analytics script and nothing else from outside. "
    "Cloudflare describes Web Analytics as collecting page-load timing and the country, "
    "browser, referring site, and page path of each visit, without cookies and without personal data. "
    "This page does not describe what Cloudflare logs on its own, such as request or security records.",
]
# Claims the config cannot establish. The page must not make them (issue 159).
PRIVACY_FORBIDDEN = ["I collect nothing", "collects nothing", "stores nothing", "no logs", "no analytics",
                     "likely block", "blocked"]
SKILL_GROUPS = [
    "Identity and access",
    "Endpoint, email, and data security",
    "Network security and zero trust",
    "Security operations and investigation",
    "Cloud, infrastructure as code, and secrets",
    "Linux and homelab",
    "Software and automation",
    "Local AI and agents",
    "Radio, RF, and telecom",
    "Where I'm headed",
]
MISSION_START = "I make cybersecurity knowledge available to more than 500K followers across all platforms"
MISSION_END = "You're not dead until you stop learning. Happy Hacking."
FOOTER_LINE = "You're not dead until you stop learning. Happy Hacking."
CONTACT = ("There's no contact form. If you want to chat as part of the community, use the Matrix room "
           "or the Discord server. The two are bridged.")
CONTACT_SOON = " Business inquiries go by email, and the address will be listed here soon."


def contact_data():
    """The contact block of data/about.yaml (email, pgp_fingerprint, pgp_url), empty strings when unset."""
    text = open(os.environ["ABOUT_DATA"], encoding="utf-8").read()
    out = {}
    for k in ("email", "pgp_fingerprint", "pgp_url"):
        m = re.search(r'^  %s: "(.*)"$' % k, text, re.M)
        out[k] = m.group(1) if m else ""
    return out


def key_fingerprint(path):
    """Primary key fingerprint of an armored public key, via gpg in a throwaway home; None without gpg."""
    import shutil
    import subprocess
    import tempfile
    if not shutil.which("gpg"):
        return None
    with tempfile.TemporaryDirectory() as home:
        r = subprocess.run(["gpg", "--homedir", home, "--show-keys", "--with-colons", "--fingerprint", path],
                           capture_output=True, text=True)
    for ln in r.stdout.splitlines():
        if ln.startswith("fpr:"):
            return ln.split(":")[9]
    return None


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links = []      # (attrs, text)
        self.tags = []       # (tag, attrs)
        self.text = []
        self.h1 = []
        self._stack = []
        self._link = None
        self.summaries = []
        self._summary = None
        self.ids = {}
        self.in_main = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags.append((tag, a))
        if "id" in a:
            self.ids[a["id"]] = tag
        self._stack.append(tag)
        if tag == "main":
            self.in_main = True
        if tag == "a" and self.in_main:
            self._link = [a, ""]
        if tag == "summary":
            self._summary = ""

    def handle_endtag(self, tag):
        if tag == "main":
            self.in_main = False
        if tag == "a" and self._link is not None:
            self.links.append((self._link[0], self._link[1].replace(" (opens in a new tab)", "").replace(" (GitHub, opens in a new tab)", "").strip()))
            self._link = None
        if tag == "summary" and self._summary is not None:
            self.summaries.append(self._summary.strip())
            self._summary = None
        if self._stack and self._stack[-1] == tag:
            self._stack.pop()

    def handle_data(self, d):
        if self._link is not None:
            self._link[1] += d
        if self._summary is not None:
            self._summary += d
        if self._stack and self._stack[-1] == "h1":
            self.h1.append(d.strip())
        self.text.append(d)

    def flat(self):
        return re.sub(r"\s+", " ", "".join(self.text)).strip()

    def count(self, tag):
        return sum(1 for t, _ in self.tags if t == tag)


def load(path):
    p = Page()
    with open(path, encoding="utf-8") as f:
        p.feed(f.read())
    return p


def common(p, errs):
    for tag in ("iframe", "script", "form", "object", "embed", "style"):
        if p.count(tag):
            errs.append("a <%s> element" % tag)
    for tag, a in p.tags:
        if "style" in a:
            errs.append("an inline style attribute")
        if tag == "img" and not (a.get("src") or "").startswith("/"):
            errs.append("an image that is not same-origin: %s" % a.get("src"))


def external_ok(a):
    rel = (a.get("rel") or "").split()
    return a.get("target") == "_blank" and "noopener" in rel


def support(p, errs, repo):
    common(p, errs)
    # /support/ alone may carry /copy.js, its pinned script; it is checked below.
    if "a <script> element" in errs:
        errs.remove("a <script> element")
    if p.h1 != ["Support my work"]:
        errs.append("h1 is %r" % p.h1)
    flat = p.flat()
    intro = ("If you want to support the streams, videos, and projects, "
             "these are the ways to do it. It is optional.")
    if intro not in flat:
        errs.append("intro text missing")
    if "live thank-you" in flat or "thank-you" in flat.lower():
        errs.append("a live thank-you promise is on the page (not supported)")
    if "Before you send, verify the full address and make sure you are using the correct network." not in flat:
        errs.append("full-address and network advice missing")
    if "first and last" in flat.lower():
        errs.append("advice to check only the first and last characters is back")
    for name, url in BUTTONS.items():
        hits = [a for a, t in p.links if re.sub(r"\s+", " ", t).startswith(name + " ")]
        if len(hits) != 1:
            errs.append("button %r appears %d times" % (name, len(hits)))
            continue
        if hits[0].get("href") != url:
            errs.append("button %r points to %r" % (name, hits[0].get("href")))
        if not external_ok(hits[0]):
            errs.append("button %r lacks target=_blank rel=noopener" % name)
        if "tile" not in (hits[0].get("class") or "").split():
            errs.append("button %r is not styled as a tile" % name)
    # The cryptocurrency section follows the four tiles (zero clicks to pay).
    html = repo["html"]
    if "Cryptocurrency tips" not in flat or html.find("Shop merch") > html.find("Cryptocurrency tips"):
        errs.append("the cryptocurrency section must follow the four tiles")
    if any(t == "details" and "coin" in (a.get("class") or "") for t, a in p.tags):
        errs.append("the cryptocurrency block is always open, not a details element")
    # One Copy button per address: hidden until the script reveals it, named for
    # the coin, wired to the id of that coin's address, with a live status region.
    for coin, addr in ADDRESSES.items():
        m = re.search(r'<button[^>]*data-copy=("?)addr-%s\1[^>]*>' % coin, html)
        if not m or "hidden" not in m.group(0).rstrip(">").split():
            errs.append("%s Copy button missing or not hidden by default" % coin)
        if not re.search(r"id=\"?addr-%s\"?" % coin, html):
            errs.append("%s address has no id for the Copy button" % coin)
    if len(re.findall(r"role=status", html)) != len(ADDRESSES):
        errs.append("each Copy button needs one role=status region")
    if html.count("<script") != 1 or "<script src=/copy.js></script>" not in html:
        errs.append("/support/ must carry exactly the one pinned <script src=/copy.js></script>")
    # Addresses: verbatim, in a <code> element each, once.
    for coin, addr in ADDRESSES.items():
        if flat.count(addr) != 1:
            errs.append("%s address appears %d times" % (coin, flat.count(addr)))
        if not re.search(r"<code[^>]*>\s*%s\s*</code>" % re.escape(addr), html):
            errs.append("%s address is not in a <code> element" % coin)
        imgs = [a for t, a in p.tags if t == "img" and (a.get("src") or "").endswith("/support/qr-%s.svg" % coin)]
        if len(imgs) != 1:
            errs.append("%s QR image appears %d times" % (coin, len(imgs)))
        elif not (imgs[0].get("alt") and imgs[0].get("width") and imgs[0].get("height")):
            errs.append("%s QR image needs alt, width and height" % coin)
    # Issue 123 (owner order 2026-11-08): no "Also find me on" section here; /social/ has every network.
    if "Also find me on" in flat:
        errs.append("the 'Also find me on' section is back on /support/")
    if any(h in (a.get("href") or "") for a, t in p.links for h in ("instagram.com", "pics.chiefgyk3d.com")):
        errs.append("a social link is on /support/ (they live on /social/)")
    # Ko-fi stays a link-out until the framing test; the TODO is in the template.
    if repo.get("template") is not None and "TODO" not in repo["template"]:
        errs.append("the Ko-fi embed TODO marker is missing from the template")


def norm(t):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", t))).strip()


def about_data():
    """The expected About text, read from data/about.yaml (ABOUT_DATA). The file has a fixed shape
    (double-quoted strings, no escapes), so a line scan avoids a YAML dependency."""
    with open(os.environ["ABOUT_DATA"], encoding="utf-8") as f:
        lines = f.read().splitlines()
    d = {"paragraphs": [], "skills": [], "speaking": {}}
    sect = None
    for ln in lines:
        m = re.match(r'^(\w+):(?: "(.*)")?$', ln)
        if m:
            sect = m.group(1)
            if m.group(2) is not None:
                d[sect] = m.group(2)
            continue
        if sect == "paragraphs":
            m = re.match(r'^  - "(.*)"$', ln)
            if m:
                d["paragraphs"].append(m.group(1))
        elif sect == "speaking":
            m = re.match(r'^  (\w+): "(.*)"$', ln)
            if m:
                d["speaking"][m.group(1)] = m.group(2)
        elif sect == "skills":
            m = re.match(r'^  - name: "(.*)"$', ln)
            if m:
                d["skills"].append({"name": m.group(1)})
            m = re.match(r'^    text: "(.*)"$', ln)
            if m:
                d["skills"][-1]["text"] = m.group(1)
    return d


def check_about_data(errs, html_src):
    """Every bio and skill text on the page must equal its data/about.yaml entry, exactly."""
    d = about_data()
    if len(d["paragraphs"]) != 2 or len(d["skills"]) != len(SKILL_GROUPS) or not d.get("opener"):
        errs.append("data/about.yaml is not the expected shape")
        return
    ps = [norm(m).replace(" (opens in a new tab)", "") for m in re.findall(r"<p[^>]*>(.*?)</p>", html_src, re.S)]
    for label, want in [("opener", d["opener"])] + [("bio paragraph %d" % (i + 1), t) for i, t in enumerate(d["paragraphs"])]:
        if want not in ps:
            errs.append("%s differs from data/about.yaml" % label)
    if not d.get("mission") or d["mission"] not in ps:
        errs.append("mission paragraph differs from data/about.yaml")
    sp = d["speaking"]
    if not any((sp["before"] + sp["link_text"] + sp["after"] + " " + sp.get("role", "")).strip() == x for x in ps):
        errs.append("speaking sentence or role differs from data/about.yaml")
    if sp.get("role") != "I volunteer there.":
        errs.append("data/about.yaml speaking role is not the owner-approved volunteer sentence")
    groups = [(norm(a), norm(b)) for a, b in re.findall(r"<h3[^>]*>(.*?)</h3>\s*<p[^>]*>(.*?)</p>", html_src, re.S)]
    want = [(g["name"], g["text"]) for g in d["skills"]]
    for w in want:
        if w not in groups:
            errs.append("skill group %r is missing or its text differs from data/about.yaml" % w[0])
    if len(groups) != len(want):
        errs.append("expected %d skill groups, found %d" % (len(want), len(groups)))


def check_project_tiles(errs, html_src, flat):
    """Issue 174: exactly six project tiles in the owner's order, then the GitHub link; every tile link https."""
    m = re.search(r"<ul class=\"?tile-grid project-tiles\"?>(.*?)</ul>", html_src, re.S)
    if not m:
        errs.append("the Current projects tile list was not found")
        return
    tiles = []
    for attrs, inner in re.findall(r"<li[^>]*><a ([^>]*)>(.*?)</a></li>", m.group(1), re.S):
        href = re.search(r"href=\"?([^\"\s>]+)", attrs)
        tiles.append((href.group(1) if href else "", norm(re.sub(r"<span[^>]*>.*?</span>", "", inner, flags=re.S)), attrs))
    want = ["Clouds Against Humanity", "Stream Daemon", "SIEM Docker Stack", "git-your-ship-together", "Reach Around", "Hammunition"]
    if len(tiles) != len(want) + 1:
        errs.append("expected %d project tiles plus the GitHub link, found %d items" % (len(want), len(tiles)))
    if [t[1] for t in tiles[:6]] != want:
        errs.append("project tiles are %r, expected %r" % ([t[1] for t in tiles[:6]], want))
    for href, name, attrs in tiles:
        if not href.startswith("https://"):
            errs.append("project tile %r link is not https: %r" % (name, href))
        if "noopener" not in attrs:
            errs.append("project tile %r link lacks rel=noopener" % name)
    if tiles[6:] and (tiles[-1][0] != "https://github.com/ChiefGyk3D" or tiles[-1][1] != "More projects on GitHub"):
        errs.append("the last tile must be the More projects on GitHub link to https://github.com/ChiefGyk3D")
    for need in ("Clouds-Against-Humanity", "Stream-Daemon", "Reach-Around"):
        if not any(need in t[0] for t in tiles):
            errs.append("missing project link %s" % need)
    i, j, k = (html_src.find(x) for x in ('id=projects', 'id=contact', 'id=skills'))
    if not (0 < i < j < k):
        errs.append("section order must be projects, contact, skills (found %d, %d, %d)" % (i, j, k))
    if flat.find("lists my skills, open-source projects") > flat.find("Current projects") or flat.find("lists my skills, open-source projects") < flat.find(MISSION_START):
        errs.append("the resume line must close the bio card, before Current projects")


def about(p, errs, repo):
    common(p, errs)
    check_about_data(errs, repo["html"])
    if p.h1 != ["About"]:
        errs.append("h1 is %r" % p.h1)
    flat = p.flat()
    if "DRAFT" in flat:
        errs.append("DRAFT marker still on the page")
    if "Hi, I'm Moshe, and I go by ChiefGyk3D online." not in flat:
        errs.append("bio opener missing")
    if "I’m more than ready for a security architecture role, and that’s where I’m headed." not in flat:
        errs.append("bio closing sentence missing")
    if "I’m a Senior Cybersecurity Engineer (CISSP), Linux nerd, open-source builder, and content creator." not in flat:
        errs.append("bio first paragraph missing")
    if MISSION_START not in flat or MISSION_END not in flat:
        errs.append("mission paragraph missing")
    if flat.find(MISSION_START) < flat.find("In 2026 I spoke at BSides") or flat.find(MISSION_START) > flat.find("Current projects"):
        errs.append("mission paragraph is not right after the bio and before the projects and Contact")
    if "In 2026 I spoke at BSides Dayton and COISSA, and I'm with the Call Center Village" not in flat:
        errs.append("speaking sentence missing")
    cc = [a for a, t in p.links if t == "Call Center Village"]
    if len(cc) != 1:
        errs.append("expected one Call Center Village link, found %d" % len(cc))
    for a in cc:
        if a.get("href") != "https://www.callcentervillage.com/":
            errs.append("Call Center Village link href is %r" % a.get("href"))
        if not external_ok(a):
            errs.append("Call Center Village link lacks target=_blank rel=noopener")
    if p.ids.get("skills") != "h2":
        errs.append("no #skills h2")
    h3s = [html.unescape(m) for m in re.findall(r"<h3[^>]*>(.*?)</h3>", repo["html"], re.S)]
    # The Skills section is asserted from data/about.yaml (names, order and text, in
    # check_about_data); this list pins the owner-approved group names and their order.
    if h3s[-1:] != ["Where I'm headed"]:
        errs.append("the last skill group must be Where I'm headed")
    skills_text = " ".join(g["text"] for g in about_data()["skills"])
    if chr(0x2014) in skills_text or chr(0x2013) in skills_text:
        errs.append("a dash character is in the skills text")
    if re.search(r"\b[A-Z]{1,2}\d[A-Z]{1,3}\b", skills_text):
        errs.append("callsign-shaped text in the skills text")
    if h3s != SKILL_GROUPS:
        errs.append("skill group headings are %r" % h3s)
    if p.count("h4") or p.count("h1") != 1:
        errs.append("heading levels are out of order")
    if "about 15 years" in flat:
        errs.append("the old bio text is still on the page")
    if not any(t == "img" and (a.get("alt") or "") and (a.get("src") or "").startswith("/brand/") for t, a in p.tags):
        errs.append("no mascot image with alt text")
    if p.ids.get("contact") not in ("h2", "h3", "section"):
        errs.append("no #contact heading or section")
    cd = contact_data()
    # One rule (layouts/_partials/contact-complete.html): the address is published only
    # when the email, the fingerprint and the key link are ALL set.
    email_set = bool(cd["email"] and cd["pgp_fingerprint"] and cd["pgp_url"])
    if CONTACT not in flat:
        errs.append("contact sentence missing")
    if email_set == (CONTACT_SOON.strip() in flat):
        errs.append("the 'address will be listed soon' sentence must show exactly while no email is set")
    hrefs = [a.get("href") for a, _ in p.links]
    for h in ("https://discord.chiefgyk3d.com", "https://matrix.to/#/#renegade-penguin:chiefgyk3d.com",
              "https://github.com/ChiefGyk3D/Stream-Daemon", "https://github.com/ChiefGyk3D/Clouds-Against-Humanity"):
        if h not in hrefs:
            errs.append("missing link %s" % h)
    if not any((h or "").startswith("https://github.com/ChiefGyk3D/") and "Reach" in (h or "") for h in hrefs):
        errs.append("missing Reach Around link")
    check_project_tiles(errs, repo["html"], flat)
    if "/resume/" not in hrefs:
        errs.append("the About body must link to /resume/")
    mailtos = [h for h in hrefs if (h or "").startswith("mailto:")]
    if not email_set and mailtos:
        errs.append("the contact config is incomplete, so the page must not link an email")
    if email_set:
        if mailtos != ["mailto:" + cd["email"]]:
            errs.append("expected exactly one mailto link, to the data email; found %r" % mailtos)
        if "Email, for business inquiries only: %s." % cd["email"] not in flat:
            errs.append("business email sentence missing")
        if "PGP fingerprint: %s." % cd["pgp_fingerprint"] not in flat:
            errs.append("PGP fingerprint missing from the contact section")
        if not any((h or "").endswith(cd["pgp_url"]) and cd["pgp_url"] for h in hrefs) or not cd["pgp_url"]:
            errs.append("PGP key link missing")
        else:
            keyfile = os.path.join(os.path.dirname(os.path.dirname(os.environ["ABOUT_DATA"])), "static", cd["pgp_url"].lstrip("/"))
            if not os.path.isfile(keyfile):
                errs.append("the PGP key file %s is not in static/" % cd["pgp_url"])
            else:
                key = open(keyfile, encoding="ascii").read()
                if "PRIVATE" in key or not key.startswith("-----BEGIN PGP PUBLIC KEY BLOCK-----"):
                    errs.append("the key file is not a public key block only")
                want = key_fingerprint(keyfile)
                if want is not None and want != cd["pgp_fingerprint"].replace(" ", "").upper():
                    errs.append("page fingerprint %s differs from the key file's %s" % (cd["pgp_fingerprint"], want))
    stray = set(re.findall(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+", flat)) - ({cd["email"]} if email_set else set())
    if stray:
        errs.append("unexpected email-shaped text on About: %r" % sorted(stray))
    # The email ban is for the contact section; the Skills text legitimately says "email security".
    m = re.search(r"<section[^>]*about-contact.*?</section>", repo["html"], re.S)
    contact = re.sub(r"<[^>]+>", " ", m.group(0)).lower() if m else ""
    if not contact:
        errs.append("the contact section was not found")
    if "TODO" in repo["html"]:
        errs.append("the page carries a TODO")
    if not email_set and ("pgp" in contact or "@" in contact or "mailto" in contact):
        errs.append("an empty email and PGP entry must render nothing")


def privacy(p, errs, repo):
    common(p, errs)
    if p.h1 != ["Privacy"]:
        errs.append("h1 is %r" % p.h1)
    for para in PRIVACY:
        if para not in p.flat():
            errs.append("privacy statement missing: " + para[:40])
    for phrase in PRIVACY_FORBIDDEN:
        if phrase.lower() in p.flat().lower():
            errs.append("privacy page makes an unsupported claim: %r" % phrase)


KINDS = {"support": support, "about": about, "privacy": privacy}

if __name__ == "__main__":
    kind, path = sys.argv[1], sys.argv[2]
    tpl = None
    if len(sys.argv) > 3:
        with open(sys.argv[3], encoding="utf-8") as f:
            tpl = f.read()
    p = load(path)
    with open(path, encoding="utf-8") as f:
        repo = {"html": f.read(), "template": tpl}
    errs = []
    KINDS[kind](p, errs, repo)
    # Every page closes with the footer line, in the footer, as its own paragraph.
    fm = re.search(r"<footer.*?</footer>", repo["html"], re.S)
    fps = [norm(x) for x in re.findall(r"<p[^>]*>(.*?)</p>", fm.group(0), re.S)] if fm else []
    if FOOTER_LINE not in fps:
        errs.append("footer line missing")
    # The footer is two calm rows: page links (with Social and Support), then the
    # line and the copyright. No repeated social or support row.
    if fm:
        # The icon row (issue 169, a nav of its own, checked in test-social-products.sh)
        # is cut out first; the page-link row is what is left.
        foot = re.sub(r"<nav[^>]*footer-social.*?</nav>", "", fm.group(0), flags=re.S)
        if foot == fm.group(0):
            errs.append("footer social icon row missing")
        hrefs = re.findall(r"<a[^>]*href=([^\s>]+)[^>]*>(.*?)</a>", foot, re.S)
        names = [norm(t) for _, t in hrefs]
        if names != ["About", "Contact", "Privacy", "Resume", "RSS", "Socials", "Support"]:
            errs.append("footer links are %r" % names)
        targets = dict((norm(t), h.strip('"')) for h, t in hrefs)
        if not targets.get("Socials", "").endswith("/social/"):
            errs.append("footer Socials does not point at /social/")
        if not targets.get("Support", "").endswith("/support/"):
            errs.append("footer Support does not point at /support/")
        if "social-row" in foot or "support-row" in foot or "icon-" in foot:
            errs.append("footer repeats the social or support row")
        if "&copy;" not in fm.group(0) and "©" not in fm.group(0):
            errs.append("footer copyright missing")
        elif "Renegade Penguin LLC" not in " ".join(fps):
            errs.append("footer copyright is not Renegade Penguin LLC")
    for e in sorted(set(errs)):
        print(e)
    sys.exit(1 if errs else 0)
PY

echo "== build"
if ! hugo --minify --gc --source "$root" --destination "$work/public" >"$work/hugo.log" 2>&1; then
    cat "$work/hugo.log"
    fail "hugo build"
    exit 1
fi
pub="$work/public"

assert() {
    # assert <kind> <html file> [template]
    local out rc=0
    out="$(ABOUT_DATA="$root/data/about.yaml" python3 -I "$asserter" "$@" 2>&1)" || rc=$?
    if [[ $rc -eq 0 ]]; then
        pass "$1 page rules"
    else
        printf '%s\n' "$out" | sed 's/^/    /'
        fail "$1 page rules"
    fi
}

for kind in support about privacy; do
    if [[ ! -f "$pub/$kind/index.html" ]]; then
        fail "$kind/index.html is not built"
    fi
done
[[ -f "$pub/support/index.html" ]] && assert support "$pub/support/index.html" "$root/layouts/support/single.html"
[[ -f "$pub/about/index.html" ]] && assert about "$pub/about/index.html"
# Guard: the About check bites. One skill group's text altered, one group omitted, and a bio
# paragraph altered must each fail (the unaltered page passed above).
if [[ -f "$pub/about/index.html" ]]; then
    mutate() { python3 -I -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); a, b = sys.argv[3], sys.argv[4]; assert a in s; open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, b, 1))' "$pub/about/index.html" "$@"; }
    mutate "$work/about-alt.html" "Okta, Microsoft Entra, " "Okta, "
    mutate "$work/about-omit.html" "<h3>Radio, RF, and telecom</h3>" "<h3>Radio, RF, and telecom</h3><p>x</p><!--"
    mutate "$work/about-tile.html" "https://github.com/ChiefGyk3D/Stream-Daemon" "http://github.com/ChiefGyk3D/Stream-Daemon"
    mutate "$work/about-more.html" "More projects on GitHub" "More on GitHub"
    mutate "$work/about-extra.html" "<li class=tile-more>" "<li><a class=tile href=https://example.org/x rel=noopener><strong>Extra</strong></a></li><li class=tile-more>"
    mutate "$work/about-bio.html" "right to repair" "right to fix"
    mutate "$work/about-mission.html" "leaving knowledge behind a price tag" "leaving knowledge behind a paywall"
    for v in alt omit tile more extra bio mission; do
        if ABOUT_DATA="$root/data/about.yaml" python3 -I "$asserter" about "$work/about-$v.html" >/dev/null 2>&1; then
            fail "guard: an About page with $v-mutated text passed"
        else
            pass "guard: an About page with $v-mutated text fails"
        fi
    done
fi
# Contact (issue 159): the populated page is asserted from data/about.yaml (one mailto,
# the fingerprint, the key link, the fingerprint equal to the key file's), and each
# break must fail. Then a copy of the repository with the email and PGP entries
# emptied must build a page that renders none of them.
if [[ -f "$pub/about/index.html" ]]; then
    mutate "$work/about-fp.html" "98B2 D533 1A9F 17AC" "98B2 D533 1A9F 17AD"
    mutate "$work/about-addr.html" "mailto:chief@chiefgyk3d.com" "mailto:other@example.org"
    mutate "$work/about-nokey.html" "/chiefgyk3d.asc" "/other.asc"
    for v in fp addr nokey; do
        if ABOUT_DATA="$root/data/about.yaml" python3 -I "$asserter" about "$work/about-$v.html" >/dev/null 2>&1; then
            fail "guard: an About page with a broken contact ($v) passed"
        else
            pass "guard: an About page with a broken contact ($v) fails"
        fi
    done
    # Fail closed: only a COMPLETE contact config (email, fingerprint and key link) publishes the
    # address. Build a copy of the repository for each combination and assert the page.
    build_contact_case() { # <case> <email> <fingerprint> <url> <expect: complete|incomplete>
        local name="$1" croot="$work/contact-$1"
        mkdir -p "$croot"
        for d in archetypes assets content data layouts static i18n; do
            [[ -e "$root/$d" ]] && cp -R "$root/$d" "$croot/$d"
        done
        for f in hugo.toml .hugo-version; do
            [[ -f "$root/$f" ]] && cp "$root/$f" "$croot/$f"
        done
        sed -i "s/^  email: \".*\"\$/  email: \"$2\"/; s/^  pgp_fingerprint: \".*\"\$/  pgp_fingerprint: \"$3\"/; s#^  pgp_url: \".*\"\$#  pgp_url: \"$4\"#" "$croot/data/about.yaml"
        if ! (cd "$croot" && hugo --minify --destination "$work/contact-public-$name" --quiet >"$work/contact-build-$name.log" 2>&1); then
            cat "$work/contact-build-$name.log"
            fail "contact case $name did not build"
            return
        fi
        local page="$work/contact-public-$name/about/index.html" has_mail=0
        grep -q "mailto:" "$page" && has_mail=1
        if [[ "$5" == complete && $has_mail -eq 0 ]] || [[ "$5" == incomplete && $has_mail -eq 1 ]]; then
            fail "contact case $name: wrong exposure of the address (mailto present: $has_mail)"
        elif grep -q "chief@chiefgyk3d.com" "$page" && [[ "$5" == incomplete ]]; then
            fail "contact case $name: the address is on the page although the config is incomplete"
        elif ABOUT_DATA="$croot/data/about.yaml" python3 -I "$asserter" about "$page" >/dev/null 2>&1; then
            pass "contact case $name ($5): the About page matches the rule"
        else
            fail "contact case $name ($5): the About asserter rejected the page"
        fi
    }
    FP="93C4 0D71 BE65 0FBA C233 8682 98B2 D533 1A9F 17AC"
    build_contact_case neither "" "" "" incomplete
    build_contact_case email-only "chief@chiefgyk3d.com" "" "" incomplete
    build_contact_case key-only "" "$FP" "/chiefgyk3d.asc" incomplete
    build_contact_case email-and-fingerprint "chief@chiefgyk3d.com" "$FP" "" incomplete
    build_contact_case email-and-url "chief@chiefgyk3d.com" "" "/chiefgyk3d.asc" incomplete
    build_contact_case both "chief@chiefgyk3d.com" "$FP" "/chiefgyk3d.asc" complete
    # The checker bites: an address injected into an incomplete page is rejected.
    python3 -I -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); a = "Business inquiries go by email"; assert a in s; open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, "Business inquiries go by <a href=mailto:chief@chiefgyk3d.com>email</a>", 1))' "$work/contact-public-email-only/about/index.html" "$work/about-mail.html"
    if ABOUT_DATA="$work/contact-email-only/data/about.yaml" python3 -I "$asserter" about "$work/about-mail.html" >/dev/null 2>&1; then
        fail "guard: an About page linking an email with an incomplete config passed"
    else
        pass "guard: an About page linking an email with an incomplete config fails"
    fi
fi
# Guard: the footer check bites. The footer line removed from About must fail.
if [[ -f "$pub/about/index.html" ]]; then
    python3 -I -c 'import re, sys; s = open(sys.argv[1], encoding="utf-8").read(); t = re.sub(r"<p class=footer-line>.*?</p>", "", s, count=1); assert t != s; open(sys.argv[2], "w", encoding="utf-8").write(t)' "$pub/about/index.html" "$work/about-nofoot.html"
    if ABOUT_DATA="$root/data/about.yaml" python3 -I "$asserter" about "$work/about-nofoot.html" >/dev/null 2>&1; then
        fail "guard: an About page without the footer line passed"
    else
        pass "guard: an About page without the footer line fails"
    fi
fi
# rel="me" identity links: Mastodon and GitHub as head links on every page type, and the
# /social/ tiles keep their rel="me" anchors.
for f in index.html about/index.html social/index.html; do
    for u in https://social.chiefgyk3d.com/@chiefgyk3d https://github.com/ChiefGyk3D; do
        if grep -q "<link rel=me href=$u>" "$pub/$f" || grep -q "<link rel=\"me\" href=\"$u\">" "$pub/$f"; then
            pass "head rel=me link $u on $f"
        else
            fail "head rel=me link $u missing on $f"
        fi
    done
done
if grep -Eq '<a[^>]*rel="?me[ "][^>]*href="?https://social.chiefgyk3d.com/@chiefgyk3d' "$pub/social/index.html" ||
    grep -Eq '<a[^>]*href="?https://social.chiefgyk3d.com/@chiefgyk3d[^>]*rel="?me[ "]' "$pub/social/index.html"; then
    pass "/social/ keeps the rel=me Mastodon anchor"
else
    fail "/social/ lost the rel=me Mastodon anchor"
fi
# Guard: the footer-links check bites. A repeated social row put back must fail.
if [[ -f "$pub/about/index.html" ]]; then
    python3 -I -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); t = s.replace("</footer>", "<ul class=social-row><li><a class=icon-twitch href=https://twitch.tv/x>Twitch</a></li></ul></footer>", 1); assert t != s; open(sys.argv[2], "w", encoding="utf-8").write(t)' "$pub/about/index.html" "$work/about-socialrow.html"
    if ABOUT_DATA="$root/data/about.yaml" python3 -I "$asserter" about "$work/about-socialrow.html" >/dev/null 2>&1; then
        fail "guard: an About page with a footer social row passed"
    else
        pass "guard: an About page with a footer social row fails"
    fi
fi
[[ -f "$pub/privacy/index.html" ]] && assert privacy "$pub/privacy/index.html"

# /contact/ is a 301 to /about/#contact, in both slash forms.
for src in /contact /contact/; do
    if awk -v s="$src" '$1 == s && $2 == "/about/#contact" && $3 == "301" { f = 1 } END { exit !f }' "$pub/_redirects"; then
        pass "_redirects: $src -> /about/#contact"
    else
        fail "_redirects has no 301 from $src to /about/#contact"
    fi
done
if [[ -d "$pub/contact" ]] && ! grep -q 'http-equiv=refresh\|http-equiv="refresh"' "$pub/contact/index.html"; then
    fail "/contact/ is a page, not a redirect"
fi

# QR files: pre-generated static SVGs whose <desc> carries the encoded text,
# which must equal the address in data/support.yaml (scripts/gen-support-qr.py
# --check re-encodes them).
for coin in btc xmr eth sol; do
    f="$pub/support/qr-$coin.svg"
    addr="$(awk -v c="$coin" '$1 == "coin:" { cur = $2 } $1 == "address:" && cur == c { gsub(/"/, "", $2); print $2 }' "$root/data/support.yaml")"
    if [[ -z "$addr" ]]; then
        fail "data/support.yaml has no $coin address"
    elif [[ ! -s "$f" ]]; then
        fail "$f is missing"
    elif ! grep -q "<desc>$addr</desc>" "$f"; then
        fail "$f does not record the address in data/support.yaml"
    else
        pass "qr-$coin.svg matches data/support.yaml"
    fi
done

# The whole built file must equal a fresh encoding of data/support.yaml, so the
# encoded modules are verified and not only the <desc> text. Needs the
# hash-pinned segno from scripts/requirements-qr.txt (network access to the
# package index); a failure to install is a failure here, not a skip.
if out="$("$root/scripts/gen-support-qr.sh" --check --dir "$pub/support" 2>&1)"; then
    pass "built QR files equal a fresh encoding of data/support.yaml"
else
    fail "built QR files differ from a fresh encoding: $out"
fi
# Guard: a file whose <desc> is intact but whose modules changed, and one whose
# <desc> changed but whose modules did not, must each fail the same check.
qrbad="$work/qrbad"
mkdir -p "$qrbad"
cp "$pub"/support/qr-*.svg "$qrbad/"
sed -i 's/M4 4h7v1h-7z/M4 4h6v1h-6z/' "$qrbad/qr-btc.svg"
if cmp -s "$qrbad/qr-btc.svg" "$pub/support/qr-btc.svg"; then
    fail "guard: could not alter the modules of the test copy"
elif "$root/scripts/gen-support-qr.sh" --check --dir "$qrbad" >/dev/null 2>&1; then
    fail "guard: altered modules with an intact <desc> were accepted"
else
    pass "guard: altered modules with an intact <desc> are rejected"
fi
cp "$pub/support/qr-btc.svg" "$qrbad/qr-btc.svg"
sed -i 's#<desc>bc1q#<desc>bc1p#' "$qrbad/qr-btc.svg"
if "$root/scripts/gen-support-qr.sh" --check --dir "$qrbad" >/dev/null 2>&1; then
    fail "guard: an altered <desc> with intact modules was accepted"
else
    pass "guard: an altered <desc> with intact modules is rejected"
fi
# The decode proof must bite: a code with its modules blanked, desc intact, fails.
if command -v google-chrome >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1; then
    cp "$pub/support/qr-btc.svg" "$qrbad/qr-btc.svg"
    sed -i -E 's#<path fill="\#000000" d="[^"]*"/>##' "$qrbad/qr-btc.svg"
    if out="$("$root/scripts/gen-support-qr.sh" --check --decode --dir "$qrbad" 2>&1)"; then
        fail "guard: a blanked QR code passed --check --decode"
    elif grep -q 'decode FAILED: qr-btc.svg' <<<"$out"; then
        pass "guard: a QR code that does not decode is rejected by --decode"
    else
        fail "guard: --decode did not report the blanked code: $out"
    fi
    if out="$("$root/scripts/gen-support-qr.sh" --check --decode --dir "$pub/support" 2>&1)"; then
        pass "every built QR code decodes to the exact address (headless Chrome + OpenCV)"
    else
        fail "built QR codes do not decode: $out"
    fi
else
    echo "skip: no Chrome or Chromium for the QR decode proof"
fi

# The CSP gained no frame-src (Ko-fi stays a link-out until the framing test).
if grep -i 'Content-Security-Policy' "$pub/_headers" | grep -qi 'frame-src'; then
    fail "_headers has a frame-src"
else
    pass "no frame-src in _headers"
fi
if [[ -e "$pub/support.js" ]]; then
    fail "support.js shipped: the only scripts are the pinned /copy.js and /search.js"
fi
# Only /support/ loads the copy script.
if grep -rl --include=index.html --include=404.html '/copy.js' "$pub" | grep -v '^'"$pub"'/support/index.html$' | grep -q .; then
    fail "a page other than /support/ loads /copy.js"
else
    pass "only /support/ loads /copy.js"
fi

# Search (issue 119): /search/ is a browse page first (every post and journal
# entry, A to Z, as plain <li> entries) and the pinned script that belongs to
# it, /search.js, enables the search box. Only /search/ loads that script.
search_check() { # search_check <page> <site root>: prints one problem per line
    python3 -I - "$1" "$2" <<'PY'
import glob, os, re, sys
html = open(sys.argv[1], encoding="utf-8").read()
root = sys.argv[2]
errs = []
if html.count("<script") != 1 or "<script src=/search.js></script>" not in html:
    errs.append("/search/ must carry exactly the one pinned <script src=/search.js></script>")
if "<form" in html:
    errs.append("a <form> (form-action is 'none'): the box is a div role=search")
m = re.search(r"<div[^>]*role=search[^>]*>", html)
if not m or re.search(r"[\s]hidden[\s>]", m.group(0)):
    errs.append("the search control must be a div role=search that is on the page from first paint (not hidden: revealing it later shifts the layout)")
inp = re.search(r"<input[^>]*id=q[ >][^>]*>", html)
if not inp or not re.search(r"[\s]disabled[\s>]", inp.group(0)):
    errs.append("the input must be disabled in the HTML; the script enables it (no script, no working box)")
if not re.search(r"<label[^>]*for=q[ >]", html) or not re.search(r"<input[^>]*id=q[ >]", html):
    errs.append("the input needs a visible label with for=q")
if not re.search(r"<p[^>]*role=status[^>]*aria-live=polite|<p[^>]*aria-live=polite[^>]*role=status", html):
    errs.append("a role=status aria-live=polite region is required")
if "<noscript>" not in html:
    errs.append("a noscript note is required")
if re.search(r"<(style)[ >]|[ ]style=|[ ]on[a-z]+=", html):
    errs.append("style element or attribute or event handler")
# Every regular page of posts and journal is a <li> with a link, A to Z by title.
titles = []
for sec in ("posts", "journal"):
    for f in sorted(glob.glob(os.path.join(root, sec, "*", "index.html"))):
        page = open(f, encoding="utf-8").read()
        if "http-equiv=refresh" in page:
            continue
        t = re.search(r"<title>([^<]*) \| ", page)
        href = "/%s/%s/" % (sec, os.path.basename(os.path.dirname(f)))
        if not re.search(r"<li><a href=%s>" % re.escape(href), html):
            errs.append("%s is not listed as a <li> link" % href)
        if t:
            titles.append((sec, t.group(1)))
li = re.findall(r'<section class=search-group[^>]*>(.*?)</section>', html, re.S)
for grp in li:
    names = re.findall(r"<li><a href=[^>]*>([^<]*)</a>", grp)
    if names != sorted(names, key=str.lower):
        errs.append("a group is not A to Z by title: %s" % names)
if not li:
    errs.append("no search groups")
for e in errs:
    print(e)
PY
}
search_page="$pub/search/index.html"
if [[ ! -f "$search_page" ]]; then
    fail "the search page was not built"
else
    out="$(search_check "$search_page" "$pub")"
    if [[ -z "$out" ]]; then
        pass "the search page: browse list, role=search box with a disabled input, status region, noscript, one pinned script"
    else
        fail "the search page: $out"
    fi
    # Guards: the checker bites on each broken page.
    bite() { # bite <label> <sed expression>
        sed -E "$2" "$search_page" >"$work/bad-search.html"
        if [[ -z "$(search_check "$work/bad-search.html" "$pub")" ]]; then
            fail "guard: a search page $1 passed"
        else
            pass "guard: a search page $1 fails"
        fi
    }
    bite "with an inline script" 's#<script src=/search.js></script>#<script>x()</script>#'
    bite "with a form" 's#<div id=search#<form></form><div id=search#'
    bite "with a hidden box" 's#<div id=search class=search-box role=search>#<div id=search class=search-box role=search hidden>#'
    bite "with an enabled input" 's#(<input[^>]*id=q[^>]*) disabled#\1#'
    bite "without the status region" 's#role=status ##'
    bite "without the label" 's#<label#<span#'
    bite "without a post entry" 's#<li><a href=/posts/sample-post/>#<li><a href=/posts/other/>#'
fi
if [[ -e "$pub/search/index.xml" ]]; then
    fail "the search page published a feed"
else
    pass "the search page has no feed"
fi
if [[ ! -f "$pub/search.js" ]]; then
    fail "search.js is not in the build"
elif grep -rl --include=index.html --include=404.html '/search.js' "$pub" | grep -v '^'"$pub"'/search/index.html$' | grep -q .; then
    fail "a page other than /search/ loads /search.js"
else
    pass "only /search/ loads /search.js"
fi
if grep -q 'href=/search/' "$pub/index.html" && grep -q 'href=/search/' "$pub/posts/index.html"; then
    pass "the main nav links to /search/"
else
    fail "the main nav has no Search link"
fi
if grep -Eq '#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(' "$root/assets/css/pages/search.css"; then
    fail "search.css has a literal color: tokens only"
else
    pass "search.css uses tokens only"
fi

# Render-review polish (issue 61): built pages and stylesheet.
css="$(cat "$pub"/css/*.css 2>/dev/null || true)"
src_css() { cat "$root"/assets/css/pages/"$1".css; }
sup="$(src_css support)"
if grep -Eq 'support-tiles[^}]*grid-template-columns: *repeat\(4, *1fr\)' <<<"$(tr '\n' ' ' <<<"$sup")" &&
    grep -Eq 'support-tiles[^}]*grid-template-columns: *repeat\(2, *1fr\)' <<<"$(tr '\n' ' ' <<<"$sup")"; then
    pass "support tiles: 4 equal columns wide, 2x2 narrow"
else
    fail "support tiles are not a 4-column grid with a 2-column phone layout"
fi
if grep -q 'auto-fill' <<<"$sup"; then
    fail "support tiles still use auto-fill (they wrap unevenly)"
else
    pass "support tiles do not use auto-fill"
fi
if grep -Eq 'support-tiles \.tile-item[^}]*display: *flex' <<<"$(tr '\n' ' ' <<<"$sup")"; then
    pass "support button cells stretch to one height"
else
    fail "support button cells do not stretch to one height"
fi
# Rule order (issue 107): the desktop .coin-name override sits inside a media
# query at equal specificity, so it must come AFTER the base rule or it never
# applies. Compares the line of the base rule (column 0) with the override.
coin_name_after_base() {
    awk '/^\.coin-name \{/ { if (!b) b = NR } /^ +\.coin-name \{/ { if (!o) o = NR } END { exit !(b && o && o > b) }'
}
if coin_name_after_base <"$root/assets/css/pages/support.css"; then
    pass "support desktop .coin-name override follows the base rule"
else
    fail "support desktop .coin-name override precedes the base rule (it would never apply)"
fi
if printf '%s\n' '  .coin-name {' '}' '.coin-name {' '}' | coin_name_after_base; then
    fail "rule-order check accepts an override placed before the base rule"
else
    pass "rule-order check rejects an override placed before the base rule"
fi
# Desktop layout widths (issue 107): the page container widens in steps, the
# reading column stays at --measure, and running text keeps a line-length cap.
main_css="$(tr '\n' ' ' <"$root"/assets/css/main.css)"
if grep -Eq '\.wrap \{[^}]*max-width: *var\(--page-max\)' <<<"$main_css" &&
    grep -Eq -- '--page-max: *var\(--measure\)' <<<"$main_css" &&
    grep -Eq 'min-width: *120rem\) \{ *:root \{ *--page-max: *90rem' <<<"$main_css"; then
    pass "page container: --page-max starts at --measure and widens to 90rem"
else
    fail "page container: .wrap must use --page-max (42rem base, up to 90rem)"
fi
if grep -Eq 'main p \{[^}]*max-width: *var\(--prose-max\)' <<<"$main_css" &&
    grep -Eq -- '--prose-max: *75ch' <<<"$main_css"; then
    pass "running text is capped at 75ch"
else
    fail "running text must be capped at 75ch (--prose-max)"
fi
if grep -Eq '\.post \{[^}]*max-width: *var\(--measure\)' <<<"$(src_css posts | tr '\n' ' ')"; then
    pass "post keeps the --measure reading column"
else
    fail "post must keep the --measure reading column"
fi
hero="$(src_css home | tr '\n' ' ')"
if grep -Eq '\.hero-actions[^}]*flex-wrap: *wrap' <<<"$hero" && grep -Eq '\.hero-mascot[^}]*align-self: *flex-start' <<<"$hero"; then
    pass "home hero: wrapping CTA row, top-aligned mascot"
else
    fail "home hero: CTA row must wrap and the mascot must be top-aligned"
fi
if grep -Eq '\.hero-actions[^}]*flex-direction: *column' <<<"$hero"; then
    fail "home hero CTAs are a stacked column"
fi
# Penguin ghost layer (issue 149): Home and 404 only, CSS only, no new asset.
# trigger_pages lists which built pages carry a ghost trigger class; the guard
# self-test below proves the check bites on a page that should not have one.
has_ghost_trigger() { grep -Eq 'class="?[^>]*\b(home-grid|not-found)\b' "$1"; }
for f in "$pub/index.html" "$pub/404.html"; do
    if has_ghost_trigger "$f"; then
        pass "ghost layer trigger present on ${f#"$pub"/}"
    else
        fail "ghost layer trigger missing on ${f#"$pub"/}"
    fi
done
for f in "$pub/about/index.html" "$pub/posts/sample-post/index.html"; do
    if has_ghost_trigger "$f"; then
        fail "ghost layer trigger must be absent on ${f#"$pub"/}"
    else
        pass "ghost layer trigger absent on ${f#"$pub"/}"
    fi
done
printf '<main><div class="home-grid"></div></main>\n' >"$work/ghost-yes.html"
printf '<main><article class="post"></article></main>\n' >"$work/ghost-no.html"
if has_ghost_trigger "$work/ghost-yes.html" && ! has_ghost_trigger "$work/ghost-no.html"; then
    pass "guard: ghost trigger check accepts home-grid and rejects a post"
else
    fail "guard: ghost trigger check does not bite"
fi
ghost="$(cat "$root"/assets/css/home-ghost.css | tr '\n' ' ')"
ghost_rule="$(grep -Eo 'main:has\(\.home-grid\)::before, *main:has\(\.not-found\)::before *\{[^}]*\}' <<<"$ghost" || true)"
ghost_ok=1
for want in 'position: *absolute' 'width: *min\(60vw, *40rem\)' 'aspect-ratio: *1' 'opacity: *0\.(08|09|1|10|11|12)\b' 'filter: *grayscale\(1\)' 'pointer-events: *none' 'z-index: *0' '/brand/mascot-512\.webp' '(^|[ ;])mask-image: *radial-gradient' '-webkit-mask-image: *radial-gradient'; do
    grep -Eq -- "$want" <<<"$ghost_rule" || {
        ghost_ok=0
        echo "  ghost rule missing: $want"
    }
done
grep -Eq 'position: *fixed' <<<"$ghost_rule" && ghost_ok=0
if [[ -n "$ghost_rule" && $ghost_ok -eq 1 ]]; then
    pass "ghost layer CSS: absolute, no CLS, masked, faint, grayscale, inert"
else
    fail "ghost layer CSS rule missing or incomplete in home-ghost.css"
fi
ghost_targets="$(grep -Eo 'main:has\([^)]*\)' <<<"$ghost" | sort -u | tr '\n' ' ')"
if [[ "$ghost_targets" == 'main:has(.home-grid) main:has(.not-found) ' ]]; then
    pass "ghost layer selects only the home and 404 pages"
else
    fail "ghost layer must select only .home-grid and .not-found"
fi
# Issue 182: the ghost rule ships in the Home and 404 stylesheet only. check-budget
# counts every url() in a page's stylesheet, so a post carrying it pays 20 KB.
css_of() { grep -Eo '/css/site[^" >]*\.css' "$1" | head -1; }
ghost_pages=0 ghost_wrong=0
for f in "$pub/index.html" "$pub/404.html"; do
    [[ -f "$f" ]] || continue
    ghost_pages=$((ghost_pages + 1))
    grep -q 'mascot-512' "$pub$(css_of "$f")" || ghost_wrong=1
done
# Every built post page (the page type the split was made for) plus the other
# pages: none may carry the ghost stylesheet or the mascot reference.
post_pages=0
for f in "$pub"/posts/*/index.html; do
    [[ -f "$f" ]] || continue
    post_pages=$((post_pages + 1))
done
if [[ $post_pages -lt 1 ]]; then ghost_wrong=1; fi
for f in "$pub"/posts/*/index.html "$pub"/about/index.html "$pub"/posts/index.html "$pub"/social/index.html "$pub"/support/index.html "$pub"/resume/index.html "$pub"/privacy/index.html; do
    [[ -f "$f" ]] || continue
    ghost_pages=$((ghost_pages + 1))
    ! grep -q 'mascot-512' "$pub$(css_of "$f")" || ghost_wrong=1
    ! grep -q 'site-ghost' "$f" || ghost_wrong=1
done
if [[ $ghost_pages -ge 8 && $ghost_wrong -eq 0 ]]; then
    pass "ghost stylesheet: on Home and 404 only ($ghost_pages pages checked)"
else
    fail "ghost stylesheet must be on Home and 404 only (checked $ghost_pages, wrong=$ghost_wrong)"
fi
if grep -q 'mascot-512.webp' "$root/brand/approved-assets.txt"; then
    pass "ghost layer image is an approved asset"
else
    fail "ghost layer image is not in approved-assets.txt"
fi

if grep -q 'Placeholder posts section' "$root/content/posts/_index.md"; then
    fail "posts index still says 'Placeholder posts section.'"
elif grep -q '^Write-ups on open-source projects, self-hosting, streaming tools, and gear I use\. Newest first\.$' "$root/content/posts/_index.md"; then
    pass "posts index intro says what the posts are"
else
    fail "posts index intro does not describe the posts"
fi
if tr '\n' ' ' <<<"$(src_css posts)" | grep -Eq '\.archive-links[^}]*margin-bottom|\.archive-tags[^}]*margin: *var\(--space-5\)'; then
    pass "tag list has spacing under the RSS link"
else
    fail "tag list has no spacing under the RSS link"
fi
# Nav: the current section carries aria-current="page" and no other link does.
nav_current() { # <html> -> text of the aria-current links in the main nav
    python3 -I - "$1" <<'PY'
import html, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
nav = re.search(r"<nav class=site-nav.*?</nav>|<nav class=\"site-nav\".*?</nav>", h, re.S)
nav = nav.group(0) if nav else ""
for m in re.finditer(r"<a\b[^>]*aria-current=\"?page\"?[^>]*>(.*?)</a>", nav, re.S):
    print(html.unescape(re.sub(r"<[^>]+>", "", m.group(1)).strip()))
PY
}
for pair in "posts:Posts" "products:Gear & tools" "social:Socials" "support:Support" "about:About"; do
    got="$(nav_current "$pub/${pair%%:*}/index.html")"
    if [[ "$got" == "${pair##*:}" ]]; then
        pass "nav marks ${pair##*:} current on /${pair%%:*}/"
    else
        fail "nav on /${pair%%:*}/ marks '$got', expected '${pair##*:}'"
    fi
done
if [[ "$(nav_current "$pub/index.html")" == "Home" ]]; then
    pass "nav marks Home current on the home page"
else
    fail "nav on the home page marks '$(nav_current "$pub/index.html")', expected 'Home'"
fi
nav_first() { # <html> -> text of the first link in the main nav
    python3 -I - "$1" <<'PY'
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
nav = re.search(r"<nav class=site-nav.*?</nav>|<nav class=\"site-nav\".*?</nav>", h, re.S)
m = re.search(r"<a\b[^>]*>(.*?)</a>", nav.group(0) if nav else "", re.S)
print(re.sub(r"<[^>]+>", "", m.group(1)).strip() if m else "")
PY
}
if [[ "$(nav_first "$pub/support/index.html")" == "Home" ]]; then
    pass "nav lists Home first"
else
    fail "the first nav item on /support/ is '$(nav_first "$pub/support/index.html")', expected 'Home'"
fi
if grep -Eq 'aria-current="?page"?' <<<"$(tr '\n' ' ' <<<"$css")"; then
    pass "stylesheet styles [aria-current]"
else
    fail "stylesheet has no [aria-current=page] rule (amber underline)"
fi
if tr '\n' ' ' <"$root/assets/css/main.css" | grep -Eq 'aria-current[^}]*(text-decoration|border-bottom|box-shadow)[^}]*var\(--accent\)'; then
    pass "current-page indicator uses the accent token"
else
    fail "current-page indicator does not use var(--accent)"
fi

# Guard self-test: each broken page must fail the asserter.
good_privacy='<h1>Privacy</h1><p>The code of this site sets no cookies and embeds nothing from other sites. Following a link takes you to another site, which has its own policies.</p> <p>The site is hosted on Cloudflare Pages, and Cloudflare Web Analytics is turned on for it. The content security policy on this site allows that analytics script and nothing else from outside. Cloudflare describes Web Analytics as collecting page-load timing and the country, browser, referring site, and page path of each visit, without cookies and without personal data. This page does not describe what Cloudflare logs on its own, such as request or security records.</p><footer><ul class=footer-row><li><a href=/about/>About</a></li><li><a href=/about/#contact>Contact</a></li><li><a href=/privacy/>Privacy</a></li><li><a href=/resume/>Resume</a></li><li><a href=/feed/index.xml>RSS</a></li><li><a href=/social/>Socials</a></li><li><a href=/support/>Support</a></li></ul><p class=footer-line>You'"'"'re not dead until you stop learning. Happy Hacking.</p><nav class=footer-social aria-label="Social profiles"><ul><li><a href=https://x.example rel=noopener aria-label=X><span class="social-icon social-icon--x"></span></a></li></ul></nav><p class=credit>&copy; 2026 Renegade Penguin LLC</p></footer>'
printf '%s\n' "$good_privacy" >"$work/ok-privacy.html"
if python3 -I "$asserter" privacy "$work/ok-privacy.html" >/dev/null 2>&1; then
    pass "guard: a correct privacy page passes"
else
    fail "guard: a correct privacy page was rejected"
fi
sed 's/sets no cookies/sets a few cookies/' "$work/ok-privacy.html" >"$work/bad-privacy.html"
if python3 -I "$asserter" privacy "$work/bad-privacy.html" >/dev/null 2>&1; then
    fail "guard: a changed privacy statement passed"
else
    pass "guard: a changed privacy statement fails"
fi
printf '%s<p>I collect nothing here.</p>\n' "$good_privacy" >"$work/bad-claim.html"
if python3 -I "$asserter" privacy "$work/bad-claim.html" >/dev/null 2>&1; then
    fail "guard: an unsupported 'collect nothing' claim passed"
else
    pass "guard: an unsupported 'collect nothing' claim fails"
fi
printf '%s<iframe src="https://ko-fi.com/"></iframe>\n' "$good_privacy" >"$work/bad-frame.html"
if python3 -I "$asserter" privacy "$work/bad-frame.html" >/dev/null 2>&1; then
    fail "guard: an iframe passed"
else
    pass "guard: an iframe fails"
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all page tests passed"
