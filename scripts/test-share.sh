#!/usr/bin/env bash
# Test the share links on posts and journal entries (issue 220).
#
# Builds a scratch site (symlinks to the real layouts, assets, data and static,
# a few synthetic entries) into the repository's gitignored tmp/, never /tmp,
# then asserts with Python's stdlib HTML parser:
#   - every kind intent / mailto entry of data/share.yaml with a template is
#     one anchor whose href is EXACTLY that template filled from the page's own
#     permalink and title (all values percent-encoded, spaces as %20), with
#     rel="noopener noreferrer", target=_blank, an accessible name that holds
#     the visible label, https or mailto only, and no tracking parameter. The
#     test reads the URL templates from the data file: it checks their shape
#     against the page, not that a remote site answers;
#   - a template that uses {image} is left out of an entry with no image, and
#     an entry with an empty template is not rendered;
#   - the mastodon and copy entries are hidden buttons carrying the permalink
#     (or the post text) as data, and the page's one script is /share.js;
#   - the syndicated front matter renders no "Discuss on" link, and a draft
#     builds with the block;
#   - the block is on posts and journal entries and no other page loads
#     /share.js; no external script is emitted anywhere; the CSP line in
#     static/_headers is unchanged in the one way that matters (script-src has
#     no new source);
#   - icon classes have a CSS rule and a committed SVG.
# A guard self-test feeds the asserter broken pages (wrong title in a URL, no
# rel, an external script, an unencoded space) and requires each to fail, so a
# green run cannot come from an asserter that checks nothing. Needs the pinned
# Hugo; a missing Hugo is a failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/share.XXXXXX")"
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

asserter="$work/assert_share.py"
cat >"$asserter" <<'PY'
import pathlib
import re
import sys
from html.parser import HTMLParser
from urllib.parse import quote

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


class Node:
    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.kids, self.parts = [], []

    def walk(self):
        yield self
        for k in self.kids:
            yield from k.walk()

    def text(self):
        return " ".join("".join(p if isinstance(p, str) else p.text() for p in self.parts).split())


