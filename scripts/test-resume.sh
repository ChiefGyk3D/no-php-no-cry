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
import re
import sys
from html.parser import HTMLParser

HEADINGS = ["Summary", "Skills", "Knowledge", "Projects", "Credentials",
            "Community and content", "Contact"]
REQUIRED = [
    "ChiefGyk3D", "CISSP", "Security+", "Network+", "A+",
    "Network System Administration", "2016", "General class",
    "Ordained Priest, Church of the Latter Day Dude",
    "Employers: references, job history and a phone number are available on "
    "request via the contact section on /about/#contact.",
]
PROJECTS = ["Clouds Against Humanity", "Stream Daemon", "SIEM Docker Stack",
            "pfSense SIEM Stack", "git-your-ship-together", "Hammunition",
            "Reach Around", "Skid Finder"]
FORBIDDEN = [r"\bITIL\b", r"\bLPI\b", r"\bWGU\b", r"Western Governors",
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
        if tag in ("img", "iframe", "script", "style") or "style" in a:
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
    for r in REQUIRED:
        if r not in text:
            out.append("missing text: " + r)
    pos = -1
    for name in PROJECTS:
        i = text.find(name, pos + 1) if pos >= 0 else text.find(name)
        if i < 0:
            out.append("missing project: " + name)
    if "Clouds Against Humanity" in text:
        projs = text[text.find("Projects"):]
        for name in PROJECTS[1:]:
            if name in projs and projs.find(name) < projs.find("Clouds Against Humanity"):
                out.append("Clouds Against Humanity is not first: " + name)
    h1 = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.S)
    if m and (not h1 or re.sub(r"<[^>]+>", "", h1.group(1)).strip() != "ChiefGyk3D"):
        out.append("name line is not exactly ChiefGyk3D")
    if "https://github.com/ChiefGyk3D/Reach-Around" not in p.links:
        out.append("missing Reach Around link")
    for pat in FORBIDDEN:
        if re.search(pat, text):
            out.append("forbidden: " + pat)
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

# baseof concatenates css/pages/*.css, and the built stylesheet carries it.
if grep -q 'resources.Match "css/pages/\*.css"' "$root/layouts/baseof.html"; then
    pass "baseof matches css/pages/*.css"
else fail "baseof does not match css/pages/*.css"; fi
if grep -l '@media print' "$work"/public/css/site.*.css >/dev/null 2>&1; then
    pass "built stylesheet carries the print block"
else fail "built stylesheet has no @media print"; fi

# Guard self-test: the asserter must bite.
bad="$work/bad.html"
printf '<h2>Skills</h2><p>ITIL N0CALL <img src="https://x.example/a.png"></p>' >"$bad"
if python3 -I "$asserter" "$bad" >/dev/null; then
    fail "guard: asserter accepted a bad page"
else pass "guard: asserter rejects a bad page"; fi

# An img inside <main> still fails when the page has the shell around it.
printf '<header><img src="/brand/mascot-128.webp"></header><main><h2>Skills</h2><img src="/x.png"></main>' >"$bad"
out="$(python3 -I "$asserter" "$bad" || true)"
if grep -q 'forbidden element/attribute: img' <<<"$out"; then
    pass "guard: an img inside main is still rejected"
else fail "guard: an img inside main was not flagged"; fi

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all resume checks passed"
