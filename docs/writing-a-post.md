# Writing a post

This guide takes you from an empty folder to a pull request. It works for a
post under `content/posts/` and for a work journal entry under
`content/journal/`. The steps are the same; the differences are noted.

You need the pinned Hugo (standard edition). The README, section "Build
locally", shows how to install it. The examples below use `hugo` for the pinned
binary.

## 1. Create the post

From the repository root:

```sh
hugo new content posts/my-post-title
```

Use lowercase words joined by hyphens. The folder name becomes the slug and the
URL (`/posts/my-post-title/`). For a journal entry, use `journal/` instead of
`posts/`.

Hugo builds a page bundle from the archetype in `archetypes/posts/index.md`:
a folder with an `index.md` and room for the images beside it. The new file is a
draft, it does not syndicate, and it carries comments that explain each choice.
Delete the comments you do not need before you open the pull request.

## 2. Front matter reference

| Field | Required | What it does |
| --- | --- | --- |
| `title` | yes | The page title and the headline in feeds and cards. |
| `date` | yes | Publication date. The archetype fills in now. A future date is not built until that day. |
| `draft` | yes | `true` keeps the page out of the normal production build. Set `false` to publish. `hugo server --buildDrafts` (section 7) is the exception: it renders drafts so you can preview them. A draft that shows in that preview, or is absent from the production site, is working as intended. |
| `description` | yes, to publish | One or two plain sentences. Used for the page description, the social card and the announcement text. Each page needs its own; the output check refuses duplicates. |
| `slug` | yes | The last part of the URL. The archetype sets it from the folder name. |
| `categories` | yes | One broad topic, for example `["Linux"]`. Reuse an existing category before you add one. |
| `tags` | no | A few specific words. They show as `#tag` links under the title. |
| `syndicate` | yes | `true` lets the deploy job announce the post once it is live. The archetype sets `false`. A journal entry is not announced unless you say so. |
| `syndicated` | no | A map of announcement links (`bluesky`, `mastodon`, `discord`, `matrix`), written by the syndication step. Do not write it by hand for a new post. Only `https://` values render, as "Discuss on ..." links. |
| `image` | no | The headline image: the name of a file in the post's folder, for example `featured.jpg` (section 3). Shown above the title, as a small thumbnail on the Posts and Home cards, and as the social card. No `image` means no hero and the default brand card. |
| `imageAlt` | yes, with `image` | What the headline image shows, in one sentence. The build fails without it. |
| `build` | with a large `image` | Set `publishResources: false` under `build:` when the headline image file is over 300 KB (section 3). |
| `affiliate` | no | A reminder for you and the reviewer. The build does not read it. Set `true` when the post has affiliate links. |
| `aliases` | no | Old paths that should redirect to this page. The build writes a 301 line for each. New posts rarely need one. |
| `archive` | no | `true` or a short text. Shows a dated "this is a record, not a current view" banner. |
| `supersededBy` | no | A site path or an `https://` URL to a newer post. Shows a forward link. |

The summary marker is the line `<!--more-->` after your opening paragraph.
Everything above it is the summary. Write the opening paragraph so it works on
its own.

## 3. Images and alt text

### Headline image

A headline image is optional. To add one:

1. Put the file in the post's folder and name it `featured.<ext>` (`featured.jpg`,
   `featured.png` or `featured.webp`). Only JPEG, PNG and WebP work.
2. Add two lines to the front matter, and write the alt text yourself:

   ```yaml
   image: "featured.jpg"
   imageAlt: "A purple 3D-printed case with a small fan sitting on a mixer with glowing pads"
   build:
     publishResources: false
   ```

3. The page shows it above the title (not lazy loaded, it is the first thing a
   reader sees), makes a small thumbnail of it for the Posts and Home cards, and
   uses a 1200 by 630 JPEG copy as the social card. A post with no `image` shows
   none of that and uses the default brand card.

Rules:

- `imageAlt` is required. A missing or `TODO alt text` value fails the build.
  The thumbnail on a card is decorative (empty alt) because the title link sits
  next to it; the hero carries the alt text.
- The page uses resized WebP copies, never the original file. The `build:` lines
  keep the original out of the published site; the budget check
  (`scripts/check-budget.py`) fails any image file over 300 KB. A small file
  does not need them.
- Landscape photos about 1200 pixels wide or more work best. The hero is capped
  in height and never cropped, so a logo or a square graphic is letterboxed on
  the dark surface instead of cut off.
- Remove EXIF data and GPS location first (`scripts/check-image-metadata.py`
  fails the build otherwise). `exiftool -all= featured.jpg` does it without
  re-encoding the picture. Keep the color profile on photos that have one:
  `exiftool -all= -tagsfromfile @ -icc_profile featured.jpg`.
- A value that starts with `/` or `https://` is a site path or URL used for the
  social card only: no hero, no thumbnail.

### Images in the text

Put each image in the post's folder, next to `index.md`. Only those files are
allowed. A remote image, or an image from elsewhere in the site, fails the
build.

