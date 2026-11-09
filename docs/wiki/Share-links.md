# Share links

Under each post and journal entry, after the permalink line, a Share row lists
the targets in `data/share.yaml`. It replaced the "Discuss on Mastodon" links.
The `syndicated` front matter map is kept as data and is not rendered. The
detailed source notes live in `docs/share-links.md`; this page is the short
version.

## What a post shows

- **The permalink line**: the canonical address of the post as a plain,
  selectable link. It works without JavaScript and is the fallback for every
  button below.
- **Plain share links**, built by `layouts/_partials/share.html` from the post's
  address and title: Threads, Bluesky, Twitter, Reddit, LinkedIn, Facebook,
  Hacker News, Pinterest and Email. Every value is percent-encoded, no tracking
  parameter is added, and each link opens in a new tab with
  `rel="noopener noreferrer"`. Pinterest needs an image, so it appears only on
  posts with a [headline image](Headline-images.md). Email is a `mailto:` with
  no address.
- **Buttons** (hidden until the script runs): Copy link, and copy-link buttons
  for Discord, Matrix and Lemmy, which have no documented share URL.
- **A Mastodon button.** Mastodon has no single share address, so on the first
  click it asks for your server name, checks its shape, keeps it in your
  browser's local storage (this site only) and opens that server's share page.
  A "Change server" button appears once a server is remembered. The Privacy page
  says this.

The post and journal pages also carry Open Graph and Twitter card tags, so a
link pasted into a chat or a social network gets a title, description and image.
The image is the post's headline image or the default brand card. See
`layouts/_partials/head-meta.html`.

## The one script

The buttons need `/share.js`, the third pinned script. It is under 1 KB gzip,
hash-pinned in `share.js.sha256`, and allowed only on posts and journal entries
(a page pattern in the allowlist, not one named page). The Content Security
Policy did not change. The stored Mastodon server is checked again every time it
is read, and a bad value is deleted. See [Search and tags](Search-and-tags.md)
for how a pinned script is held to its pages.

## Why the design is like this

- **Plain links first.** Anchors work with scripts off.
- **No tracking.** No parameters are added to the shared address.
- **Every script is a decision.** Each new one is a policy change with its own
  review. See [Build checks and budgets](Build-checks-and-budgets.md).
- **Source and date for every URL.** `data/share.yaml` and `docs/share-links.md`
  record where each template came from and when it was read. Several are
  third-party and can change without notice. `scripts/test-share.sh` checks the
  shape of each URL, not the remote site.

## Changing the list

Edit `data/share.yaml` (a template change needs its source and date), then run
`scripts/test-share.sh`.
