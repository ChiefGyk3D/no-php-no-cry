#!/usr/bin/env bash
# Check the brand asset manifest against the tree.
#
# Usage: scripts/check-brand-assets.sh [repo-root]      (default: this repo)
#
# Fails when: a file under static/brand/ or static/fonts/, or an image or font
# anywhere under content/ or assets/, is not listed in brand/approved-assets.txt,
# a listed file is missing, a listed file's sha256 differs, a file name is on
# the ban list, or a font has no OFL.txt beside it (Orbitron also needs
# OFL-Orbitron.txt).
# Findings are printed as plain sentences naming the path.
set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
manifest="$root/brand/approved-assets.txt"
findings=0

report() {
    printf '%s\n' "$1"
    findings=$((findings + 1))
}

if [[ ! -f "$manifest" ]]; then
    echo "brand/approved-assets.txt is missing"
    exit 1
fi

# Names that must never ship, matched case-insensitively against the path.
banned='twitter v2|do not use|star|cyber'

declare -A listed=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    path="${line%% | *}"
    rest="${line#* | }"
    sum="${rest%% | *}"
    listed["$path"]="$sum"
    if [[ ! -f "$root/$path" ]]; then
        report "$path is listed but missing"
        continue
    fi
    actual="$(sha256sum "$root/$path" | cut -d' ' -f1)"
    if [[ "$actual" != "$sum" ]]; then
        report "$path: sha256 mismatch (manifest $sum, file $actual)"
    fi
done <"$manifest"

while IFS= read -r -d '' file; do
    rel="${file#"$root"/}"
    if [[ -z "${listed[$rel]+x}" ]]; then
        report "$rel is not in approved-assets.txt"
    fi
    # A post bundle folder name is the page slug (URL text), so the ban is
    # matched on what follows it: the file name and any folder below it.
    ban_part="$rel"
    if [[ "$rel" == content/posts/*/* ]]; then
        ban_part="${rel#content/posts/*/}"
    fi
    if printf '%s' "$ban_part" | grep -q -i -E "$banned"; then
        report "$rel has a banned name"
    fi
done < <(
    find "$root/static/brand" "$root/static/fonts" -type f -print0 2>/dev/null
    find "$root/content" "$root/assets" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' -o -iname '*.ico' -o -iname '*.svg' -o -iname '*.woff' -o -iname '*.woff2' -o -iname '*.ttf' -o -iname '*.otf' \) -print0 2>/dev/null
)

if compgen -G "$root/static/fonts/*.woff2" >/dev/null || compgen -G "$root/static/fonts/*.ttf" >/dev/null; then
    [[ -f "$root/static/fonts/OFL.txt" ]] || report "static/fonts has a font but no OFL.txt license text"
fi
if compgen -G "$root/static/fonts/orbitron*" >/dev/null && [[ ! -f "$root/static/fonts/OFL-Orbitron.txt" ]]; then
    report "static/fonts has Orbitron but no OFL-Orbitron.txt license text"
fi

if ((findings > 0)); then
    exit 1
fi
echo "brand assets match approved-assets.txt"
