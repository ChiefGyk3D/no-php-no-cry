#!/usr/bin/env bash
# Prints the owner-approved business email from data/about.yaml, but only when the
# contact config is COMPLETE: email, pgp_fingerprint and pgp_url all non-empty.
# Prints nothing otherwise (fail closed), so no check ever allows an address the
# page does not publish. layouts/_partials/contact-complete.html is the same rule
# for the template; scripts/test-pages.sh holds the two together (issue 159).
#
#   scripts/about-email.sh [path/to/about.yaml]
set -euo pipefail
file="${1:-$(dirname "${BASH_SOURCE[0]}")/../data/about.yaml}"
get() { sed -n "s/^  $1: \"\\(.*\\)\"\$/\\1/p" "$file" | head -n 1; }
email="$(get email)"
fp="$(get pgp_fingerprint)"
url="$(get pgp_url)"
if [[ -n "$email" && -n "$fp" && -n "$url" ]]; then
    printf '%s\n' "$email"
fi
