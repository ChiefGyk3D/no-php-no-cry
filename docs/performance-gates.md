# Performance and accessibility gates

Issue 65, item 18 of the redesign plan (`docs/redesign-brief.md` section 10 and
12). Two scripts run in CI on every pull request, after the site is built:

| Script | Needs | What it does |
|---|---|---|
| `scripts/check-budget.py [dir]` | Python 3 only | Static size budget per page and per asset type |
| `scripts/browser-gate.py [dir]` | Chrome or Chromium, Python 3 | Loads each template in a real browser at four widths |

Both exit 1 on any finding and print `[rule] page detail` lines. Page content is
never printed. Their negative tests are `scripts/test-check-budget.sh` (no
browser) and `scripts/test-browser-gate.sh` (fixture sites, one broken rule each).

## Size budget (`check-budget.py`)

Measured on the built site, nothing fetched or run. Text types (HTML, CSS, SVG,
TTF, XML, JS) are measured gzip -9 because the host compresses them; woff2, WebP,
PNG and the other already-compressed types are measured as stored. Where the
browser chooses, the upper bound counts: every `url()` in a stylesheet, and the
largest candidate of an `<img srcset>`.

| Rule | Limit | Today (largest) | Source |
|---|---|---|---|
| `js-count`, `js-name`, `js-page` | only the hash-pinned scripts ship, each only on its own page; the table is read from `PINNED_SCRIPTS` in `scripts/artifact-rules.sh` (today `/copy.js` on `/support/`, `/search.js` on `/search/` and `/share.js` on posts and journal entries), and `test-check-budget.sh` fails if the two ever differ; any `.js`, `.mjs` or `.cjs` file counts, the file count limit is the size of that table, and each script is under 1 KB gzip (`js-size`) | `/copy.js` and `/search.js` (2 files) | docs/pinned-script.md; the hash pin and CSP rules stay in `check-output.sh` |
| `js-size` | 1 KB gzip | n/a | brief section 10 |
| `css-count`, `css-size` | 1 stylesheet per page, 20 KB gzip | 6.1 KB (6.3 KB on Home and 404) | brief (target 12 KB) |
| `font-count`, `font-size` | at most 2 font files per page, each 30 KB transferred | Jost 26.6 KB, Orbitron 19.9 KB | brief says one font; the brand kit ships two (Jost body, Orbitron headings), so the count is 2 |
| `html-size` | 15 KB gzip per page | 4.2 KB | brief: home page HTML |
| `image-size` | 120 KB per image an `<img>` loads | 20.7 KB | brief |
| `image-file-size` | 300 KB per image file anywhere in the build | 267 KB (Open Graph card, never loaded by a page) | local limit |
| `page-total` | 150 KB cold transfer per page | 82.1 KB (Home, the largest) | brief: home page |
| `post-no-images` | 80 KB for a post page without its body images | 61.0 KB for the sample post; 61.8 to 64.1 KB for four real batch-1 posts (see the fixed weight below) | brief |
| `missing-asset`, `no-pages` | every referenced file exists; there are pages | | |

To change a limit, edit `LIMITS` in the script and this table in one commit.

### Fixed weight of a post page (issue 182)

What every post pays before its own text, measured with the script's own
accounting (gzip -9 for HTML, CSS, SVG and TTF; stored size for woff2 and WebP;
every `url()` in the stylesheet counts, used or not). Measured on the sample post
(a post with about 2 KB of gzip HTML text on top of the shell):

| Item | Raw | Counted |
|---|---|---|
| `fonts/jost-latin-wght-normal.woff2` | 26.6 KB | 26.6 KB |
| `fonts/orbitron-wght.ttf` | 38.6 KB | 19.9 KB |
| `css/site.min.*.css` | 28.9 KB | 6.1 KB |
| the 12 footer social icons (`brand/icons/*.svg`, in the stylesheet) | 9.9 KB | 4.9 KB |
| the post HTML | about 18 KB | about 6 KB |
| Total, sample post | | 61.0 KB, so about 19 KB of the 80 KB limit remains for text |

The Home and 404 penguin ghost (`mascot-512.webp`, 20.7 KB) is its own file,
`assets/css/home-ghost.css`, appended to the stylesheet of those two pages only
(`layouts/baseof.html`). Before issue 182 it sat in `pages/home.css`, so every
page was charged for an image only Home and 404 draw, which left a post about
2 KB for text. `scripts/test-pages.sh` fails if a stylesheet other than Home or
404 mentions `mascot-512`. Not taken, because each changes either the look or the
license position: subsetting Jost or Orbitron (Orbitron carries a Reserved Font
Name, so a subset would need a new name) and converting Orbitron to woff2.

## Browser gate (`browser-gate.py`)

It serves the built directory on `127.0.0.1` with the response headers from the
build's own `_headers` file, so the real Content-Security-Policy is enforced and
a blocked request shows up as a console error. It starts Chrome headless and
talks to it over the DevTools protocol through a pipe: no WebSocket library, no
Node, no pip packages. A fresh tab is used for every page and width.

Templates: home, posts list, the first post, social, products, support, about,
resume, privacy, and 404 (loaded from a path that does not exist, so the page
arrives with status 404; that one status is allowed on that page only).

Widths: 1440, 1024, 768, 393 and 390 CSS px (393 is run at 393 x 852, the iPhone 15
viewport the issue names; 390 at 390 x 844 stays; the rest at 900 px tall). Two more viewports check reflow and zoom
(overflow, console, network, keyboard only): `zoom200` is 1440 px at 200 percent
(720 CSS px, device pixel ratio 2) and `reflow320` is 320 CSS px (WCAG 1.4.10).

