#!/usr/bin/env bash
# Tests for the /contact/ page's metadata and wiring (issue 329): its title and description
# (seoTitle front matter, in the style of the issue 318 title work), the sitemap entry, the footer
# link, and that the About page no longer carries the address. Builds the site into the
# repository's gitignored tmp/ (never /tmp). With --against DIR it checks an already built
# site instead (used to show the test fails on the build from before the page existed).
# A guard self-test breaks each rule on a copy of the page and requires a failure.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/contact-page.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

pub=""
if [[ "${1:-}" == "--against" ]]; then
    pub="$2"
else
    command -v hugo >/dev/null 2>&1 || {
        echo "FAIL: hugo is not on PATH (see .hugo-version)"
        exit 1
    }
    hugo --minify --gc --quiet --destination "$work/public" >"$work/hugo.log" 2>&1 || {
        cat "$work/hugo.log"
        echo "FAIL: build"
        exit 1
    }
    pub="$work/public"
fi

checker="$work/check.py"
cat >"$checker" <<'PY'
import html
import re
import sys

pub, root = sys.argv[1], sys.argv[2]
page = sys.argv[3] if len(sys.argv) > 3 else pub + "/contact/index.html"
errs = []


def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return None


fm = read(root + "/content/contact/index.md") or ""


def front(key):
    m = re.search(r'^%s: "(.*)"$' % key, fm, re.M)
    return m.group(1) if m else None


seo, desc = front("seoTitle"), front("description")
if not seo or not desc:
    errs.append("content/contact/index.md needs seoTitle and description")
postal = [front(key) for key in ("postalName", "postalStreet", "postalSuite", "postalLocality")]
want_postal = ["ChiefGyk3D", "3000 E Main St", "Suite B 187", "Columbus, OH 43209"]
if postal != want_postal:
    errs.append("content/contact/index.md needs the public postal mailbox")
h = read(page)
if h is None:
    errs.append("the /contact/ page is not built")
    h = ""
title = re.search(r"<title>(.*?)</title>", h, re.S)
title = html.unescape(title.group(1)) if title else ""
baseof = read(root + "/layouts/baseof.html") or ""
# Until the seoTitle layout change of issue 318 lands, the title is the page title.
want = (seo if "seoTitle" in baseof else "Contact") + " | "
if not title.startswith(want):
    errs.append("title is %r, expected it to start with %r" % (title, want))
if seo and not (30 <= len(seo) <= 62 and seo.startswith("Contact")):
    errs.append("seoTitle must start with Contact and be 30 to 62 characters: %r" % seo)
m = re.search(r'<meta name=description content="?([^">]*)', h)
got = html.unescape(m.group(1)) if m else ""
if desc and got != desc:
    errs.append("meta description is %r, expected %r" % (got, desc))
if desc and not (70 <= len(desc) <= 160):
    errs.append("description must be 70 to 160 characters (found %d)" % len(desc))
if chr(8212) in h or chr(8211) in h:
    errs.append("an em or en dash is on the page")
address = re.search(r'<address class="?contact-postal"?>(.*?)</address>', h, re.S)
if not address:
    errs.append("the Contact page needs a semantic postal address")
else:
    address_text = html.unescape(re.sub(r"<[^>]*>", "\n", address.group(1)))
    address_lines = [line.strip() for line in address_text.splitlines() if line.strip()]
    if address_lines != want_postal:
        errs.append("the postal address must contain the public mailbox as plain text")
    if re.search(r"<a\b", address.group(1), re.I):
        errs.append("the postal address must not be a link")
sm = read(pub + "/sitemap.xml") or ""
if "/contact/</loc>" not in sm:
    errs.append("the sitemap does not list /contact/")
fl = re.search(r'<a[^>]*href=([^\s>]+)[^>]*>Contact</a>', h)
if not fl or fl.group(1).strip('"').endswith("/about/#contact") or not fl.group(1).strip('"').endswith("/contact/"):
    errs.append("the footer Contact link must point at /contact/ (found %r)" % (fl.group(1) if fl else None))
ab = read(pub + "/about/index.html") or ""
if "mailto:" in ab:
    errs.append("the About page still carries the email link")
if "/contact/" not in ab:
    errs.append("the About page must point to /contact/")
