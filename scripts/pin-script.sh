#!/usr/bin/env bash
# Usage: scripts/pin-script.sh [--check] [script-file]     (default: static/copy.js)
#
# Pins the copy script by hash. The build accepts /copy.js only when its sha256
# equals the line in copy.js.sha256 at the repository root (override the path
# with SCRIPT_HASH_FILE), so a change to the script needs a reviewed change to
# that file in the same pull request.
#
#   pin-script.sh [file]           write the hash file: one line,
#                                 "<sha256>  copy.js" (sha256sum format). The
#                                 script must be under 1 KB gzip.
#   pin-script.sh --check [file]   exit 1 unless the hash file matches the script
#
# Exit codes: 0 ok, 1 refused or mismatch, 2 usage or missing file.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/artifact-rules.sh
source "$root/scripts/artifact-rules.sh"
hash_file="${SCRIPT_HASH_FILE:-$root/copy.js.sha256}"

mode="write"
if [[ "${1:-}" == --check ]]; then
    mode=check
    shift
fi
if [[ $# -gt 1 ]]; then
    echo "usage: pin-script.sh [--check] [script-file]" >&2
    exit 2
fi
script_file="${1:-$root/static/copy.js}"
[[ -f "$script_file" ]] || {
    echo "pin-script: no such file: $script_file" >&2
    exit 2
}

sum="$(sha256sum "$script_file" | cut -d' ' -f1)"
if [[ $mode == check ]]; then
    rc=0
    pinned="$(script_hash_state "$hash_file")" || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "pin-script: no valid hash file at $hash_file" >&2
        exit 1
    fi
    if [[ "$pinned" != "$sum" ]]; then
        echo "pin-script: $script_file does not match $hash_file (run scripts/pin-script.sh)" >&2
        exit 1
    fi
    echo "pin-script: ok ($sum)"
    exit 0
fi

gz="$(gzip -9 -n -c "$script_file" | wc -c)"
if ((gz >= 1024)); then
    echo "pin-script: $script_file is ${gz} bytes gzip (budget: under 1024)" >&2
    exit 1
fi
printf '%s  copy.js\n' "$sum" >"$hash_file"
echo "pin-script: wrote $hash_file ($sum)"
