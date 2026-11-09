#!/usr/bin/env bash
# Test the page titles and meta descriptions (issue 318) against the built site.
#
# Builds the site into the repository's gitignored tmp/ (never /tmp) and checks the
# Home title, and the title and description of About, Search, Privacy, Support, Gear and
# Journal: the exact strings, every title is "<title> | ChiefGyk3D" with the suffix once
# (the Home title is the one exception and carries it inside), titles and descriptions are
# unique, and no title or description holds a dash character or the word radio.
# Needs the pinned Hugo; a missing Hugo is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/titles.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

if ! command -v hugo >/dev/null 2>&1; then
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
fi
if ! hugo --minify --gc --source "$root" --destination "$work/public" >"$work/hugo.log" 2>&1; then
    cat "$work/hugo.log"
    echo "FAIL: hugo build"
    exit 1
fi

python3 -I - "$work/public" <<'PY'
import re
import sys
from html.parser import HTMLParser

pub = sys.argv[1]
SUFFIX = " | ChiefGyk3D"

WANT = {
    "index.html": (
        "ChiefGyk3D | Cybersecurity, Linux, and Open Source",
        "Hands-on cybersecurity, Linux, homelabs, and open-source projects. I write about what I build, test, and learn.",
    ),
    "about/index.html": (
        "About ChiefGyk3D: Security and Open-Source Work" + SUFFIX,
        "Background, skills, current projects, homelab hardware, and contact details for ChiefGyk3D, a cybersecurity engineer and open-source builder.",
    ),
    "search/index.html": (
        "Find Security, Linux, and Homelab Posts" + SUFFIX,
        "Find published posts and the journal entry by title, summary, or tag, covering cybersecurity, Linux, homelabs, hardware, and open source.",
    ),
    "privacy/index.html": (
        "How This Site Handles Privacy and Analytics" + SUFFIX,
        "Read how this static site handles cookies, local storage, share tools, clipboard access, hosting, and Cloudflare Web Analytics.",
    ),
    "support/index.html": (
        "Ways to Support ChiefGyk3D's Technical Work" + SUFFIX,
        "Ways to support my technical videos, streams, and open-source work, including tips, memberships, merchandise, and cryptocurrency.",
    ),
    "products/index.html": (
        "Security, Homelab, and Creator Gear and Tools" + SUFFIX,
        "A practical list of security gear, privacy services, audio equipment, repair tools, and creator software. Affiliate links are disclosed.",
    ),
    "journal/index.html": (
        "ChiefGyk3D's Technical Journal Index Page" + SUFFIX,
        "The technical journal currently contains one synthetic sample entry and is set up for short notes on builds, tests, and troubleshooting.",
    ),
}


class Head(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title, self.in_title, self.desc = "", False, None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "title":
            self.in_title = True
        if tag == "meta" and a.get("name") == "description":
            self.desc = a.get("content")

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title += data


fails = []
got = {}
for rel, (want_t, want_d) in WANT.items():
    p = Head()
    try:
        p.feed(open(f"{pub}/{rel}", encoding="utf-8").read())
    except OSError as e:
        fails.append(f"{rel}: {e}")
        continue
    t, d = p.title.strip(), (p.desc or "").strip()
    got[rel] = (t, d)
    if t != want_t:
        fails.append(f"{rel}: title is {t!r}, want {want_t!r}")
    if d != want_d:
        fails.append(f"{rel}: description is {d!r}, want {want_d!r}")
    if rel != "index.html" and (not t.endswith(SUFFIX) or t.count("ChiefGyk3D |") != 1 and t.count(SUFFIX) != 1):
        fails.append(f"{rel}: title does not carry the site suffix exactly once: {t!r}")
    if t.count(SUFFIX) > 1:
        fails.append(f"{rel}: title is double-suffixed: {t!r}")
    for label, s in (("title", t), ("description", d)):
        if re.search(r"[\u2013\u2014]|--", s):
            fails.append(f"{rel}: {label} holds a dash character: {s!r}")
        if re.search(r"radio", s, re.I):
            fails.append(f"{rel}: {label} mentions radio: {s!r}")
        if re.search(r"\bcry" + "pto\\b", s, re.I):
            fails.append(f"{rel}: {label} uses the short form of cryptocurrency: {s!r}")
        if re.search(r"gear I use|I recommend|would recommend", s, re.I):
            fails.append(f"{rel}: {label} makes a gear claim: {s!r}")
for idx in (0, 1):
    vals = [v[idx] for v in got.values()]
    if len(set(vals)) != len(vals):
        fails.append(("titles" if idx == 0 else "descriptions") + " are not unique")

if fails:
    for f in fails:
        print("FAIL:", f)
    sys.exit(1)
print("ok: home title, six inner titles and descriptions: exact, suffixed once, unique, clean")
PY
