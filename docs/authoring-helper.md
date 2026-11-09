# Authoring helper

`scripts/author.py` is a small command-line helper (Python 3, standard library only)
that starts a post or journal entry the safe way. It is phase 1 of the local
authoring editor (epic #237); the full check command, editor settings and the
publish step arrive in later issues.

It does no network, git or browser work, and it writes only a new folder and
`index.md` under `content/`.

## New post or journal entry

From the repository root:

```sh
python3 -I scripts/author.py new post "My post title" \
  --description "One or two plain sentences that pitch the post." \
  --tag hugo --tag web-editor
python3 -I scripts/author.py new journal "Bench notes" --description "What I tried today."
```

| Option | Meaning |
| --- | --- |
| `TITLE` | Required, at most 200 characters, one line. |
| `--description TEXT` | Required, 1 to 160 characters, even on a draft. On a terminal the helper asks for it when you leave it out; without a terminal it stops with an error. |
| `--date YYYY-MM-DD` | A real calendar date. Default: today in UTC. A future date is refused unless you add `--allow-future`. |
| `--tag SLUG` | A lowercase slug (a-z, 0-9, single hyphens, at most 40 characters). Repeat for more, at most 10. |

The helper builds the slug from the title: ASCII letters and digits joined by single
hyphens, at most 80 characters. Accents are folded (`Café` becomes `cafe`) and other
scripts are dropped; a title with nothing left is refused. The new page is
`content/posts/<slug>/index.md` (or `content/journal/<slug>/index.md`), always with
`draft: true` and `syndicate: false`, and a short body that ends the summary with
`<!--more-->`.

It never overwrites: if the folder, or any file or link of that name, exists, it stops
and changes nothing. It refuses a `content/` folder or section that is a symlink.

## Check a page

```sh
python3 -I scripts/author.py check content/posts/my-post-title
```

This runs `scripts/check-content.py` on that page (an `index.md`, or its folder) and
prints its result and exit code. A page the helper creates passes. Publishing is a
separate step: set `draft: false` only when the page is ready, then open a pull
request; the CI check applies the same rules.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Done, or the check found nothing. |
| 1 | A validation error (bad input, collision, unsafe path) or findings from the check. |
| 2 | A usage error (missing or unknown argument). |

## Tests

`scripts/test-author.sh` builds throwaway repository layouts under `tmp/` and covers
slugs, dates, tags, collisions, traversal, symlinks, the check on a created page and a
mutation proof (the same page published with an unfinished description fails the check).
It runs in `scripts/gate.sh` and in the `content checks` CI job.
