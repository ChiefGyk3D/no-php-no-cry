#!/usr/bin/env bash
# Check the brand asset manifest against the tree.
#
# Usage: scripts/check-brand-assets.sh [repo-root]      (default: this repo)
#
# Fails when: a file under static/brand/ or static/fonts/ is not listed in
# brand/approved-assets.txt, a listed file is missing, a listed file's sha256
# differs, a file name is on the ban list, or a font has no OFL.txt beside it.
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
banned='twitter v2|do not use|star'

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
    if printf '%s' "$rel" | grep -q -i -E "$banned"; then
        report "$rel has a banned name"
    fi
done < <(find "$root/static/brand" "$root/static/fonts" -type f -print0 2>/dev/null)

if compgen -G "$root/static/fonts/*.woff2" >/dev/null && [[ ! -f "$root/static/fonts/OFL.txt" ]]; then
    report "static/fonts has a font but no OFL.txt license text"
fi

if ((findings > 0)); then
    exit 1
fi
echo "brand assets match approved-assets.txt"