class Dom(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", [], None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs, self.cur)
        self.cur.kids.append(n)
        self.cur.parts.append(n)
        if tag not in VOID:
            self.cur = n

    def handle_endtag(self, tag):
        n = self.cur
        while n is not None and n.tag != tag:
            n = n.parent
        if n is not None and n.parent is not None:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.parts.append(data)


def load(path):
    d = Dom()
    d.feed(pathlib.Path(path).read_text(encoding="utf-8"))
    return d.root


def entries(root):
    """data/share.yaml read without a YAML library: '- id:' starts an entry, then simple key: value lines."""
    out, cur = [], None
    for line in pathlib.Path(root, "data/share.yaml").read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("- "):
            cur = {}
            out.append(cur)
            line = line[2:]
        k, _, v = line.strip().partition(":")
        v = v.strip()
        if len(v) > 1 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        cur[k.strip()] = v
    return out


def enc(s):
    return quote(s, safe="-_.~")


def expected(entry, title, url, image):
    t = entry["template"]
    text = (title[:200] if len(title) <= 200 else title[:199] + "…") + " " + url
    for k, v in (("{title}", title), ("{url}", url), ("{text}", text), ("{image}", image)):
        t = t.replace(k, enc(v))
    return t


def check_page(root, path, title, url, image, bad):
    doc = load(path)
    ents = entries(root)
    groups = [n for n in doc.walk() if "share" in (n.attrs.get("class") or "").split()]
    if len(groups) != 1:
        bad.append("%s: %d share blocks, wanted 1" % (path, len(groups)))
        return
    g = groups[0]
    if g.attrs.get("aria-label") != "Share this post":
        bad.append("share block has no accessible name")
    anchors = [n for n in g.walk() if n.tag == "a"]
    buttons = [n for n in g.walk() if n.tag == "button"]
    scripts = [n for n in g.walk() if n.tag == "script"]
    if len(scripts) != 1 or scripts[0].attrs != {"src": "/share.js"}:
        bad.append("the block must carry exactly <script src=/share.js>, got %r" % [s.attrs for s in scripts])
    seen = set()
    for e in ents:
        if e["kind"] in ("intent", "mailto"):
            if not e["template"] or ("{image}" in e["template"] and not image):
                if any("icon-" + e["id"] in (a.attrs.get("class") or "").split() for a in anchors):
                    bad.append("%s rendered but must be left out" % e["id"])
                continue
            hits = [a for a in anchors if "icon-" + e["id"] in (a.attrs.get("class") or "").split()]
            if len(hits) != 1:
                bad.append("%s: %d anchors, wanted 1" % (e["id"], len(hits)))
                continue
            a = hits[0]
            seen.add(id(a))
            want = expected(e, title, url, image)
            if a.attrs.get("href") != want:
                bad.append("%s: href %r, wanted %r" % (e["id"], a.attrs.get("href"), want))
            if not a.attrs.get("href", "").startswith(("https://", "mailto:")):
                bad.append("%s: not https or mailto" % e["id"])
            if " " in a.attrs.get("href", "") or "utm_" in a.attrs.get("href", ""):
                bad.append("%s: space or tracking parameter in href" % e["id"])
            if set((a.attrs.get("rel") or "").split()) != {"noopener", "noreferrer"}:
                bad.append("%s: rel must be noopener noreferrer, got %r" % (e["id"], a.attrs.get("rel")))
            if a.attrs.get("target") != "_blank":
                bad.append("%s: target must be _blank" % e["id"])
            if e["label"] not in (a.attrs.get("aria-label") or "") or a.text() != e["label"]:
                bad.append("%s: accessible name must hold the visible label %r" % (e["id"], e["label"]))
        elif e["kind"] in ("copy", "mastodon"):
            hits = [b for b in buttons if b.text() == e["label"]]
            if len(hits) != 1:
                bad.append("%s: %d buttons, wanted 1" % (e["id"], len(hits)))
                continue
            b = hits[0]
            seen.add(id(b))
            if b.attrs.get("type") != "button" or "hidden" not in b.attrs:
                bad.append("%s: must be a hidden type=button until the script runs" % e["id"])
            if e["label"] not in (b.attrs.get("aria-label") or ""):
                bad.append("%s: accessible name must hold the visible label" % e["id"])
            if e["kind"] == "copy" and b.attrs.get("data-url") != url:
                bad.append("%s: data-url must be the permalink" % e["id"])
            if e["kind"] == "mastodon":
                if b.attrs.get("data-text") != title + " " + url:
                    bad.append("mastodon: data-text must be title, a space, the permalink")
    extra = [n for n in anchors + buttons if id(n) not in seen and n.attrs.get("data-share") != "server"]
    if extra:
        bad.append("share block holds %d element(s) the data file does not list" % len(extra))
    for n in doc.walk():
        if n.tag == "script" and n.attrs.get("src", "").startswith(("http:", "https:", "//")):
            bad.append("external script %r" % n.attrs["src"])


def main():
    root, kind = sys.argv[1], sys.argv[2]
    bad = []
    if kind == "page":
        path, title, url, image = sys.argv[3:7]
        check_page(root, path, title, url, image, bad)
    elif kind == "noshare":
        doc = load(sys.argv[3])
        for n in doc.walk():
            if n.tag == "script" and n.attrs.get("src", "").lstrip("/") == "share.js":
                bad.append("%s loads /share.js" % sys.argv[3])
            if "share" in (n.attrs.get("class") or "").split():
                bad.append("%s has a share block" % sys.argv[3])
    elif kind == "css":
        css = pathlib.Path(sys.argv[3]).read_text()
        for e in entries(root):
            if e["id"] == "lemmy":  # no clearly licensed glyph yet: a text-only button (brand/approved-assets.txt)
                continue
            m = re.search(r"\.icon-%s\s*\{[^}]*url\(\"?([^\")]+)\"?\)" % re.escape(e["id"]), css)
            if not m:
                bad.append("no icon rule for icon-%s" % e["id"])
                continue
            rel = m.group(1)
            f = pathlib.Path(root, "static", rel.replace("../", "", 1)) if rel.startswith("../") else None
            if f is None or not f.is_file():
                bad.append("icon-%s: %s is not a committed file" % (e["id"], rel))
    for b in bad:
        print(b)
    sys.exit(1 if bad else 0)


main()
PY

# The scratch site.
site="$work/site"
mkdir -p "$site/content/posts/with-image" "$site/content/posts/no-image" "$site/content/posts/a-draft" "$site/content/journal/entry" "$site/content/search" "$site/content/social" "$site/content/support" "$site/content/about" "$site/content/products" "$site/content/privacy" "$site/content/resume"
for d in layouts assets data static archetypes; do ln -s "$root/$d" "$site/$d"; done
ln -s "$root/hugo.toml" "$site/hugo.toml"
for f in content/_index.md content/posts/_index.md content/search/_index.md content/social/_index.md content/support/index.md content/about/index.md content/products/_index.md content/privacy/index.md content/resume/index.md content/journal/_index.md; do
    mkdir -p "$(dirname "$site/$f")"
    cp "$root/$f" "$site/$f"
done
tricky='Fish & Chips: 100% "quoted" + more?'
printf -- '---\ntitle: '"'"'%s'"'"'\ndate: 2026-10-01T09:00:00-05:00\ndraft: false\ndescription: "A summary."\nimage: https://img.example.org/pic one.jpg\nsyndicated:\n  mastodon: "https://social.example/@x/1"\n---\n\nBody.\n' "${tricky//\'/\'\'}" >"$site/content/posts/with-image/index.md"
printf -- '---\ntitle: "Plain post"\ndate: 2026-10-02T09:00:00-05:00\ndraft: false\ndescription: "A summary."\n---\n\nBody.\n' >"$site/content/posts/no-image/index.md"
printf -- '---\ntitle: "A draft post"\ndate: 2026-10-03T09:00:00-05:00\ndraft: true\ndescription: "A summary."\n---\n\nBody.\n' >"$site/content/posts/a-draft/index.md"
printf -- '---\ntitle: "A journal entry"\ndate: 2026-10-04T09:00:00-05:00\ndraft: false\ndescription: "A summary."\n---\n\nBody.\n' >"$site/content/journal/entry/index.md"

public="$site/public"
if (cd "$site" && HUGO_MINIFY_MINIFYOUTPUT=false hugo --buildDrafts --destination "$public" --quiet >"$work/build.log" 2>&1); then
    pass "scratch site builds (with drafts)"
else
    fail "scratch site did not build: $(tail -n 5 "$work/build.log" | tr '\n' ' ')"
fi

base="$(sed -n 's/^baseURL *= *"\(.*\)"/\1/p' "$root/hugo.toml")"
a() { python3 -I "$asserter" "$root" "$@"; }

if [[ -f "$public/posts/with-image/index.html" ]]; then
    if a page "$public/posts/with-image/index.html" "$tricky" "${base}posts/with-image/" "https://img.example.org/pic one.jpg"; then
        pass "post with an image: every share URL is built from its permalink, title and image"
    else
        fail "post with an image: $(a page "$public/posts/with-image/index.html" "$tricky" "${base}posts/with-image/" "https://img.example.org/pic one.jpg" 2>&1 | head -n 5 | tr '\n' ';')"
    fi
    if grep -q "Discuss on" "$public/posts/with-image/index.html"; then
        fail "the syndicated map still renders a Discuss link"
    else
        pass "the syndicated map renders no Discuss link"
    fi
    if grep -q 'rel="canonical"' "$public/posts/with-image/index.html" && grep -q "Permalink:" "$public/posts/with-image/index.html"; then
        pass "the canonical link and the permalink line are kept"
    else
        fail "the canonical link or the permalink line is gone"
    fi
fi
if a page "$public/posts/no-image/index.html" "Plain post" "${base}posts/no-image/" ""; then
    pass "post with no image: share URLs match, Pinterest is left out"
else
    fail "post with no image: $(a page "$public/posts/no-image/index.html" "Plain post" "${base}posts/no-image/" "" 2>&1 | head -n 5 | tr '\n' ';')"
fi
if grep -q "pinterest" "$public/posts/no-image/index.html"; then
    fail "Pinterest rendered for a post with no image"
else
    pass "no Pinterest button without an image"
fi
if a page "$public/posts/a-draft/index.html" "A draft post" "${base}posts/a-draft/" ""; then
    pass "a draft builds with the block"
else
    fail "draft page: share block wrong"
fi
if a page "$public/journal/entry/index.html" "A journal entry" "${base}journal/entry/" ""; then
    pass "a journal entry has the block"
else
    fail "journal entry: share block wrong"
fi
while IFS= read -r -d '' f; do
    case "${f#"$public"/}" in
        posts/with-image/index.html | posts/no-image/index.html | posts/a-draft/index.html | journal/entry/index.html) continue ;;
    esac
    if ! a noshare "$f" >/dev/null 2>&1; then
        fail "${f#"$public"/} carries the share block or loads /share.js"
    fi
