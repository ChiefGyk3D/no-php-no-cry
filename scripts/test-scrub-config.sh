#!/usr/bin/env bash
# The scrub term list lives in the owner-only secrets config stg_scrub. Any
# tracked file that names a secrets config for SCRUB_TERMS must name stg_scrub
# and nothing else, and the docs must say the CI deploy identity cannot read it.
# The checks are functions so the fixtures at the bottom can prove they bite.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
allowed="stg_scrub"
fail=0
bad() {
    echo "FAIL: $*" >&2
    fail=1
}

# cmd_values <line>: every value that follows --config (space or = form).
cmd_values() {
    grep -oE -- '--config[ =][^ ]*' <<<"$1" | sed -E 's/^--config[ =]//; s/["'"'"'`;|).,]+$//' || true
}

# cmd_line_bad <line>: succeeds when the line names any config but stg_scrub.
cmd_line_bad() {
    local v
    while IFS= read -r v; do
        [[ "$v" == "$allowed" ]] || return 0
    done < <(cmd_values "$1")
    return 1
}

# prose_names <file>: every backtick-delimited name that follows the word
# config(s) in prose, one per line, including lists such as config `a` and `b`.
prose_names() {
    { grep -oE 'configs? `[^`]+`(,? (and |or )?`[^`]+`)*' "$1" || true; } |
        { grep -oE '`[^`]+`' || true; } | tr -d '`'
}

# prose_bad <file>: succeeds when the prose names any config but stg_scrub.
prose_bad() {
    local v
    while IFS= read -r v; do
        [[ "$v" == "$allowed" ]] || return 0
    done < <(prose_names "$1")
    return 1
}

if [[ "${1:-}" != "--fixtures-only" ]]; then
    # 1. Every command line that touches SCRUB_TERMS in the secret manager uses
    #    only --config stg_scrub.
    while IFS=: read -r f n line; do
        if cmd_line_bad "$line"; then
            bad "$f:$n names a config other than stg_scrub for SCRUB_TERMS"
        fi
    done < <(git grep -nI 'SCRUB_TERMS' -- . ':!scripts/test-scrub-config.sh' | grep -E -- '--config' || true)

    # 2. The prose names no config other than stg_scrub for the term list.
    prose_bad docs/scrub-terms.md && bad "docs/scrub-terms.md names a config other than stg_scrub"
    grep -q 'config `stg_scrub`' docs/scrub-terms.md || bad "docs/scrub-terms.md does not name config stg_scrub"
    grep -q 'owner-only environment that the CI deploy identity cannot read' docs/scrub-terms.md ||
        bad "docs/scrub-terms.md lacks the owner-only sentence"
fi

# 3. Fixtures: each check must accept the good form and reject the bad ones.
expect_cmd() { # <good|bad> <line>
    local got=good
    cmd_line_bad "$2" && got=bad
    [[ "$got" == "$1" ]] || bad "fixture expected $1 for command line: $2"
}
expect_prose() { # <good|bad> <text>
    local tmp got=good
    tmp="$(mktemp)"
    printf '%s\n' "$2" >"$tmp"
    prose_bad "$tmp" && got=bad
    rm -f "$tmp"
    [[ "$got" == "$1" ]] || bad "fixture expected $1 for prose: $2"
}
expect_cmd good 'doppler secrets get SCRUB_TERMS --config stg_scrub --plain'
expect_cmd good 'doppler secrets get SCRUB_TERMS --config=stg_scrub --plain'
expect_cmd bad 'doppler secrets get SCRUB_TERMS --config stg_scrub_backup --plain'
expect_cmd bad 'doppler secrets get SCRUB_TERMS --config stg_scrub --config dev'
expect_cmd bad 'doppler secrets get SCRUB_TERMS --config dev --config stg_scrub'
expect_cmd bad 'doppler secrets get SCRUB_TERMS --config=prd'
expect_prose good 'Doppler project `x`, config `stg_scrub`, secret `SCRUB_TERMS`.'
expect_prose bad 'Doppler project `x`, config `qa`, secret `SCRUB_TERMS`.'
expect_prose bad 'Doppler project `x`, config `stg_scrub_backup`.'
expect_prose bad 'Use configs `stg_scrub` and `dev` for it.'
expect_prose bad 'The config `dev` holds it.'

[[ $fail -eq 0 ]] && echo "ok: scrub terms config is stg_scrub everywhere"
exit $fail
