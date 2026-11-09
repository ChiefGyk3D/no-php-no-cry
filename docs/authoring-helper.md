# Authoring helper

`scripts/author.py` is a small command-line helper (Python 3, standard library only)
that starts a post or journal entry the safe way. It is phase 1 of the local
authoring editor (epic #237); the full check command, editor settings and the
publish step arrive in later issues.

It does no git or browser work and opens no outside network connection. It writes only a new folder and `index.md`
under `content/` (new post or journal entry) or one new image file inside an existing
page bundle (img add). The preview command listens on loopback only.

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
```

This runs `scripts/check-content.py` on that page (an `index.md`, or its folder) and
prints its result and exit code. A page the helper creates passes. Publishing is a
separate step: set `draft: false` only when the page is ready, then open a pull
request; the CI check applies the same rules.

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
```

Runs `hugo server -D` (drafts shown) bound to `127.0.0.1` on a free port, prints the URL
and opens no browser. Any `--host` other than `127.0.0.1` is refused, so the preview is
never reachable from the network. `--port N` (1024 to 65535) picks the port. Press Ctrl-C to
stop. It uses the `hugo` on your `PATH` (or `--hugo PATH`) and refuses unless that is the
standard edition named in `.hugo-version`, using `scripts/check-hugo-version.sh`. If Hugo is
not installed it says so and stops. Hugo is started with an argument list, never through a
shell.

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
The `img add` tests build tiny synthetic JPEG and PNG files in the test, with metadata blocks
holding a fake GPS marker (never a real picture or coordinate), and cover alt text, content
sniffing, hostile files, paths, and a mutation proof: with the stripping step replaced by a
copy, the marker survives and `scripts/check-image-metadata.py` fails. The preview tests use a
stub Hugo that records its arguments (loopback bind, refused hosts and ports, wrong version, no Hugo).
It runs in `scripts/gate.sh` and in the `content checks` CI job.
