#!/usr/bin/env bash
# Tests for scripts/check-content.py: a good post passes, each rule has a failing fixture
# (and a passing twin where the rule has an edge), hostile front matter and hostile body
# text are errors rather than crashes or hangs, a huge file stays bounded, and non-UTF-8
# input is an error.
#
# Fixtures are throwaway repositories under the repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/check-content.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}
check_py() { timeout 60 python3 -I "$root/scripts/check-content.py" "$@"; }

# --- image makers (stdlib Python; written once) -----------------------------------------------
mk="$work/mkimg.py"
cat >"$mk" <<'PY'
import struct, sys, zlib
kind, out = sys.argv[1], sys.argv[2]
extra = int(sys.argv[3]) if len(sys.argv) > 3 else 0
# A TIFF block with one tag in IFD0: any tag is an EXIF finding.
TIFF = bytes.fromhex("4d4d002a000000080001010f0002000000024100000000000000000000")

def png(exif=False, w=1, h=1):
    def chunk(t, b):
        return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
    d = bytes([0x89]) + b"PNG\r\n" + bytes([0x1A, 0x0A])
    d += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    if exif:
        d += chunk(b"eXIf", TIFF)
    d += chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00"))
    d += chunk(b"IEND", b"")
    return d

def jpeg(exif=False):
    d = bytes([0xFF, 0xD8])
    if exif:
        seg = b"Exif\x00\x00" + TIFF
        d += bytes([0xFF, 0xE1]) + struct.pack(">H", len(seg) + 2) + seg
    d += bytes([0xFF, 0xC0]) + struct.pack(">HBHHB", 11, 8, 1, 1, 1) + b"\x01\x11\x00"
    return d + bytes([0xFF, 0xDA]) + b"\x00" * 8 + bytes([0xFF, 0xD9])

def webp(exif=False):
    body = b"WEBP" + b"VP8L" + struct.pack("<I", 6) + b"\x2f\x00\x00\x00\x00\x00"
    if exif:
        body += b"EXIF" + struct.pack("<I", len(TIFF)) + TIFF + b"\x00" * (len(TIFF) & 1)
    return b"RIFF" + struct.pack("<I", len(body)) + body

NS = 'xmlns="http://www.w3.org/2000/svg"'

def svg(inner="", head='viewBox="0 0 10 10"', pre=""):
    return (pre + '<svg %s %s><title>t</title>%s</svg>\n' % (NS, head, inner)).encode()

