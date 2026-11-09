#!/usr/bin/env bash
# Test the social identity metadata (issue 329): the Mastodon author attribution
# meta tag (fediverse:creator) on posts and journal entries only, rel="me"
# profile links for Mastodon, Bluesky and Threads from data/socials.yaml, no
# twitter:site, and no new script. Builds the real site and a copy with a
# malformed fediverse_creator under the repository's gitignored tmp/.
# Needs the pinned Hugo; a missing Hugo is a failure.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/social-identity.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT
command -v hugo >/dev/null 2>&1 || {
    echo "FAIL: hugo is not on PATH (see .hugo-version)"
    exit 1
}

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

CREATOR='@chiefgyk3d@social.chiefgyk3d.com'
hugo --minify --source "$root" --destination "$work/public" --quiet >"$work/hugo.log" 2>&1 || {
    echo "FAIL: build: $(tail -n 5 "$work/hugo.log")"
    exit 1
}
pub="$work/public"

# creators <file>: the content of every fediverse:creator meta tag, one per line.
creators() {
    python3 -I - "$1" <<'PY'
import sys
from html.parser import HTMLParser
class P(HTMLParser):
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta" and a.get("name") == "fediverse:creator":
            print(a.get("content"))
P().feed(open(sys.argv[1], encoding="utf-8").read())
PY
}

post="$(find "$pub/posts" -mindepth 2 -name index.html | head -n 1)"
entry="$pub/journal/sample-entry/index.html"
for f in "$post" "$entry"; do
    got="$(creators "$f")"
    if [[ "$got" == "$CREATOR" ]]; then pass "exactly one fediverse:creator ($CREATOR) on ${f#"$pub"/}"; else fail "fediverse:creator on ${f#"$pub"/} is '$got', want '$CREATOR'"; fi
done
for f in index.html about/index.html social/index.html posts/index.html journal/index.html; do
    if [[ -z "$(creators "$pub/$f")" ]]; then pass "no fediverse:creator on $f (not an article)"; else fail "fediverse:creator on $f"; fi
done

# Head rel="me" links: Mastodon, Bluesky and Threads (data/socials.yaml rel_me).
for u in https://social.chiefgyk3d.com/@chiefgyk3d https://bsky.app/profile/chiefgyk3d.com https://www.threads.com/@chiefgyk3d; do
    if grep -qE "<link rel=\"?me\"? href=\"?$u\"?>" "$pub/index.html"; then pass "head rel=me $u"; else fail "head rel=me $u missing"; fi
    if grep -qE "<a [^>]*href=\"?$u\"?[^>]*rel=\"?me\"?|<a [^>]*rel=\"?me\"?[^>]*href=\"?$u\"?" "$pub/index.html"; then pass "footer link keeps rel=me $u"; else fail "footer link rel=me $u missing"; fi
done

# X is not wanted: no twitter:site (or twitter:creator) anywhere.
if grep -rlE 'name="?twitter:(site|creator)' "$pub" >/dev/null; then fail "twitter:site or twitter:creator is present"; else pass "no twitter:site or twitter:creator"; fi

# No new script: compare the multiset of script tags with the build of origin/main's set
# (the pinned scripts and JSON-LD data); this change adds none.
unexpected="$(grep -rhoE --include='*.html' '<script[^>]*>' "$pub" | sort -u | grep -vE '^<script src="?/(copy|search|share)\.js"?>$' | grep -vE '^<script type="?application/ld\+json"?>$' || true)"
if [[ -z "$unexpected" ]]; then pass "no script element beyond the pinned scripts and JSON-LD data"; else fail "unexpected script elements: $unexpected"; fi

# A malformed creator fails the build (never a silent wrong tag).
cp -r "$root" "$work/bad" 2>/dev/null || true
rm -rf "$work/bad/tmp" "$work/bad/public" "$work/bad/.git"
sed -i 's|^\(  *\)fediverse_creator: .*|\1fediverse_creator: "not-a-handle"|' "$work/bad/data/socials.yaml"
if hugo --source "$work/bad" --destination "$work/bad-public" --quiet >"$work/bad.log" 2>&1; then fail "a malformed fediverse_creator built"; else pass "a malformed fediverse_creator fails the build"; fi

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all social identity checks passed"
