#!/usr/bin/env bash
# Usage: scripts/pin-theme.sh [--check] [theme-file]     (default: static/theme.js)
#
# Pins the theme script by hash. The build accepts /theme.js only when its sha256
# equals the line in theme.js.sha256 at the repository root (override the path
# with THEME_HASH_FILE), so a change to the script needs a reviewed change to
# that file in the same pull request.
#
#   pin-theme.sh [file]           write the hash file: one line,
#                                 "<sha256>  theme.js" (sha256sum format). The
#                                 script must be under 1 KB gzip.
#   pin-theme.sh --check [file]   exit 1 unless the hash file matches the script
#
# Exit codes: 0 ok, 1 refused or mismatch, 2 usage or missing file.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/artifact-rules.sh
source "$root/scripts/artifact-rules.sh"
hash_file="${THEME_HASH_FILE:-$root/theme.js.sha256}"

mode="write"
if [[ "${1:-}" == --check ]]; then
    mode=check
    shift
fi
if [[ $# -gt 1 ]]; then
    echo "usage: pin-theme.sh [--check] [theme-file]" >&2
    exit 2
fi
theme="${1:-$root/static/theme.js}"
[[ -f "$theme" ]] || {
    echo "pin-theme: no such file: $theme" >&2
    exit 2
}

sum="$(sha256sum "$theme" | cut -d' ' -f1)"
if [[ $mode == check ]]; then
    rc=0
    pinned="$(theme_hash_state "$hash_file")" || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "pin-theme: no valid hash file at $hash_file" >&2
        exit 1
    fi
    if [[ "$pinned" != "$sum" ]]; then
        echo "pin-theme: $theme does not match $hash_file (run scripts/pin-theme.sh)" >&2
        exit 1
    fi
    echo "pin-theme: ok ($sum)"
    exit 0
fi

gz="$(gzip -9 -n -c "$theme" | wc -c)"
if ((gz >= 1024)); then
    echo "pin-theme: $theme is ${gz} bytes gzip (budget: under 1024)" >&2
    exit 1
fi
printf '%s  theme.js\n' "$sum" >"$hash_file"
echo "pin-theme: wrote $hash_file ($sum)"
