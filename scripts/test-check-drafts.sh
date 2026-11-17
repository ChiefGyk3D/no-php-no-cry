#!/usr/bin/env bash
# Tests for scripts/check-drafts.py on synthetic content and output trees (scratch
# directory under the repository's gitignored tmp/, never /tmp). Needs no Hugo.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-drafts.py"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/check-drafts.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fails=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fails=$((fails + 1))
}

content="$work/content"
mkdir -p "$content/posts/commented" "$content/posts/crlf" "$content/posts/dots" "$content/posts/broken"
printf -- '---\ntitle: "C"\ndraft: true # keep for review\nslug: "commented-slug" # note\n---\nbody\n' >"$content/posts/commented/index.md"
printf -- '---\r\ntitle: "W"\r\ndraft: true\r\n---\r\nbody\r\n' >"$content/posts/crlf/index.md"
printf -- '---\ntitle: "P"\ndraft: true\n...\nbody\n' >"$content/posts/dots/index.md"
printf -- '---\ntitle: "B"\ndraft: true\nthis line is not yaml\n---\nbody\n' >"$content/posts/broken/index.md"
mkdir -p "$content/posts/draft-post" "$content/posts/live-post" "$content/journal/loose" "$content/posts/renamed"
printf -- '---\ntitle: "D"\ndraft: true\n---\nbody\n' >"$content/posts/draft-post/index.md"
printf -- '---\ntitle: "L"\ndraft: false\n---\nbody\n' >"$content/posts/live-post/index.md"
printf -- '---\ntitle: "Q"\ndraft: "true"\n---\nbody\n' >"$content/journal/loose/quoted.md"
printf -- '---\ntitle: "R"\ndraft: true\nslug: "other-name"\n---\nbody\n' >"$content/posts/renamed/index.md"

# run <label> <expect-rc> <expect-text> <site> <mode>
run() {
    local label="$1" want="$2" text="$3" site="$4" mode="$5" out rc=0
    out="$(python3 -I "$checker" "$site" "$mode" "$content" 2>&1)" || rc=$?
    if [[ $rc -eq $want ]] && grep -qF -- "$text" <<<"$out"; then ok "$label"; else
        bad "$label (rc=$rc, out: $out)"
    fi
}

prod="$work/prod"
mkdir -p "$prod/posts/live-post"
: >"$prod/posts/live-post/index.html"
run "production without drafts passes" 0 "ok" "$prod" absent
run "staging without its drafts fails" 1 "[draft-missing] posts/draft-post/index.html" "$prod" present

mkdir -p "$prod/posts/draft-post"
: >"$prod/posts/draft-post/index.html"
run "production with a draft page fails" 1 "[draft-in-production] posts/draft-post/index.html" "$prod" absent

mkdir -p "$prod/posts/other-name"
: >"$prod/posts/other-name/index.html"
run "a draft with a slug is found under the slug" 1 "[draft-in-production] posts/other-name/index.html" "$prod" absent
quoted_out="$(python3 -I "$checker" "$prod" present "$content" 2>&1 || true)"
if grep -q "journal/loose" <<<"$quoted_out"; then bad "a quoted draft value was read as a draft"; else ok "a quoted draft value is not a draft"; fi

# Every accepted way of writing the front matter is found (a trailing comment, CRLF lines, a ...
# closing fence, a slug with a comment, and a page the content parser rejects).
for page in commented-slug crlf dots broken; do
    mkdir -p "$prod/posts/$page"
    : >"$prod/posts/$page/index.html"
    run "a draft written with the $page form is found" 1 "[draft-in-production] posts/$page/index.html" "$prod" absent
done

stage="$work/stage"
mkdir -p "$stage/posts/draft-post" "$stage/posts/other-name" "$stage/posts/commented-slug" "$stage/posts/crlf" "$stage/posts/dots" "$stage/posts/broken"
for d in draft-post other-name commented-slug crlf dots broken; do : >"$stage/posts/$d/index.html"; done
run "staging with every draft passes" 0 "ok" "$stage" present
run "bad mode is refused" 2 "Drafts" "$stage" sideways

# The real repository: content/ names its drafts, and both modes read it.
mkdir -p "$work/empty"
python3 -I "$checker" "$work/empty" absent >/dev/null 2>&1 && ok "real content, empty tree passes absent" || bad "real content, absent"

((fails == 0)) || exit 1
echo "check-drafts tests: ok"
