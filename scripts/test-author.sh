#!/usr/bin/env bash
# Tests for scripts/author.py (issue #253): slug rules, dates, tags, collisions, path and
# symlink safety, a created page that passes scripts/check-content.py, and a mutation proof
# (the same page published with an unfinished description fails the check).
#
# Fixtures are throwaway repository layouts under the repository's gitignored tmp/, never
# /tmp, and never the real content/.
# shellcheck disable=SC2015  # "cond && ok || bad" is the intended report idiom here
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/author.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}

n=0
# repo: a fresh fixture repository; sets $r
repo() {
    n=$((n + 1))
    r="$work/r$n"
    mkdir -p "$r/content/posts" "$r/content/journal" "$r/brand"
    printf '# manifest\n' >"$r/brand/approved-assets.txt"
}
# au <args>: run the helper against $r, capture stdout+stderr in $out and the exit in $rc
au() {
    rc=0
    out="$(timeout 60 python3 -I "$root/scripts/author.py" --root "$r" "$@" 2>&1 </dev/null)" || rc=$?
}
# expect <name> <exit> <grep pattern or -> <args...>
expect() {
    local name="$1" want="$2" pat="$3"
    shift 3
    au "$@"
    if [[ $rc -ne $want ]]; then
        bad "$name (exit $rc, want $want): $out"
    elif [[ "$pat" != "-" ]] && ! grep -qE -- "$pat" <<<"$out"; then
        bad "$name (output lacks /$pat/): $out"
    else
        ok "$name"
    fi
}
tree_empty() { [[ -z "$(find "$r/content/posts" "$r/content/journal" -mindepth 1 -print -quit)" ]]; }

D="A plain sentence that describes the page."

# --- a good post and a good journal entry -----------------------------------------------------
repo
expect "new post" 0 "created content/posts/my-first-post/index.md" new post "My first post" --description "$D" --tag hugo --tag web-editor --date 2026-11-08
f="$r/content/posts/my-first-post/index.md"
grep -q '^draft: true$' "$f" && ok "post is draft true" || bad "post is draft true"
grep -q '^tags: \["hugo", "web-editor"\]$' "$f" && ok "post tags" || bad "post tags"
grep -q '^date: 2026-11-08$' "$f" && ok "post date" || bad "post date"
grep -q '^slug: "my-first-post"$' "$f" && ok "post slug" || bad "post slug"
au check content/posts/my-first-post
[[ $rc -eq 0 ]] && ok "check passes on the new post (bundle path)" || bad "check on new post: $out"
au check content/posts/my-first-post/index.md
[[ $rc -eq 0 ]] && ok "check passes on the new post (file path)" || bad "check on new post file: $out"
# the checker itself agrees, called directly
rc=0
python3 -I "$root/scripts/check-content.py" --root "$r" content/posts/my-first-post/index.md >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] && ok "check-content.py passes on the new post" || bad "check-content.py rc $rc"

expect "new journal" 0 "created content/journal/day-one/index.md" new journal "Day one" --description "$D"
au check content/journal/day-one
[[ $rc -eq 0 ]] && ok "check passes on the new journal entry" || bad "check on journal: $out"
grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}-0[45]:00$' "$r/content/journal/day-one/index.md" && ok "default date is now with the Eastern offset" || bad "default date"
grep -q '^syndicate: true$' "$r/content/journal/day-one/index.md" && ok "syndicate is true" || bad "syndicate"

# --- mutation proof: the same page, published with an unfinished description, must fail ------
repo
au new post "Mutation proof" --description "$D"
f="$r/content/posts/mutation-proof/index.md"
sed -e 's/^draft: true$/draft: false/' -e 's/^description: .*/description: "TODO write a description"/' "$f" >"$f.new" && mv "$f.new" "$f"
au check content/posts/mutation-proof
if [[ $rc -eq 1 ]] && grep -q '^todo: ' <<<"$out"; then ok "mutation: draft false with a placeholder description fails"; else bad "mutation (exit $rc): $out"; fi
sed -e 's/^description: .*/description: ""/' "$f" >"$f.new" && mv "$f.new" "$f"
au check content/posts/mutation-proof
if [[ $rc -eq 1 ]] && grep -q '^description: ' <<<"$out"; then ok "mutation: an empty description fails"; else bad "mutation empty (exit $rc): $out"; fi

# --- description is required ------------------------------------------------------------------
repo
expect "no description is refused" 1 "description is required" new post "No description"
tree_empty && ok "no description: nothing created" || bad "no description left files"
expect "blank description is refused" 1 "description is required" new post "Blank" --description "   "
expect "long description is refused" 1 "at most 160" new post "Long" --description "$(printf 'x%.0s' $(seq 1 161))"
expect "description with a newline is refused" 1 "one line" new post "Newline" --description $'two\nlines'
tree_empty && ok "bad descriptions: nothing created" || bad "bad descriptions left files"

