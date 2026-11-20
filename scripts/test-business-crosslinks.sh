#!/usr/bin/env bash
# Test the business-site crosslinks (issue 407) against two real builds.
#
# params.businessSiteURL is empty in hugo.toml, so a build that does not set it
# (production, built by the private pipeline) shows nothing. The dev deploy sets
# HUGO_PARAMS_BUSINESSSITEURL. This builds the site both ways into the
# repository's gitignored tmp/ (never /tmp) and asserts, with Python's stdlib
# HTML parser:
#   set:   the nav item (after About), the About block, the Resume block and the
#          footer line all appear with the exact approved text, every link
#          equals the param plus its path, and carries rel="noopener".
#   empty: none of the four appears and the page holds no empty anchor.
# A guard self-test feeds the asserter pages that break each rule and requires
# a failure. Needs the pinned Hugo; a missing Hugo is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/crosslinks.XXXXXX")"
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

asserter="$work/assert_crosslinks.py"
cat >"$asserter" <<'PY'
import json
import re
import sys
from html.parser import HTMLParser

# The owner-approved copy. A second copy lives here on purpose: a change to
# data/business.yaml must be a reviewed change to this test too.
NAV_LABEL = "Work with me"
ABOUT_BLOCK = ("If you want to hire me for security advisory work, I do it through Renegade Penguin LLC. "
               "The first step is a free 30 minute fit call.")
RESUME_BLOCK = "I am available for advisory, assessment, and speaking work through Renegade Penguin LLC."
FOOTER_LINE = "Hire me through Renegade Penguin LLC."
LINK_TEXT = "Renegade Penguin LLC"
# Issue 414: the credit link, the Person node's worksFor and jobTitle, the llms.txt block.
# JOB_TITLE is the text the business site's own Person node uses for the same person.
JOB_TITLE = "Founder, Renegade Penguin LLC"
LLMS_HEADING = "## Work with me"
LLMS_NOTE = "My advisory firm provides hands-on security assessments, AI security reviews, and virtual CISO and CIO guidance."
# The Contact page notice (owner-approved wording; LINK_TEXT is replaced by the link).
CONTACT_NOTICE = ("If you're looking to hire me for consulting or advisory work, please head to LINK_TEXT "
                  "so your request reaches Renegade Penguin LLC. This page and email address are for "
                  "content, community, and personal messages.")
CONTACT_LINK_TEXT = "renegadepenguinllc.com"
CREDIT_TEXT = re.compile("^\N{COPYRIGHT SIGN} \\d{4} Renegade Penguin LLC \N{MIDDLE DOT} Powered by No PHP No Cry$")
# The credit exactly as it ships today (minified), for the empty-param check.
CREDIT_RAW = re.compile(
    "^(?:&copy;|\N{COPYRIGHT SIGN}) \\d{4} Renegade Penguin LLC <span aria-hidden=\"?true\"?>(?:&middot;|&#183;|\N{MIDDLE DOT})</span> Powered by "
    "<a href=\"?https://github\\.com/ChiefGyk3D/no-php-no-cry\"? rel=\"?noopener\"?>No PHP No Cry"
    "<span class=\"?visually-hidden\"?> \\(external site\\)</span></a>$")


