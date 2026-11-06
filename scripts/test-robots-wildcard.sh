#!/usr/bin/env bash
# Test the shared robots.txt wildcard parser (scripts/robots-wildcard.sh) and
# that scripts/check-output.sh and scripts/verify-live.sh both use it instead of
# carrying their own copy. Guard self-test: a script that defines its own
# robots_wildcard is reported.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/scripts/robots-wildcard.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/robots-wildcard.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

if [[ ! -f "$lib" ]]; then
    fail "scripts/robots-wildcard.sh does not exist"
    echo "$failures failure(s)"
    exit 1
fi
# shellcheck source=scripts/robots-wildcard.sh
source "$lib"

# parse <label> <expected flags> <robots.txt text (printf format)>
parse() {
    local got
    printf '%b' "$3" >"$work/robots.txt"
    got="$(robots_wildcard "$work/robots.txt")"
    if [[ "$got" == "$2" ]]; then
        pass "$1"
    else
        fail "$1: got '$got', wanted '$2'"
    fi
}
parse "allow-all group" "1 0 1 0" 'User-agent: *\nAllow: /\n'
parse "disallow everything" "1 1 0 0" 'User-agent: *\nDisallow: /\n'
parse "a partial disallow" "1 0 0 1" 'User-agent: *\nDisallow: /private/\n'
parse "empty disallow means allow" "1 0 0 0" 'User-agent: *\nDisallow:\n'
parse "another crawler's group says nothing" "0 0 0 0" 'User-agent: Googlebot\nDisallow: /\n'
parse "a rule before any User-agent says nothing" "1 0 1 0" 'Disallow: /\nUser-agent: *\nAllow: /\n'
parse "consecutive User-agent lines share a group" "1 1 0 0" 'User-agent: Googlebot\nUser-agent: *\nDisallow: /\n'
parse "a new group resets the wildcard" "1 0 1 0" 'User-agent: *\nAllow: /\nUser-agent: Bingbot\nDisallow: /\n'
parse "comments and CRLF are ignored" "1 1 0 0" 'User-agent: * # all\r\nDisallow: / # nothing\r\n'
parse "no content" "0 0 0 0" ''

# Both scripts source the helper and carry no copy of the parser.
uses_shared() { # uses_shared <script>: sources the helper, defines no function of its own
    grep -q 'robots-wildcard.sh' "$1" && ! grep -qE '^robots_wildcard\(\)' "$1"
}
for s in check-output verify-live; do
    if uses_shared "$root/scripts/$s.sh"; then
        pass "$s.sh uses the shared parser"
    else
        fail "$s.sh does not source scripts/robots-wildcard.sh, or still defines its own robots_wildcard"
    fi
done
# Guard self-test: the check bites on a copy that defines its own parser.
printf '#!/usr/bin/env bash\nrobots_wildcard() {\n    :\n}\n' >"$work/own.sh"
if uses_shared "$work/own.sh"; then
    fail "guard: a script with its own robots_wildcard was accepted"
else
    pass "guard: a script with its own robots_wildcard is reported"
fi

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all robots-wildcard checks passed"