R = '<rect width="5" height="5"%s/>'
SVGS = {
    "svg": svg(R % ""),
    "svg-xmldecl": svg(R % "", pre='<?xml version="1.0" encoding="UTF-8"?>\n'),
    "svg-style-local": svg(R % ' style="fill:url(#g)"'),
    "svg-marker": svg('<defs><marker id="m" markerWidth="2" markerHeight="2"><path d="M0 0L1 1"/></marker></defs><path d="M0 0L5 5" marker-end="url(#m)"/>'),
    "svg-script": svg("<script>1</script>"),
    "svg-script-upper": svg("<SCRIPT>1</SCRIPT>"),
    "svg-script-mixed": svg("<ScRiPt>1</ScRiPt>"),
    "svg-script-prefixed": svg('<s:script xmlns:s="http://www.w3.org/2000/svg">1</s:script>'),
    "svg-script-xhtml": svg('<h:script xmlns:h="http://www.w3.org/1999/xhtml">1</h:script>'),
    "svg-script-noprefix-ns": ('<svg %s viewBox="0 0 1 1"><script xmlns="http://www.w3.org/1999/xhtml">1</script></svg>' % NS).encode(),
    "svg-foreign": svg("<foreignObject/>"),
    "svg-animate": svg((R % "") + '<animate attributeName="x" to="9"/>'),
    "svg-set": svg('<set attributeName="href" to="javascript:alert(1)"/>'),
    "svg-use": svg('<use x="1"/>'),
    "svg-href": svg(R % ' href="#x"'),
    "svg-href-upper": svg(R % ' HREF="#x"'),
    "svg-xlink-href": svg(R % ' xlink:href="#x"').replace(b"<svg ", b'<svg xmlns:xlink="http://www.w3.org/1999/xlink" '),
    "svg-onclick": svg(R % ' onclick="1"'),
    "svg-onclick-case": svg(R % ' OnClick="1"'),
    "svg-onload-root": svg("", 'viewBox="0 0 1 1" onload="1"'),
    "svg-unknown-attr": svg(R % ' data-x="1"'),
    "svg-fill-url": svg(R % ' fill="url(https://example.invalid/x)"'),
    "svg-fill-url-rel": svg(R % ' fill="url(other.svg#a)"'),
    "svg-style-url": svg(R % ' style="fill:url(https://example.invalid/x)"'),
    "svg-style-import": svg(R % ' style="@import url(#a)"'),
    "svg-style-escape": svg(R % ' style="fill:\\75rl(x)"'),
    "svg-js-attr": svg(R % ' fill="JaVaScRiPt:alert(1)"'),
    "svg-text-url": svg("<text>see https://example.invalid/x</text>"),
    "svg-text-scheme": svg("<text>JaVaScRiPt:alert(1)</text>"),
    "svg-text-protorel": svg("<text>//example.invalid/x</text>"),
    "svg-title-url": svg("<desc>http://example.invalid</desc>"),
    "svg-pi-stylesheet": svg("", pre='<?xml-stylesheet href="a.css"?>'),
    "svg-pi-wrapped": svg('<?foo <script>alert(1)</script> ?>'),
    "svg-pi-late": svg('<?php echo 1; ?>' + R % ""),
    "svg-comment": svg("<!-- <script>1</script> -->"),
    "svg-cdata": svg("<text><![CDATA[<script>]]></text>"),
    "svg-doctype": ('<!DOCTYPE svg><svg %s viewBox="0 0 1 1"/>' % NS).encode(),
    "svg-doctype-lower": ('<!doctype svg [<!entity a "b">]><svg %s viewBox="0 0 1 1"/>' % NS).encode(),
    "svg-ns-other": svg("", 'viewBox="0 0 1 1" xmlns:x="http://example.invalid/ns"'),
    "svg-no-ns": b'<svg viewBox="0 0 1 1"/>',
    "svg-novb": svg("", ""),
    "svg-utf16": svg(R % "").decode().encode("utf-16"),
    "svg-utf16le": svg(R % "").decode().encode("utf-16-le"),
    "svg-utf16be-bom": b"\xfe\xff" + svg(R % "").decode().encode("utf-16-be"),
    "svg-utf32": svg(R % "").decode().encode("utf-32"),
    "svg-utf8-bom": b"\xef\xbb\xbf" + svg(R % ""),
    "svg-latin1": svg("<text>caf\xe9</text>").decode().encode("latin-1"),
    "svg-declared-latin1": svg(R % "", pre='<?xml version="1.0" encoding="ISO-8859-1"?>'),
    "svg-malformed": b"<svg",
}

data = SVGS.get(kind) or {"png-wide": png(False, 12000, 10), "png-huge": png(False, 9000, 9000), "png": png(), "png-exif": png(True), "jpg": jpeg(), "jpg-exif": jpeg(True), "webp": webp(), "webp-exif": webp(True)}[kind]
open(out, "wb").write(data + b"\x00" * extra)
PY

# --- fixture builders ---------------------------------------------------------------------------
# repo <name>: an empty repository tree with an empty brand manifest.
repo() {
    local d="$work/$1"
    mkdir -p "$d/content/posts/p" "$d/brand" "$d/static/brand" "$d/static/fonts"
    printf '# manifest\n' >"$d/brand/approved-assets.txt"
    : >"$d/content/posts/p/pic.png"
    echo "$d"
}
good_fm='---
title: "A real title"
date: 2026-11-08T09:30:00-05:00
draft: false
description: "A plain sentence that describes the post."
slug: "p"
categories: ["Notes"]
tags: ["hugo", "web-editor"]
syndicate: false
aliases:
  - "/old/"
build:
  publishResources: false
---
'
# put <name> <full file text>: writes content/posts/p/index.md and echoes the repo.
put() {
    local d
    d="$(repo "$1")"
    printf '%s' "$2" >"$d/content/posts/p/index.md"
    echo "$d"
}
# expect <name> <exit> <rule or -> <full file text>
expect() {
    local d out rc=0
    d="$(put "$1" "$4")"
    out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
    if [[ $rc -ne "$2" ]]; then
        bad "$1 (exit $rc, want $2): $out"
    elif [[ "$3" != "-" ]] && ! grep -q "^$3: content/posts/p/index.md: " <<<"$out"; then
        bad "$1 (exit ok but rule $3 not reported): $out"
    else
        ok "$1"
    fi
}
nl=$'\n'
body='Opening paragraph.