# --- usage errors exit 2 ----------------------------------------------------------------------
repo
expect "no command" 2 -
expect "missing title" 2 - new post
expect "unknown kind" 2 - new page "Title" --description "$D"
expect "unknown option" 2 - new post "Title" --nope
expect "check without a path" 2 - check

# --- slug rules -------------------------------------------------------------------------------
slug_case() { # <name> <title> <expected slug>
    repo
    au new post "$2" --description "$D"
    if [[ $rc -eq 0 && -f "$r/content/posts/$3/index.md" ]]; then
        ok "slug: $1"
        au check "content/posts/$3"
        [[ $rc -eq 0 ]] || bad "slug $1: check-content failed: $out"
    else
        bad "slug $1 (exit $rc, want $3): $out"
    fi
}
slug_case "punctuation" "Hello, World! It's 100% fine." "hello-world-it-s-100-fine"
slug_case "unicode accents" "Café déjà vu: naïve Zoë" "cafe-deja-vu-naive-zoe"
slug_case "spaces and hyphens" "  --Many   spaces--and---hyphens  " "many-spaces-and-hyphens"
slug_case "uppercase" "SHOUTING TITLE" "shouting-title"
slug_case "mixed script keeps the ASCII part" "Привет hello мир" "hello"
repo
long="$(printf 'word%.0s ' $(seq 1 30))"
au new post "$long" --description "$D"
s="$(basename "$(dirname "$(find "$r/content/posts" -name index.md | head -1)")")"
if [[ $rc -eq 0 && ${#s} -le 80 && "$s" != *- && "$s" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then ok "slug: long title is cut at most 80, on a word"; else bad "long slug '$s' (exit $rc)"; fi
repo
expect "empty title" 1 "must not be empty" new post "" --description "$D"
expect "title with no ASCII letters" 1 "no ASCII letters" new post "Привет мир" --description "$D"
expect "punctuation-only title" 1 "no ASCII letters" new post "!!! ???" --description "$D"
expect "title over the cap" 1 "at most 200" new post "$(printf 'a%.0s' $(seq 1 201))" --description "$D"
tree_empty && ok "bad titles: nothing created" || bad "bad titles left files"

# --- quoting: quotes and backslashes in a title survive and pass the check --------------------
repo
au new post 'He said "hi" and \o/ left' --description 'Say "hi": a colon and a # sign' --tag a
[[ $rc -eq 0 ]] || bad "quoting: $out"
au check content/posts/he-said-hi-and-o-left
[[ $rc -eq 0 ]] && ok "quotes, backslash, colon and # in text pass the check" || bad "quoting check: $out"
grep -q '^title: "He said \\"hi\\" and \\\\o/ left"$' "$r/content/posts/he-said-hi-and-o-left/index.md" && ok "quoting is escaped" || bad "quoting escape"

# --- dates ------------------------------------------------------------------------------------
repo
expect "invalid date format" 1 "date must look like" new post "D1" --description "$D" --date 08-11-2026
expect "impossible date" 1 "not a real calendar date" new post "D2" --description "$D" --date 2026-02-30
expect "month 13" 1 "not a real calendar date" new post "D3" --description "$D" --date 2026-13-01
expect "future date refused" 1 "in the future" new post "D4" --description "$D" --date 2999-01-01
tree_empty && ok "bad dates: nothing created" || bad "bad dates left files"
expect "future date with the flag" 0 "created" new post "D5" --description "$D" --date 2999-01-01 --allow-future
au check content/posts/d5
[[ $rc -eq 0 ]] && ok "future date still passes the check when allowed" || bad "future check: $out"
expect "leap day" 0 "created" new post "D6" --description "$D" --date 2024-02-29

# --- tags -------------------------------------------------------------------------------------
repo
expect "uppercase tag refused" 1 "not a lowercase slug" new post "T1" --description "$D" --tag Hugo
expect "tag with a space refused" 1 "not a lowercase slug" new post "T2" --description "$D" --tag "a b"
expect "tag with a slash refused" 1 "not a lowercase slug" new post "T3" --description "$D" --tag "a/b"
expect "tag with double hyphen refused" 1 "not a lowercase slug" new post "T4" --description "$D" --tag "a--b"
expect "empty tag refused" 1 "not a lowercase slug" new post "T5" --description "$D" --tag ""
expect "long tag refused" 1 "not a lowercase slug" new post "T6" --description "$D" --tag "$(printf 'a%.0s' $(seq 1 41))"
tags=()
for i in $(seq 1 11); do tags+=(--tag "t$i"); done
expect "eleven tags refused" 1 "at most 10 tags" new post "T7" --description "$D" "${tags[@]}"
tree_empty && ok "bad tags: nothing created" || bad "bad tags left files"
expect "duplicate tags are folded" 0 "created" new post "T8" --description "$D" --tag a --tag a
grep -q '^tags: \["a"\]$' "$r/content/posts/t8/index.md" && ok "duplicate tag written once" || bad "duplicate tag"
expect "no tags" 0 "created" new post "T9" --description "$D"
grep -q '^tags: \[\]$' "$r/content/posts/t9/index.md" && ok "no tags is an empty list" || bad "empty tags"

# --- collisions: never overwrite --------------------------------------------------------------
repo
au new post "Same title" --description "$D"
before="$(sha256sum "$r/content/posts/same-title/index.md")"
expect "second post with the same slug refused" 1 "already exists" new post "Same title!" --description "Another sentence."
[[ "$(sha256sum "$r/content/posts/same-title/index.md")" == "$before" ]] && ok "collision left the file unchanged" || bad "collision changed the file"
mkdir -p "$r/content/posts/taken" && printf 'x' >"$r/content/posts/taken"/keep.txt
expect "existing directory without index.md refused" 1 "already exists" new post "Taken" --description "$D"
[[ ! -e "$r/content/posts/taken/index.md" ]] && ok "no file added to the existing directory" || bad "wrote into an existing directory"
printf 'x' >"$r/content/posts/plainfile"
expect "existing plain file refused" 1 "already exists" new post "Plainfile" --description "$D"
ln -s /nonexistent "$r/content/posts/dangling"
expect "dangling symlink at the slug refused" 1 "already exists" new post "Dangling" --description "$D"
au new journal "Same title" --description "$D"
[[ $rc -eq 0 ]] && ok "the same slug in the other section is fine" || bad "cross-section: $out"

# --- path traversal and symlinks --------------------------------------------------------------
repo
outside="$work/outside$n"
mkdir -p "$outside"
rm -rf "$r/content/posts"
ln -s "$outside" "$r/content/posts"
expect "content/posts as a symlink refused" 1 "real directory" new post "Escape" --description "$D"
[[ -z "$(ls -A "$outside")" ]] && ok "nothing written through the symlinked section" || bad "wrote through a symlink"
repo
rm -rf "$r/content"
mkdir -p "$work/realcontent$n/posts"
ln -s "$work/realcontent$n" "$r/content"
expect "content as a symlink refused" 1 "real directory" new post "Escape2" --description "$D"
[[ -z "$(ls -A "$work/realcontent$n/posts")" ]] && ok "nothing written through the symlinked content" || bad "wrote through content symlink"
repo
rm -rf "$r/content"
expect "missing content directory refused" 1 "does not exist" new post "Nocontent" --description "$D"
repo
expect "title with slashes and dots cannot traverse" 0 "created content/posts/etc-passwd/index.md" new post "../../etc/passwd" --description "$D"
[[ ! -e "$work/etc" && ! -e "$r/etc" ]] && ok "no directory made outside content/" || bad "traversal made a directory"
repo
echo secret >"$work/target$n.md"
mkdir -p "$r/content/posts/linked"
ln -s "$work/target$n.md" "$r/content/posts/linked/index.md"
expect "check refuses a symlinked index.md" 1 "not a regular file|symlink" check content/posts/linked
expect "check refuses a path outside content" 1 "not inside content/" check ../../etc/passwd
expect "check refuses the repo root file" 1 "not inside content/" check brand/approved-assets.txt
repo
mkdir -p "$work/realc$n/posts/p"
printf -- '---\ntitle: "x"\n---\n' >"$work/realc$n/posts/p/index.md"
rm -rf "$r/content"
ln -s "$work/realc$n" "$r/content"
expect "check refuses a symlinked content/" 1 "symlink" check content/posts/p/index.md
repo
expect "check refuses content/ itself" 1 "not inside content/" check content
ln -s "$outside" "$r/content/journal/viasym"
expect "check refuses a path through a symlinked directory" 1 "symlink" check content/journal/viasym/index.md
expect "check on a missing file" 1 "not a regular file" check content/posts/nope

# --- check reports findings and passes the exit code -------------------------------------------
repo
mkdir -p "$r/content/posts/bad"
printf -- '---\ntitle: "Bad"\ndate: 2026-11-08\ndraft: true\nslug: "bad"\n---\nbody\n' >"$r/content/posts/bad/index.md"
expect "check prints findings and exits 1" 1 "description: content/posts/bad/index.md" check content/posts/bad

# --- img add (issue #256) ---------------------------------------------------------------------
# Fixtures are built here from bytes: tiny synthetic JPEG and PNG files whose metadata blocks carry
# an obviously fake GPS sentinel (never a real coordinate, callsign, address or personal image).
fx="$work/fx"
mkdir -p "$fx"
python3 -I - "$fx" <<'PY'
import struct, sys, zlib, os
out = sys.argv[1]
SENT = b"FAKEGPS-SENTINEL-0000"

def exif(orient=1):
    # little-endian TIFF: IFD0 {Make, Orientation, GPS pointer}, GPS IFD {LatRef, Lat}
    make = b"FAKECAM-SENTINEL\0"
    ifd0_off = 8
    n0 = 3
    gps_ifd_off = ifd0_off + 2 + n0 * 12 + 4
    n1 = 2
    make_off = gps_ifd_off + 2 + n1 * 12 + 4
    lat_off = make_off + len(make)
    ifd0 = struct.pack("<H", n0)
    ifd0 += struct.pack("<HHII", 0x010F, 2, len(make), make_off)
    ifd0 += struct.pack("<HHIHH", 0x0112, 3, 1, orient, 0)
    ifd0 += struct.pack("<HHII", 0x8825, 4, 1, gps_ifd_off) + struct.pack("<I", 0)
    gps = struct.pack("<H", n1)
    gps += struct.pack("<HHI", 0x0001, 2, 2) + b"N\0\0\0"
    gps += struct.pack("<HHII", 0x0002, 5, 3, lat_off) + struct.pack("<I", 0)
    rationals = struct.pack("<6I", 0, 1, 0, 1, 0, 1) + SENT
    return b"II*\0" + struct.pack("<I", 8) + ifd0 + gps + make + rationals

def seg(m, payload):
    return bytes([0xFF, m]) + struct.pack(">H", len(payload) + 2) + payload

def jpeg(w=8, h=8, exif_blob=None, trunc=False):
    b = b"\xff\xd8"
    b += seg(0xE0, b"JFIF\0\1\1\0\0\1\0\1\0\0")
    if exif_blob is not None:
        b += seg(0xE1, b"Exif\0\0" + exif_blob)
    b += seg(0xE1, b"http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>" + SENT + b"</x:xmpmeta>")
    b += seg(0xED, b"Photoshop 3.0\0" + SENT)
    b += seg(0xFE, b"comment " + SENT)
    b += seg(0xDB, b"\0" + bytes(range(1, 65)))
    b += seg(0xC0, bytes([8]) + struct.pack(">HH", h, w) + bytes([1, 1, 0x11, 0]))
    b += seg(0xC4, b"\x00" + bytes([1] + [0] * 15) + b"\x00")
    b += seg(0xDA, bytes([1, 1, 0, 0, 63, 0]))
    b += bytes([0x12, 0xFF, 0x00, 0x34, 0x56])
    if not trunc:
        b += b"\xff\xd9"
    return b

def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))

def png(w=4, h=4, meta=True):
    b = b"\x89PNG\r\n\x1a\n"
    b += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
    if meta:
        b += chunk(b"eXIf", exif())
        b += chunk(b"tEXt", b"Comment\0" + SENT)
        b += chunk(b"iTXt", b"XML:com.adobe.xmp\0\0\0\0\0<x:xmpmeta>" + SENT + b"</x:xmpmeta>")
        b += chunk(b"tIME", struct.pack(">HBBBBB", 2026, 1, 2, 3, 4, 5))
    rows = b"".join(b"\0" + bytes([i * 16] * 4) for i in range(4)) if (w, h) == (4, 4) else b"\0"
    b += chunk(b"IDAT", zlib.compress(rows))
    b += chunk(b"IEND", b"")
    return b

def w(name, data):
    with open(os.path.join(out, name), "wb") as f:
        f.write(data)

good_png = png()
w("photo.jpg", jpeg(exif_blob=exif()))
w("shot.png", good_png)
w("rot6.jpg", jpeg(exif_blob=exif(6)))
w("clean.png", png(meta=False))
w("fake.jpg", b"This is a text file renamed to jpg.\n" * 20)
w("webp-as.jpg", b"RIFF\x10\0\0\0WEBPVP8 " + bytes(40))
w("trunc.jpg", jpeg(exif_blob=exif(), trunc=True))
w("bomb.png", png(w=70000, h=70000))
w("bomb.jpg", jpeg(w=65000, h=65000, exif_blob=exif()))
w("zero.jpg", b"")
w("polyglot.jpg", jpeg(exif_blob=exif()) + b"<?php system($_GET['c']); ?>")
w("bad-crc.png", good_png[:-8] + b"\0\0\0\0" + good_png[-4:])
def bare_png(w_, h_, depth, ctype, raw):
    head = chunk(b"IHDR", struct.pack(">IIBBBBB", w_, h_, depth, ctype, 0, 0, 0))
    return b"\x89PNG\r\n\x1a\n" + head + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

w("png-depth3.png", bare_png(1, 1, 3, 0, b""))
w("png-short.png", bare_png(4, 4, 8, 0, b"\0" * 7))
w("png-long.png", bare_png(4, 4, 8, 0, b"\0" * 40))
w("png-badtype.png", bare_png(1, 1, 8, 5, b"\0\0"))
w("png-nopalette.png", bare_png(1, 1, 8, 3, b"\0\0"))
w("png-garbage.png", good_png[:33] + chunk(b"IDAT", b"\1\2\3") + chunk(b"IEND", b""))
w("big.jpg", jpeg() + bytes(5 * 1024 * 1024))
PY
SENT="FAKEGPS-SENTINEL-0000"
img() { # img <bundle> <file> <args...>
    local b="$1" f="$2"
    shift 2
    au img add "$b" "$f" "$@"
}
mkbundle() {
    repo
    mkdir -p "$r/content/posts/pic"
    printf -- '---\ntitle: "Pic"\ndate: 2026-11-08\ndraft: true\ndescription: "A plain sentence that describes the page."\nslug: "pic"\n---\nbody\n' >"$r/content/posts/pic/index.md"
}
ALT="A synthetic gray gradient used as a test image"

mkbundle
img content/posts/pic "$fx/photo.jpg" --alt "$ALT"
if [[ $rc -eq 0 ]]; then ok "img add jpeg"; else bad "img add jpeg: $out"; fi
grep -qF '![A synthetic gray gradient used as a test image](photo.jpg)' <<<"$out" && ok "prints the exact markdown" || bad "markdown line: $out"
dest="$r/content/posts/pic/photo.jpg"
[[ -f "$dest" && ! -L "$dest" ]] && ok "jpeg landed in the bundle" || bad "jpeg not in bundle"
if grep -qF "$SENT" "$dest" || grep -qF "FAKECAM" "$dest"; then bad "sentinel survived in jpeg"; else ok "no GPS or camera sentinel in the cleaned jpeg"; fi
rc=0
python3 -I "$root/scripts/check-image-metadata.py" "$r/content/posts/pic" >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] && ok "check-image-metadata.py passes on the cleaned jpeg" || bad "metadata check rc $rc on jpeg"
python3 -I - "$fx/photo.jpg" "$dest" <<'PY' && ok "jpeg scan data unchanged" || bad "jpeg scan data changed"
import sys
a, b = (open(p, "rb").read() for p in sys.argv[1:3])
tail = bytes([0x12, 0xFF, 0x00, 0x34, 0x56]) + b"\xff\xd9"
assert a.endswith(tail) and b.endswith(tail) and b[:2] == b"\xff\xd8"
PY
[[ "$(sha256sum <"$fx/photo.jpg")" != "$(sha256sum <"$dest")" ]] && ok "output differs from the source" || bad "output equals source"
[[ -f "$fx/photo.jpg" ]] && grep -q "brand/approved-assets.txt" <<<"$out" && ok "tells the owner about the brand manifest entry" || bad "no manifest note: $out"
# the page passes the content check once the owner has approved the image (the manifest line is what the owner adds)
sum="$(sha256sum "$dest" | cut -d' ' -f1)"
printf 'content/posts/pic/photo.jpg | %s | synthetic test image | test fixture\n' "$sum" >>"$r/brand/approved-assets.txt"
printf '\n![A synthetic gray gradient used as a test image](photo.jpg)\n' >>"$r/content/posts/pic/index.md"
au check content/posts/pic
[[ $rc -eq 0 ]] && ok "check passes on the page with the added image" || bad "check after img add: $out"

