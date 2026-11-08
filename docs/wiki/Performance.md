# Performance

The goal is a fast page on a mid-range phone on a slow connection, reached by
sending very little: no framework, no third-party request, one small
stylesheet. The numbers are enforced by two scripts on every pull request, not
by a one-time audit. The source of truth is
[docs/performance-gates.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/performance-gates.md);
this page is the map.

## What keeps the pages light

- **No JavaScript by default.** Three scripts ship, each under 1 KB gzip and each
  only on its own pages (Support, Search, and posts and journal entries). Everything else is HTML and CSS: the phone
  menu is a native popover, accordions are native `<details>`.
- **No third-party requests.** The Content Security Policy forbids them and the
  build fails on any. Zero external fonts, scripts, styles, images or embeds.
- **One stylesheet per page,** concatenated, minified and fingerprinted by Hugo
  Pipes. Page-specific CSS lives in `assets/css/pages/`, and the penguin ghost
  image used only on Home and 404 is its own file appended on those two pages,
  so a post is not charged for it.
- **Two fonts,** Jost for body text and Orbitron for headings, both served from
  the site and preloaded in the head.
- **Images are resized by the build.** The render hook and the headline-image
  partial write `srcset`, `width` and `height` and lazy loading (the hero is
  eager and `fetchpriority="high"`), and the headline image is served only as
  resized WebP copies. See [Images and alt text](Images-and-alt-text.md) and
  [Headline images](Headline-images.md).
- **Search is part of the page,** not a separate index request.

## The budget, in short

Enforced by `scripts/check-budget.py` (static, no browser). The limits:

| Item | Limit |
| --- | --- |
| Scripts | Only the pinned ones, 1 KB gzip each |
| Stylesheet | One per page, 20 KB gzip |
| Fonts | At most 2 files per page, 30 KB each |
| Page HTML | 15 KB gzip |
| Any image a page loads | 120 KB |
| Any image file in the build | 300 KB |
| A page, cold transfer | 150 KB |
| A post without its body images | 80 KB |

The full table, today's measurements and the fixed weight every post pays are in
`docs/performance-gates.md`. See also
[Build checks and budgets](Build-checks-and-budgets.md).

## Measured in a browser

`scripts/browser-gate.py` serves the built folder on `127.0.0.1` with the real
`_headers`, starts headless Chrome and loads each template at several widths. For
performance it fails when:

| Rule | Limit |
| --- | --- |
| Largest Contentful Paint (cold) | over 2000 ms |
| Cumulative Layout Shift | over 0.05 |
| A failed or blocked request, or any request that leaves the local server | any |
| A console error or a CSP violation | any |
| Horizontal overflow | any, at six viewports including 320 CSS px and 200 percent zoom |
| A visible raster image drawn wider than the file the browser chose | any |

LCP and CLS are measured under a throttled profile (1.6 Mbps down, 150 ms round
trip, 4x CPU slowdown), the same shape as Lighthouse's mobile preset. The gate
waits for the page and its fonts to load and settle before it reads the layout
shift. Fonts use `font-display: optional` with a preload so a late font never
reflows the text. `docs/performance-gates.md` lists what the gate does not prove: these are lab numbers on a fixed profile, not field data, and the Chrome
version is not pinned.

## Lighthouse and PageSpeed

Lighthouse itself is not a CI check, but a pass was done and recorded in
`docs/performance.md` (issue #232, 2026-11-08, Lighthouse 13.6.0). On a local
production build, desktop and mobile scored 100 for accessibility, best practices
and SEO on every page except the 404 page, whose SEO score is 69 on purpose
because it is `noindex`. Performance was 96 to 100; mobile differences of a few
points between runs were noise. The pass fixed the About mascot, which was drawn
wider than its file, by adding a `srcset`, and added an `image` rule to the
browser gate that fails any visible raster image drawn wider than the file the
browser chose. The public staging site scores SEO 69 by design (`noindex`) and
Best Practices 92 because of a blocked analytics beacon request; those are
owner decisions listed in `docs/performance.md`.

## Tips for authors

- Resize images before you commit them and prefer WebP.
- Do not embed. Link.
- Check a long post against the 80 KB post limit with `scripts/check-budget.py`
  on a build.