<!--more-->

Text.
'
# fm_with <line prefix to drop> <lines to add after the opening fence>: the good front matter, changed.
fm_with() {
    printf '%s' "$good_fm" | awk -v drop="$1" -v add="$2" '
        NR==1 { print; if (add != "") print add; next }
        drop != "" && index($0, drop) == 1 { next }
        { print }'
}

# --- front matter and fields -------------------------------------------------------------------------
expect good-post 0 - "$good_fm$body"
expect good-flow-list 0 - "$(fm_with 'tags:' 'tags: [a, "b-c", '"'d'"']')$nl$body"
expect no-front-matter 1 front-matter "No front matter here.
"
expect unterminated-front-matter 1 front-matter "---
title: x
"
expect toml-front-matter 1 front-matter "+++
title = 'x'
+++
"
expect missing-title 1 title "$(fm_with 'title:' '')$nl$body"
expect empty-title 1 title "$(fm_with 'title:' 'title: ""')$nl$body"
expect missing-date 1 date "$(fm_with 'date:' '')$nl$body"
expect bad-date-format 1 date "$(fm_with 'date:' 'date: November 8')$nl$body"
expect bad-date-calendar 1 date "$(fm_with 'date:' 'date: 2026-02-30')$nl$body"
expect good-date-only 0 - "$(fm_with 'date:' 'date: 2026-11-08')$nl$body"
expect missing-description 1 description "$(fm_with 'description:' '')$nl$body"
expect empty-description 1 description "$(fm_with 'description:' 'description: ""')$nl$body"
long="$(printf 'a%.0s' $(seq 1 161))"
expect description-161 1 description "$(fm_with 'description:' "description: \"$long\"")$nl$body"
expect description-160 0 - "$(fm_with 'description:' "description: \"${long%a}\"")$nl$body"
expect draft-quoted 1 draft "$(fm_with 'draft:' 'draft: "false"')$nl$body"
expect draft-yes 1 draft "$(fm_with 'draft:' 'draft: yes')$nl$body"
expect draft-true-ok 0 - "$(fm_with 'draft:' 'draft: true')$nl$body"
expect tag-uppercase 1 tags "$(fm_with 'tags:' 'tags: ["Hugo"]')$nl$body"
expect tag-space 1 tags "$(fm_with 'tags:' 'tags: ["work from home"]')$nl$body"
expect tag-not-list 1 tags "$(fm_with 'tags:' 'tags: hugo')$nl$body"
expect tag-block-list-ok 0 - "$(fm_with 'tags:' 'tags:
  - hugo
  - web-editor')$nl$body"

# --- headline image alt ------------------------------------------------------------------------------------
d="$(put image-needs-alt "$(fm_with 'syndicate:' 'image: "featured.png"')$nl$body")"
python3 -I "$mk" png "$d/content/posts/p/featured.png"
rc=0
out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^image-alt: content/posts/p/index.md' <<<"$out"; then ok "image without imageAlt fails"; else bad "image without imageAlt (exit $rc): $out"; fi
printf '%s' "$(fm_with 'syndicate:' 'image: "featured.png"
imageAlt: "TODO alt text"')$nl$body" >"$d/content/posts/p/index.md"
rc=0
out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^image-alt: .*placeholder' <<<"$out"; then ok "placeholder imageAlt fails"; else bad "placeholder imageAlt (exit $rc): $out"; fi
printf '%s' "$(fm_with 'syndicate:' 'image: "featured.png"
imageAlt: "A red square used as a stand-in photo."')$nl$body" >"$d/content/posts/p/index.md"
sum="$(sha256sum "$d/content/posts/p/featured.png" | cut -d' ' -f1)"
printf 'content/posts/p/featured.png | %s | test | looked at\n' "$sum" >>"$d/brand/approved-assets.txt"
rc=0
out="$(check_py --root "$d" content/posts/p/index.md content/posts/p/featured.png 2>&1)" || rc=$?
if [[ $rc -eq 0 ]]; then ok "image with real imageAlt and a listed file passes"; else bad "good image post (exit $rc): $out"; fi
printf '%s' "$(fm_with 'draft:' 'draft: true
image: "featured.png"')$nl$body" >"$d/content/posts/p/index.md"
rc=0
out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 0 ]]; then ok "a draft may have an image without imageAlt"; else bad "draft image (exit $rc): $out"; fi