done < <(find "$public" -name '*.html' -print0)
pass "no other page has the share block or loads /share.js"

css="$(find "$public/css" -name 'site*.css' | head -n 1)"
if [[ -n "$css" ]] && a css "$css"; then
    pass "every icon class has a CSS rule and a committed SVG"
else
    fail "icon rules: $(a css "${css:-/nonexistent}" 2>&1 | head -n 5 | tr '\n' ';')"
fi

# Targets are at least --tap (44 px) square, the browser gate's rule (scripts/browser-gate.py).
share_css="$root/assets/css/pages/share.css"
tap_ok() { grep -qE 'min-height: var\(--tap\);' "$1" && grep -qE 'min-width: var\(--tap\);' "$1"; }
if tap_ok "$share_css"; then
    pass "share controls are at least --tap square"
else
    fail "share.css does not give every control min-height and min-width var(--tap)"
fi
sed -E 's/var\(--tap\)/2rem/' "$share_css" >"$work/share-small.css"
if tap_ok "$work/share-small.css"; then
    fail "guard: the tap-size check accepted a 2rem target"
else
    pass "guard: the tap-size check fails on a 2rem target"
fi

# The CSP is unchanged: script-src names 'self' and the Cloudflare beacon, nothing else.
if grep -q "script-src 'self' https://static.cloudflareinsights.com/beacon.min.js;" "$root/static/_headers"; then
    pass "CSP script-src is unchanged"