mkbundle
img content/posts/pic "$fx/shot.png" --alt "$ALT" --name "My Screen Shot!"
[[ $rc -eq 0 ]] && ok "img add png" || bad "img add png: $out"
dest="$r/content/posts/pic/my-screen-shot.png"
[[ -f "$dest" ]] && ok "name sanitized to my-screen-shot.png" || bad "sanitized name: $out"
grep -qF '![A synthetic gray gradient used as a test image](my-screen-shot.png)' <<<"$out" && ok "png markdown line" || bad "png markdown: $out"
if grep -qF "$SENT" "$dest" || grep -qF "eXIf" "$dest" || grep -qF "tIME" "$dest"; then bad "metadata chunk survived in png"; else ok "no metadata chunks in the cleaned png"; fi
rc=0
python3 -I "$root/scripts/check-image-metadata.py" "$r/content/posts/pic" >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] && ok "check-image-metadata.py passes on the cleaned png" || bad "metadata check rc $rc on png"
python3 -I - "$dest" <<'PY' && ok "png still decodes (chunk CRCs valid, IDAT intact)" || bad "cleaned png is broken"
import struct, sys, zlib
b = open(sys.argv[1], "rb").read()
assert b[:8] == b"\x89PNG\r\n\x1a\n"
i, kinds, idat = 8, [], b""
while i < len(b):
    n = struct.unpack(">I", b[i:i+4])[0]
    t, d = b[i+4:i+8], b[i+8:i+8+n]
    assert zlib.crc32(t + d) == struct.unpack(">I", b[i+8+n:i+12+n])[0]
    kinds.append(t)
    if t == b"IDAT":
        idat += d
    i += 12 + n