| Rule | Fails when | Threshold |
|---|---|---|
| `overflow` | the document is wider than the viewport, at any of the six viewports | 0 px |
| `console` | any console error or warning, uncaught exception, CSP violation | none |
| `network` | a failed request, an HTTP status of 400 or more, a request that leaves 127.0.0.1 | none |
| `axe` | any axe-core violation with tags wcag2a, wcag2aa, wcag21a, wcag21aa, wcag22aa, best-practice | none |
| `lcp` | Largest Contentful Paint over the limit, cold (cache off) | 2000 ms |
| `cls` | Cumulative Layout Shift over the limit (layout shifts not caused by input) | 0.05 |
| `image` | a visible raster `<img>` is drawn wider (CSS px, device pixel ratio 1) than the file the browser chose is wide; SVG is skipped (issue 232) | 0 px |
| `tile` | text or a box inside a `.tile` (the /social/ grid) sticks out of the tile on any of its four sides (half a pixel of slack), so a handle or name that does not wrap is caught at every viewport (issue 170) | 0 px |
| `target` | a control smaller than 44 x 44 CSS px | 44 px |
| `tab` | see below | |
| `toggle` | see below | |
| `setup` | axe-core does not match its hash, no browser, no pages | |

LCP and CLS are measured under a mid-range phone on 4G, applied at every width:
1.6 Mbps down, 150 ms round trip, 4x CPU slowdown (Lighthouse's mobile preset),
which is stricter than the brief's "mid-range phone, 4G" under 2.0 s. The
gate reads the browser's own `largest-contentful-paint` and `layout-shift`
entries after the page and its fonts have loaded and settled for 700 ms. On a
developer laptop the slowest page measures about 1.2 s, so there is margin for a
slower runner. Throttling is turned off again before axe and the keyboard pass.
When a CLS finding appears, the line names the elements that shifted.

Tap targets: links, buttons, summaries and form controls that are visible and
larger than 1 px. A link inside running text (its block, a paragraph or list
item, has text of its own around the link) is exempt, the WCAG 2.5.8 inline
exception; a link that stands alone (a footer link, a tag, a list title) must be
44 x 44. The skip link is clipped until focused and is covered by the keyboard
pass.

Keyboard (`tab`): Tab is pressed once per focusable control. The first stop must
be the skip link; no control may use a `tabindex` above 0; the focus order must
equal document order, with every control reached; each focused control must be on
screen and show a focus ring (an outline or a box shadow). At 768 px and below,
the Menu button (`.nav-menu .nav-toggle`, a popover button) must open with
Enter, move Tab into the list, close with Escape (focus returns to the button),
reopen, and close with Enter again. A click outside the list also closes the
native popover (light dismiss) but is not exercised by the gate.

Fit (`fit`), a standing rule: short pages fit 1920x1080 without scrolling. Each
template not in `FIT_ALLOW` is loaded at 1920x930 (the content area of a 1920x1080
browser) and its `scrollHeight` must not exceed the viewport height. Pages that
cannot fit (posts, a post, products, about, resume, search) are named in
`FIT_ALLOW` in `scripts/browser-gate.py`, each with a reason; a stale name fails
`[setup]`. Home, Social, Support, Privacy and the 404 page must fit.

Hero and box text (`hero`, `boxtext`, issue 308): every template is loaded at 1878x930 (the
owner's real window) and 1366x768. `[hero]` fails when the `.hero-actions` buttons are on more
than one row or the page scrolls sideways; `[boxtext]` fails when the widest text line of a
bordered box (`.panel`, `.skill-group`, `.about-contact`) with a wrapping paragraph ends more
than 25 percent of the box width short of its right edge. See `docs/viewport-matrix.md`.

Toggle (`toggle`): the dark-only brand kit has no theme toggle yet (the redesign
brief's `/theme.js` is not implemented). The check runs only when the build
ships `/theme.js`: the header must hold a real `<button>` (`aria-pressed` or
`data-theme-toggle`), Tab must reach it, and Enter must change `data-theme` or
`aria-pressed`. Today it is dormant; `test-browser-gate.sh` proves it bites with
a fixture that ships a script and no button.

### axe-core

`tools/axe/axe.min.js` is axe-core 4.10.2, unmodified, from the npm tarball
(registry shasum `85228e3e1d8b8532a27659b332e39b7fa0e022df`, integrity
`sha512-RE3mdQ7P3FRSe7eqCWoeQ/Z9QXrtniSjp...`), with its MPL-2.0 `LICENSE`. The
file's sha256 is in `tools/axe/axe.min.js.sha256`; the gate refuses to run if the
file does not match. To upgrade: download the new npm tarball, verify the
registry hash, replace both files, and re-run the gate. Nothing is loaded from a
CDN at run time, and the build output never contains axe.

### What the gate does not prove

- axe cannot decide `color-contrast` where text sits on the page's background
  gradient (it reports "incomplete"). `scripts/check-contrast.py` checks the
  token pairs, and the manual worst-case calculation in the #65 audit passes.
- No screen reader is run. Names, roles and states are checked by axe only.
- Forced-colors and print are not exercised by this gate.
- Chrome is the runner image's Chrome, not a pinned build; a Chrome update can
  move a number slightly, which is why the thresholds keep headroom.
- Lab LCP and CLS on a fixed profile are not field data.

## Running it locally

```sh
hugo --minify --gc --destination /path/to/out
python3 -I scripts/check-budget.py /path/to/out
python3 -I scripts/browser-gate.py /path/to/out --shots /path/to/shots
scripts/test-check-budget.sh && scripts/test-browser-gate.sh
```

`--pages home,post` and `--widths 390` narrow a run while debugging; CI runs
everything. `CHROME=/path/to/chrome` selects a browser. `--shots DIR` saves a
PNG of each page and width.
