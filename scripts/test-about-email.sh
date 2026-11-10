#!/usr/bin/env bash
# Test that the Contact page's business email is readable without JavaScript
# (issue 329). Cloudflare Email Address Obfuscation rewrites an address in the
# served HTML into "[email protected]" plus a decoder script, unless the address
# sits between <!--email_off--> and <!--/email_off--> (Cloudflare docs, Email
# Address Obfuscation, "Prevent Cloudflare from obfuscating email"). This test
# builds the production site and the image variant, runs
# scripts/check-about-email.sh on each, and requires the checker to fail on
# every mutant that loses the markers, carries the host rewrite, or leaks the
# address into the image variant's alt text. Needs the pinned Hugo; a missing
# Hugo is a failure. Scratch lives under the repository's gitignored tmp/.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-about-email.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/about-email.XXXXXX")"
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
expect_pass() { # <label> <checker args...>
    local label="$1"
    shift
    if "$checker" "$@" >"$work/out.log" 2>&1; then pass "$label"; else fail "$label: $(tr '\n' ' ' <"$work/out.log")"; fi
}
expect_fail() { # <label> <rule> <checker args...>
    local label="$1" rule="$2"
    shift 2
    if "$checker" "$@" >"$work/out.log" 2>&1; then
        fail "$label passed but must fail"
    elif grep -q "\[$rule\]" "$work/out.log"; then
        pass "$label fails with $rule"
    else
        fail "$label failed with the wrong rule: $(tr '\n' ' ' <"$work/out.log")"
    fi
}

[[ -x "$checker" ]] || {
    fail "scripts/check-about-email.sh is missing or not executable"
    echo "$failures failure(s)"
    exit 1
}

# 1. The production build (text mode, the default).
if ! hugo --minify --gc --source "$root" --destination "$work/public" --quiet >"$work/hugo.log" 2>&1; then
    fail "production build: $(tail -n 5 "$work/hugo.log" | tr '\n' ' ')"
    echo "$failures failure(s)"
    exit 1
fi
expect_pass "production Contact page shows the address with no host rewrite" "$work/public"

mutant() { # <name>: a copy of the production site, Contact page edited by $2 (a python expression on s)
    local d="$work/m-$1"
    cp -r "$work/public" "$d"
    if ! python3 -I - "$d/contact/index.html" "$2" <<'PY'
import re, sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
before = s
s = eval(expr)
assert s != before, "mutation changed nothing"
open(p, "w", encoding="utf-8").write(s)
PY
    then
        return 1
    fi
    printf '%s' "$d"
}
EXPECT_MAIL="$("$root/scripts/about-email.sh")"
[[ -n "$EXPECT_MAIL" ]] || {
    fail "about-email.sh printed no address (contact config incomplete)"
    exit 1
}

d="$(mutant no-markers 's.replace("<!--email_off-->", "").replace("<!--/email_off-->", "")')"
expect_fail "Contact page without the email_off markers" about-email-unprotected "$d"
d="$(mutant cfemail 're.sub(r"<a href=\"?mailto:[^>]*>[^<]*</a>", "<a href=\"/cdn-cgi/l/email-protection#00\" class=\"__cf_email__\" data-cfemail=\"00\">[email&#160;protected]</a>", s)')"
expect_fail "Contact page with the host rewrite (data-cfemail)" about-email-rewritten "$d"
d="$(mutant decoder 's.replace("</body>", "<script src=\"/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js\"></script></body>")')"
expect_fail "Contact page with the host decoder script" about-email-rewritten "$d"
d="$(mutant placeholder 's.replace("'"$EXPECT_MAIL"'", "[email protected]")')"
expect_fail "Contact page that shows the placeholder instead of the address" about-email-rewritten "$d"
d="$(mutant no-text 's.replace(">'"$EXPECT_MAIL"'</a>", ">write to me</a>")')"
expect_fail "Contact page whose link text is not the address" about-email-missing "$d"

# 2. A rewrite on any other page is also a failure.
cp -r "$work/public" "$work/other"
printf '%s\n' '<a class="__cf_email__" data-cfemail="00">[email&#160;protected]</a>' >>"$work/other/index.html"
expect_fail "A rewritten address on the home page" about-email-rewritten "$work/other"

# 3. The image variant (off by default, switched on per build).
if ! HUGO_PARAMS_EMAILASIMAGE=true hugo --minify --gc --source "$root" --destination "$work/public-image" --quiet >"$work/hugo-image.log" 2>&1; then
    fail "image variant build: $(tail -n 5 "$work/hugo-image.log" | tr '\n' ' ')"
    echo "$failures failure(s)"
    exit 1
fi
expect_pass "image variant: alt names no address, no text address" --mode image "$work/public-image"
expect_fail "the text build checked as an image build" about-email-missing --mode image "$work/public"
expect_fail "the image build checked as a text build" about-email-missing "$work/public-image"
cp -r "$work/public-image" "$work/image-alt"
python3 -I - "$work/image-alt/contact/index.html" "$EXPECT_MAIL" <<'PY'
import re, sys
p, mail = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s2 = re.sub(r'alt="[^"]*"', 'alt="' + mail + '"', s, count=0)
assert s2 != s
open(p, "w", encoding="utf-8").write(s2)
PY
expect_fail "image variant whose alt text is the address" about-email-image-alt --mode image "$work/image-alt"

# 4. Both builds still pass the repository's output checks (CSP, scripts, email-shaped text).
for v in public public-image; do
    if EXPECT_ENV=production "$root/scripts/check-output.sh" "$work/$v" >"$work/co-$v.log" 2>&1; then
        pass "check-output passes on $v"
    else
        fail "check-output on $v: $(tr '\n' ' ' <"$work/co-$v.log" | cut -c1-300)"
    fi
done

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all about-email checks passed"