assert kinds[0] == b"IHDR" and kinds[-1] == b"IEND"
assert len(zlib.decompress(idat)) == 4 * 5
PY

# featured image: prints the front matter lines, never edits the page
mkbundle
before="$(sha256sum <"$r/content/posts/pic/index.md")"
img content/posts/pic "$fx/clean.png" --alt "$ALT" --featured
[[ $rc -eq 0 ]] && grep -qF 'image: "clean.png"' <<<"$out" && grep -qF 'imageAlt: "A synthetic gray gradient used as a test image"' <<<"$out" && ok "--featured prints image and imageAlt lines" || bad "--featured: $out"
[[ "$before" == "$(sha256sum <"$r/content/posts/pic/index.md")" ]] && ok "index.md left untouched" || bad "index.md was edited"

# never overwrites
mkbundle
img content/posts/pic "$fx/photo.jpg" --alt "$ALT"
h1="$(sha256sum <"$r/content/posts/pic/photo.jpg")"
img content/posts/pic "$fx/photo.jpg" --alt "$ALT"
[[ $rc -eq 1 ]] && grep -q "already exists" <<<"$out" && [[ "$h1" == "$(sha256sum <"$r/content/posts/pic/photo.jpg")" ]] && ok "refuses to overwrite and leaves the file alone" || bad "overwrite: rc $rc $out"
img content/posts/pic "$fx/photo.jpg" --alt "$ALT" --name photo-two
[[ $rc -eq 0 && -f "$r/content/posts/pic/photo-two.jpg" ]] && ok "--name picks another file name" || bad "--name: $out"

