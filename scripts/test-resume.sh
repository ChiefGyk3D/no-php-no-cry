#!/usr/bin/env bash
# Test the /resume/ page (issue #86): content rules, print stylesheet, and the
# CSS concat in baseof. Builds the real site into the repository's gitignored
# tmp/ and asserts on the output with the Python stdlib. Needs the pinned Hugo;
# a missing Hugo is a failure, not a skip. A guard self-test feeds the asserter
# a page that breaks each rule and requires it to fail.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/resume.XXXXXX")"
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

asserter="$work/assert_resume.py"
cat >"$asserter" <<'PY'
import html as htmlmod
import re
import sys
from html.parser import HTMLParser

HEADINGS = ["Summary", "Background", "Skills", "Tools and platforms", "This site is the proof", "Open-Source Projects",
            "Homelab and engineering practice", "Certifications",
            "Education", "Speaking and community", "Creator and teaching work",
            "Outside work", "Contact"]
# "Selected accomplishments" renders only when data/resume.yaml `experience` is non-empty
# (issue 262); it is empty until the owner supplies approved text, so it must not show.
GONE_HEADINGS = ["Core Skills", "Technical Knowledge", "Selected accomplishments"]
REQUIRED = [
    "ChiefGyk3D", "CISSP", "Security+", "Network+", "A+", "February 2026",
    "Yes, the order is odd. CISSP came first, in 2024. I earned all three "
    "CompTIA certs in February 2026 while working toward my WGU bachelor",
    "Network System Administration", "2016", "General class",
    "Ordained Priest, Church of the Latter Day Dude",
    "I can secure the network and officiate the wedding afterward.",
    "Senior Cybersecurity Engineer",
    "References, job history and a phone number are available to prospective "
    "employers on request.",
    "How to reach me, on the About page",
    "Speaker: BSides Dayton and COISSA, 2026.",
    "Member of DEFCON 614. With the Call Center Village, where I volunteer.",
    # Issue 262: owner text reused from data/about.yaml and the profile README.
    "I’m primarily self-taught.",
    "I’m more than ready for a security architecture role",
    "I care about end-to-end encryption, zero trust, owning my infrastructure",
    "I share cybersecurity knowledge with more than 500K followers across platforms",
    "You’re not dead until you stop learning. Happy hacking.",
    "Everything I build is open source.",
    "Educational content focused on giving aspiring tech and cybersecurity professionals",
    "Cybersecurity investigations and real-world threat and news breakdowns",
    "I built this site on Cloudflare Pages, and the security headers include a strict CSP with hashed scripts pinned by SHA-256.",
    "Identity and access", "Where I'm headed", "Network and security",
    "Radio, SDR, and time", "Cloud extension", "Cares about",
]
PROJECTS = ["Clouds Against Humanity", "SIEM Docker Stack",
            "pfSense SIEM Stack", "git-your-ship-together", "Skid Finder",
            "Stream Daemon", "Reach Around", "Hammunition", "Penguin Overlord",
            "Star-Daemon", "Typo Sniper", "FrankenLLM", "NetPulse",
            "Department of Internal Arguments", "Scrum Around and Find Out",
            "The Great InfoCon Recovery", "Patch-Gremlin"]
