#!/usr/bin/env bash
# Mirror docs/wiki/*.md into a clone of the GitHub wiki, rewriting internal links.
#
# docs/wiki stays the single source: its pages link to each other as `Page.md`, which
# is right in the repository browser. GitHub's wiki documents full wiki addresses for
# links between pages, so this script rewrites `Page.md` and `Page.md#anchor` to
# `https://github.com/<owner>/<repo>/wiki/Page` and `.../Page#anchor` in the copies.
# Fenced blocks and inline code are left alone. It exits non-zero, writing nothing,
# when a link points to a page that is not in docs/wiki or to any other relative path
# (which would be dead on the wiki).
#
# usage: scripts/publish-wiki.sh <wiki-clone-dir> [source-dir]
# It only writes files; committing and pushing stay a separate, reviewed step.
# No network access, no credentials.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <wiki-clone-dir> [source-dir]" >&2
    exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$1"
src="${2:-$root/docs/wiki}"
base="${WIKI_BASE:-https://github.com/ChiefGyk3D/no-php-no-cry/wiki}"

[[ -d "$dest" ]] || {
    echo "publish-wiki: not a directory: $dest" >&2
    exit 2
}
[[ -d "$src" ]] || {
    echo "publish-wiki: not a directory: $src" >&2
    exit 2
}

timeout 60 python3 -I - "$src" "$dest" "$base" <<'PY'
import os, re, sys

src, dest, base = sys.argv[1:4]
pages = sorted(f for f in os.listdir(src) if f.endswith(".md"))
if not pages:
    print("publish-wiki: no pages in", src, file=sys.stderr)
    sys.exit(1)
names = {p[:-3] for p in pages}

span = re.compile(r"(`+[^`]*`+)")
# An unescaped inline link: a [label] then (destination, optional title).
link = re.compile(r"""((?<!\\)\[[^\]\n]*\]\(\s*)(<[^>\n]+>|[^)\s]+)((?:\s+(?:"[^"]*"|'[^']*'))?\s*\))""")
fence = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
errors, rewritten, out = [], 0, {}


def fix(target, page, n):
    global rewritten
    if re.match(r"^([a-zA-Z][a-zA-Z0-9+.-]*:|#|/)", target):
        return target
    path, _, anchor = target.partition("#")
    if path.endswith(".md") and "/" not in path:
        if path[:-3] in names:
            rewritten += 1
            return base + "/" + path[:-3] + ("#" + anchor if anchor else "")
        errors.append(f"{page}:{n}: link to missing page {path}")
        return target
    errors.append(f"{page}:{n}: relative link not valid on the wiki: {path}")
    return target


def fix_dest(dest_text, page, n):
    if dest_text.startswith("<") and dest_text.endswith(">"):
        return "<" + fix(dest_text[1:-1], page, n) + ">"
    return fix(dest_text, page, n)


for page in pages:
    lines, opener = [], None
    with open(os.path.join(src, page), encoding="utf-8") as fh:
        for n, line in enumerate(fh.read().split("\n"), 1):
            m = fence.match(line)
            if opener is None and m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
                opener = m.group(1)
                lines.append(line)
                continue
            if opener is not None:
                if m and m.group(1)[0] == opener[0] and len(m.group(1)) >= len(opener) and not m.group(2).strip():
                    opener = None
                lines.append(line)
                continue
            parts = span.split(line)
            for i in range(0, len(parts), 2):
                parts[i] = link.sub(lambda m: m.group(1) + fix_dest(m.group(2), page, n) + m.group(3), parts[i])
            lines.append("".join(parts))
    out[page] = "\n".join(lines)

if errors:
    for e in errors:
        print("publish-wiki: " + e, file=sys.stderr)
    print(f"publish-wiki: {len(errors)} problem(s), nothing written", file=sys.stderr)
    sys.exit(1)

for page, text in out.items():
    with open(os.path.join(dest, page), "w", encoding="utf-8") as fh:
        fh.write(text)
removed = 0
for f in sorted(os.listdir(dest)):
    if f.endswith(".md") and f not in out and os.path.isfile(os.path.join(dest, f)):
        os.remove(os.path.join(dest, f))
        print("publish-wiki: removed stale page", f)
        removed += 1
print(f"publish-wiki: ok ({len(pages)} pages written, {rewritten} links rewritten, {removed} stale removed)")
PY