# The Discord and Matrix tiles (issue 329): icon, name and address in separate elements, a hint,
# an accessible name with both platform and address, new-tab link handled like other external links.
tiles = re.findall(r'<a class="?tile contact-tile"?[^>]*>.*?</a>', h, re.S)
if len(tiles) != 2:
    errs.append("expected 2 contact tiles, found %d" % len(tiles))
for t, n in zip(tiles, ("Discord", "Matrix")):
    if 'social-icon--' + n.lower() not in t:
        errs.append("the %s tile has no platform icon" % n)
    nm = re.search(r'class="?contact-tile-name"?[^>]*>([^<]*)<', t)
    ad = re.search(r'class="?contact-tile-address"?[^>]*>(.*?)(?=<span[^>]*contact-tile-go)', t, re.S)
    if not nm or nm.group(1).strip() != n:
        errs.append("the %s tile needs the name alone in .contact-tile-name" % n)
    if not ad or not re.sub("<[^>]*>", "", ad.group(1)).strip():
        errs.append("the %s tile needs the address alone in .contact-tile-address" % n)
    al = re.search(r'aria-label="([^"]*)"', t)
    if not al or n not in al.group(1) or not ad or html.unescape(re.sub("<[^>]*>", "", ad.group(1))).strip() not in html.unescape(al.group(1)):
        errs.append("the %s tile accessible name must include the platform and the address" % n)
    if 'contact-tile-go' not in t:
        errs.append("the %s tile needs an open-in-new hint" % n)
    if 'target=_blank' not in t.replace('"', '') or 'noopener' not in t:
        errs.append("the %s tile must open in a new tab with rel noopener" % n)
# Focus (issue 329 review): wherever a :focus-visible rule gives a child the on-accent color, the
# tile itself must take the same amber fill and tick as hover, or the dark child text lands on the
# dark surface. A rule is "the tile's own" when its selector is exactly .contact-tile:focus-visible.
css = read(sys.argv[4] if len(sys.argv) > 4 else root + "/assets/css/pages/contact.css") or ""
css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
child_on_accent = False
own = ""
for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
    sels = [x.strip() for x in sel.split(",")]
    if any(re.search(r"\.contact-tile:focus-visible\s+\S", x) for x in sels) and "var(--on-accent)" in body:
        child_on_accent = True
    if ".contact-tile:focus-visible" in sels:
        own += body
if child_on_accent:
    for need in (r"--fill:\s*var\(--accent\)", r"--tick:\s*var\(--on-accent\)", r"color:\s*var\(--on-accent\)", r"outline:[^;]*var\(--focus\)"):
        if not re.search(need, own):
            errs.append("the .contact-tile:focus-visible rule must set %s (the focus state needs the hover fill before the on-accent child colors)" % need)
for e in errs:
    print(e)
sys.exit(1 if errs else 0)
PY

failures=0
if python3 -I "$checker" "$pub" "$root"; then
    echo "ok: the contact page metadata and wiring"
else
    failures=$((failures + 1))
    echo "FAIL: the contact page metadata and wiring"
fi

if [[ "${1:-}" != "--against" ]]; then
    mk() { # <name> <python expression on s>
        python3 -I -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); t = eval(sys.argv[3]); assert t != s; open(sys.argv[2], "w", encoding="utf-8").write(t)' "$pub/contact/index.html" "$work/bad-$1.html" "$2"
    }
    mk title 's.replace("<title>", "<title>x", 1)'
    mk desc 's.replace("<meta name=description content=", "<meta name=description content=x", 1)'
    for b in title desc; do
        if python3 -I "$checker" "$pub" "$root" "$work/bad-$b.html" >/dev/null 2>&1; then
            echo "FAIL: guard: a contact page with a broken $b passed"
            failures=$((failures + 1))
        else
            echo "ok: guard: a contact page with a broken $b fails"
        fi
    done
fi

if [[ "${1:-}" != "--against" ]]; then
    python3 -I -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); t = s.replace("--fill: var(--accent);", "--fill: none;"); assert t != s; open(sys.argv[2], "w", encoding="utf-8").write(t)' "$root/assets/css/pages/contact.css" "$work/bad-focus.css"
    if python3 -I "$checker" "$pub" "$root" "$pub/contact/index.html" "$work/bad-focus.css" >/dev/null 2>&1; then
        echo "FAIL: guard: a focus rule without the fill passed"
        failures=$((failures + 1))
    else
        echo "ok: guard: a focus rule without the fill fails"
    fi
fi

[[ $failures -eq 0 ]] || exit 1
echo "test-contact-page: all passed"
