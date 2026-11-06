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
    "Merch shop": "https://shop.chiefgyk3d.com/",
}
PRIVACY = ("This site uses no analytics, cookies, embeds, or third-party requests. "
           "Following a link takes you to another site. I collect nothing here.")
CONTACT = ("There's no contact form. Reach me on Matrix or Discord, or use the email "
           "address listed as plain text.")


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
    # /support/ alone may carry the one pinned script; it is checked below.
    if "a <script> element" in errs:
        errs.remove("a <script> element")
    if p.h1 != ["Support my work"]:
        errs.append("h1 is %r" % p.h1)
    flat = p.flat()
    intro = ("Want to help keep the streams, videos, and projects going? "
             "Pick an option below, and thanks for the support.")
    if intro not in flat:
        errs.append("intro text missing")
    if "StreamElements tips get a live thank-you during the stream." not in flat:
        errs.append("StreamElements note missing")
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
    if "Cryptocurrency tips" not in flat or html.find("Merch shop") > html.find("Cryptocurrency tips"):
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
    # Socials: Instagram is a link; Pixelfed is marked coming soon and not a link.
    insta = [a for a, t in p.links if t == "Instagram"]
    if len(insta) != 1 or insta[0].get("href") != "https://www.instagram.com/chiefgyk3d/":
        errs.append("Instagram link missing or wrong")
    elif not external_ok(insta[0]):
        errs.append("Instagram link lacks target=_blank rel=noopener")
    if "Pixelfed" not in flat or "coming soon" not in flat.lower():
        errs.append("Pixelfed not marked coming soon")
    for a, t in p.links:
        if "pics.chiefgyk3d.com" in (a.get("href") or "") or t.startswith("Pixelfed"):
            errs.append("Pixelfed must not be a link")
    # Ko-fi stays a link-out until the framing test; the TODO is in the template.
    if repo.get("template") is not None and "TODO" not in repo["template"]:
        errs.append("the Ko-fi embed TODO marker is missing from the template")


def about(p, errs, repo):
    common(p, errs)
    if p.h1 != ["About"]:
        errs.append("h1 is %r" % p.h1)
    flat = p.flat()
    if "DRAFT" in flat:
        errs.append("DRAFT marker still on the page")
    if "I'm ChiefGyk3D, a cybersecurity engineer, creator, and open-source builder" not in flat or "If you need references, contact me directly." not in flat:
        errs.append("chosen bio text missing")
    if not any(t == "img" and (a.get("alt") or "") and (a.get("src") or "").startswith("/brand/") for t, a in p.tags):
        errs.append("no mascot image with alt text")
    if p.ids.get("contact") not in ("h2", "h3", "section"):
        errs.append("no #contact heading or section")
    if CONTACT not in flat:
        errs.append("contact sentence missing")
    hrefs = [a.get("href") for a, _ in p.links]
    for h in ("https://discord.chiefgyk3d.com", "https://matrix.to/#/#renegade-penguin:chiefgyk3d.com",
              "https://github.com/ChiefGyk3D/Stream-Daemon", "https://github.com/ChiefGyk3D/Clouds-Against-Humanity"):
        if h not in hrefs:
            errs.append("missing link %s" % h)
    if not any((h or "").startswith("https://github.com/ChiefGyk3D/") and "Reach" in (h or "") for h in hrefs):
        errs.append("missing Reach Around link")
    for name in ("Stream Daemon", "Reach Around", "Clouds Against Humanity"):
        if name not in flat:
            errs.append("project tile %r missing" % name)
    if "/resume/" not in hrefs:
        errs.append("the About body must link to /resume/")
    if "mailto:" in " ".join(h or "" for h in hrefs):
        errs.append("the email address must be plain text, not a mailto: link")
    if "TODO" not in repo["html"] and "email address will be added" not in flat.lower():
        errs.append("email placeholder not marked")


def privacy(p, errs, repo):
    common(p, errs)
    if p.h1 != ["Privacy"]:
        errs.append("h1 is %r" % p.h1)
    if PRIVACY not in p.flat():
        errs.append("privacy statement missing")


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
    out="$(python3 -I "$asserter" "$@" 2>&1)" || rc=$?
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
    fail "support.js shipped: the only script is the pinned /copy.js"
fi
# Only /support/ loads the copy script.
if grep -rl --include=index.html --include=404.html '/copy.js' "$pub" | grep -v '^'"$pub"'/support/index.html$' | grep -q .; then
    fail "a page other than /support/ loads /copy.js"
else
    pass "only /support/ loads /copy.js"
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
if grep -q 'Placeholder posts section' "$root/content/posts/_index.md"; then
    fail "posts index still says 'Placeholder posts section.'"
elif grep -q '^Newest first\.$' "$root/content/posts/_index.md"; then
    pass "posts index intro is 'Newest first.'"
else
    fail "posts index intro is not 'Newest first.'"
fi
if tr '\n' ' ' <<<"$(src_css posts)" | grep -Eq '\.archive-links[^}]*margin-bottom|\.archive-tags[^}]*margin: *var\(--space-5\)'; then
    pass "tag list has spacing under the RSS link"
else
    fail "tag list has no spacing under the RSS link"
fi
# Nav: the current section carries aria-current="page" and no other link does.
nav_current() { # <html> -> text of the aria-current links in the main nav
    python3 -I - "$1" <<'PY'
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
nav = re.search(r"<nav class=site-nav.*?</nav>|<nav class=\"site-nav\".*?</nav>", h, re.S)
nav = nav.group(0) if nav else ""
for m in re.finditer(r"<a\b[^>]*aria-current=\"?page\"?[^>]*>(.*?)</a>", nav, re.S):
    print(re.sub(r"<[^>]+>", "", m.group(1)).strip())
PY
}
for pair in "posts:Posts" "products:Products" "social:Social" "support:Support" "about:About"; do
    got="$(nav_current "$pub/${pair%%:*}/index.html")"
    if [[ "$got" == "${pair##*:}" ]]; then
        pass "nav marks ${pair##*:} current on /${pair%%:*}/"
    else
        fail "nav on /${pair%%:*}/ marks '$got', expected '${pair##*:}'"
    fi
done
if [[ -z "$(nav_current "$pub/index.html")" ]]; then
    pass "nav marks nothing current on the home page"
else
    fail "nav marks something current on the home page"
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
good_privacy='<h1>Privacy</h1><p>This site uses no analytics, cookies, embeds, or third-party requests. Following a link takes you to another site. I collect nothing here.</p>'
printf '%s\n' "$good_privacy" >"$work/ok-privacy.html"
if python3 -I "$asserter" privacy "$work/ok-privacy.html" >/dev/null 2>&1; then
    pass "guard: a correct privacy page passes"
else
    fail "guard: a correct privacy page was rejected"
fi
sed 's/I collect nothing here/I collect a little/' "$work/ok-privacy.html" >"$work/bad-privacy.html"
if python3 -I "$asserter" privacy "$work/bad-privacy.html" >/dev/null 2>&1; then
    fail "guard: a changed privacy statement passed"
else
    pass "guard: a changed privacy statement fails"
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
