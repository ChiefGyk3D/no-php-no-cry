#!/usr/bin/env bash
# Test /llms.txt (layouts/home.llms.txt) against a real build of this site.
#
# Builds into the repository's gitignored tmp/ (never /tmp) and asserts: the file
# exists in production and staging builds, follows the llms.txt shape (H1, "> "
# summary, H2 sections), links every section the site has and the first post,
# lists every https URL of data/socials.yaml and data/support.yaml, carries no
# affiliate link from data/products.yaml and no wallet address. A guard
# self-test feeds the checker a bad file for each rule and requires a failure.
# Needs the pinned Hugo; a missing Hugo is a failure, not a skip.
set -euo pipefail
exit 1 # scratch broken-leg CI proof, issue 185

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/llms.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

if ! command -v hugo >/dev/null 2>&1; then
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
fi

failures=0
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# wallet_addresses: the value of every "address:" key in data/support.yaml, quotes
# stripped, one per line.
wallet_addresses() {
    grep -hE '^[[:space:]]*(-[[:space:]]+)?address:' "$root/data/support.yaml" | sed -E 's/^[^:]*:[[:space:]]*//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

# check_llms <file>: prints one line per violation.
check_llms() {
    local f="$1" n=0 path url
    [[ -s "$f" ]] || {
        echo "missing or empty"
        return 0
    }
    head -n1 "$f" | grep -qE '^# .+' || echo "no H1 first line"
    grep -qE '^> .+' "$f" || echo "no summary line"
    for h in "## Sections" "## Latest posts" "## Feeds" "## Find me online" "## Support"; do
        grep -qxF "$h" "$f" || echo "no section: $h"
    done
    for path in posts journal social support products about resume privacy posts/sample-post; do
        grep -qE "\]\(https://[^/)]+/${path}/\)" "$f" || echo "no link to /${path}/"
    done
    # Every https URL in the data files must be listed (kind: cryptocurrency has none).
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        grep -qF "]($url)" "$f" || echo "missing data link: $url"
        n=$((n + 1))
    done < <(grep -hE '^[[:space:]]*(-[[:space:]]+)?url:[[:space:]]*https://' "$root/data/socials.yaml" "$root/data/support.yaml" | sed -E 's/^[^:]*:[[:space:]]*//')
    [[ $n -gt 0 ]] || echo "no data links read (test bug)"
    # No affiliate link, no wallet address.
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        ! grep -qF "$url" "$f" || echo "affiliate link listed: $url"
    done < <(grep -hE '^[[:space:]]*url:[[:space:]]*https://' "$root/data/products.yaml" | sed -E 's/^[^:]*:[[:space:]]*//')
    # Every address: in data/support.yaml (Bitcoin, Monero, Ethereum, Solana, ...).
    n=0
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        ! grep -qF "$url" "$f" || echo "wallet address listed: ${url:0:8}..."
        n=$((n + 1))
    done < <(wallet_addresses)
    [[ $n -ge 4 ]] || echo "fewer than 4 wallet addresses read (test bug)"
    ! grep -qE 'bc1q[a-z0-9]{20}|0x[0-9a-fA-F]{40}' "$f" || echo "wallet address listed"
    # Layout: "## " only at the start of a line, and each H2 is followed by a blank
    # line or a list item on its own line (never glued to the first item).
    ! grep -qE '.## ' "$f" || echo "H2 marker mid-line"
    awk '/^## / { h = $0; getline nx; if (nx !~ /^$/ && nx !~ /^- \[/) print "H2 not followed by blank or list item: " h }' "$f"
    ! grep -qE '<|javascript:|http://' "$f" || echo "markup or http link"
    return 0
}

build() { # build <dest> [env]
    (cd "$root" && HUGO_PARAMS_ENVIRONMENT="${2:-production}" hugo --minify --gc --destination "$1" >/dev/null)
}

for env in production staging; do
    build "$work/$env" "$env"
    out="$(check_llms "$work/$env/llms.txt")"
    if [[ -n "$out" ]]; then
        fail "$env llms.txt: $(tr '\n' ';' <<<"$out")"
    else
        echo "ok: $env llms.txt"
    fi
done

# Guard self-test: each mutation of a good file must be caught.
good="$work/production/llms.txt"
guard() { # guard <label> <sed-expr>
    sed -E "$2" "$good" >"$work/bad.txt"
    if [[ -z "$(check_llms "$work/bad.txt")" ]]; then
        fail "guard: $1 was not caught"
    else
        echo "ok: guard catches $1"
    fi
}
guard "no H1" '1s/^# /x /'
guard "no summary" 's/^> /x /'
guard "dropped posts link" 's#\]\(https://[^/)]+/posts/\)#](x)#'
guard "dropped data link" 's#\]\(https://github\.com/ChiefGyk3D\)#](x)#'
guard "http link" 's#\(https://github#(http://github#'
# One planted address per coin, taken from data/support.yaml, so every coin is caught.
while IFS= read -r addr; do
    guard "wallet ${addr:0:6}..." "\$a ${addr}"
done < <(wallet_addresses)
guard "H2 glued to first item" '/^## Sections$/{N;s/\n//}'
guard "H2 mid-line" 's/^(- \[Posts\].*)$/\1 ## x/'
: >"$work/empty.txt"
[[ -n "$(check_llms "$work/empty.txt")" ]] && echo "ok: guard catches empty file" || fail "guard: empty file not caught"

if [[ $failures -gt 0 ]]; then
    echo "test-llms: $failures failure(s)"
    exit 1
fi
echo "test-llms: ok"