# Added in issue 244: each project's exact GitHub URL, and the closing link.
NEW_PROJECT_URLS = [
    "https://github.com/ChiefGyk3D/penguin-overlord",
    "https://github.com/ChiefGyk3D/Star-Daemon",
    "https://github.com/ChiefGyk3D/typo-sniper",
    "https://github.com/ChiefGyk3D/FrankenLLM",
    "https://github.com/ChiefGyk3D/netpulse",
    "https://github.com/ChiefGyk3D/department-of-internal-arguments",
    "https://github.com/ChiefGyk3D/scrum-around-and-find-out",
    "https://github.com/ChiefGyk3D/the-great-infocon-recovery",
    "https://github.com/ChiefGyk3D/Patch-Gremlin",
]
MORE_URL = "https://github.com/ChiefGyk3D"
MORE_LABEL = "More on GitHub"
SUMMARY = [
    "Senior Cybersecurity Engineer and CISSP with about 15 years across IT and "
    "security. I design, build, integrate, and test security systems across "
    "identity, network defense, SIEM engineering, cloud security, zero trust, "
    "and automation. I question unnecessary access and use hands-on testing to "
    "check whether the design actually works.",
    "I maintain open-source security tools and reusable CI workflows, and I "
    "share cybersecurity knowledge through tutorials, security breakdowns, and "
    "livestreams with more than 500,000 followers across YouTube, Twitch, Kick, "
    "and social platforms. My goal is to break down knowledge barriers.",
]


def load_skills(path):
    """Exact (group, [items]) pairs from data/resume.yaml, stdlib only. The skills
    block is a list of `- group: X` lines each followed by a flow-list
    `items: [a, "b, c"]` line."""
    import csv
    groups, cur = [], None
    in_skills = False
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if re.match(r"^skills:\s*$", line):
            in_skills = True
            continue
        if in_skills and re.match(r"^\S", line):
            break
        if not in_skills:
            continue
        g = re.match(r"^\s+- group:\s*(.+?)\s*$", line)
        if g:
            cur = (g.group(1).strip('"'), [])
            groups.append(cur)
            continue
        it = re.match(r"^\s+items:\s*\[(.*)\]\s*$", line)
        if it and cur is not None:
            row = next(csv.reader([it.group(1)], skipinitialspace=True, quotechar='"'))
            cur[1].extend(x.strip() for x in row)
    return groups


def load_community(path):
    """The `community:` list lines from data/resume.yaml, stdlib only (double-quoted items)."""
    items, on = [], False
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if re.match(r"^community:\s*$", line):
            on = True
            continue
        if on and re.match(r"^\S", line):
            break
        m = re.match(r'^\s+- "(.*)"\s*$', line)
        if on and m:
            items.append(m.group(1))
    return items


import os
YAML = os.environ.get("RESUME_YAML", "data/resume.yaml")
SKILLS = load_skills(YAML)
COMMUNITY = load_community(YAML)


def load_linkedin(path):
    """linkedin_url from data/resume.yaml (issue 195): the one profile link of the Contact section."""
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^linkedin_url:\s*(\S+)\s*$", line)
        if m:
            return m.group(1).strip('"')
    return ""


LINKEDIN = load_linkedin(YAML)
FORBIDDEN = [r"\bITIL\b", r"\bLPI\b", r"Western Governors",
             r"\bMoshe\b", r"\bTODO\b", r"map\["]
CALLSIGN = r"\b[A-Z]{1,2}\d[A-Z]{1,3}\b"
GRID = r"\b[A-R]{2}\d\d(?:[a-x]{2})?\b"


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text, self.h2, self.links, self.bad = [], [], [], []
        self.cur = None
        self.first_project_seen = None
        self.in_projects = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        # The one allowed image is the owner's portrait (issue 179; its attributes are asserted in
        # scripts/test-pages.sh): a same-origin /brand/portrait file, nothing else.
        portrait = tag == "img" and re.fullmatch(r"/brand/portrait-(320|640)\.webp", a.get("src") or "") and a.get("class") == "resume-portrait"
        if (tag in ("img", "iframe", "script", "style") or "style" in a) and not portrait:
            if tag != "script":
                self.bad.append(tag)
        if tag == "h2":
            self.cur = ""
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])

    def handle_endtag(self, tag):
        if tag == "h2" and self.cur is not None:
            self.h2.append(self.cur.strip())
            self.cur = None

    def handle_data(self, d):
        self.text.append(d)
        if self.cur is not None:
            self.cur += d


