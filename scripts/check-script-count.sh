#!/usr/bin/env bash
# Docs and comments must not state a stale count of pinned scripts (issue 271).
#
# The site ships the scripts listed in PINNED_SCRIPTS in scripts/artifact-rules.sh
# (copy.js, search.js and share.js today). This check fails on a tracked text file that
# still says "two pinned scripts", "one of the two pinned scripts", "those two", "the
# two pinned ones" and the like, printing "[stale-script-count] file:line".
#
# Usage: scripts/check-script-count.sh [repo-dir]   (default: the repository root)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${1:-$here/..}"
cd "$dir"
pattern='(\btwo|\b2) (small |pinned |hash-pinned )+(scripts?|ones|files)|(one of|only|both|those|these) (of )?the two (pinned|scripts)|\bthe two pinned\b|those two the only|\bonly (the )?two names\b|\bexactly two\b.{0,30}(copy|search)\.js|\btwo pinned scripts\b'
if [[ -e .git ]]; then
    files="$(git ls-files -z | tr '\0' '\n')"
else
    files="$(find . -type f -not -path './.git/*' | sed 's#^\./##')"
fi
rc=0
while IFS= read -r f; do
    case "$f" in
        scripts/check-script-count.sh | scripts/test-check-script-count.sh | docs/redesign-brief.md | tools/axe/* | brand/* | *.png | *.webp | *.ttf | *.woff2 | *.asc) continue ;;
    esac
    [[ -f "$f" ]] || continue
    if hits="$(grep -nIiE -- "$pattern" "$f" 2>/dev/null)"; then
        while IFS= read -r line; do
            echo "[stale-script-count] $f:${line%%:*}"
        done <<<"$hits"
        rc=1
    fi
done <<<"$files"
[[ $rc -ne 0 ]] || echo "ok: no stale pinned-script count"
exit $rc