class P(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.anchors = []   # dicts: href, rel, text (visually-hidden text dropped), nav
        self.paras = []     # (class, text) of every p
        self.navlinks = []  # text of every link inside the main nav, in order
        self._a = None
        self._p = None
        self._hidden = 0
        self._stack = []
        self._in_nav = 0
        self._in_credit = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").split()
        hid = "visually-hidden" in cls
        if tag not in ("br", "img", "meta", "link", "input", "hr", "source"):
            self._stack.append((tag, hid, tag == "nav" and a.get("aria-label") == "Main"))
        if hid:
            self._hidden += 1
        if tag == "nav" and a.get("aria-label") == "Main":
            self._in_nav += 1
        if tag == "a":
            self._a = {"href": a.get("href"), "rel": a.get("rel"), "label": a.get("aria-label") or "", "text": "", "nav": bool(self._in_nav), "credit": self._in_credit}
        if tag == "p":
            self._p = [" ".join(cls), ""]
            self._in_credit = "credit" in cls

    def handle_endtag(self, tag):
        while self._stack:
            t, hid, isnav = self._stack.pop()
            if hid:
                self._hidden -= 1
            if isnav:
                self._in_nav -= 1
            if t == tag:
                break
        if tag == "a" and self._a is not None:
            self.anchors.append(self._a)
            if self._a["nav"]:
                self.navlinks.append(self._a["text"].strip())
            self._a = None
        if tag == "p" and self._p is not None:
            self.paras.append(tuple(self._p))
            self._p = None
            self._in_credit = False

    def handle_data(self, d):
        if self._hidden:
            return
        if self._a is not None:
            self._a["text"] += d
        if self._p is not None:
            self._p[1] += d


def parse(path):
    p = P()
    p.feed(open(path, encoding="utf-8").read())
    return p


def norm(s):
    return " ".join(s.split())


def noopener(a):
    return "noopener" in (a["rel"] or "").split()


def empty_anchors(name, p):
    return [f"{name}: empty anchor {a!r}" for a in p.anchors if not (a["href"] or "").strip() or not (a["text"].strip() or a["label"].strip())]


def check_set(pages, base):
    bad = []
    contact = base + "/contact/"
    home = base + "/"
    for name, p in pages.items():
        nav = [a for a in p.anchors if a["nav"] and a["text"].strip() == NAV_LABEL]
        if len(nav) != 1:
            bad.append(f"{name}: expected one nav item {NAV_LABEL!r}, found {len(nav)}")
        else:
            if nav[0]["href"] != contact:
                bad.append(f"{name}: nav href {nav[0]['href']!r} is not {contact!r}")
            if not noopener(nav[0]):
                bad.append(f"{name}: nav link lacks rel=noopener")
        labels = p.navlinks
        if NAV_LABEL not in labels or "About" not in labels or labels.index(NAV_LABEL) != labels.index("About") + 1:
            bad.append(f"{name}: nav item does not follow About ({labels})")
        foot = [t for c, t in p.paras if norm(t) == FOOTER_LINE]
        if len(foot) != 1:
            bad.append(f"{name}: expected one footer line {FOOTER_LINE!r}, found {len(foot)}")
        fa = [a for a in p.anchors if a["href"] == home and norm(a["text"]) == LINK_TEXT and not a["credit"]]
        if len(fa) != 1:
            bad.append(f"{name}: expected one footer link to {home!r}, found {len(fa)}")
        elif not noopener(fa[0]):
            bad.append(f"{name}: footer link lacks rel=noopener")
        bad += empty_anchors(name, p)
    for name, block in (("about", ABOUT_BLOCK), ("resume", RESUME_BLOCK)):
        p = pages[name]
        hits = [t for c, t in p.paras if norm(t) == block or norm(t).startswith(block)]
        if len(hits) != 1:
            bad.append(f"{name}: expected one block paragraph {block!r}, found {len(hits)}")
        links = [a for a in p.anchors if a["href"] == contact and norm(a["text"]) == LINK_TEXT and not a["nav"]]
        if len(links) != 1:
            bad.append(f"{name}: expected one block link {LINK_TEXT!r} to {contact!r}, found {len(links)}")
        elif not noopener(links[0]):
            bad.append(f"{name}: block link lacks rel=noopener")
    return bad


def check_empty(pages):
    bad = []
    for name, p in pages.items():
        bad += empty_anchors(name, p)
        for a in p.anchors:
            if "renegadepenguinllc.com" in (a["href"] or "") or "staging.example" in (a["href"] or ""):
                bad.append(f"{name}: business link present while the param is empty: {a['href']!r}")
        if any(a["text"].strip() == NAV_LABEL for a in p.anchors):
            bad.append(f"{name}: nav item present while the param is empty")
        for c, t in p.paras:
            n = norm(t)
            if ABOUT_BLOCK in n or RESUME_BLOCK in n or FOOTER_LINE in n:
                bad.append(f"{name}: business text present while the param is empty: {n!r}")
    return bad


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def person_node(root):
    """The home page Person node from the JSON-LD data block (parsed, not grepped)."""
    html = read(f"{root}/index.html")
    blocks = re.findall(r'<script type="?application/ld\+json"?>(.*?)</script>', html, re.S)
    if len(blocks) != 1:
        return None, [f"home: expected one JSON-LD block, found {len(blocks)}"]
    try:
        graph = json.loads(blocks[0])["@graph"]
    except (ValueError, KeyError) as e:
        return None, [f"home: JSON-LD does not parse: {e}"]
    persons = [n for n in graph if n.get("@type") == "Person"]
    if len(persons) != 1:
        return None, [f"home: expected one Person node, found {len(persons)}"]
    return persons[0], []


def check_extras(mode, base, root, pages):
    """Credit link, Person worksFor and jobTitle, llms.txt block (issue 414)."""
    bad = []
    llms = read(f"{root}/llms.txt")
    person, errs = person_node(root)
    bad += errs
    for name, rel in (("home", "index.html"), ("about", "about/index.html"), ("resume", "resume/index.html"), ("posts", "posts/index.html"), ("contact", "contact/index.html")):
        m = re.search(r'<p class="?credit"?>(.*?)</p>', read(f"{root}/{rel}"), re.S)
        if not m:
            bad.append(f"{name}: no credit paragraph")
            continue
        credit = [a for a in pages[name].anchors if a["credit"] and norm(a["text"]) == LINK_TEXT]
        text = [norm(t) for c, t in pages[name].paras if "credit" in c.split()]
        if mode == "set":
            if len(credit) != 1:
                bad.append(f"{name}: expected one credit link {LINK_TEXT!r}, found {len(credit)}")
            else:
                if credit[0]["href"] != base + "/":
                    bad.append(f"{name}: credit href {credit[0]['href']!r} is not {base + '/'!r}")
                rel_tokens = (credit[0]["rel"] or "").split()
                if "me" not in rel_tokens or "noopener" not in rel_tokens:
                    bad.append(f"{name}: credit link rel {credit[0]['rel']!r} lacks me and noopener")
            if len(text) != 1 or not CREDIT_TEXT.match(text[0]):
                bad.append(f"{name}: credit text changed: {text!r}")
        else:
            if credit:
                bad.append(f"{name}: credit link present while the param is empty")
            if not CREDIT_RAW.match(m.group(1)):
                bad.append(f"{name}: credit markup is not the plain-text original: {m.group(1)!r}")
    if person is not None:
        if mode == "set":
            want = {"@type": "Organization", "@id": base + "/#organization", "name": LINK_TEXT, "url": base + "/"}
            if person.get("worksFor") != want:
                bad.append(f"Person worksFor is {person.get('worksFor')!r}, want {want!r}")
            if person.get("jobTitle") != JOB_TITLE:
                bad.append(f"Person jobTitle is {person.get('jobTitle')!r}, want {JOB_TITLE!r}")
        else:
            for k in ("worksFor", "jobTitle"):
                if k in person:
                    bad.append(f"Person has {k} while the param is empty")
    block = f"{LLMS_HEADING}\n- [{LINK_TEXT}]({base}/): {LLMS_NOTE}\n"
    if mode == "set":
        if llms.count(block) != 1:
            bad.append("llms.txt: the Work with me block is missing, altered or repeated")
        elif llms.index(block) > llms.index("## Find me online"):
            bad.append("llms.txt: the Work with me block must come before Find me online")
    else:
        if LLMS_HEADING in llms or "renegadepenguin" in llms.lower():
            bad.append("llms.txt: a business reference is present while the param is empty")
    bad += check_contact(mode, base, root, pages["contact"])
    return bad


def check_contact(mode, base, root, p):
    """The Contact page notice: exact words, one link to the business home, before the email address."""
    bad = []
    raw = read(f"{root}/contact/index.html")
    notes = [norm(t) for c, t in p.paras if "contact-notice" in c.split()]
    links = [a for a in p.anchors if norm(a["text"]) == CONTACT_LINK_TEXT]
    if raw.count("<!--email_off-->") != 1 or raw.count("<!--/email_off-->") != 1 or not re.search(
            r"<!--email_off-->\s*<p class=\"?contact-email\"?>.*?mailto:.*?</p><!--/email_off-->", raw, re.S):
        bad.append("contact: the email_off markers no longer wrap the address")
    if mode == "set":
        want = norm(CONTACT_NOTICE.replace("LINK_TEXT", CONTACT_LINK_TEXT))
        if notes != [want]:
            bad.append(f"contact: notice paragraphs are {notes!r}, want exactly [{want!r}]")
        if len(links) != 1:
            bad.append(f"contact: expected one link with text {CONTACT_LINK_TEXT!r}, found {len(links)}")
        else:
            if links[0]["href"] != base + "/":
                bad.append(f"contact: notice link href {links[0]['href']!r} is not {base + '/'!r}")
            if not noopener(links[0]):
                bad.append("contact: notice link lacks rel=noopener")
        i = raw.find("contact-notice")
        j = raw.find("<!--email_off-->")
        if i < 0 or j < 0 or i > j:
            bad.append("contact: the notice must come before the email address")
    else:
        if notes or links or "contact-notice" in raw or "hire me for consulting" in raw:
            bad.append("contact: notice or link present while the param is empty")
    return bad


def main(argv):
    mode, base, root = argv[1], argv[2], argv[3]
    pages = {}
    for name, rel in (("home", "index.html"), ("about", "about/index.html"), ("resume", "resume/index.html"), ("posts", "posts/index.html"), ("contact", "contact/index.html")):
        pages[name] = parse(f"{root}/{rel}")
    bad = check_set(pages, base) if mode == "set" else check_empty(pages)
    bad += check_extras(mode, base, root, pages)
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

base="https://staging.example"
build() {
    # $1 name, $2 the param value (may be empty)
    local name="$1"
    if ! HUGO_PARAMS_BUSINESSSITEURL="$2" hugo --minify --gc --destination "$work/$name" --cacheDir "$work/cache" >"$work/$name.log" 2>&1; then
        cat "$work/$name.log"
        fail "hugo build ($name)"
        return 1
    fi
}

if build dev "$base"; then
    if python3 -I "$asserter" set "$base" "$work/dev"; then pass "dev build shows every crosslink with the exact text and URL"; else fail "dev build crosslinks"; fi
fi
# The production apex, character for character (the id must match the business site's).
apex="https://renegadepenguinllc.com"
if build apex "$apex"; then
    if python3 -I "$asserter" set "$apex" "$work/apex"; then pass "apex build: credit link, worksFor id, jobTitle and llms block exact"; else fail "apex build crosslinks"; fi
fi
if build prod ""; then
    if python3 -I "$asserter" empty "" "$work/prod"; then pass "empty param renders none of the four placements and no empty anchor"; else fail "empty-param build shows a crosslink"; fi
fi

# A hostile or malformed value must fail the build, never render as markup.
hostile=(
    'https://x.example/" onmouseover="alert(1)'
    "https://x.example/' onmouseover='alert(1)"
    'https://x.example/><script>alert(1)</script>'
    'https://x.example/ space'
    'https://x.example/\evil'
    'https://x.example/<b>'
    'http://staging.example'
    'javascript:alert(1)'
)
for i in "${!hostile[@]}"; do
    if HUGO_PARAMS_BUSINESSSITEURL="${hostile[$i]}" hugo --minify --gc --destination "$work/hostile-$i" --cacheDir "$work/cache" >"$work/hostile-$i.log" 2>&1; then
        fail "hostile value $i built: ${hostile[$i]}"
    elif [[ -d "$work/hostile-$i" ]] && grep -rIlE 'x\.example|staging\.example' "$work/hostile-$i" >/dev/null 2>&1; then
        fail "hostile value $i left injected markup in the output"
    elif grep -q 'businessSiteURL' "$work/hostile-$i.log"; then
        pass "hostile value $i fails the build naming businessSiteURL"
    else
        fail "hostile value $i failed the build for another reason (see $work/hostile-$i.log)"
        cat "$work/hostile-$i.log"
    fi
done
# A valid value with a port and a path still builds and renders under the same assertions.
if build ok-path "https://staging.example:8443/base"; then
    if python3 -I "$asserter" set "https://staging.example:8443/base" "$work/ok-path"; then pass "a valid value with a port and a path renders exactly"; else fail "valid value with a port and a path"; fi
fi

# hugo.toml itself ships the param empty (production shows nothing until opted in).
if grep -Eq '^[[:space:]]*businessSiteURL[[:space:]]*=[[:space:]]*""[[:space:]]*(#.*)?$' "$root/hugo.toml"; then
    pass "hugo.toml ships params.businessSiteURL empty"
else
    fail "hugo.toml must set params.businessSiteURL = \"\""
fi
# The dev deploy build sets it to the staging business host.
if grep -Eq 'HUGO_PARAMS_BUSINESSSITEURL:[[:space:]]*https://staging\.renegadepenguinllc\.com[[:space:]]*$' "$root/.github/workflows/deploy.yml"; then
    pass "deploy.yml sets the param for the dev build"
else
    fail "deploy.yml must set HUGO_PARAMS_BUSINESSSITEURL to the staging business host"
fi

# Guard self-test: the asserter must fail on pages that break each rule.
if [[ -d "$work/dev" ]]; then
    mut() {
        # $1 label, $2 sed expression applied to a copy of the dev build
        local d="$work/mut-$1" f
        cp -r "$work/dev" "$d"
        for f in "$d/index.html" "$d/about/index.html" "$d/resume/index.html" "$d/posts/index.html" "$d/contact/index.html" "$d/llms.txt"; do
            sed -i -E "$2" "$f"
        done
        if python3 -I "$asserter" set "$base" "$d" >/dev/null 2>&1; then
            fail "guard: $1 was not rejected"
        else
            pass "guard: $1 is rejected"
        fi
    }
    mut wrong-url 's#href="?https://staging\.example/contact/"?#href=https://staging.example/other/#g'
    mut no-noopener 's# rel="?noopener"?##g'
    mut wrong-text 's#Work with me#Hire me#g'
    mut empty-anchor 's#<a href="?https://staging\.example/"?#<a href=""#g'
    mut credit-no-me 's#rel="me noopener"#rel=noopener#g'
    mut credit-wrong-href 's#(<p class="?credit"?>[^<]*<a href="?)https://staging\.example/#\1https://staging.example/x/#g'
    mut worksfor-wrong-id 's#/\#organization"#/\#org"#g'
    mut no-jobtitle 's#"jobTitle":"[^"]*",?##g'
    mut notice-edited-words 's#hire me for consulting#hire me for work#g'
    mut notice-link-missing 's#(<p class="?contact-notice"?>[^<]*)<a href="?https://staging\.example/"? rel="?noopener"?>[^<]*<span[^>]*>[^<]*</span></a>#\1apex#g'
    mut notice-other-host 's#(<p class="?contact-notice"?>[^<]*)<a href="?https://staging\.example/"?#\1<a href=https://evil.example/#g'
    mut no-llms-heading 's#^\#\# Work with me$#\#\# Other#'
    # The empty-mode guard must bite on a page that still shows the links.
    if python3 -I "$asserter" empty "" "$work/dev" >/dev/null 2>&1; then
        fail "guard: empty-mode accepted a page with crosslinks"
    else
        pass "guard: empty-mode rejects a page with crosslinks"
    fi
fi

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all business crosslink checks passed"