def check(html):
    # The shell (header mark, footer links) is checked elsewhere; the content
    # rules apply to <main> when the page has one.
    m = re.search(r"<main\b.*?</main>", html, re.S)
    if m:
        html = m.group(0)
    p = Page()
    p.feed(html)
    out = []
    text = re.sub(r"\s+", " ", " ".join(p.text))
    for h in HEADINGS:
        if h not in p.h2:
            out.append("missing heading: " + h)
    for h in GONE_HEADINGS:
        if h in p.h2:
            out.append("heading should be gone: " + h)
    # The degree sits under Education, radio and the ordination under Outside work.
    for h, want in (("Education", "Network System Administration"),
                    ("Education", "Working toward a bachelor's degree at WGU"),
                    ("Outside work", "General class"), ("Outside work", "Latter Day Dude")):
        sec = re.search(r"%s</h2>(.*?)(?:<h2|$)" % h, html, re.S)
        if not sec or want not in htmlmod.unescape(sec.group(1)):
            out.append("%s is not under %s" % (want, h))
    cert = re.search(r"Certifications</h2>(.*?)<h2", html, re.S)
    if cert and re.search(r"Associate degree|General class|Latter Day Dude", cert.group(1)):
        out.append("a degree, the radio license or the ordination is under Certifications")
    # Issue 195: the Contact section carries the one LinkedIn link, read from the data, with the
    # visible text LinkedIn and rel noopener, and no other profile link.
    if not LINKEDIN.startswith("https://www.linkedin.com/in/"):
        out.append("data/resume.yaml linkedin_url is not a LinkedIn profile URL: %r" % LINKEDIN)
    cs = re.search(r"Contact</h2>(.*?)(?:<h2|</article>|$)", html, re.S)
    csec = cs.group(1) if cs else ""
    want = re.search(r'<a [^>]*href="?%s"?[^>]*>LinkedIn</a>' % re.escape(LINKEDIN), csec)
    if not want or "noopener" not in want.group(0):
        out.append("Contact lacks the LinkedIn link (text LinkedIn, rel noopener) from data/resume.yaml")
    if "Find me online: LinkedIn" not in re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", csec)):
        out.append("Contact lacks the line 'Find me online: LinkedIn'")
    if sum(1 for l in p.links if "linkedin.com" in l) != 1:
        out.append("the page must link LinkedIn exactly once")
    if re.search(r'href="?/about/#contact', html) is None:
        out.append("contact link must point at the About page contact section")
    if "/about/#contact" in text:
        out.append("literal route text on the page")
    for r in REQUIRED:
        if r not in text:
            out.append("missing text: " + r)
    cred = re.compile(
        r"CISSP.*?2024.*?Security\+.*?February 2026.*?"
        r"Network\+.*?February 2026.*?A\+.*?February 2026")
    if not cred.search(text):
        out.append("credential order: CISSP 2024, then Security+, Network+, "
                   "A+ each with February 2026")
    sec = re.search(r"Open-Source Projects</h2>(.*?)(?:<h2|$)", html, re.S)
    names = re.findall(r"<li><a [^>]*>(.*?)</a>", sec.group(1) if sec else "")
    if names != PROJECTS:
        out.append("project order: want %r, got %r" % (PROJECTS, names))
    sm = re.search(r"Summary</h2>(.*?)(?:<h2|$)", html, re.S)
    paras = [htmlmod.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", x))).strip()
             for x in re.findall(r"<p>(.*?)</p>", sm.group(1) if sm else "", re.S)]
    if paras != SUMMARY:
        out.append("summary must be exactly the two approved paragraphs")
    if sm and "<li>" in sm.group(1):
        out.append("summary must be paragraphs, not a list")
    sk = re.search(r"Skills</h2>(.*?)(?:<h2|$)", html, re.S)
    groups = re.findall(r"<dt>(.*?)</dt>", sk.group(1) if sk else "")
    dds = [htmlmod.unescape(x) for x in re.findall(r"<dd>(.*?)</dd>", sk.group(1) if sk else "", re.S)]
    if len(SKILLS) != 7 or sum(len(i) for _, i in SKILLS) != 37:
        out.append("yaml skills: want 7 groups and 37 items, got %d and %d"
                   % (len(SKILLS), sum(len(i) for _, i in SKILLS)))
    if groups != [g for g, _ in SKILLS]:
        out.append("skill groups: want %r, got %r" % ([g for g, _ in SKILLS], groups))
    if dds != [", ".join(i) for _, i in SKILLS]:
        out.append("skill items differ from data/resume.yaml (exact, per group, in order)")
    # The community list is exactly data/resume.yaml's community lines, in order (issue 186).
    cm = re.search(r"Speaking and community</h2>(.*?)(?:<h2|$)", html, re.S)
    cm_items = [htmlmod.unescape(re.sub(r"<[^>]+>", "", x)).strip()
                for x in re.findall(r"<li>(.*?)</li>", cm.group(1) if cm else "", re.S)]
    if cm_items != COMMUNITY or len(COMMUNITY) != 5:
        out.append("community list differs from data/resume.yaml: want %r, got %r" % (COMMUNITY, cm_items))
    # Issue 262: the section order, and the homelab repo links come from data/about.yaml.
    if [h for h in p.h2 if h in HEADINGS] != HEADINGS:
        out.append("section order: want %r, got %r" % (HEADINGS, p.h2))
    for u in ("https://github.com/ChiefGyk3D/siem-docker-stack", "https://github.com/ChiefGyk3D/FrankenLLM",
              "https://github.com/Renegade-Penguin/hammunition-hill", "https://github.com/ChiefGyk3D/mother-ticker"):
        if u not in p.links:
            out.append("missing homelab link: " + u)
    if not re.search(r'class="?resume-subtitle', html):
        out.append("missing discipline subtitle line")
    h1 = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.S)
    if m and (not h1 or re.sub(r"<[^>]+>", "", h1.group(1)).strip() != "ChiefGyk3D"):
        out.append("name line is not exactly ChiefGyk3D")
    for u in NEW_PROJECT_URLS:
        if u not in p.links:
            out.append("missing project link: " + u)
    if not re.search(r'<a [^>]*href="?%s"?[^>]*>%s</a>' % (re.escape(MORE_URL), MORE_LABEL), html):
        out.append("missing '%s' link to %s" % (MORE_LABEL, MORE_URL))
    if "https://github.com/ChiefGyk3D/Reach-Around" not in p.links:
        out.append("missing Reach Around link")
    for pat in FORBIDDEN:
        if re.search(pat, text):
            out.append("forbidden: " + pat)
    if "—" in text or "–" in text:
        out.append("em or en dash in text")
    if re.search(CALLSIGN, text):
        out.append("callsign-shaped text")
    if re.search(GRID, text):
        out.append("grid-square-shaped text")
    if p.bad:
        out.append("forbidden element/attribute: " + ",".join(p.bad))
    gh = [l for l in p.links if l.startswith("https://github.com/")]
    if len(gh) < 7:
        out.append("fewer than 7 GitHub project links")
    for l in p.links:
        if l.startswith("http://") or l.startswith("//"):
            out.append("insecure/scheme-relative link: " + l)
    return out


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        problems = check(f.read())
    for x in problems:
        print(x)
    sys.exit(1 if problems else 0)