# refusals: exit 1, the message matches, and nothing but index.md is in the bundle
mkbundle
imgrefuse() { # <name> <pattern> <file> <args...>
    local name="$1" pat="$2" f="$3"
    shift 3
    img content/posts/pic "$f" "$@"
    if [[ $rc -eq 1 ]] && grep -qE -- "$pat" <<<"$out" && [[ -z "$(find "$r/content/posts/pic" -type f ! -name index.md -print -quit)" ]]; then ok "$name"; else bad "$name (rc $rc): $out"; fi
}
imgrefuse "empty alt refused" "alt text" "$fx/photo.jpg" --alt ""
imgrefuse "blank alt refused" "alt text" "$fx/photo.jpg" --alt "   "
imgrefuse "filename-like alt refused" "alt text" "$fx/photo.jpg" --alt "photo.jpg"
imgrefuse "placeholder alt refused" "alt text" "$fx/photo.jpg" --alt "TODO"
imgrefuse "overlong alt refused" "at most" "$fx/photo.jpg" --alt "$(printf 'word %.0s' $(seq 1 100))"
imgrefuse "control character in alt refused" "plain text" "$fx/photo.jpg" --alt "$(printf 'two\nlines of alt')"
au img add content/posts/pic "$fx/photo.jpg"
[[ $rc -eq 2 ]] && ok "missing --alt is a usage error" || bad "missing --alt: rc $rc $out"

