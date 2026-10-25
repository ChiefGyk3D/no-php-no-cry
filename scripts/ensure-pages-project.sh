#!/usr/bin/env bash
# Make sure the Cloudflare Pages project exists, creating it when it is missing.
#
# Idempotent: an existing project is left alone. Reads the token from the
# environment and gives it to curl on stdin, so it never appears in a process
# list or a log.
#
# Environment:
#   CLOUDFLARE_API_TOKEN    token with Account > Cloudflare Pages > Edit
#   CLOUDFLARE_ACCOUNT_ID   32 hex characters
#   CLOUDFLARE_PAGES_PROJECT  project name, lowercase letters, digits, hyphens
#   PRODUCTION_BRANCH       branch Pages treats as production (default main)
#   CF_API_BASE             override for tests (default the real API)
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is not set}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is not set}"
: "${CLOUDFLARE_PAGES_PROJECT:?CLOUDFLARE_PAGES_PROJECT is not set}"
branch="${PRODUCTION_BRANCH:-main}"
base="${CF_API_BASE:-https://api.cloudflare.com/client/v4}"

[[ "$CLOUDFLARE_ACCOUNT_ID" =~ ^[0-9a-f]{32}$ ]] || {
    echo "::error title=Pages project::CLOUDFLARE_ACCOUNT_ID is not 32 hex characters"
    exit 1
}
[[ "$CLOUDFLARE_PAGES_PROJECT" =~ ^[a-z0-9-]{1,58}$ ]] || {
    echo "::error title=Pages project::CLOUDFLARE_PAGES_PROJECT is not a valid project name"
    exit 1
}
[[ "$branch" =~ ^[A-Za-z0-9._/-]{1,100}$ ]] || {
    echo "::error title=Pages project::PRODUCTION_BRANCH has unexpected characters"
    exit 1
}

url="$base/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT

# api <method> <url> [json]: prints the HTTP status, leaves the response in $body.
api() {
    local method="$1" target="$2" data="${3:-}"
    local args=(-sS -K - -o "$body" -w '%{http_code}' -X "$method" --max-time 30)
    if [[ -n "$data" ]]; then
        args+=(-H 'Content-Type: application/json' --data "$data")
    fi
    printf 'header = "Authorization: Bearer %s"\n' "$CLOUDFLARE_API_TOKEN" |
        curl "${args[@]}" "$target"
}

status="$(api GET "$url/$CLOUDFLARE_PAGES_PROJECT")"
case "$status" in
    200)
        echo "Pages project $CLOUDFLARE_PAGES_PROJECT already exists."
        exit 0
        ;;
    404) ;;
    *)
        echo "::error title=Pages project::looking up the project returned HTTP $status (check the token has Account > Cloudflare Pages > Edit)"
        exit 1
        ;;
esac

echo "Pages project $CLOUDFLARE_PAGES_PROJECT is missing; creating it."
status="$(api POST "$url" "{\"name\":\"$CLOUDFLARE_PAGES_PROJECT\",\"production_branch\":\"$branch\"}")"
if [[ "$status" != "200" ]]; then
    echo "::error title=Pages project::creating the project returned HTTP $status"
    exit 1
fi
echo "Created Pages project $CLOUDFLARE_PAGES_PROJECT (production branch $branch)."