PY

export RESUME_YAML="$root/data/resume.yaml"
hugo --minify --gc --destination "$work/public" --cacheDir "$work/cache" >"$work/build.log" 2>&1 || {
    cat "$work/build.log"
    fail "hugo build"
}

page="$work/public/resume/index.html"
if [[ -f "$page" ]]; then
    if python3 -I "$asserter" "$page"; then pass "resume page content rules"; else fail "resume page content rules"; fi
else
    fail "public/resume/index.html was not built"
fi

# The print stylesheet: a separate file, light-on-white only inside @media print
# and only through system colors (Canvas, CanvasText, LinkText), so no color
# value is hard-coded and nothing needs a contrast pair. Screen stays on tokens.
css="$root/assets/css/pages/resume.css"
if [[ -f "$css" ]]; then
    if grep -Eqi '#[0-9a-f]{3,8}\b|rgba?\(|hsla?\(' "$css"; then
        fail "resume.css hard-codes a color (tokens or system colors only)"
    else pass "resume.css has no hard-coded color"; fi
    if grep -q '@media print' "$css" && grep -Eq 'color-scheme: *light' "$css"; then
        pass "resume.css has @media print with color-scheme light"
    else fail "resume.css lacks @media print or color-scheme: light"; fi
    # color-scheme: light must appear only inside the print block.
    if python3 -I - "$css" <<'PY'
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
i = css.find("@media print")
outside = css[:i] if i >= 0 else css
sys.exit(1 if re.search(r"color-scheme|Canvas\b", outside) else 0)
PY
    then
        pass "light colors only inside @media print"
    else fail "light colors outside @media print"; fi
