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
scripts/test-archetype.sh
```

`scripts/test-archetype.sh` proves that a post made from the archetype builds and
passes the output checks and that a missing alt text fails the build.

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