imgrefuse "text renamed to .jpg refused" "not a JPEG or PNG" "$fx/fake.jpg" --alt "$ALT"
imgrefuse "WebP renamed to .jpg refused" "not a JPEG or PNG" "$fx/webp-as.jpg" --alt "$ALT"
imgrefuse "empty file refused" "not a JPEG or PNG|empty" "$fx/zero.jpg" --alt "$ALT"
imgrefuse "truncated jpeg refused" "truncated|malformed" "$fx/trunc.jpg" --alt "$ALT"
imgrefuse "bad png crc refused" "malformed|checksum" "$fx/bad-crc.png" --alt "$ALT"
imgrefuse "PNG with illegal bit depth for its color type refused" "malformed" "$fx/png-depth3.png" --alt "$ALT"
imgrefuse "PNG with invalid color type refused" "malformed" "$fx/png-badtype.png" --alt "$ALT"
imgrefuse "palette PNG without PLTE refused" "malformed" "$fx/png-nopalette.png" --alt "$ALT"
imgrefuse "PNG whose image data is too short refused" "malformed" "$fx/png-short.png" --alt "$ALT"
imgrefuse "PNG whose image data is too long refused" "malformed" "$fx/png-long.png" --alt "$ALT"
imgrefuse "PNG whose image data is not a zlib stream refused" "malformed" "$fx/png-garbage.png" --alt "$ALT"
imgrefuse "decompression-bomb png dimensions refused" "dimensions" "$fx/bomb.png" --alt "$ALT"
imgrefuse "decompression-bomb jpeg dimensions refused" "dimensions" "$fx/bomb.jpg" --alt "$ALT"
imgrefuse "bytes after the end of the image refused" "after the end|malformed" "$fx/polyglot.jpg" --alt "$ALT"
imgrefuse "oversize file refused with the limit" "5 MiB" "$fx/big.jpg" --alt "$ALT"
imgrefuse "orientation other than 1 refused with a clear message" "orientation" "$fx/rot6.jpg" --alt "$ALT"
imgrefuse "missing source refused" "does not exist|not a regular file" "$fx/nope.jpg" --alt "$ALT"
imgrefuse "directory as source refused" "regular file" "$fx" --alt "$ALT"