else
    fail "assets/css/pages/resume.css is missing"
fi

# Print must reset every muted or accent screen color to CanvasText: each class
# the screen rules color with var(--muted) or var(--accent) must be listed in a
# print rule that sets color: CanvasText.
if [[ -f "$css" ]]; then
    if python3 -I - "$css" <<'PY'
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
i = css.find("@media print")
screen, pr = css[:i], css[i:]
need = set()
for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", screen):
    if re.search(r"color:\s*var\(--(muted|accent)\)", body):
        need.update(x.strip() for x in sel.split(","))
reset = set()
for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", pr):
    if re.search(r"(?<![-\w])color:\s*CanvasText", body):
        reset.update(x.strip() for x in sel.split(","))
missing = need - reset
if not need or missing:
    print("print rules do not reset: %s" % sorted(missing or {"(nothing found)"}))
    sys.exit(1)
PY
    then
        pass "print resets every muted or accent screen color"
    else fail "print stylesheet does not reset a muted or accent color"; fi
    # Guard: dropping .resume-subtitle from the print reset must be flagged.
    sed 's/^  \.resume-subtitle,$//' "$css" >"$work/resume-nosub.css"
    if python3 -I - "$work/resume-nosub.css" >/dev/null 2>&1 <<'PY'
import re, sys
css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
i = css.find("@media print")
screen, pr = css[:i], css[i:]
need, reset = set(), set()
for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", screen):
    if re.search(r"color:\s*var\(--(muted|accent)\)", body):
        need.update(x.strip() for x in sel.split(","))
for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", pr):
    if re.search(r"(?<![-\w])color:\s*CanvasText", body):
        reset.update(x.strip() for x in sel.split(","))
sys.exit(1 if need - reset else 0)
PY
    then
        fail "guard: print check accepted a css without the subtitle reset"
    else pass "guard: print check rejects a css without the subtitle reset"; fi
fi

# baseof concatenates css/pages/*.css, and the built stylesheet carries it.
if grep -q 'resources.Match "css/pages/\*.css"' "$root/layouts/baseof.html"; then
    pass "baseof matches css/pages/*.css"
else fail "baseof does not match css/pages/*.css"; fi
if grep -l '@media print' "$work"/public/css/site.*.css >/dev/null 2>&1; then
    pass "built stylesheet carries the print block"
else fail "built stylesheet has no @media print"; fi

# Guard self-test: the asserter must bite.
bad="$work/bad.html"
printf '<h2>Core Skills</h2><p>ITIL N0CALL <img src="https://x.example/a.png"></p>' >"$bad"
if python3 -I "$asserter" "$bad" >/dev/null; then
    fail "guard: asserter accepted a bad page"
else pass "guard: asserter rejects a bad page"; fi

# An img inside <main> still fails when the page has the shell around it.
printf '<header><img src="/brand/mascot-128.webp"></header><main><h2>Core Skills</h2><img src="/x.png"></main>' >"$bad"
out="$(python3 -I "$asserter" "$bad" || true)"
if grep -q 'forbidden element/attribute: img' <<<"$out"; then
    pass "guard: an img inside main is still rejected"
