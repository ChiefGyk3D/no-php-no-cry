#!/usr/bin/env bash
# The Contact page's business email must be readable without JavaScript (issue 329).
#
# Usage: scripts/check-about-email.sh [--mode text|image] [output-dir]   (default: public)
#
# Cloudflare Email Address Obfuscation rewrites an address in the served HTML
# into "[email protected]" (data-cfemail, a /cdn-cgi/l/email-protection link) and
# injects email-decode.min.js, so the address needs JavaScript. The documented
# opt-out is to put the address between <!--email_off--> and <!--/email_off-->
# (developers.cloudflare.com/waf/tools/scrape-shield/email-address-obfuscation/,
# "Prevent Cloudflare from obfuscating email"). Findings, printed as "[rule] file":
#
#   about-email-rewritten    any page carries the host rewrite or decoder markers
#   about-email-unprotected  the Contact page has the address outside email_off markers
#   about-email-missing      the Contact page lacks the address in the expected form:
#                            text mode, the address as the link text of a mailto link;
#                            image mode, a mailto link around an <img> and no address as text
#   about-email-image-alt    image mode, the image's alt text contains the address, or is
#                            not the fixed accessible name
#
# The address comes from scripts/about-email.sh (empty while the contact config is
# incomplete; then the page must show no address and only the rewrite check runs).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode=text
if [[ "${1:-}" == "--mode" ]]; then
    mode="${2:-}"
    shift 2
fi
[[ "$mode" == text || "$mode" == image ]] || {
    echo "usage: $0 [--mode text|image] [output-dir]" >&2
    exit 2
}
dir="${1:-public}"
[[ -d "$dir" ]] || {
    echo "no such directory: $dir" >&2
    exit 2
}
mail="$("$here/about-email.sh")"

python3 -I - "$dir" "$mode" "$mail" <<'PY'
import os
import re
import sys

root, mode, mail = sys.argv[1:4]
ALT = "email address image, open your mail client to write to me"
REWRITE = re.compile(r"data-cfemail|cdn-cgi/l/email-protection|email-decode|__cf_email__|\[email(?:&#160;|&nbsp;|\s)protected\]", re.I)
findings = []

for base, _, files in os.walk(root):
    for name in files:
        if not name.endswith(".html"):
            continue
        path = os.path.join(base, name)
        rel = os.path.relpath(path, root)
        if REWRITE.search(open(path, encoding="utf-8", errors="replace").read()):
            findings.append(("about-email-rewritten", rel))

about = os.path.join(root, "contact", "index.html")
if mail and os.path.exists(about):
    s = open(about, encoding="utf-8").read()
    rel = "contact/index.html"
    m = re.escape(mail)
    # Every occurrence of the address (text or href) must sit inside one email_off region.
    regions = [(a.end(), b.start()) for a, b in zip(re.finditer(r"<!--email_off-->", s), re.finditer(r"<!--/email_off-->", s))]
    for hit in re.finditer(m, s, re.I):
        if not any(lo <= hit.start() < hi for lo, hi in regions):
            findings.append(("about-email-unprotected", rel))
            break
    if not regions:
        findings.append(("about-email-unprotected", rel))
    link = re.search(r"<a\b[^>]*href=[\"']?mailto:" + m + r"[\"']?[^>]*>(.*?)</a>", s, re.I | re.S)
    if mode == "text":
        if not (link and link.group(1).strip().lower() == mail.lower()):
            findings.append(("about-email-missing", rel))
    else:
        img = re.search(r"<img\b[^>]*>", link.group(1), re.I) if link else None
        text_outside_link = re.sub(r"<a\b[^>]*href=[\"']?mailto:[^>]*>.*?</a>", "", s, flags=re.I | re.S)
        if not img or re.search(m, re.sub(r"<[^>]*>", " ", text_outside_link), re.I):
            findings.append(("about-email-missing", rel))
        else:
            alt = re.search(r"alt=(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))", img.group(0), re.I)
            altv = next((g for g in (alt.groups() if alt else ()) if g is not None), None)
            if altv is None or mail.lower() in altv.lower() or "@" in altv or altv != ALT:
                findings.append(("about-email-image-alt", rel))
            elif re.search(m, re.sub(r"<[^>]*>", " ", link.group(1)), re.I):
                findings.append(("about-email-missing", rel))

for rule, rel in dict.fromkeys(findings):
    print("[%s] %s" % (rule, rel))
sys.exit(1 if findings else 0)
PY