```md
![A terminal showing the failed login attempts, grouped by hour](failed-logins.webp)
```

Rules:

- Use WebP when you can. JPEG and PNG also work. Other formats fail the build.
- Keep files small. Resize before you commit; the page makes smaller copies for
  small screens, but the original still ships in the repository. If a size
  budget has been added to the CI gates, the check names the limit.
- Alt text is required. An empty one fails the build.
- The text `TODO alt text` marks an image that still needs a description (the
  WordPress converter writes it). It is allowed in a draft and fails the build
  on a published page.
- Describe what the image shows and why it is there. Do not start with "image
  of". If the image is only decoration, leave it out.
- Remove EXIF data and GPS location from photos before you add them.
- Crop or blur anything private: screen names, addresses, serial numbers,
  device labels.

## 4. Affiliate links and the disclosure

If a post has an affiliate link:

1. Set `affiliate: true` in the front matter.
2. Say so near the first link, in plain words.
3. Keep the line "As an Amazon Associate I earn from qualifying purchases."
   once in the body for Amazon links.
4. Mark the link text clearly. Do not hide it behind a button or a shortener
   without saying what it is.

Long lists of products belong on the Products page (`data/products.yaml`),
which carries its own disclosure at the bottom of the page. Change that disclosure text only
with the maintainer's agreement.

## 5. Syndication fields

`syndicate` tells the deploy job whether to announce the post after it is live.
Leave it `false` while you write. Set it to `true` only for a post that should
be announced. The announcement uses the title, the description and the canonical
URL, so the description is the one writing step that feeds both the page and the
announcement. Posts converted from the old site are always `false`, so old posts
are never announced again.

The contract is in `docs/redesign-brief.md`, section 5.

## 6. Draft workflow

1. Create the post. It starts as `draft: true`.
2. Write it. Preview with drafts shown (see the next section).
3. Fill in `description`, `categories`, `tags` and the alt text.
4. Set `draft: false`.
5. Run the checks (section 8).
6. Open a pull request.

A draft is never built, so it adds nothing to the site, the feed, the sitemap
or `_redirects`.

## 7. Preview locally

```sh
hugo server --buildDrafts
```

The preview address is printed in the terminal. Without `--buildDrafts`, the
server shows only published pages, which is what the real site will show.

## 8. What CI checks and why

CI builds the site twice (production and staging) and then runs checks on the
output. These are the ones a post meets:

- `scripts/check-output.sh` reads the built files. It fails on a missing
  description, canonical link or social card tags, a duplicate description, a
  script or style the Content Security Policy would block, an `http://`
  reference, and an alias without its redirect line.
- The Content Security Policy in `static/_headers` allows only the site's own
  files: no third-party scripts, styles, fonts or images, and no inline script
  or style. So a post cannot embed a video, a tweet or an outside image. Link to
  it instead. Raw HTML in Markdown is off for the same reason.
- The image render hook (`layouts/_markup/render-image.html`) fails the build on
  missing alt text, the `TODO alt text` placeholder, an image outside the post's
  folder, and an unsupported format.
- `scripts/check-wording.sh` enforces the house wording rule below.
- `scripts/test-archetype.sh` proves that a post made from the archetype builds
  and passes the output checks, and that a missing alt text fails.
- Secret and shell scans run on every pull request.

To run the ones you need before you push:

```sh
hugo --minify --gc
EXPECT_ENV=production scripts/check-output.sh public
scripts/check-wording.sh
scripts/test-archetype.sh
```

## 9. House wording

Never use the short form of the word cryptocurrency. Write "cryptocurrency" for
coins and payments, or name the coin. Write "cryptography" for the math and the
protocols. `scripts/check-wording.sh` fails on the short form in any file, and
the words "cryptography", "cryptographic" and "cryptosystem" are fine.

Use American English. Keep sentences short. Do not use em dashes.

## 10. Private data

The site is public and the repository is public. Never put any of these in a
post, an image, a commit message, an issue or a pull request:

- a real amateur radio callsign or grid square
- the name of an employer or a client
- the name or address of a real machine, or any internal hostname or IP address
- a serial number or an asset tag
- a password, a token, a key or a recovery phrase
- a location more precise than a city

Use placeholders: `N0CALL`, `N0TST`, `FN31pr`, `host.example`, `192.0.2.1`.

If you import old material, the WordPress converter in `tools/wxr2hugo/` has a
scrub pass that stops on private data. See [scrub-terms.md](scrub-terms.md). The
scrub pass is a safety net, not a substitute for reading what you wrote.

## 11. Propose a post by pull request

1. Open an issue with the "Post proposal" template. State the topic, who it is
   for and what the reader will learn. Wait for a reply before you write a long
   post.
2. Fork the repository and create a branch from `main`.
3. Create the post as above. Keep one post per pull request.
4. Run the checks (section 8).
5. Open the pull request. Fill in the template and link the issue.
6. Fix review comments with new commits. The maintainer merges when `CI green`
   passes.

The maintainer may ask for changes in tone or wording.
