# Share links on posts (issue 220)

Under each post and journal entry, after the permalink line, a "Share" row lists
the targets in `data/share.yaml`. They replace the "Discuss on Mastodon" links,
which did not work. The `syndicated` front matter map is kept as data and is not
rendered. The canonical permalink line is kept.

Built by `layouts/_partials/share.html` (called from `layouts/single.html`, posts
and journal only). Static anchors, no embed, no third-party script, no API key,
no tracking parameter. CSP in `static/_headers` is unchanged. Every link carries
`rel="noopener noreferrer"` and `target="_blank"`, a visible label, and an
accessible name that holds the label ("Share on Threads"). Targets are at least
32 px tall (`assets/css/pages/share.css`). The label is "Twitter" everywhere, by
the owner's ruling, and its icon is the earlier bird mark, also on purpose.

All values are percent-encoded (spaces as `%20`). Placeholders in a template:
`{title}`, `{url}` (the permalink), `{text}` (title cut to 200 characters, a
space, the permalink), `{image}` (front matter `image` as an absolute URL).

## Where each URL came from

Read by a researcher on **2026-11-08**. "Vendor" means the vendor's own
documentation page. Anything else can change without notice and needs a manual
click test while logged in and logged out (the checklist is in the pull request).
The test (`scripts/test-share.sh`) checks the SHAPE of every URL against the
page's permalink and title; it does not ask the remote site.

