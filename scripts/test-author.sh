#!/usr/bin/env bash
# Tests for scripts/author.py (issue #253): slug rules, dates, tags, collisions, path and
# symlink safety, a created page that passes scripts/check-content.py, and a mutation proof
# (the same page published with an unfinished description fails the check).
#
# Fixtures are throwaway repository layouts under the repository's gitignored tmp/, never
# /tmp, and never the real content/.
# shellcheck disable=SC2015  # "cond && ok || bad" is the intended report idiom here
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/author.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$work"' EXIT

fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}

n=0
# repo: a fresh fixture repository; sets $r
repo() {
    n=$((n + 1))
    r="$work/r$n"
    mkdir -p "$r/content/posts" "$r/content/journal" "$r/brand"
    printf '# manifest\n' >"$r/brand/approved-assets.txt"
}
# au <args>: run the helper against $r, capture stdout+stderr in $out and the exit in $rc
au() {
    rc=0
    out="$(timeout 60 python3 -I "$root/scripts/author.py" --root "$r" "$@" 2>&1 </dev/null)" || rc=$?
}
# expect <name> <exit> <grep pattern or -> <args...>
expect() {
    local name="$1" want="$2" pat="$3"
    shift 3
    au "$@"
    if [[ $rc -ne $want ]]; then
        bad "$name (exit $rc, want $want): $out"
    elif [[ "$pat" != "-" ]] && ! grep -qE -- "$pat" <<<"$out"; then
        bad "$name (output lacks /$pat/): $out"
    else
        ok "$name"
    fi
}
tree_empty() { [[ -z "$(find "$r/content/posts" "$r/content/journal" -mindepth 1 -print -quit)" ]]; }

D="A plain sentence that describes the page."

# --- a good post and a good journal entry -----------------------------------------------------
repo
expect "new post" 0 "created content/posts/my-first-post/index.md" new post "My first post" --description "$D" --tag hugo --tag web-editor --date 2026-11-08
f="$r/content/posts/my-first-post/index.md"
grep -q '^draft: true$' "$f" && ok "post is draft true" || bad "post is draft true"
grep -q '^tags: \["hugo", "web-editor"\]$' "$f" && ok "post tags" || bad "post tags"
grep -q '^date: 2026-11-08$' "$f" && ok "post date" || bad "post date"
grep -q '^slug: "my-first-post"$' "$f" && ok "post slug" || bad "post slug"
au check content/posts/my-first-post
[[ $rc -eq 0 ]] && ok "check passes on the new post (bundle path)" || bad "check on new post: $out"
au check content/posts/my-first-post/index.md
[[ $rc -eq 0 ]] && ok "check passes on the new post (file path)" || bad "check on new post file: $out"
# the checker itself agrees, called directly
rc=0
python3 -I "$root/scripts/check-content.py" --root "$r" content/posts/my-first-post/index.md >/dev/null 2>&1 || rc=$?
[[ $rc -eq 0 ]] && ok "check-content.py passes on the new post" || bad "check-content.py rc $rc"

expect "new journal" 0 "created content/journal/day-one/index.md" new journal "Day one" --description "$D"
au check content/journal/day-one
[[ $rc -eq 0 ]] && ok "check passes on the new journal entry" || bad "check on journal: $out"
grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}-0[45]:00$' "$r/content/journal/day-one/index.md" && ok "default date is now with the Eastern offset" || bad "default date"
grep -q '^syndicate: true$' "$r/content/journal/day-one/index.md" && ok "syndicate is true" || bad "syndicate"

# --- mutation proof: the same page, published with an unfinished description, must fail ------
repo
au new post "Mutation proof" --description "$D"
f="$r/content/posts/mutation-proof/index.md"
sed -e 's/^draft: true$/draft: false/' -e 's/^description: .*/description: "TODO write a description"/' "$f" >"$f.new" && mv "$f.new" "$f"
au check content/posts/mutation-proof
if [[ $rc -eq 1 ]] && grep -q '^todo: ' <<<"$out"; then ok "mutation: draft false with a placeholder description fails"; else bad "mutation (exit $rc): $out"; fi
sed -e 's/^description: .*/description: ""/' "$f" >"$f.new" && mv "$f.new" "$f"
au check content/posts/mutation-proof
if [[ $rc -eq 1 ]] && grep -q '^description: ' <<<"$out"; then ok "mutation: an empty description fails"; else bad "mutation empty (exit $rc): $out"; fi

# --- description is required ------------------------------------------------------------------
repo
expect "no description is refused" 1 "description is required" new post "No description"
tree_empty && ok "no description: nothing created" || bad "no description left files"
expect "blank description is refused" 1 "description is required" new post "Blank" --description "   "
expect "long description is refused" 1 "at most 160" new post "Long" --description "$(printf 'x%.0s' $(seq 1 161))"
expect "description with a newline is refused" 1 "one line" new post "Newline" --description $'two\nlines'
tree_empty && ok "bad descriptions: nothing created" || bad "bad descriptions left files"