# paths: symlinks, traversal, confinement
ln -s "$fx/photo.jpg" "$work/link.jpg"
imgrefuse "symlink source refused" "symlink" "$work/link.jpg" --alt "$ALT"
mkdir -p "$work/realdir"
cp "$fx/photo.jpg" "$work/realdir/photo.jpg"
ln -s "$work/realdir" "$work/linkdir"
imgrefuse "source through a symlinked directory refused" "symlink" "$work/linkdir/photo.jpg" --alt "$ALT"
img content/posts/../../../escape "$fx/photo.jpg" --alt "$ALT"
[[ $rc -eq 1 ]] && grep -q "not inside content/" <<<"$out" && ok "bundle traversal refused" || bad "bundle traversal: rc $rc $out"
img /etc "$fx/photo.jpg" --alt "$ALT"
[[ $rc -eq 1 ]] && grep -q "not inside content/" <<<"$out" && ok "bundle outside content/ refused" || bad "bundle outside: rc $rc $out"
img content/posts "$fx/photo.jpg" --alt "$ALT"
[[ $rc -eq 1 ]] && ok "a section folder is not a bundle" || bad "section as bundle: rc $rc $out"
img content/posts/nope "$fx/photo.jpg" --alt "$ALT"
[[ $rc -eq 1 ]] && ok "missing bundle refused" || bad "missing bundle: rc $rc $out"
mkdir -p "$work/outside"
printf -- '---\ntitle: "x"\n---\n' >"$work/outside/index.md"
ln -s "$work/outside" "$r/content/posts/viasym"
img content/posts/viasym "$fx/photo.jpg" --alt "$ALT"
[[ $rc -eq 1 ]] && grep -q "symlink" <<<"$out" && [[ -z "$(find "$work/outside" -name '*.jpg' -print -quit)" ]] && ok "symlinked bundle refused, nothing written outside" || bad "symlinked bundle: rc $rc $out"
rm -f "$r/content/posts/pic/index.md"
img content/posts/pic "$fx/photo.jpg" --alt "$ALT"
[[ $rc -eq 1 ]] && grep -q "index.md" <<<"$out" && ok "a folder without index.md is not a bundle" || bad "no index.md: rc $rc $out"

