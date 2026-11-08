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
| Mastodon | `https://SERVER/share?text=..` | **Inferred**: the route exists in Mastodon's source, undocumented; the `text` parameter is unconfirmed. Needs a login on that server. No default server |
| Reddit | `https://www.reddit.com/submit?url=..&title=..` | Third-party only; no vendor page found |
| LinkedIn | `https://www.linkedin.com/sharing/share-offsite/?url=..` | Third-party; `url` only. The vendor docs cover an API and a script plugin, not this URL |
| Facebook | `https://www.facebook.com/sharer/sharer.php?u=..` | Third-party; `u` only. The vendor-documented dialog needs an app id, so it is not used |
| Hacker News | `https://news.ycombinator.com/submitlink?u=..&t=..` | Third-party, forum-sourced; shows a login screen when logged out |
| Pinterest | `https://pinterest.com/pin/create/button/?url=..&media=..&description=..` | Third-party. The endpoint wants an image: `media` is the post's front matter `image`; a post with no image has **no** Pinterest button. `description` may be ignored |
| Discord, Matrix, Lemmy | none (copy-link buttons) | No documented share URL. The Matrix spec limits matrix.to links to room, user and event ids. Lemmy: a per-instance submit URL is unconfirmed; if one is confirmed it can reuse the Mastodon prompt |
| Copy link | none (button) | Standard: https://developer.mozilla.org/en-US/docs/Web/API/Clipboard/writeText. `navigator.clipboard.writeText` in a click handler, secure context (HTTPS) only; fallback is a prompt holding the link |

The Email link is the only `mailto:` the output check accepts, and only in the
exact shape `mailto:?subject=V&body=V` with percent-encoded V holding no
email-shaped text once decoded (`scripts/scan-markup.py`). A post title that
decodes to `name@host` therefore fails the build until it is reworded.

## Behavior without JavaScript

The anchors work as they are. The buttons (Mastodon, Discord, Matrix, Lemmy, Copy
link) carry `hidden` and appear only when `/share.js` runs. The documented
fallback is the permalink line above the row: a plain link whose text can be
selected and copied, so a visitor without script can still paste the address into
Mastodon, Discord, Matrix or Lemmy.

## Mastodon and `/share.js`

Mastodon has no single share URL: it is per server. On first click `/share.js`
asks for the server name, checks its shape, keeps it in `localStorage`
(`mastodonServer`, this site only) and opens `https://SERVER/share?text=TITLE PERMALINK`
in a new tab with `noopener,noreferrer`. After that it opens directly; a "Change
server" button appears once a server is remembered. If storage is blocked the
server is asked for each time.

The server name is validated with one rule, at the prompt and again every time a
stored value is read, right before the new tab opens: lowercase ASCII labels
separated by dots, a letter or `xn--` last label, and the parsed host must equal
the value. A stored value that fails (userinfo, path, query, fragment, space,
uppercase, a port, an IP address, a non-ASCII lookalike) is deleted and the
prompt asks again. Ports are not accepted, and an international name must be
typed in its `xn--` form. A pasted `https://` URL is reduced to its host. `/share.js` is pinned (`share.js.sha256`), under
1 KB gzip, and allowed on `posts/*/index.html` and `journal/*/index.html` only
(`docs/pinned-script.md`).

## Icons

Platform glyphs are first-party files under `static/brand/` used as CSS masks
(`assets/css/pages/icons.css`, `share.css`). Threads, Bluesky, Mastodon, Discord
and Matrix reuse `static/brand/icons/` (Simple Icons, see `brand/ICONS.md`).
Twitter (file `bird.svg`), Reddit, LinkedIn, Facebook, Hacker News, Pinterest, Email and Copy link
come from Font Awesome Free 7.3.1 (icons CC BY 4.0), in `static/brand/share/`,
unmodified, with a provenance line each in `brand/approved-assets.txt`. **Lemmy
has no icon**: no clearly licensed glyph was available, so the button is text
only until one is supplied.

## Changing the list

Edit `data/share.yaml` (a template change needs its source and date), then run
`scripts/test-share.sh`. A new target needs an icon rule in `share.css` and a
manifest line, or no icon (`lemmy` is the only text-only exception the test
allows).
