# Share links

> **Lands with PR #229.** The share row described in the second half of this
> page is an open pull request and is not on `main` yet. The first half is what
> `main` does today. Drop this note and rewrite the page from the merged code
> when the pull request merges.

## What a post shows today (on main)

Under the post body, `layouts/single.html` writes a small block:

- **A permalink line**: the canonical address of the post as a plain, selectable
  link. It works without JavaScript.
- **"Discuss on ..." links**, only when the post's `syndicated` front matter map
  holds `https://` values. The keys are `bluesky`, `mastodon`, `discord` and
  `matrix`. They are written by an announcement step after a post goes out (no
  workflow in this repository does that today), so most posts show none. A value
  that does not start with `https://` is not rendered.

The post and journal pages also carry Open Graph and Twitter card tags, so a
link pasted into a chat or a social network gets a title, description and image.
The image is the post's [headline image](Headline-images.md) or the default
brand card. See `layouts/_partials/head-meta.html`.

There are no share buttons that load a third-party script, and the design
decision behind that is recorded in `docs/redesign-brief.md`, section 5.

## What PR #229 changes (not merged)

From the pull request description at the time of writing; the merged code is
the source of truth.

- The "Discuss on Mastodon" links are replaced by a share row. The permalink
  line stays, and the `syndicated` data stays in front matter but is no longer
  rendered.
- Each target is a plain link built from the post's address and title, with
  every value percent-encoded and no tracking parameters. The URL templates and
  where each one was verified are kept in one data file, with a read date.
- Targets listed in the pull request: Threads, Bluesky, Mastodon, Twitter,
  Discord, Matrix, Lemmy, Reddit, LinkedIn, Facebook, Hacker News, Pinterest
  (only on posts with a headline image), Email (a `mailto:` with no address) and
  Copy link.
- Mastodon, Discord, Matrix, Lemmy and Copy link are buttons that need a third
  pinned script, hidden until it runs. Mastodon asks for the visitor's server
  once and keeps it in the browser's local storage; the pull request adds a
  sentence about that to the Privacy page.
- The build checks learn a new rule: a pinned script may be allowed on a page
  pattern (all posts and journal entries) instead of one page, and a `mailto:`
  is accepted only when it has no address.

Open questions in that pull request are recorded there (the third script, the
storage note, the Email target, a missing Lemmy icon).

## Why the design is like this

- **Plain links first.** Anchors work with scripts off.
- **No tracking.** No parameters are added to the shared address.
- **Every script is a decision.** The site allows two pinned scripts today; a
  third is a policy change with its own review. See
  [Search and tags](Search-and-tags.md) for how a pinned script is held to its
  page, and [Build checks and budgets](Build-checks-and-budgets.md).
