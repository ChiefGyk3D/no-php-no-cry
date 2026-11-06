#!/usr/bin/env bash
# Usage: scripts/check-wording.sh [repo-dir]      (default: the repository root)
#
# Wording rule (brand/README.md, "Wording"): the short form of cryptocurrency
# never appears anywhere in the repository: not in pages, data, docs, scripts or
# CSS class names. Write "cryptocurrency" or the coin name. Words that really
# mean cryptography (cryptography, cryptographic, cryptosystem) are fine, and so
# is any longer word that starts with the same letters and is not the bare short
# form. The pattern is a negative lookahead on the bare word.
#
# Scans tracked and untracked-but-not-ignored text files (git ls-files), or every
# file under the directory when it is not a git checkout. This script and its
# test are skipped because they have to name the pattern. tools/axe/ is skipped
# too: it is the vendored, checksum-pinned axe-core build (third-party minified
# code that reads the browser's own crypto object), not text we write.
# Exit codes: 0 clean, 1 a finding, 2 usage.
set -euo pipefail

dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -d "$dir" ]] || {
    echo "usage: check-wording.sh [repo-dir]" >&2
    exit 2
}
cd "$dir"

# "cry" + "pto" so this file does not match itself.
pat="\\b$(printf 'cry%s' pto)(?!graph|system)\\b"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    list() { git ls-files -z -c -o --exclude-standard; }
else
    list() { find . -type f -not -path './.git/*' -print0; }
fi

found=0
while IFS= read -r -d '' f; do
    case "$f" in
        scripts/check-wording.sh | scripts/test-check-wording.sh) continue ;;
        tools/axe/* | ./tools/axe/*) continue ;;
    esac
    [[ -f "$f" ]] || continue
    if grep -IqiP -- "$pat" "$f" 2>/dev/null; then
        grep -InP -i -- "$pat" "$f" | sed "s#^#[wording] $f:#" | cut -c1-200
        found=1
    fi
done < <(list)

if [[ $found -ne 0 ]]; then
    echo "check-wording: use 'cryptocurrency' (or the coin name), never the short form"
    exit 1
fi
echo "check-wording: ok"
