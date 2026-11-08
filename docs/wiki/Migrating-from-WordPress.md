# Migrating from WordPress

`tools/wxr2hugo/` turns a WordPress export (WXR) into Hugo page bundles. It
uses only the Python 3 standard library (the optional WebP step needs one
pinned package). It was written for this site and is meant to be reused.

Raw WordPress material is never committed: exports, database dumps, crawls,
`wp-config*`, unscrubbed drafts and commenter data stay outside the repository.
The converter refuses an input, terms or output path inside the repository.

## Convert

```sh
python3 -I tools/wxr2hugo/convert.py --wxr PATH/export.xml --out DIR \
    [--scrub-terms FILE|-] [--require-terms] [--site-url URL] [--media DIR] \
    [--draft-all] [--posts-only] [--annotations tools/wxr2hugo/annotations.json]
```

`python3 -I tools/wxr2hugo/convert.py --help` lists the options. The output:

- `posts/<slug>/index.md` for posts and `<slug>/index.md` for pages (with a
  `url:` front matter key), images and `comments.json` beside them;
- `permalink-map.json` and `decision-log.json`. The log's `review` list names
  each page the owner must look at before it goes public, with the reasons.

What it does, in the order a reader of the code meets it:

- **Old addresses become redirects.** Each old permalink is written into the
  page's `aliases`, and the build writes a 301 line for each into `_redirects`.
  A directory-style alias gets two lines (with and without the trailing slash);
  an alias ending in `.html` gets one. A permalink that is not a plain path
  (whitespace, quotes, `..`, `//`) gets no alias and is logged.
- **Drafts stay drafts.** `--draft-all` makes everything a draft while the
  aliases still exist; Hugo builds no draft, so no redirect goes live until the
  owner removes `draft`.
- **No old post is announced again.** `syndicate` is always `false` on converted
  content. A recorded Mastodon announcement URL becomes `syndicated.mastodon`.
- **Comments.** Only approved comments are kept, written as `comments.json`
  beside the post. ActivityPub items are dropped. The site renders archived
  comments from `data/comments/` (`layouts/_partials/comments-archive.html`).
- **Images.** File names are reduced to `[A-Za-z0-9._-]`. An image without alt
  text gets `TODO alt text` and a warning; the render hook then fails the build
  for a published page that still has it. See [Images and alt text](Images-and-alt-text.md).
- **Affiliate links.** A post with an `amzn.to` link gets the Amazon Associate
  line appended once, and the log records it.
- **Collisions.** A page slug that matches `posts`, `journal` or another
  top-level folder stops the run (exit 2) and writes nothing.
- **Annotations.** `--annotations` adds front matter the export cannot carry
  (an `archive` banner text, a `supersededBy` forward link) from a reviewed JSON
  file keyed by post slug.

## Convert images to WebP

```sh
python3 -I tools/wxr2hugo/webp.py DIR
```

Converts the PNG and JPEG images in the bundles to WebP (only when the result is
smaller), drops EXIF and GPS data, applies orientation, and updates the
references in `index.md`. Non-images, decompression bombs, animated PNGs and
symlinks are refused and left alone. It needs Pillow, pinned with hashes in
`tools/wxr2hugo/requirements-webp.txt`; run it from a virtual environment that
installed that file.

## The scrub pass

Before it writes anything, the converter checks its output for private data and
stops on a finding (exit 3, nothing written; it prints the category, file and
line only):

- built in, no terms needed: callsign and grid-square shapes, and generic
  private-network hostnames (10/8, 172.16/12 and 192.168/16 addresses, and names
  ending `.local`, `.lan`, `.internal` or `.home.arpa`);
- from a terms file: `employer`, `hostname` and `serial` terms, one
  `category:term` per line, with `allow:TOKEN` to exempt a false positive.

The run prints which categories ran and `NOT RUN` for each term category without
terms, so a missing terms file cannot look like a clean pass. `--require-terms`
turns a missing file into exit 2. `--scrub-terms -` reads the terms from standard
input so they can live only in a secrets manager and never touch disk. Terms are
never echoed, logged or written. Where the real terms live and how to add one is
in [docs/scrub-terms.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/scrub-terms.md);
real term values never go in the repository, an issue or a pull request.

The scrub pass is a safety net, not a substitute for reading what you migrate.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Converted. |
| 2 | A refused path, a bad or missing terms file, or a slug collision. |
| 3 | The scrub pass found private data. Nothing was written. |

## Tests

```sh
scripts/test-wxr2hugo.sh         # unit tests for the converter
scripts/test-wxr2hugo-webp.sh    # the WebP step (pinned Pillow in a throwaway venv, needs a package index)
scripts/test-migration.sh        # converter output builds with this site's layouts: drafts, redirects, banners, alt guard
```

## What a real migration also needs

- Old upload addresses: `docs/migration-uploads.md` lists the redirects that go
  with each post once it is published, and `scripts/test-redirects.sh` checks
  the `_redirects` file.
- The feed: the old WordPress feed addresses redirect to `/feed/index.xml`.
- The parity table and the cutover steps: `docs/parity.md` and `docs/cutover.md`.