# mutation proof: with the stripping step replaced by a copy, the same input keeps its GPS sentinel and
# fails the metadata check; the real helper removes it. So the stripping is what removes the GPS.
mut="$work/mut"
mkdir -p "$mut"
cp "$root"/scripts/*.py "$root"/scripts/*.sh "$mut/"
grep -q 'clean, dims = strip_image(kind, data)' "$mut/author.py" || bad "mutation anchor missing in author.py"
sed -i 's/clean, dims = strip_image(kind, data)/clean, dims = data, (1, 1)/' "$mut/author.py"
mkbundle
rc=0
timeout 60 python3 -I "$mut/author.py" --root "$r" img add content/posts/pic "$fx/photo.jpg" --alt "$ALT" >/dev/null 2>&1 </dev/null || rc=$?
if [[ $rc -eq 0 ]] && grep -qF "$SENT" "$r/content/posts/pic/photo.jpg"; then ok "mutant (no stripping): the sentinel survives"; else bad "mutant did not keep the sentinel (rc $rc)"; fi
rc=0
python3 -I "$root/scripts/check-image-metadata.py" "$r/content/posts/pic" >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] && ok "mutant output fails check-image-metadata.py" || bad "mutant output passed the metadata check"

# --- preview (issue #254): a stub Hugo records its arguments; the helper must bind loopback only ---------
repo
echo "0.168.0" >"$r/.hugo-version"
stubdir="$work/stub"
mkdir -p "$stubdir"
cat >"$stubdir/hugo" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "version" ]]; then
    echo "${STUB_VERSION:-hugo v0.168.0-deadbeef linux/amd64 BuildDate=unknown}"
    exit 0
fi
printf '%s\n' "$@" >"${STUB_ARGS:?}"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$stubdir/hugo"
export STUB_ARGS="$work/stub-args"
rm -f "$STUB_ARGS"
expect "preview runs the stub and prints the URL" 0 "http://127\.0\.0\.1:[0-9]+/" preview --hugo "$stubdir/hugo"
if [[ -f "$STUB_ARGS" ]] && grep -qx -- "server" "$STUB_ARGS" && grep -qx -- "-D" "$STUB_ARGS" && grep -qx -- "--bind" "$STUB_ARGS" && grep -qx -- "127.0.0.1" "$STUB_ARGS"; then ok "hugo server -D --bind 127.0.0.1"; else bad "stub args: $(cat "$STUB_ARGS" 2>/dev/null)"; fi
if grep -qE -- '0\.0\.0\.0|::|localhost' "$STUB_ARGS"; then bad "a non-loopback address reached hugo"; else ok "no wildcard or name host reached hugo"; fi
if grep -qE -- '--openBrowser|--open' "$STUB_ARGS"; then bad "preview asked hugo to open a browser"; else ok "no browser opened"; fi
port="$(grep -E -o 'http://127\.0\.0\.1:[0-9]+/' <<<"$out" | head -1 | sed -E 's|.*:([0-9]+)/|\1|')"
grep -qx -- "$port" "$STUB_ARGS" && ok "the printed port is the port hugo got" || bad "port mismatch ($port)"
expect "preview with a chosen port" 0 "http://127\.0\.0\.1:41234/" preview --hugo "$stubdir/hugo" --port 41234
STUB_EXIT=3 expect "preview passes the exit code of hugo" 3 - preview --hugo "$stubdir/hugo" --port 41234
for h in 0.0.0.0 :: localhost 192.168.1.5 example.com ""; do
    rm -f "$STUB_ARGS"
    au preview --hugo "$stubdir/hugo" --host "$h"
    if [[ $rc -eq 1 ]] && grep -q "127.0.0.1" <<<"$out" && [[ ! -e "$STUB_ARGS" ]]; then ok "host '$h' refused, hugo never started"; else bad "host '$h' (rc $rc): $out"; fi
done
expect "explicit 127.0.0.1 accepted" 0 "http://127\.0\.0\.1:" preview --hugo "$stubdir/hugo" --host 127.0.0.1
expect "port 0 refused" 1 "port" preview --hugo "$stubdir/hugo" --port 0
expect "port 70000 refused" 1 "port" preview --hugo "$stubdir/hugo" --port 70000
STUB_VERSION="hugo v0.100.0-abc linux/amd64" expect "wrong hugo version refused" 1 "version" preview --hugo "$stubdir/hugo"
STUB_VERSION="hugo v0.168.0-abc+extended linux/amd64" expect "extended edition refused" 1 "extended" preview --hugo "$stubdir/hugo"
expect "missing hugo path says so plainly" 1 "hugo is not installed" preview --hugo "$work/no-such-hugo"
rc=0
py3="$(command -v python3)"
out="$(PATH="$work/nobin" "$py3" -I "$root/scripts/author.py" --root "$r" preview 2>&1 </dev/null)" || rc=$?
[[ $rc -eq 1 ]] && grep -q "hugo is not installed" <<<"$out" && ok "no hugo on PATH says so plainly" || bad "no hugo on PATH (rc $rc): $out"
unset STUB_ARGS
if grep -nE '"0\.0\.0\.0"|shell=True|os\.system' "$root/scripts/author.py"; then bad "author.py has a wildcard address or a shell call"; else ok "author.py has no wildcard address and no shell call"; fi

# --- nothing outside content/ was written, no git, no network ---------------------------------
repo
before="$(cd "$r" && find . -path ./content -prune -o -print | sort | sha256sum)"
au new post "Scope" --description "$D"
after="$(cd "$r" && find . -path ./content -prune -o -print | sort | sha256sum)"
[[ "$before" == "$after" ]] && ok "nothing written outside content/" || bad "wrote outside content/"
[[ ! -e "$r/.git" ]] && ok "no git repository touched" || bad ".git appeared"
if grep -nE '^\s*(import|from)\s+(urllib|http|requests|webbrowser|ftplib|smtplib)\b' "$root/scripts/author.py"; then bad "author.py imports a network module"; else ok "author.py imports no network or browser module"; fi
# socket is imported only inside preview, to find a free loopback port: every bind names 127.0.0.1
if grep -nE '\.bind\(' "$root/scripts/author.py" | grep -vF '.bind((LOOPBACK, 0))'; then bad "author.py binds something other than loopback"; else ok "author.py binds loopback only"; fi
if grep -nE '"git"|webbrowser|xdg-open' "$root/scripts/author.py"; then bad "author.py names git or a browser"; else ok "author.py runs no git or browser"; fi

if [[ $fail -ne 0 ]]; then
    echo "test-author: FAILED"
    exit 1
fi
echo "test-author: all passed"
