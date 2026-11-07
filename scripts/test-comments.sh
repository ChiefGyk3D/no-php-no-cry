#!/usr/bin/env bash
# Test the archived comments from the old site (issue 121) against built output.
#
# Each post that has a data/comments/<slug>.json file shows "Comments from the
# old site" under the post: the quoted text, the display name only, and the
# original date. Builds into the repository's gitignored tmp/ (never /tmp).
# The migrated posts are drafts, so the build uses --buildDrafts; a normal build
# must show none of it. Asserts with Python's stdlib HTML parser, checks the
# data files carry only author, date and content, that no raw HTML or commenter
# metadata (email, IP, URL) reaches the page, that the published output holds no
# comment data file, and that scripts/check-output.sh stays green on the drafts
# build. A guard self-test feeds the asserter pages that break each rule.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/comments.XXXXXX")"
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

# slug|expected display names in order. The names are the reviewed set: a change
# to a data file must be a reviewed change here too.
EXPECTED=(
    "best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100|Spencer"
    "must-have-tools-for-3d-printing-and-pc-repair-my-recommended-starter-kit|Rod MacPherson"
    "why-i-use-multiple-phones-a-personal-dive-into-device-diversification|RYAN,Nagaram"
)

asserter="$work/assert_comments.py"
cat >"$asserter" <<'PY'
import re
import sys
from html.parser import HTMLParser

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]")


