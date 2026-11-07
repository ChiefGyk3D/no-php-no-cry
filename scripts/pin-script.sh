#!/usr/bin/env bash
# Usage: scripts/pin-script.sh [--check] [script-file]
#        (default: every pinned script, static/copy.js and static/search.js)
#
# Pins a script by hash. The site ships exactly the scripts on the allowlist in
# scripts/artifact-rules.sh, copy.js (loaded by /support/ only) and search.js
# (loaded by /search/ only). The build accepts a script only when its sha256
# equals the line in its own hash file, <name>.sha256 at the repository root
# (override the directory with SCRIPT_HASH_DIR), so a change to a script needs a
# reviewed change to that file in the same pull request. The hash file is named
# after the script file's name; a name that is not on the allowlist is refused.
#
#   pin-script.sh [file]           write the hash file: one line,
#                                 "<sha256>  <name>" (sha256sum format). The
#                                 script must be under 1 KB gzip.
#   pin-script.sh --check [file]   exit 1 unless the hash file matches the script
#
# Exit codes: 0 ok, 1 refused or mismatch, 2 usage, unknown script or missing file.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/artifact-rules.sh
source "$root/scripts/artifact-rules.sh"

mode="write"
if [[ "${1:-}" == --check ]]; then
    mode=check
    shift
fi
if [[ $# -gt 1 ]]; then
    echo "usage: pin-script.sh [--check] [script-file]" >&2
    exit 2
fi

# pin_one <script file>: pins or checks one script; prints its result, returns
# the exit code.
pin_one() {
    local script_file="$1" name hash_file sum pinned gz rc=0
    name="$(basename "$script_file")"
    pinned_script_page "$name" >/dev/null || {
        echo "pin-script: $name is not a pinned script (allowed: $(pinned_script_names | paste -sd' ' -))" >&2
        return 2
    }
    [[ -f "$script_file" ]] || {
        echo "pin-script: no such file: $script_file" >&2
        return 2
    }
    hash_file="$(pinned_hash_file "$name")"
    sum="$(sha256sum "$script_file" | cut -d' ' -f1)"
    if [[ $mode == check ]]; then
        pinned="$(script_hash_state "$hash_file" "$name")" || rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "pin-script: no valid hash file at $hash_file" >&2
            return 1
        fi
        if [[ "$pinned" != "$sum" ]]; then
            echo "pin-script: $script_file does not match $hash_file (run scripts/pin-script.sh)" >&2
            return 1
        fi
        echo "pin-script: ok ($name $sum)"
        return 0
    fi
    gz="$(gzip -9 -n -c "$script_file" | wc -c)"
    if ((gz >= $(script_gzip_budget))); then
        echo "pin-script: $script_file is ${gz} bytes gzip (budget: under $(script_gzip_budget))" >&2
        return 1
    fi
    printf '%s  %s\n' "$sum" "$name" >"$hash_file"
    echo "pin-script: wrote $hash_file ($sum)"
}

if [[ $# -eq 1 ]]; then
    pin_one "$1"
    exit $?
fi
status=0
while IFS= read -r name; do
    rc=0
    pin_one "$root/static/$name" || rc=$?
    ((rc > status)) && status=$rc
done < <(pinned_script_names)
exit "$status"