else fail "guard: an img inside main was not flagged"; fi

# Credential order guard: mutate the real built page and require the asserter
# to flag each case (reordered certs, a lost date) and to accept the original.
if [[ -f "$page" ]]; then
    python3 -I - "$page" "$work" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
a = "CompTIA Security+, earned February 2026"
b = "CompTIA Network+, earned February 2026"
assert a in src and b in src, "credential entries not found in built page"
open(sys.argv[2] + "/cred-ok.html", "w", encoding="utf-8").write(src)
swapped = src.replace(a, "@@A@@").replace(b, a).replace("@@A@@", b)
open(sys.argv[2] + "/cred-reordered.html", "w", encoding="utf-8").write(swapped)
open(sys.argv[2] + "/cred-nodate.html", "w", encoding="utf-8").write(
    src.replace(b, "CompTIA Network+, earned"))
PY
    if python3 -I "$asserter" "$work/cred-ok.html" >/dev/null; then
        pass "guard: unmutated page passes the credential order rule"
    else fail "guard: unmutated page fails the asserter"; fi
    for c in reordered nodate; do
        out="$(python3 -I "$asserter" "$work/cred-$c.html" || true)"
        if grep -q 'credential order' <<<"$out"; then
            pass "guard: credential $c is rejected"
        else fail "guard: credential $c was not flagged"; fi
    done
fi

# LinkedIn guard (issue 195): the link removed, its text changed, or rel dropped must each fail.
if [[ -f "$page" ]]; then
    for c in removed text norel; do
        python3 -I - "$page" "$work/li-$c.html" "$c" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<a [^>]*linkedin\.com[^>]*>LinkedIn</a>", src)
assert m, "LinkedIn link not in the built page"
a = m.group(0)
new = {"removed": "", "text": a.replace(">LinkedIn<", ">Profile<"),
       "norel": re.sub(r"\s*rel=\"?noopener\"?", "", a)}[sys.argv[3]]
assert new != a
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(a, new, 1))
PY
        out="$(python3 -I "$asserter" "$work/li-$c.html" || true)"
        if grep -q 'LinkedIn' <<<"$out"; then
            pass "guard: LinkedIn link $c is rejected"
        else fail "guard: LinkedIn link $c was not flagged"; fi
    done
fi

# Skill item guard: removing any single item from the built page must fail.
if [[ -f "$page" ]]; then
    n="$(
        RESUME_YAML="$root/data/resume.yaml" python3 -I - "$page" "$work" "$asserter" <<'PY'
import html, re, subprocess, sys
src = open(sys.argv[1], encoding="utf-8").read()
sys.argv = [sys.argv[3]]
ns = {}
exec(compile(open(sys.argv[0]).read().split('if __name__')[0], "a", "exec"), ns)
items = [i for _, l in ns["SKILLS"] for i in l]
bad = 0
for it in items:
    mut = None
    for m in re.finditer(r"<dd>(.*?)</dd>", src, re.S):
        body = m.group(1)
        for c in (it, html.escape(it, quote=False), html.escape(it, quote=False).replace("'", "&#39;")):
            if c in body:
                mut = src[:m.start(1)] + body.replace(c, "", 1) + src[m.end(1):]
                break
        if mut is not None:
            break
    if mut is None:
        print("item not found in a skills dd: " + it, file=sys.stderr)
        bad += 1
        continue
    if not any("skill items" in x for x in ns["check"](mut)):
        print("removal not flagged: " + it, file=sys.stderr)
        bad += 1
print(len(items), bad)
sys.exit(1 if bad or len(items) != 37 else 0)
PY
    )" && pass "guard: removing any single skill item is rejected ($n)" || fail "guard: a removed skill item was not flagged"
fi

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all resume checks passed"
