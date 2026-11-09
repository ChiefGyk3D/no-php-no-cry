# Writing a post

The short version. The complete guide, with every front matter field, is
[docs/writing-a-post.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/writing-a-post.md);
this page does not repeat its tables.

## Steps

1. **Propose it.** Open an issue with the "Post proposal" template: topic, who
   it is for and what the reader will learn.
2. **Create it.** From the repository root:

   ```sh
   hugo new content posts/my-post-title
   ```

   Lowercase words joined by hyphens: the folder name becomes the slug and the
   address (`/posts/my-post-title/`). Hugo builds a page bundle from
   `archetypes/posts/index.md`: a folder holding `index.md`, with room for the
   images beside it. The new post is a draft and does not syndicate.
3. **Write it.** The file starts with front matter, then the opening paragraph,
   then the line `<!--more-->`. Everything above that line is the summary, so
   write the opening paragraph to stand on its own.
4. **Fill in the front matter.** The fields a reader of the repository meets
   first:

   | Field | Why |
   | --- | --- |
   | `title`, `date`, `slug` | The headline, the publication date and the address. |
   | `description` | One or two plain sentences. It becomes the page description, the social card text and the announcement text. Each page needs its own; the output check refuses duplicates. |
   | `categories`, `tags` | One broad category, a few specific tags. Reuse existing ones first. Tags show as `#tag` links and feed [Search and tags](Search-and-tags.md). |
   | `draft` | `true` keeps the page out of the production build. Set `false` to publish. |
   | `syndicate` | A flag for a later announcement step; no workflow in this repository announces posts today, and the flag does not change the feed. Leave `false` while writing. |
   | `image`, `imageAlt` | The optional headline image. See [Headline images](Headline-images.md). |
   | `aliases` | Old addresses that redirect here. New posts rarely need one. |

5. **Add images** beside `index.md` with real alt text. See
   [Images and alt text](Images-and-alt-text.md).
6. **Preview** with `hugo server --buildDrafts`.
7. **Publish**: set `draft: false`, build, and run the checks below.
8. **Open a pull request** that links the issue. The maintainer merges when
   `CI green` passes.

## Check before you push

```sh
hugo --minify --gc
EXPECT_ENV=production scripts/check-output.sh public
scripts/check-wording.sh
python3 -I scripts/check-content.py
scripts/test-archetype.sh
```

`scripts/test-archetype.sh` proves that a post made from the archetype builds and
passes the output checks and that a missing alt text fails the build.

## What CI checks on a post (and the phone path)

`scripts/check-content.py` reads every Markdown file and image that your pull
request adds or changes under `content/`. It is the only safeguard when you write
from the GitHub web editor on a phone, so it is strict and each error says what
to fix. It runs in the `CI green` gate and prints `rule: path: message`.

**The phone path.** Open the repository on GitHub, add a folder
`content/posts/<slug>/` with an `index.md`, keep `draft: true` while you
write, and upload images into the same folder. Open the pull request; the check
tells you what is missing. Set `draft: false` only when the post is done. The
image resize happens at build time, so a phone photo only needs to be small enough
for the size cap below.

| Rule | What fails |
| --- | --- |
| `front-matter` | Missing or unclosed `---` lines, TOML (`+++`), anchors, aliases, tags, duplicate keys or tabs. |
| `title`, `date`, `slug`, `description` | A missing title, a missing or non-lowercase-hyphen slug, a date that is not a real date (`2026-11-08` or `2026-11-08T09:30:00-05:00`), and for posts a description that is empty or over 160 characters. |
| `draft` | Anything but unquoted `true` or `false`. A missing `draft` counts as published. |
| `tags` | A tag that is not a lowercase slug: `work-from-home`, not `Work from home`. |
| `image-alt`, `inline-alt` | On a published page: an `image` without `imageAlt`, or an inline image whose alt text is empty, a file name such as `IMG_1234.jpg`, or a placeholder such as `TODO alt text`. A draft is not checked. |
| `image-remote` | An inline or headline image that is not a real file inside the post folder: a link, an absolute path, a `../` path or a file that is not there. |
| `image-unreferenced` | A bundle image that the post never uses, neither as `image:` nor inline. Reference it or remove it. |
| `unsafe-link`, `raw-html` | `javascript:`, `vbscript:` or `data:` links, and script, iframe, object, embed or style tags and `on*=` handlers. Code samples are exempt. |
| `todo` | A `TODO` or `FIXME` anywhere in a published post, comments included. Delete the archetype comments before publishing. |
| `guard-word` | An employer-name guard word or a term from `SCRUB_TERMS` ([Scrub terms](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/scrub-terms.md)). The word is never printed. |
| `image-name`, `image-type` | A bundle image whose name is not lowercase letters, digits, dot, hyphen and underscore (no spaces), or that is not WebP, JPEG or PNG. |
| `image-metadata` | EXIF (which holds GPS), XMP or IPTC data. Strip it before you upload. |
| `image-dimensions` | A bundle image over 10000 pixels on a side or 64 megapixels, or one whose size cannot be read. A small file can still be enormous once decoded. |
| `image-size` | A bundle image over 5 MiB. This is a source cap only: Hugo resizes at build, and `scripts/check-budget.py` still limits what readers download. The 5 MiB figure is a proposal; the built-image limits are in [Build checks and budgets](Build-checks-and-budgets.md). |
| `brand-asset` | An image missing from `brand/approved-assets.txt`, or listed with another sha256. See [Images and alt text](Images-and-alt-text.md). |

Run it yourself with `python3 -I scripts/check-content.py` (files changed against
`origin/main`), `--all` for the whole tree, or `--json` for machine output.

## Rules that apply to every post

- **No embeds and no outside images.** The Content Security Policy allows only
  the site's own files, and raw HTML in Markdown is off. Link to a video or a
  post instead of embedding it.
- **Affiliate links** need `affiliate: true`, a plain statement near the first
  link and, for Amazon links, the line "As an Amazon Associate I earn from
  qualifying purchases." once in the body.
- **House wording.** Write "cryptocurrency" or the coin name, never the short
  form; write "cryptography" for the math. Use American English, short
  sentences and no em dashes. `scripts/check-wording.sh` enforces the first rule.
- **Private data.** Never put a real callsign, grid square, employer, internal
  hostname, serial number, token or exact location in a post, image or commit.
  Use placeholders: `N0CALL`, `N0TST`, `FN31pr`, `host.example`, `192.0.2.1`.

For work notes rather than articles, see [Journal entries](Journal-entries.md).