| Target | Template | Source |
| --- | --- | --- |
| Threads | `https://www.threads.com/intent/post?text=..&url=..` | Vendor: https://developers.facebook.com/docs/threads/threads-web-intents (the domain is threads.com, not threads.net) |
| Bluesky | `https://bsky.app/intent/compose?text=..` | Vendor: https://raw.githubusercontent.com/bluesky-social/bsky-docs/main/docs/advanced-guides/intent-links.md (the raw docs source; the rendered page came back empty). Text only, so the link goes inside the text; 300 graphemes at most |
| Twitter | `https://x.com/intent/tweet?text=..&url=..` | Vendor: https://docs.x.com/x-for-websites/post-button/guides/web-intent.md. `twitter.com/intent/tweet` redirects (301) to x.com, so the href uses x.com |
| Email | `mailto:?subject=..&body=..` | Standard: RFC 6068 |
| Mastodon | `https://HOST/share?text=..` | **Inferred from source, read 2026-11-09** (not on docs.joinmastodon.org): `config/routes.rb` has `resource :share, only: [:show]` (https://github.com/mastodon/mastodon/blob/main/config/routes.rb), and `render_initial_state` in `app/helpers/application_helper.rb` builds the compose text from `[params[:title], params[:text], params[:url]]` joined by spaces. Needs a login on that instance. No default instance |
| Reddit | `https://www.reddit.com/submit?url=..&title=..` | Third-party only; no vendor page found |
| LinkedIn | `https://www.linkedin.com/sharing/share-offsite/?url=..` | Third-party; `url` only. The vendor docs cover an API and a script plugin, not this URL |
| Facebook | `https://www.facebook.com/sharer/sharer.php?u=..` | Third-party; `u` only. The vendor-documented dialog needs an app id, so it is not used |
| Hacker News | `https://news.ycombinator.com/submitlink?u=..&t=..` | Third-party, forum-sourced; shows a login screen when logged out |
| Pinterest | `https://pinterest.com/pin/create/button/?url=..&media=..&description=..` | Third-party. The endpoint wants an image: `media` is the post's front matter `image`; a post with no image has **no** Pinterest button. `description` may be ignored |
| Lemmy | `https://HOST/create_post?title=..&url=..` | **Inferred from source, read 2026-11-09** (not on join-lemmy.org docs): lemmy-ui `src/shared/components/post/create-post.tsx` `getCreatePostQueryParams` reads `communityId`, `url`, `body`, `languageId`, `nsfw`, `customThumbnailUrl`, `title` and `altText` from the query (https://github.com/LemmyNet/lemmy-ui). Needs a login on that instance. No default instance |
| Copy link | none (button) | Standard: https://developer.mozilla.org/en-US/docs/Web/API/Clipboard/writeText. `navigator.clipboard.writeText` in a click handler, secure context (HTTPS) only; on success the page's live region says "Link copied" for a few seconds; if the clipboard is blocked it says "Copy failed" and shows the link selected in a field (no browser prompt) |

Discord and Matrix have no share intent (the Matrix spec limits matrix.to links to room, user and event ids; Discord has none) and were removed from the panel on 2026-11-09 (issue 289); Copy link covers them.

The Email link is the only `mailto:` the output check accepts, and only in the
exact shape `mailto:?subject=V&body=V` with percent-encoded V holding no
email-shaped text once decoded (`scripts/scan-markup.py`). A post title that
decodes to `name@host` therefore fails the build until it is reworded.

The Email link is wrapped in `<!--email_off-->` and `<!--/email_off-->`
(Cloudflare's documented opt-out, read 2026-11-08:
https://developers.cloudflare.com/waf/tools/scrape-shield/email-address-obfuscation/).
Without it the edge rewrote the `mailto:` href to `/cdn-cgi/l/email-protection#...`
and injected `email-decode.min.js` into every post, which broke the link without
JavaScript and failed the post-deploy smoke test (issue 249). The minifier drops
comments by default, so `hugo.toml` sets `[minify.tdewolff.html] keepComments`;
these two markers are the only comments in the output.

## Behavior without JavaScript

The anchors work as they are. The buttons (Mastodon, Lemmy, Copy
link) carry `hidden` and appear only when `/share.js` runs. The documented
fallback is the permalink line above the row: a plain link whose text can be
selected and copied, so a visitor without script can still paste the address into
Mastodon, Lemmy, Discord or Matrix.

## The instance picker and `/share.js`

Mastodon and Lemmy are per instance, so there is no single URL. The icon opens an
inline picker under the icons (a labelled field, a Remember checkbox, Share and
Cancel); no browser prompt. Focus moves into the field, Escape or Cancel closes
it and returns focus to the icon, Enter shares. It loads nothing from another
site, and the host typed is never sent to this site or anyone else. Share opens
in a new tab with `noopener,noreferrer`:

- Mastodon: `https://HOST/share?text=TITLE PERMALINK`
- Lemmy: `https://HOST/create_post?title=TITLE&url=PERMALINK`

The host is trimmed and lowercased, then validated with one rule, at submit:
lowercase ASCII labels separated by dots, a letter or `xn--` last label, and the
parsed host must equal the value. A scheme, path, query, fragment, userinfo,
port, space, IP address or non-ASCII lookalike is refused with a message in the
live region (an international name is typed in its `xn--` form). The host is kept
in `localStorage` (`mastodonServer`, `lemmyServer`, this site only) only if
Remember is ticked, and unticking it removes the stored value. A remembered host
prefills the field (checked) and a stored value that fails the rule is ignored.
If storage is blocked the share still works.

Copy link: on success the live region (`role=status`, polite) says "Link copied"
for five seconds. If the clipboard is blocked or the page is not a secure context
it says "Copy failed. The link is selected: press Ctrl+C." and reveals a read-only
field holding the link, selected. `/share.js` is pinned (`share.js.sha256`), under
1 KB gzip, and allowed on `posts/*/index.html` and `journal/*/index.html` only
(`docs/pinned-script.md`).

## Icons

Platform glyphs are first-party files under `static/brand/` used as CSS masks
(`assets/css/pages/icons.css`, `share.css`). Threads, Bluesky and Mastodon reuse `static/brand/icons/` (Simple Icons, see `brand/ICONS.md`).
Twitter (file `bird.svg`), Reddit, LinkedIn, Facebook, Hacker News, Pinterest, Email and Copy link
come from Font Awesome Free 7.3.1 (icons CC BY 4.0), in `static/brand/share/`,
unmodified, with a provenance line each in `brand/approved-assets.txt`. Lemmy is
the Simple Icons 16.36.0 glyph, whose per-icon license is the Lemmy project's
AGPL v3 (not the CC0 of the other Simple Icons files); the license text is kept
in `brand/LICENSE-lemmy-agpl-3.0.txt`.

The share block is one quiet panel: a grid of equal icon buttons (the words are
hidden, each link keeps its `aria-label` and a `title` tooltip) and a Copy link
button with its words. The picker, when open, takes a full row under the icons.

## Changing the list

Edit `data/share.yaml` (a template change needs its source and date), then run
`scripts/test-share.sh`. A new target needs an icon rule in `share.css` and a
manifest line.
