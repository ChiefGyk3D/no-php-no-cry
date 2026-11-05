#!/usr/bin/env bash
# Test the generated _redirects file (layouts/home.redirects).
#
# Builds throwaway sites (this repository's layouts, assets and static files,
# plus pages written here) under the repository's gitignored tmp/, never /tmp.
# Asserts that an alias_fragment outside the narrow fragment grammar (letters,
# digits, '.', '_', '~', '-') fails the build, that a valid one builds, and that
# every generated _redirects line is a comment or exactly "/from /to 301" with
# an allowed status and internal paths. A guard self-test feeds the line checker
# bad lines and requires a failure. Needs the pinned Hugo; a missing Hugo is a
# failure, not a skip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/redirects.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

if ! command -v hugo >/dev/null 2>&1; then
    echo "FAIL: hugo is not on PATH (install the pinned version, see .hugo-version)"
    exit 1
fi

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# check_lines <file>: every line is a '#' comment or exactly three fields:
# an internal source path, an internal target path (with an optional fragment
# from the allowed grammar), and an allowed status. Prints each violation.
check_lines() {
    awk '
        /^#/ { next }
        {
            n = NF
            if (n != 3) { print "line " NR ": " n " fields"; bad = 1; next }
            if ($1 !~ /^\/[A-Za-z0-9._~\/%-]*$/) { print "line " NR ": bad source"; bad = 1 }
            if ($2 !~ /^\/[A-Za-z0-9._~\/%-]*(#[A-Za-z0-9._~-]+)?$/) { print "line " NR ": bad target"; bad = 1 }
            if ($3 != "301") { print "line " NR ": status " $3; bad = 1 }
        }
        END { exit bad }
    ' "$1"
}

build_site() { # build_site <dir> <fragment-yaml-or-empty>
    local site="$1" frag="$2"
    mkdir -p "$site/content/posts/x"
    cp -r "$root/layouts" "$root/assets" "$root/static" "$site/"
    cp "$root/hugo.toml" "$site/hugo.toml"
    printf -- '---\ntitle: "Home"\n---\n' >"$site/content/_index.md"
    printf -- '---\ntitle: "Posts"\n---\n' >"$site/content/posts/_index.md"
    {
        printf -- '---\ntitle: "X"\ndate: 2024-01-02T03:04:05-05:00\naliases:\n  - /old-x/\n'
        [[ -n "$frag" ]] && printf 'alias_fragment: %s\n' "$frag"
        printf -- '---\n\nBody.\n'
    } >"$site/content/posts/x/index.md"
    (cd "$site" && hugo --destination "$site/public" >"$site/build.log" 2>&1)
}

# --- a valid fragment builds, and every line is well formed ------------------
for good in 'contact' 'a.b_c~d-9'; do
    s="$work/good-$RANDOM"
    if build_site "$s" "\"$good\""; then
        if grep -q "^/old-x/ /posts/x/#$good 301\$" "$s/public/_redirects" && out="$(check_lines "$s/public/_redirects" 2>&1)"; then
            pass "fragment '$good' builds and every _redirects line is well formed"
        else
            fail "fragment '$good': unexpected _redirects: ${out:-no matching line}"
        fi
    else
        fail "fragment '$good' should build: $(tail -n 3 "$s/build.log")"
    fi
done

# --- rejected fragments fail the build ----------------------------------------
reject() { # reject <label> <yaml value>
    local s="$work/bad-$RANDOM"
    if build_site "$s" "$2"; then
        fail "$1: the build should have failed"
    elif grep -q 'alias_fragment' "$s/build.log"; then
        pass "$1: the build fails and names alias_fragment"
    else
        fail "$1: the build failed for another reason: $(tail -n 3 "$s/build.log")"
    fi
}
reject "newline" '"a\nb"'
reject "space" '"a b"'
reject "hash" '"a#b"'
reject "percent-encoded newline" '"a%0Ab"'
reject "redirect-like text" '"x\n/evil /elsewhere 301"'
reject "redirect-like text on one line" '"x /evil 301"'
reject "slash" '"a/b"'

# --- the real site's file is well formed --------------------------------------
if hugo --quiet --source "$root" --destination "$work/real" >"$work/real.log" 2>&1; then
    if out="$(check_lines "$work/real/_redirects" 2>&1)"; then
        pass "the site's own _redirects has only well-formed lines"
    else
        fail "the site's own _redirects: $out"
    fi
else
    fail "the site did not build: $(tail -n 3 "$work/real.log")"
fi

# --- guard self-test: the line checker must reject bad lines -------------------
i=0
for bad in '/a /b' '/a /b 301 extra' '/a /b 200' '/a https://evil.example/ 301' '/a /b#c%20d 301' '/a /b 308'; do
    i=$((i + 1))
    printf '# header\n%s\n' "$bad" >"$work/line$i"
    if check_lines "$work/line$i" >/dev/null 2>&1; then
        fail "guard: line '$bad' was accepted"
    fi
done
printf '# header\n/a /b 301\n/c/ /d/#ok 301\n' >"$work/ok"
if check_lines "$work/ok" >/dev/null 2>&1; then
    pass "guard: bad lines are rejected and good lines accepted"
else
    fail "guard: a good line was rejected"
fi

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all redirect checks passed"