# --- usage errors exit 2 ----------------------------------------------------------------------
repo
expect "no command" 2 -
expect "missing title" 2 - new post
expect "unknown kind" 2 - new page "Title" --description "$D"
expect "unknown option" 2 - new post "Title" --nope
expect "check without a path" 2 - check

# --- slug rules -------------------------------------------------------------------------------
slug_case() { # <name> <title> <expected slug>
    repo
    au new post "$2" --description "$D"
    if [[ $rc -eq 0 && -f "$r/content/posts/$3/index.md" ]]; then
        ok "slug: $1"
        au check "content/posts/$3"
        [[ $rc -eq 0 ]] || bad "slug $1: check-content failed: $out"
    else
        bad "slug $1 (exit $rc, want $3): $out"
    fi
}
slug_case "punctuation" "Hello, World! It's 100% fine." "hello-world-it-s-100-fine"
slug_case "unicode accents" "Café déjà vu: naïve Zoë" "cafe-deja-vu-naive-zoe"
slug_case "spaces and hyphens" "  --Many   spaces--and---hyphens  " "many-spaces-and-hyphens"
slug_case "uppercase" "SHOUTING TITLE" "shouting-title"
slug_case "mixed script keeps the ASCII part" "Привет hello мир" "hello"
repo
long="$(printf 'word%.0s ' $(seq 1 30))"
au new post "$long" --description "$D"
s="$(basename "$(dirname "$(find "$r/content/posts" -name index.md | head -1)")")"
if [[ $rc -eq 0 && ${#s} -le 80 && "$s" != *- && "$s" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then ok "slug: long title is cut at most 80, on a word"; else bad "long slug '$s' (exit $rc)"; fi
repo
expect "empty title" 1 "must not be empty" new post "" --description "$D"
expect "title with no ASCII letters" 1 "no ASCII letters" new post "Привет мир" --description "$D"
expect "punctuation-only title" 1 "no ASCII letters" new post "!!! ???" --description "$D"
expect "title over the cap" 1 "at most 200" new post "$(printf 'a%.0s' $(seq 1 201))" --description "$D"
tree_empty && ok "bad titles: nothing created" || bad "bad titles left files"

# --- quoting: quotes and backslashes in a title survive and pass the check --------------------
repo
au new post 'He said "hi" and \o/ left' --description 'Say "hi": a colon and a # sign' --tag a
[[ $rc -eq 0 ]] || bad "quoting: $out"
au check content/posts/he-said-hi-and-o-left
[[ $rc -eq 0 ]] && ok "quotes, backslash, colon and # in text pass the check" || bad "quoting check: $out"
grep -q '^title: "He said \\"hi\\" and \\\\o/ left"$' "$r/content/posts/he-said-hi-and-o-left/index.md" && ok "quoting is escaped" || bad "quoting escape"

# --- dates ------------------------------------------------------------------------------------
repo
expect "invalid date format" 1 "date must look like" new post "D1" --description "$D" --date 08-11-2026
expect "impossible date" 1 "not a real calendar date" new post "D2" --description "$D" --date 2026-02-30
expect "month 13" 1 "not a real calendar date" new post "D3" --description "$D" --date 2026-13-01
expect "future date refused" 1 "in the future" new post "D4" --description "$D" --date 2999-01-01
tree_empty && ok "bad dates: nothing created" || bad "bad dates left files"
expect "future date with the flag" 0 "created" new post "D5" --description "$D" --date 2999-01-01 --allow-future
au check content/posts/d5
[[ $rc -eq 0 ]] && ok "future date still passes the check when allowed" || bad "future check: $out"
expect "leap day" 0 "created" new post "D6" --description "$D" --date 2024-02-29

# --- tags -------------------------------------------------------------------------------------
repo
expect "uppercase tag refused" 1 "not a lowercase slug" new post "T1" --description "$D" --tag Hugo
expect "tag with a space refused" 1 "not a lowercase slug" new post "T2" --description "$D" --tag "a b"
expect "tag with a slash refused" 1 "not a lowercase slug" new post "T3" --description "$D" --tag "a/b"
expect "tag with double hyphen refused" 1 "not a lowercase slug" new post "T4" --description "$D" --tag "a--b"
expect "empty tag refused" 1 "not a lowercase slug" new post "T5" --description "$D" --tag ""
expect "long tag refused" 1 "not a lowercase slug" new post "T6" --description "$D" --tag "$(printf 'a%.0s' $(seq 1 41))"
tags=()
for i in $(seq 1 11); do tags+=(--tag "t$i"); done
expect "eleven tags refused" 1 "at most 10 tags" new post "T7" --description "$D" "${tags[@]}"
tree_empty && ok "bad tags: nothing created" || bad "bad tags left files"
expect "duplicate tags are folded" 0 "created" new post "T8" --description "$D" --tag a --tag a
grep -q '^tags: \["a"\]$' "$r/content/posts/t8/index.md" && ok "duplicate tag written once" || bad "duplicate tag"
expect "no tags" 0 "created" new post "T9" --description "$D"
grep -q '^tags: \[\]$' "$r/content/posts/t9/index.md" && ok "no tags is an empty list" || bad "empty tags"

# --- collisions: never overwrite --------------------------------------------------------------
repo
au new post "Same title" --description "$D"
before="$(sha256sum "$r/content/posts/same-title/index.md")"
expect "second post with the same slug refused" 1 "already exists" new post "Same title!" --description "Another sentence."
[[ "$(sha256sum "$r/content/posts/same-title/index.md")" == "$before" ]] && ok "collision left the file unchanged" || bad "collision changed the file"
mkdir -p "$r/content/posts/taken" && printf 'x' >"$r/content/posts/taken"/keep.txt
expect "existing directory without index.md refused" 1 "already exists" new post "Taken" --description "$D"
[[ ! -e "$r/content/posts/taken/index.md" ]] && ok "no file added to the existing directory" || bad "wrote into an existing directory"
printf 'x' >"$r/content/posts/plainfile"
expect "existing plain file refused" 1 "already exists" new post "Plainfile" --description "$D"
ln -s /nonexistent "$r/content/posts/dangling"
expect "dangling symlink at the slug refused" 1 "already exists" new post "Dangling" --description "$D"
au new journal "Same title" --description "$D"
[[ $rc -eq 0 ]] && ok "the same slug in the other section is fine" || bad "cross-section: $out"

# --- path traversal and symlinks --------------------------------------------------------------
repo
outside="$work/outside$n"
mkdir -p "$outside"
rm -rf "$r/content/posts"
ln -s "$outside" "$r/content/posts"
expect "content/posts as a symlink refused" 1 "real directory" new post "Escape" --description "$D"
[[ -z "$(ls -A "$outside")" ]] && ok "nothing written through the symlinked section" || bad "wrote through a symlink"
repo
rm -rf "$r/content"
mkdir -p "$work/realcontent$n/posts"
ln -s "$work/realcontent$n" "$r/content"
expect "content as a symlink refused" 1 "real directory" new post "Escape2" --description "$D"
[[ -z "$(ls -A "$work/realcontent$n/posts")" ]] && ok "nothing written through the symlinked content" || bad "wrote through content symlink"
repo
rm -rf "$r/content"
expect "missing content directory refused" 1 "does not exist" new post "Nocontent" --description "$D"
repo
expect "title with slashes and dots cannot traverse" 0 "created content/posts/etc-passwd/index.md" new post "../../etc/passwd" --description "$D"
[[ ! -e "$work/etc" && ! -e "$r/etc" ]] && ok "no directory made outside content/" || bad "traversal made a directory"
repo
echo secret >"$work/target$n.md"
mkdir -p "$r/content/posts/linked"
ln -s "$work/target$n.md" "$r/content/posts/linked/index.md"
expect "check refuses a symlinked index.md" 1 "not a regular file|symlink" check content/posts/linked
expect "check refuses a path outside content" 1 "not inside content/" check ../../etc/passwd
expect "check refuses the repo root file" 1 "not inside content/" check brand/approved-assets.txt
repo
mkdir -p "$work/realc$n/posts/p"
printf -- '---\ntitle: "x"\n---\n' >"$work/realc$n/posts/p/index.md"
rm -rf "$r/content"
ln -s "$work/realc$n" "$r/content"
expect "check refuses a symlinked content/" 1 "symlink" check content/posts/p/index.md
repo
expect "check refuses content/ itself" 1 "not inside content/" check content
ln -s "$outside" "$r/content/journal/viasym"
expect "check refuses a path through a symlinked directory" 1 "symlink" check content/journal/viasym/index.md
expect "check on a missing file" 1 "not a regular file" check content/posts/nope

# --- check reports findings and passes the exit code -------------------------------------------
repo
mkdir -p "$r/content/posts/bad"
printf -- '---\ntitle: "Bad"\ndate: 2026-11-08\ndraft: true\nslug: "bad"\n---\nbody\n' >"$r/content/posts/bad/index.md"
expect "check prints findings and exits 1" 1 "description: content/posts/bad/index.md" check content/posts/bad

# --- nothing outside content/ was written, no git, no network ---------------------------------
repo
before="$(cd "$r" && find . -path ./content -prune -o -print | sort | sha256sum)"
au new post "Scope" --description "$D"
after="$(cd "$r" && find . -path ./content -prune -o -print | sort | sha256sum)"
[[ "$before" == "$after" ]] && ok "nothing written outside content/" || bad "wrote outside content/"
[[ ! -e "$r/.git" ]] && ok "no git repository touched" || bad ".git appeared"
if grep -nE '^\s*(import|from)\s+(socket|urllib|http|requests|webbrowser|ftplib|smtplib)\b' "$root/scripts/author.py"; then bad "author.py imports a network module"; else ok "author.py imports no network or browser module"; fi
if grep -nE '"git"|webbrowser|xdg-open' "$root/scripts/author.py"; then bad "author.py names git or a browser"; else ok "author.py runs no git or browser"; fi

if [[ $fail -ne 0 ]]; then
    echo "test-author: FAILED"
    exit 1
fi
echo "test-author: all passed"