else
    fail "static/_headers script-src changed"
fi

# Guard self-tests: the asserter must reject broken pages.
good="$public/posts/no-image/index.html"
if [[ -f "$good" ]]; then
    guard() { # guard <name> <sed expression>
        local out="$work/guard-$1.html"
        sed -E "$2" "$good" >"$out"
        if cmp -s "$good" "$out"; then
            fail "guard $1 did not change the page (the test is stale)"
        elif a page "$out" "Plain post" "${base}posts/no-image/" "" >/dev/null 2>&1; then
            fail "guard $1: the asserter accepted a broken page"
        else
            pass "guard $1 fails as it should"
        fi
    }
    guard wrong-title 's#(bsky\.app/intent/compose\?text=)Plain#\1Other#'
    guard no-rel 's# rel="noopener noreferrer"##'
    guard external-script 's#<script src="?/share\.js"?></script>#<script src=https://evil.example/x.js></script>#'
    guard raw-space 's#(intent/tweet\?text=)Plain%20post#\1Plain post#'
    guard no-hidden 's#(data-share=copy[^>]*) hidden#\1#; s#(data-share="copy"[^>]*) hidden#\1#'
    guard tracking 's#(facebook\.com/sharer/sharer\.php\?u=[^"]*)#\1\&utm_source=x#'
else
    fail "no page to run the guard self-tests on"
fi