class P(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.sections = []   # attrs of each section.comments-archive
        self.headings = []   # (tag, id, text) in order, whole page
        self.figs = []       # per comment: dict(name, time, datetime, quote)
        self.cur = None
        self.tags = []
        self._h = None
        self.in_section = False
        self.depth_section = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.stack.append(tag)
        self.tags.append((tag, a, self.in_section))
        if tag == "section" and "comments-archive" in (a.get("class") or "").split():
            self.sections.append(a)
            self.in_section = True
            self.depth_section = len(self.stack)
        if re.fullmatch(r"h[1-6]", tag):
            self._h = [tag, a.get("id"), ""]
        if self.in_section and tag == "figure":
            self.cur = {"name": "", "time": "", "datetime": None, "quote": "", "cite": a.get("cite")}
        if self.cur is not None and tag == "time":
            self.cur["datetime"] = a.get("datetime")
        if self.cur is not None and tag == "blockquote":
            self.cur["cite"] = a.get("cite")

    def handle_endtag(self, tag):
        if self._h and self._h[0] == tag:
            self.headings.append(tuple(self._h))
            self._h = None
        if tag == "figure" and self.cur is not None:
            self.figs.append(self.cur)
            self.cur = None
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()
        if tag == "section" and self.in_section and len(self.stack) < self.depth_section:
            self.in_section = False

    def handle_data(self, d):
        if self._h:
            self._h[2] += d
        if self.cur is not None:
            if "figcaption" in self.stack and "time" in self.stack:
                self.cur["time"] += d
            elif "figcaption" in self.stack and "span" in self.stack:
                self.cur["name"] += d
            elif "blockquote" in self.stack:
                self.cur["quote"] += d


def main(mode, path, names):
    p = P()
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    p.feed(raw)
    errs = []
    if mode == "absent":
        if p.sections or "Comments from the old site" in raw:
            errs.append("comments shown on a page that must not show them")
        return errs
    if len(p.sections) != 1:
        return ["expected exactly one comments section, found %d" % len(p.sections)]
    if p.sections[0].get("aria-labelledby") is None:
        errs.append("section has no aria-labelledby")
    h = [x for x in p.headings if x[1] == p.sections[0].get("aria-labelledby")]
    if len(h) != 1 or h[0][0] != "h2" or h[0][2].strip() != "Comments from the old site":
        errs.append("heading is not an h2 'Comments from the old site' with the labelled id")
    if sum(1 for t, _, _ in p.tags if t == "h1") != 1:
        errs.append("page does not have exactly one h1")
    got = [f["name"].strip() for f in p.figs]
    if got != names:
        errs.append("display names %r != expected %r" % (got, names))
    for f in p.figs:
        if not f["quote"].strip():
            errs.append("empty quote")
        if not re.fullmatch(r"\d{4}-\d\d-\d\d", f["datetime"] or ""):
            errs.append("comment time has no YYYY-MM-DD datetime")
        if not re.fullmatch(r"[A-Z][a-z]+ \d{1,2}, \d{4}", f["time"].strip()):
            errs.append("comment date not shown as 'Month D, YYYY'")
    for t, a, inside in p.tags:
        if inside and t not in ("section", "h2", "p", "figure", "blockquote", "figcaption", "span", "time"):
            errs.append("unexpected <%s> inside the comments section" % t)
        if inside and set(a) - {"class", "id", "aria-labelledby", "datetime"}:
            errs.append("unexpected attributes on <%s>: %s" % (t, sorted(a)))
    sec = re.search(r"<section class=\"?comments-archive.*?</section>", raw, re.S)
    text = sec.group(0) if sec else ""
    if EMAIL.search(text) or "mailto:" in text.lower():
        errs.append("email-shaped text in comments")
    if re.search(r"https?://|\b\d{1,3}(\.\d{1,3}){3}\b", text):
        errs.append("URL or IP in comments")
    return errs


if __name__ == "__main__":
    mode, path = sys.argv[1], sys.argv[2]
    names = sys.argv[3].split(",") if len(sys.argv) > 3 else []
    errs = main(mode, path, names)
    for e in errs:
        print(e)
    sys.exit(1 if errs else 0)
PY

# 1. The data files carry only author, date and content, with the reviewed names.
data_check=$(
    python3 -I - "$root" "${EXPECTED[@]}" <<'PY'
import json
import sys
root = sys.argv[1]
exp = {}
for e in sys.argv[2:]:
    slug, names = e.split("|")
    exp[slug] = names.split(",")
import glob
import os
found = {os.path.basename(p)[:-5] for p in glob.glob(root + "/data/comments/*.json")}
if found != set(exp):
    print("data/comments files %s != expected %s" % (sorted(found), sorted(exp)))
for slug, names in exp.items():
    path = "%s/data/comments/%s.json" % (root, slug)
    try:
        data = json.load(open(path, encoding="utf-8"))
    except OSError:
        print("missing " + path)
        continue
    if [c.get("author") for c in data] != names:
        print("%s: authors differ" % slug)
    for c in data:
        if set(c) != {"author", "date", "content"}:
            print("%s: keys %s, want author, date, content only" % (slug, sorted(c)))
PY
)
if [[ -z "$data_check" ]]; then
    pass "data/comments files hold only author, date and content, with the reviewed names"
else
    fail "data/comments: $data_check"
fi

# 2. A drafts build shows the comments; a normal build shows none of it.
hugo --minify --buildDrafts --destination "$work/drafts" >"$work/drafts.log" 2>&1 || {
    cat "$work/drafts.log"
    fail "hugo --buildDrafts failed"
}
hugo --minify --destination "$work/normal" >"$work/normal.log" 2>&1 || {
    cat "$work/normal.log"
    fail "hugo build failed"
}
for e in "${EXPECTED[@]}"; do
    slug="${e%%|*}"
    names="${e#*|}"
    page="$work/drafts/posts/$slug/index.html"
    if [[ ! -f "$page" ]]; then
        fail "$slug: not built with --buildDrafts"
        continue
    fi
    if out="$(python3 -I "$asserter" present "$page" "$names")"; then
        pass "$slug: comments by $names rendered"
    else
        fail "$slug: $out"
    fi
    if [[ -f "$work/normal/posts/$slug/index.html" ]]; then
        fail "$slug: a draft was built without --buildDrafts"
    else
        pass "$slug: not built (draft) without --buildDrafts"
    fi
done
# Posts without comments show no section.
none=0
for page in "$work"/drafts/posts/*/index.html; do
    slug="$(basename "$(dirname "$page")")"
    case "$slug" in
        best-headphone-* | must-have-tools-* | why-i-use-multiple-*) continue ;;
    esac
    none=$((none + 1))
    python3 -I "$asserter" absent "$page" >/dev/null || fail "$slug: shows a comments section it has no data for"
done
[[ $none -gt 0 ]] && pass "$none other posts show no comments section" || fail "no other posts were checked"

# 3. No comment data is published, and the checker stays green on the drafts build.
if find "$work/drafts/posts" -name '*.json' | grep -q .; then
    fail "a comment data file was published"
else
    pass "no comment data file is published"
fi
if find "$work/drafts" -type f -name '*.html' -print0 | xargs -0 grep -lE '\[email protected\]' >/dev/null 2>&1; then
    fail "an obfuscated email placeholder is in the output"
fi
if EXPECT_ENV=production "$root/scripts/check-output.sh" "$work/drafts" >"$work/co.log" 2>&1; then
    pass "check-output.sh is green on the drafts build"
else
    cat "$work/co.log"
    fail "check-output.sh failed on the drafts build"
fi

# 4. Guard self-test: the asserter bites.
good="$work/drafts/posts/why-i-use-multiple-phones-a-personal-dive-into-device-diversification/index.html"
if [[ -f "$good" ]]; then
    bad() { # bad <name> <sed expr> <names>
        sed -E "$2" "$good" >"$work/bad-$1.html"
        if python3 -I "$asserter" present "$work/bad-$1.html" "$3" >/dev/null 2>&1; then
            fail "guard: $1 passed"
        else
            pass "guard: $1 fails"
        fi
    }
    names="RYAN,Nagaram"
    bad wrong-name 's#Nagaram#Someone#' "$names"
    bad email 's#</figcaption>#<span>a.b@example.org</span></figcaption>#' "$names"
    bad mailto 's#<blockquote>#<blockquote><a href="mailto:a@example.org">x</a>#' "$names"
    bad url 's#</figcaption>#<span>https://example.org/x</span></figcaption>#' "$names"
    bad heading-level 's#<h2 id=([a-z-]+)>Comments#<h4 id=\1>Comments#' "$names"
    bad raw-html 's#<blockquote>#<blockquote><img src=x>#' "$names"
    bad no-section 's#comments-archive#other#' "$names"
    if python3 -I "$asserter" absent "$good" >/dev/null 2>&1; then
        fail "guard: the absent check passed a page with comments"
    else
        pass "guard: the absent check fails a page with comments"
    fi
else
    fail "guard: no built page to mutate"
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all comment tests passed"