# --- inline images ------------------------------------------------------------------------------------------------
expect inline-alt-good 0 - "$good_fm$body
![A red square beside the headline.](pic.png)
"
expect inline-alt-empty 1 inline-alt "$good_fm$body
![](pic.png)
"
expect inline-alt-todo 1 inline-alt "$good_fm$body
![TODO alt text](pic.png)
"
expect inline-alt-filename 1 inline-alt "$good_fm$body
![IMG_1234.jpg](pic.png)
"
expect inline-alt-camera-name 1 inline-alt "$good_fm$body
![IMG_1234](pic.png)
"
expect inline-alt-same-as-file 1 inline-alt "$good_fm$body
![pic](pic.png)
"
expect inline-alt-nested-brackets 1 inline-alt "$good_fm$body
![[todo]](pic.png)
"
expect inline-alt-reference-style 1 inline-alt "$good_fm$body
![][r]

[r]: pic.png
"
expect inline-alt-in-draft-ok 0 - "$(fm_with 'draft:' 'draft: true')$nl$body
![](pic.png)
"
expect inline-alt-in-code-ok 0 - "$good_fm$body
\`\`\`
![](pic.png)
\`\`\`
"
expect inline-remote 1 image-remote "$good_fm$body
![A remote picture of a red square.](https://example.com/x.png)
"

# --- links, HTML, markers, guard words ---------------------------------------------------------------------------------
expect js-link 1 unsafe-link "$good_fm$body
[click](javascript:alert(1))
"
expect js-link-case-and-space 1 unsafe-link "$good_fm$body
[click](  JaVa	script:alert(1))
"
expect js-link-entity 1 unsafe-link "$good_fm$body
[click](&#106;avascript:alert(1))
"
expect js-link-reference 1 unsafe-link "$good_fm$body
[click][x]

[x]: javascript:alert(1)
"
expect data-link 1 unsafe-link "$good_fm$body
<a href=\"data:text/html;base64,AAAA\">x</a>
"
expect javascript-word-ok 0 - "$good_fm$body
JavaScript: the good parts, and a [link](https://example.com/js).
"
expect raw-script 1 raw-html "$good_fm$body
<script>alert(1)</script>
"
expect raw-script-split-by-comment 1 raw-html "$good_fm$body
<scr<!-- x -->ipt>alert(1)</script>
"
expect raw-iframe 1 raw-html "$good_fm$body
<iframe src=\"https://example.com\"></iframe>
"
expect raw-event-handler 1 raw-html "$good_fm$body
<img src=x onerror=alert(1)>
"
expect script-in-code-ok 0 - "$good_fm$body
Use \`<script>\` carefully.

\`\`\`html
<script>alert(1)</script>
\`\`\`
"
expect todo-published 1 todo "$good_fm$body
TODO write the ending.
"
expect todo-in-draft-ok 0 - "$(fm_with 'draft:' 'draft: true')$nl$body
TODO write the ending.
"
expect todo-in-code-ok 0 - "$good_fm$body
\`\`\`
# TODO in a code sample
\`\`\`
"
expect guard-builtin-word 1 guard-word "$good_fm$body
I studied for the ITIL exam.
"
terms="$work/terms.txt"
printf 'employer:Acme Widgets\nhostname:lab-box-9\n' >"$terms"
d="$(put guard-terms "$good_fm${body}Worked at ACME widgets once.
")"
rc=0
out="$(check_py --root "$d" --terms-file "$terms" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^guard-word: ' <<<"$out" && ! grep -qi 'acme' <<<"$out"; then
    ok "a term from the terms file fails and is never printed"
else bad "terms file (exit $rc): $out"; fi
rc=0
out="$(SCRUB_TERMS="$(cat "$terms")" check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && ! grep -qi 'acme' <<<"$out"; then ok "the SCRUB_TERMS variable works and is never printed"; else bad "SCRUB_TERMS (exit $rc): $out"; fi

# --- hostile front matter ------------------------------------------------------------------------------------------------
expect hostile-anchor 1 front-matter "---
title: &a x
date: 2026-11-08
description: d
---
"
expect hostile-alias 1 front-matter "---
title: *a
date: 2026-11-08
description: d
---
"
expect hostile-tag 1 front-matter "---
title: !!python/object/apply:os.system [id]
date: 2026-11-08
description: d
---
"
expect hostile-merge-key 1 front-matter "---
<<: *base
title: x
---
"
expect hostile-duplicate-key 1 front-matter "---
title: a
title: b
date: 2026-11-08
description: d
---
"
expect hostile-tab-indent 1 front-matter "---
title: a
build:
	x: 1
date: 2026-11-08
description: d
---
"
expect hostile-unclosed-quote 1 front-matter "---
title: \"never closed
date: 2026-11-08
description: d
---
"
expect hostile-bad-key 1 front-matter "---
title: a
not a key: 1
---
"
expect hostile-flow-nest 1 front-matter "---
title: a
tags: [[[[[[[[[[[x]]]]]]]]]]]
---
"
deep=""
for _ in $(seq 1 500); do deep="$deep  - x
"; done
expect hostile-too-many-lines 1 front-matter "---
title: a
aliases:
$deep---
"

# --- bounded and non-UTF-8 input ---------------------------------------------------------------------------------------------
d="$(repo huge)"
{
    printf '%s' "$good_fm"
    head -c 3000000 /dev/zero | tr '\0' 'a'
} >"$d/content/posts/p/index.md"
start=$SECONDS
rc=0
out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^size: content/posts/p/index.md' <<<"$out" && [[ $((SECONDS - start)) -lt 10 ]]; then
    ok "a 3 MB file is a size error, fast"
else bad "huge file (exit $rc, $((SECONDS - start))s): $out"; fi

# Near the cap, with patterns that would be quadratic in a naive scanner.
for pat in '![' '`' '<!--' '[' '<a'; do
    d="$(repo pathological)"
    {
        printf '%s' "$good_fm"
        python3 -I -c "import sys; sys.stdout.write(sys.argv[1] * (900000 // len(sys.argv[1])))" "$pat"
    } >"$d/content/posts/p/index.md"
    start=$SECONDS
    rc=0
    check_py --root "$d" content/posts/p/index.md >"$work/path.out" 2>&1 || rc=$?
    if [[ $rc -le 1 && $((SECONDS - start)) -lt 20 ]]; then
        ok "900 KB of '$pat' finishes in $((SECONDS - start))s (exit $rc)"
    else bad "900 KB of '$pat' (exit $rc, $((SECONDS - start))s)"; fi
done

d="$(repo nonutf8)"
printf -- '---\ntitle: "caf\xe9"\ndate: 2026-11-08\ndescription: d\n---\n' >"$d/content/posts/p/index.md"
rc=0
out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^encoding: content/posts/p/index.md' <<<"$out"; then ok "non-UTF-8 input is an encoding error"; else bad "non-UTF-8 (exit $rc): $out"; fi

d="$(repo nul)"
printf -- '---\ntitle: "a"\ndate: 2026-11-08\ndescription: d\n---\nx\0y\n' >"$d/content/posts/p/index.md"
rc=0
out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^encoding: ' <<<"$out"; then ok "a NUL byte is an encoding error"; else bad "NUL (exit $rc): $out"; fi

d="$(put symlink "$good_fm$body")"
ln -s index.md "$d/content/posts/p/other.md"
rc=0
out="$(check_py --root "$d" content/posts/p/other.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^file-type: .*symbolic link' <<<"$out"; then ok "a symbolic link is rejected"; else bad "symlink (exit $rc): $out"; fi

d="$(put fifo "$good_fm$body")"
mkfifo "$d/content/posts/p/pipe.md"
rc=0
out="$(check_py --root "$d" content/posts/p/pipe.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^file-type: .*not a regular file' <<<"$out"; then ok "a FIFO is rejected without blocking"; else bad "fifo (exit $rc): $out"; fi

# --- bundle images ------------------------------------------------------------------------------------------------------------------------
# img_case <name> <exit> <rule or -> <maker kind> <file name> [extra bytes] [list in manifest yes|no]
img_case() {
    local name="$1" want="$2" rule="$3" kind="$4" fname="$5" extra="${6:-0}" listed="${7:-yes}" d out rc=0
    d="$(put "img-$name" "$good_fm$body
![A test image used by the fixture.](<$fname>)
")"
    python3 -I "$mk" "$kind" "$d/content/posts/p/$fname" "$extra"
    if [[ "$listed" == yes ]]; then
        printf 'content/posts/p/%s | %s | test | looked at\n' "$fname" "$(sha256sum "$d/content/posts/p/$fname" | cut -d' ' -f1)" >>"$d/brand/approved-assets.txt"
    fi
    out="$(check_py --root "$d" "content/posts/p/$fname" 2>&1)" || rc=$?
    if [[ $rc -ne "$want" ]]; then
        bad "image $name (exit $rc, want $want): $out"
    elif [[ "$rule" != "-" ]] && ! grep -q "^$rule: content/posts/p/" <<<"$out"; then
        bad "image $name (rule $rule not reported): $out"
    else
        ok "image $name"
    fi
}
img_case good-png 0 - png pic.png
img_case good-jpg 0 - jpg pic.jpg
img_case good-webp 0 - webp pic.webp
img_case exif-png 1 image-metadata png-exif pic.png
img_case exif-jpg 1 image-metadata jpg-exif pic.jpg
img_case exif-webp 1 image-metadata webp-exif pic.webp
img_case uppercase-name 1 image-name png Pic.png
img_case space-name 1 image-name png 'my pic.png'
img_case leading-dot-name 1 image-name png .hidden.png
# svg_case <name> <exit> <code or -> <fixture kind>: the finding carries the [svg-...] code
svg_case() {
    local name="$1" want="$2" code="$3" kind="$4" d out rc=0
    d="$(put "svg-$name" "$good_fm$body
![A test image used by the fixture.](<pic.svg>)
")"
    python3 -I "$mk" "$kind" "$d/content/posts/p/pic.svg"
    printf 'content/posts/p/pic.svg | %s | test | looked at\n' "$(sha256sum "$d/content/posts/p/pic.svg" | cut -d' ' -f1)" >>"$d/brand/approved-assets.txt"
    out="$(check_py --root "$d" content/posts/p/pic.svg 2>&1)" || rc=$?
    if [[ $rc -ne "$want" ]]; then
        bad "svg $name (exit $rc, want $want): $out"
    elif [[ "$code" != "-" ]] && ! grep -q "^image-svg: content/posts/p/pic.svg: \[$code\]" <<<"$out"; then
        bad "svg $name (code $code not reported): $out"
    else
        ok "svg $name"
    fi
}
svg_case good-svg 0 - svg
svg_case good-svg-xml-declaration 0 - svg-xmldecl
svg_case good-svg-local-style-url 0 - svg-style-local
svg_case good-svg-local-marker-url 0 - svg-marker
svg_case script 1 svg-element svg-script
svg_case script-upper-case 1 svg-element svg-script-upper
svg_case script-mixed-case 1 svg-element svg-script-mixed
svg_case script-with-svg-prefix 1 svg-element svg-script-prefixed
svg_case script-in-xhtml-namespace 1 svg-namespace svg-script-xhtml
svg_case script-xhtml-default-namespace 1 svg-namespace svg-script-noprefix-ns
svg_case foreignObject 1 svg-element svg-foreign
svg_case animate 1 svg-element svg-animate
svg_case set 1 svg-element svg-set
svg_case use 1 svg-element svg-use
svg_case href 1 svg-href svg-href
svg_case href-upper-case 1 svg-href svg-href-upper
svg_case xlink-href 1 svg-namespace svg-xlink-href
svg_case onclick 1 svg-event-handler svg-onclick
svg_case onclick-case 1 svg-event-handler svg-onclick-case
svg_case onload-on-root 1 svg-event-handler svg-onload-root
svg_case unknown-attribute 1 svg-attribute svg-unknown-attr
svg_case fill-external-url 1 svg-external-ref svg-fill-url
svg_case fill-relative-url 1 svg-external-ref svg-fill-url-rel
svg_case style-external-url 1 svg-external-ref svg-style-url
svg_case style-import 1 svg-external-ref svg-style-import
svg_case style-css-escape 1 svg-external-ref svg-style-escape
svg_case javascript-scheme-in-attribute 1 svg-external-ref svg-js-attr
svg_case url-in-text 1 svg-external-ref svg-text-url
svg_case scheme-in-text 1 svg-external-ref svg-text-scheme
svg_case protocol-relative-in-text 1 svg-external-ref svg-text-protorel
svg_case url-in-desc 1 svg-external-ref svg-title-url
svg_case pi-stylesheet 1 svg-pi svg-pi-stylesheet
svg_case pi-wrapped-payload 1 svg-pi svg-pi-wrapped
svg_case pi-before-content 1 svg-pi svg-pi-late
svg_case comment 1 svg-comment svg-comment
svg_case cdata 1 svg-cdata svg-cdata
svg_case doctype 1 svg-doctype svg-doctype
svg_case doctype-entity-lower-case 1 svg-doctype svg-doctype-lower
svg_case foreign-namespace-declaration 1 svg-namespace svg-ns-other
svg_case no-namespace 1 svg-namespace svg-no-ns
svg_case no-viewbox 1 svg-viewbox svg-novb
svg_case utf16-with-bom 1 svg-encoding svg-utf16
svg_case utf16-le-no-bom 1 svg-encoding svg-utf16le
svg_case utf16-be-bom 1 svg-encoding svg-utf16be-bom
svg_case utf32 1 svg-encoding svg-utf32
svg_case utf8-bom 1 svg-encoding svg-utf8-bom
svg_case latin1-bytes 1 svg-encoding svg-latin1
svg_case declared-latin1 1 svg-encoding svg-declared-latin1
svg_case malformed 1 svg-parse svg-malformed
img_case wrong-type-gif 1 image-type png pic.gif
img_case too-big 1 image-size png pic.png 6000000
img_case unlisted 1 brand-asset png pic.png 0 no
img_case too-wide 1 image-dimensions png-wide pic.png
img_case too-many-pixels 1 image-dimensions png-huge pic.png

# unreferenced image: the page never uses it
d="$(put orphan "$good_fm$body")"
python3 -I "$mk" png "$d/content/posts/p/orphan.png"
printf 'content/posts/p/orphan.png | %s | test | looked at\n' "$(sha256sum "$d/content/posts/p/orphan.png" | cut -d' ' -f1)" >>"$d/brand/approved-assets.txt"
rc=0
out="$(check_py --root "$d" content/posts/p/orphan.png 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^image-unreferenced: content/posts/p/orphan.png' <<<"$out"; then ok "an image no page uses fails"; else bad "orphan (exit $rc): $out"; fi
printf '%s' "$good_fm$body
![An orphan that is now used.](orphan.png)
" >"$d/content/posts/p/index.md"
rc=0
out="$(check_py --root "$d" content/posts/p/orphan.png 2>&1)" || rc=$?
if [[ $rc -eq 0 ]]; then ok "the same image passes once the page uses it"; else bad "referenced (exit $rc): $out"; fi

# headline and inline images must be real files inside the page folder
expect headline-missing-file 1 image-remote "$(fm_with 'syndicate:' 'image: "nope.png"
imageAlt: "A description of the missing file."')$nl$body"
expect headline-climbs-out 1 image-remote "$(fm_with 'syndicate:' 'image: "../p/index.md"
imageAlt: "A description of a file outside the bundle."')$nl$body"
expect headline-absolute 1 image-remote "$(fm_with 'syndicate:' 'image: "/etc/hostname"
imageAlt: "A description of an absolute path."')$nl$body"
expect inline-missing-file 1 image-remote "$good_fm$body
![A picture that is not in the folder.](missing.png)
"
expect inline-climbs-out 1 image-remote "$good_fm$body
![A picture from another folder.](../p/index.md)
"
expect inline-encoded-climb 1 image-remote "$good_fm$body
![A picture from another folder.](%2e%2e/p/index.md)
"
expect inline-absolute 1 image-remote "$good_fm$body
![A picture at an absolute path.](/etc/hostname)
"

# slug
expect slug-missing 1 slug "$(fm_with 'slug:' '')$nl$body"
expect slug-uppercase 1 slug "$(fm_with 'slug:' 'slug: "My-Post"')$nl$body"
expect slug-space 1 slug "$(fm_with 'slug:' 'slug: "my post"')$nl$body"
expect slug-underscore 1 slug "$(fm_with 'slug:' 'slug: "my_post"')$nl$body"

d="$(put wrong-sha "$good_fm$body")"
python3 -I "$mk" png "$d/content/posts/p/pic.png"
printf 'content/posts/p/pic.png | %064d | test | looked at\n' 0 >>"$d/brand/approved-assets.txt"
rc=0
out="$(check_py --root "$d" content/posts/p/pic.png 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^brand-asset: content/posts/p/pic.png: ' <<<"$out"; then ok "a changed image fails the sha256 rule"; else bad "wrong sha (exit $rc): $out"; fi

d="$(put cap-flag "$good_fm$body")"
python3 -I "$mk" png "$d/content/posts/p/pic.png" 2000
printf 'content/posts/p/pic.png | %s | test | looked at\n' "$(sha256sum "$d/content/posts/p/pic.png" | cut -d' ' -f1)" >>"$d/brand/approved-assets.txt"
rc=0
out="$(check_py --root "$d" --max-image-bytes 1000 content/posts/p/pic.png 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^image-size: ' <<<"$out"; then ok "--max-image-bytes lowers the cap"; else bad "cap flag (exit $rc): $out"; fi

d="$(put other-file "$good_fm$body")"
printf 'x' >"$d/content/posts/p/notes.txt"
rc=0
out="$(check_py --root "$d" content/posts/p/notes.txt 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^file-type: ' <<<"$out"; then ok "a stray file type under content/ fails"; else bad "stray file (exit $rc): $out"; fi

# --- output shape, JSON and selecting files ------------------------------------------------------------------------------------------------------
d="$(put shape "$(fm_with 'title:' '')$nl$body")"
rc=0
out="$(check_py --root "$d" content/posts/p/index.md 2>&1)" || rc=$?
if grep -q '^title: content/posts/p/index.md: ' <<<"$out" && tail -n1 <<<"$out" | grep -q '^check-content: 1 error(s) in 1 file(s); checked 1'; then
    ok "errors print as rule: path: message with a summary line"
else bad "output shape: $out"; fi
rc=0
out="$(check_py --root "$d" --json content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && python3 -I -c '
import json, sys
j = json.loads(sys.argv[1])
assert j["ok"] is False and j["errors"][0]["rule"] == "title" and j["errors"][0]["path"] == "content/posts/p/index.md"
assert set(j) >= {"files", "markdown", "images"}' "$out"; then
    ok "--json prints one valid JSON object"
else bad "--json: $out"; fi
d="$(put clean-json "$good_fm$body")"
rc=0
out="$(check_py --root "$d" --json content/posts/p/index.md 2>&1)" || rc=$?
if [[ $rc -eq 0 ]] && python3 -I -c 'import json,sys; j=json.loads(sys.argv[1]); assert j["ok"] and j["errors"] == []' "$out"; then ok "--json on a clean file"; else bad "clean --json: $out"; fi

rc=0
check_py --bogus >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then ok "an unknown option is a usage error"; else bad "unknown option exit $rc, want 2"; fi

# Changed-file mode: only files changed against the base are checked.
d="$(repo gitmode)"
printf '%s%s%s' "$(fm_with 'title:' '')" "$nl" "$body" >"$d/content/posts/p/index.md" # an old, bad post
git -C "$d" init -q -b main
git -C "$d" -c user.name=t -c user.email=t@example.com add -A
git -C "$d" -c user.name=t -c user.email=t@example.com commit -q -m base
mkdir -p "$d/content/posts/q"
printf '%s%s' "$good_fm" "$body" >"$d/content/posts/q/index.md"
git -C "$d" add -A
git -C "$d" -c user.name=t -c user.email=t@example.com commit -q -m change
rc=0
out="$(check_py --root "$d" --base HEAD~1 2>&1)" || rc=$?
if [[ $rc -eq 0 ]] && grep -q 'ok (1 files' <<<"$out"; then ok "default mode checks only the files changed against the base"; else bad "changed mode (exit $rc): $out"; fi
rc=0
out="$(check_py --root "$d" --all 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^title: content/posts/p/index.md' <<<"$out"; then ok "--all checks existing content too"; else bad "--all (exit $rc): $out"; fi
printf 'x\n' >"$d/content/posts/p/untracked-note.txt"
rc=0
out="$(check_py --root "$d" --base HEAD~1 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q '^file-type: content/posts/p/untracked-note.txt' <<<"$out"; then ok "an untracked new file is checked"; else bad "untracked (exit $rc): $out"; fi
rm -f "$d/content/posts/p/untracked-note.txt"

exit "$fail"