# /share.js behavior (Node, a fake page): the Mastodon server is validated at the
# sink. A stored value is used only if it is a plain lowercase ASCII hostname;
# anything else (userinfo, path, query, fragment, whitespace, uppercase, a port,
# a lookalike or non-ASCII name, an IP address) is deleted and the prompt asks
# again, and the opened URL is built only from a valid hostname.
harness="$work/share-harness.js"
cat >"$harness" <<'JS'
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(process.argv[2], "utf8");
const bad = [];
function run(stored, answers) {
  const store = new Map(), opened = [], prompts = [];
  if (stored !== null) store.set("mastodonServer", stored);
  const btn = { getAttribute: (n) => ({ "data-share": "mastodon", "data-text": "Title https://site.example/p/" })[n] };
  const status = { textContent: "" }, change = { hidden: true };
  let click;
  const root = {
    querySelector: (q) => (q === ".share-status" ? status : change),
    querySelectorAll: () => [],
    addEventListener: (t, f) => { if (t === "click") click = f; },
  };
  const ctx = {
    document: { querySelector: () => root },
    localStorage: { getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: (k) => store.delete(k) },
    prompt: (m, d) => { prompts.push(d); return answers.length ? answers.shift() : null; },
    window: { open: (u) => opened.push(u), isSecureContext: true },
    navigator: {},
    encodeURIComponent, URL,
  };
  vm.runInNewContext(src, ctx);
  click({ target: { closest: () => btn } });
  return { opened, prompts, store, status };
}
const text = encodeURIComponent("Title https://site.example/p/");
const valid = ["mastodon.social", "social.example.org", "a-b.example.co", "xn--e1afmkfd.example"];
for (const v of valid) {
  const r = run(v, []);
  if (r.opened.length !== 1 || r.opened[0] !== "https://" + v + "/share?text=" + text || r.prompts.length) bad.push("valid stored " + JSON.stringify(v) + " was not used as is: " + JSON.stringify(r.opened));
}
const hostile = ["good.example@evil.example", "evil.example/path", "evil.example?x=1", "evil.example#f", "evil.example:8443", "user:pw@evil.example",
  " evil.example", "evil.example ", "evil.example\n", "Evil.Example", "https://evil.example", "evil.example.", ".evil.example", "-a.example", "a..example",
  "exаmple.com", "ехample.org", "ｅｖｉｌ.example", "mаstodon.social", "127.0.0.1", "localhost", "1.2.3.4", "evil.example\\@good.example", "evil.example%2f", "", "a.b"];
for (const v of hostile) {
  // The prompt answer is valid: the opened URL must be built from it, never from the stored value.
  const r = run(v, ["good.example"]);
  const want = "https://good.example/share?text=" + text;
  if (v === "") continue;
  if (r.opened.length !== 1 || r.opened[0] !== want) bad.push("hostile stored " + JSON.stringify(v) + " opened " + JSON.stringify(r.opened));
  if (!r.prompts.length) bad.push("hostile stored " + JSON.stringify(v) + " did not re-open the prompt");
  if (r.store.get("mastodonServer") !== "good.example") bad.push("hostile stored " + JSON.stringify(v) + " was not replaced");
  // The prompt is dismissed: nothing opens and the bad value is gone.
  const r2 = run(v, []);
  if (r2.opened.length || r2.store.has("mastodonServer")) bad.push("hostile stored " + JSON.stringify(v) + " survived a dismissed prompt: " + JSON.stringify([r2.opened, [...r2.store]]));
}
// A hostile prompt answer is refused too (port, userinfo, lookalike), and a pasted URL is reduced to its host.
for (const a of ["good.example:8443", "good.example@evil.example", "exаmple.com", "good.example?x=1", "127.0.0.1"]) {
  const r = run(null, [a]);
  if (r.opened.length || r.store.has("mastodonServer")) bad.push("hostile prompt answer " + JSON.stringify(a) + " was accepted: " + JSON.stringify(r.opened));
}
const r3 = run(null, ["  HTTPS://Good.Example/path/x "]);
if (r3.opened[0] !== "https://good.example/share?text=" + text) bad.push("a pasted URL was not reduced to its host: " + JSON.stringify(r3.opened));
bad.forEach((b) => console.log(b));
process.exit(bad.length ? 1 : 0);
JS
if ! command -v node >/dev/null 2>&1; then
    fail "node is not on PATH (needed for the /share.js behavior test)"
elif node "$harness" "$root/static/share.js" >"$work/harness.out" 2>&1; then
    pass "/share.js: stored and typed Mastodon servers are validated at the sink"
else
    fail "/share.js server validation: $(head -n 6 "$work/harness.out" | tr '\n' ';')"
fi
# Guard: the harness must fail on a script that trusts the stored value.
if command -v node >/dev/null 2>&1; then
    sed -E 's#^  function good\(v\) \{.*#  function good(v) { return !!v; }#' "$root/static/share.js" >"$work/share-trusting.js"
    if node "$harness" "$work/share-trusting.js" >/dev/null 2>&1; then
        fail "guard: the harness accepted a script that trusts stored values"
    else
        pass "guard: the harness fails on a script that trusts stored values"
    fi
fi

if ((failures > 0)); then
    echo "test-share: ${failures} failure(s)"
    exit 1
fi
echo "test-share: all passed"
