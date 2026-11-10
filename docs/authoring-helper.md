# Authoring helper

`scripts/author.py` is a small command-line helper (Python 3, standard library only)
that starts a post or journal entry the safe way. It is phase 1 of the local
authoring editor (epic #237); editor settings and the writing guide arrive in later issues.

`new` and `img add` write only under `content/` and do no git, network or browser work.
`preview` listens on loopback only. `publish` is the only command that runs `git` and `gh`.
The helper never merges and never touches `main`.

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
| `--date YYYY-MM-DD` | A real calendar date. Default: now, in Eastern time with its offset (for example `2026-11-09T09:30:00-05:00`). A future date is refused unless you add `--allow-future`. |
| `--tag SLUG` | A lowercase slug (a-z, 0-9, single hyphens, at most 40 characters). Repeat for more, at most 10. |

The helper builds the slug from the title: ASCII letters and digits joined by single
hyphens, at most 80 characters. Accents are folded (`Café` becomes `cafe`) and other
scripts are dropped; a title with nothing left is refused. The new page is
`content/posts/<slug>/index.md` (or `content/journal/<slug>/index.md`), always with
`draft: true` and `syndicate: true` (a draft is never built or announced, so the flag only takes effect once you publish), and a short body that ends the summary with
`<!--more-->`.

It never overwrites: if the folder, or any file or link of that name, exists, it stops
and changes nothing. It refuses a `content/` folder or section that is a symlink.

## Check a page

```sh
python3 -I scripts/author.py check content/posts/my-post-title
python3 -I scripts/author.py check content/posts/my-post-title --require-published
python3 -I scripts/author.py check content/posts/my-post-title --build --hugo ~/bin/hugo
```

`PATH` is an `index.md`, its folder, or a slug path under `content/`. Every step runs, each
prints `[ok] name` or `[FAIL] name`, and the exit code is 0 only when all pass.

| Step | What it checks |
| --- | --- |
| `content` | `scripts/check-content.py`: front matter fields, image alt text, links, raw HTML, placeholders, size caps. |
| `images` | `scripts/check-image-metadata.py` on the bundle (EXIF, GPS, XMP, IPTC). Skipped when the bundle has no image. |
| `dashes` | No em dash or en dash in the file; findings print as `dashes: path:LINE: ...`. |
| `wording` | The short form of the coin word is not used on any line of the page. |
| `draft` | Reports `draft: true`. With `--require-published` a draft fails this step. |
| `build`, `check-output` | Only with `--build`: the pinned Hugo runs `--minify --gc` into a temporary folder (no drafts, production mode), then `scripts/check-output.sh` runs on it. The folder is removed afterwards. |

A page the helper creates passes (as a draft). Publishing is a separate step (see `publish`).

## Add an image

```sh
python3 -I scripts/author.py img add content/posts/my-post-title ~/Pictures/bench.jpg \
  --alt "A breadboard with a small radio module wired to a microcontroller"
python3 -I scripts/author.py img add content/posts/my-post-title ~/Pictures/hero.png \
  --alt "The finished enclosure on a desk" --featured
```

`BUNDLE` is a page folder under `content/` that has its own `index.md`. `FILE` is the
picture to add. The helper copies a cleaned version into the bundle and prints the line
to paste; it never edits `index.md`.

| Option | Meaning |
| --- | --- |
| `--alt TEXT` | Required. Real alt text, at most 300 characters, one line. Empty, a placeholder (`TODO`), or file-name-like text (`photo.jpg`, `IMG_1234`) is refused, by the same rules the content check applies. |
| `--name NAME` | The file name to use (default: the source file name). It is lowercased to letters, digits and single hyphens, at most 60 characters; the extension comes from the content (`.jpg` or `.png`). |
| `--featured` | Print `image:` and `imageAlt:` front matter lines instead of a Markdown image line. |

What the helper does, and refuses:

- **JPEG or PNG only, by content.** The first bytes decide, never the extension. A text
  file renamed `.jpg`, a WebP, or an empty file is refused.
- **Metadata removed.** A JPEG keeps only its tables, frame and scan data; EXIF (and with
  it GPS), XMP, IPTC, ICC, comments, thumbnails and every other application block are
  dropped. A PNG keeps IHDR, PLTE, tRNS, IDAT, IEND and the plain colour chunks
  (gAMA, cHRM, sRGB); `eXIf`, text, XMP and time chunks are dropped. The picture data is
  copied as it is, not re-encoded, so quality is unchanged. This uses only the standard
  library (no new dependency).
- **Rotated images are refused.** If EXIF says the picture is stored rotated or mirrored
  (orientation other than 1), the helper cannot rotate pixels without an image library, and
  removing the tag would show it sideways. Rotate it in an editor, save it with orientation
  normal, and add it again.
- **Size and shape.** At most 5 MiB (the content check's cap), 10000 pixels a side and 64
  megapixels; truncated or malformed files, bad PNG checksums and extra bytes after the end
  of the image are refused. Hugo resizes at build time, so nothing is resized here.
- **Confinement.** The bundle must be inside `content/` with no symlink on the way; the
  source file must be a regular file reached through no symlink. The new file is written
  with exclusive create and is never overwritten (use `--name` for a second copy).

The brand check requires every image under `content/` to be listed in
`brand/approved-assets.txt` with its sha256. The helper prints the exact line with the hash
of the cleaned file; look at the image, fill in the source and what you checked, and add it
yourself. The helper never writes the manifest, because that line records your own review.

## Preview

```sh
python3 -I scripts/author.py preview
python3 -I scripts/author.py preview --port 4000 --no-drafts
```

Runs `hugo server` bound to `127.0.0.1` on a free port (or `--port N`, 1024 to 65535), prints
the URL and opens no browser. Drafts are shown by default (the point of a preview);
`--no-drafts` hides them. Any `--host` other than `127.0.0.1` is refused before Hugo starts, so
the preview is never reachable from the network. Press Ctrl-C to stop. It uses the `hugo` on
your `PATH` (or `--hugo PATH`) and refuses unless that is the standard edition named in
`.hugo-version`, using `scripts/check-hugo-version.sh`. If Hugo is not installed it says so and
stops. Hugo is started with an argument list, never through a shell.

## Publish

```sh
python3 -I scripts/author.py publish content/posts/my-post-title --issue 254 --dry-run
python3 -I scripts/author.py publish content/posts/my-post-title --issue 254 --set-draft-false
```

Run it from `main` or any other branch. `publish` runs the check, creates and switches to a new
branch `post/<slug>` (the bundle folder name), commits only the bundle there, pushes only that
branch and opens a pull request with `gh` against `main` (`--base`). Then it switches back to
the branch you started on and prints the pull request URL. The post now lives on the pull
request branch, so it is no longer in your starting tree. The merge stays yours.

| Option | Meaning |
| --- | --- |
| `BUNDLE` | A page folder under `content/`, named with a lowercase slug. |
| `--issue N` | Required: `254`, `#254` or `owner/repo#254`. The helper puts `Refs #N` on the template's `Refs #` line (or appends it) and fills the summary line with the bundle and the passed check steps. |
| `--set-draft-false` | Sets `draft: false`, only when this flag is given. Without it the draft state is committed as it is. The check then runs again with `--require-published` and the page is restored if it fails. |
| `--dry-run` | Run the checks and print the plan; commit, push and `gh` are not touched. |
| `--remote R`, `--base B`, `--gh PATH` | Remote name (default `origin`), target branch (default `main`), the `gh` binary. |

Safety properties:

- Refuses a detached HEAD, and refuses when `post/<slug>` already exists locally or on the remote.
- Refuses a dirty tree: any change outside the bundle (staged, modified or untracked) stops it.
  Only the bundle is committed.
- Refuses unless every check step passes; nothing is committed on failure.
- Never merges, never force-pushes, never pushes to `main` or the default branch: it pushes
  exactly `refs/heads/post/<slug>:refs/heads/post/<slug>`.
- Leaves nothing behind on failure. If the commit, the push or `gh` fails, it undoes the
  commit (keeping your files), switches back to the starting branch, deletes the local
  `post/<slug>` and restores the draft line, so the tree is as it was. After a `gh` failure the
  pushed remote branch stays and the message names it; open the pull request by hand.
- Flips only the single `draft:` line inside the front matter. Two such lines, or a body line
  that looks like one, cannot change which line is edited. The write goes through a temporary
  file and a rename.
- Refuses a bundle containing a symlink or special file, a post file over 1 MiB, a bundle name
  that is not a lowercase slug, a path outside `content/`, and issue, remote or base text with
  anything but plain name characters (all programs get argument lists, never a shell).
- Stores and reads no token: authentication is whatever `git` and `gh` already have.
- Fill in the rest of the pull request template (the checklist) yourself.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Done, or the check found nothing. |
| 1 | A validation error (bad input, collision, unsafe path) or findings from the check. |
| 2 | A usage error (missing or unknown argument). |

## Tests

`scripts/test-author.sh` builds throwaway repository layouts under `tmp/` and covers
slugs, dates, tags, collisions, traversal, symlinks, the check steps (with a mutation proof for
each: the same page with an unfinished description, a dash, the short form or an image carrying
EXIF fails) and `publish` against a temporary git repository with a bare remote and a fake `gh`
(branch creation from `main` and from a feature branch, existing branches, restore after each
failure, no push to `main`, draft flip, hostile names, a symlinked post, a huge file).
The `img add` tests build tiny synthetic JPEG and PNG files in the test, with metadata blocks
holding a fake GPS marker (never a real picture or coordinate), and cover alt text, content
sniffing, hostile files, paths, and a mutation proof: with the stripping step replaced by a
copy, the marker survives and `scripts/check-image-metadata.py` fails. The preview and `check --build` tests use a
stub Hugo that records its arguments (loopback bind, refused hosts and ports, wrong version, no Hugo).
It runs in `scripts/gate.sh` and in the `content checks` CI job.
