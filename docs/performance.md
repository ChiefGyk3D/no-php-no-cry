# PageSpeed and Lighthouse scores

Issue 232. Lab measurements of the built site, with the opportunities each run
named. The pass/fail thresholds the repo enforces are in
`docs/performance-gates.md`; this page is the Lighthouse record. Lab numbers are
not field data and move a few points between runs (see "Noise").

## How it was measured (2026-11-08)

- Lighthouse 13.6.0 (npm, installed in a private directory), Google Chrome
  156.0.8078.73, headless, Hugo 0.168.0 (`.hugo-version`).
- Build: `hugo --minify --gc --destination <dir>` (production environment).
- Served on `127.0.0.1` by a small static server that sends the build's own
  `_headers` (the real CSP), gzip for text types, and `Cache-Control:
  public, max-age=0, must-revalidate` (the host's default for static files).
- Command per page and strategy (mobile is the default preset, desktop adds
  `--preset=desktop`):
  `lighthouse URL [--preset=desktop] --only-categories=performance,accessibility,best-practices,seo --output=json --chrome-flags="--headless=new --no-sandbox"`
- Pages: home, a published post (`/posts/boosting-your-mastodon-servers-...`),
  the posts list, search, about, and the 404 page. Lighthouse refuses a page
  that answers 404, so the 404 page was audited as `/404.html`, which serves
  the same file with status 200.
- The public PageSpeed Insights API (keyless, `runPagespeed` for the staging
  address in `docs/deploy.md`) answered HTTP 429 `RESOURCE_EXHAUSTED` ("Queries
  per day" quota of the shared project) on 2026-11-08, so no PSI numbers are
  recorded. Lighthouse was run against the public staging site instead (below).

## Scores: local production build

P = performance, A = accessibility, BP = best practices, SEO. Before is
`origin/main` at db5e615; after is this branch.

| Page | Strategy | Before P/A/BP/SEO | After P/A/BP/SEO |
|---|---|---|---|
| Home | mobile | 100/100/100/100 | 97/100/100/100 (noise, see below) |
| Home | desktop | 100/100/100/100 | 100/100/100/100 |
| Post | mobile | 99/100/100/100 | 100/100/100/100 |
| Post | desktop | 100/100/100/100 | 100/100/100/100 |
| Posts list | mobile | 100/100/100/100 | 100/100/100/100 |
| Posts list | desktop | 100/100/100/100 | 100/100/100/100 |
| Search | mobile | 100/100/100/100 | 100/100/100/100 |
| Search | desktop | 100/100/100/100 | 100/100/100/100 |
| About | mobile | 100/100/100/100 | 99/100/100/100 (noise) |
| About | desktop | 100/100/**96**/100 | 100/100/**100**/100 |
| 404 | mobile | 100/100/100/**69** | 100/100/100/**69** |
| 404 | desktop | 100/100/100/**69** | 100/100/100/**69** |

Noise: Home mobile was re-run three more times on the unchanged page and scored
97, 99 and 96 (Total Blocking Time 0 to 180 ms on a shared laptop); About mobile
moved the same way. Performance differences of 1 to 4 points between the two
columns are run-to-run variance, not a change in the page. LCP stayed at 0.8 s
(mobile) and 0.2 to 0.4 s (desktop) for every page except the post (1.7 s, the
hero photo, simulated Slow 4G); CLS was 0 everywhere.

## Scores: public staging site (live headers)

Lighthouse run from this machine against `https://test-blog.chiefgyk3d.com`
(2026-11-08), before this change. Staging is deliberately `noindex` and its
`robots.txt` disallows everything, and Cloudflare injects its analytics beacon.

| Page | Mobile P/A/BP/SEO | Desktop P/A/BP/SEO |
|---|---|---|
| Home | 99/100/92/69 | 100/100/92/69 |
| Post | 95/100/92/69 | 100/100/92/69 |
| Posts list | 99/100/92/69 | 100/100/92/69 |
| Search | 99/100/92/69 | 100/100/92/69 |
| About | 100/100/92/69 | 100/100/88/69 |

## What changed

- About page mascot (issue 232): `mascot-128.webp` was drawn 176 px wide from
  1024 px up, so Lighthouse failed `image-size-responsive` (Best Practices 96 on
  desktop). The image now has a `srcset` (128w, 256w) and `sizes` matching the CSS
  widths (11rem from 60rem, 5rem from 40rem, 4rem below). `mascot-256.webp`
  already shipped; the largest candidate is 6.4 KB, far inside the budget.
- New browser-gate rule `image` (`scripts/browser-gate.py`,
  `docs/performance-gates.md`): any visible raster `<img>` drawn wider than the
  file the browser chose fails. It was proven red on the unfixed About page (two
  findings, 1024 and 1440 px) and on a fixture (`low-res-image` in
  `scripts/test-browser-gate.sh`).

## What cannot reach 100, and who owns it

| Item | Evidence | Owner action |
|---|---|---|
| Staging SEO 69 (`is-crawlable`) | `<meta name="robots" content="noindex, nofollow">` and `robots.txt` `Disallow: /` on test-blog, by design | None. Production builds score SEO 100 locally on every indexable page. Re-measure after cutover. |
| 404 page SEO 69 | The 404 template carries `<meta name=robots content="noindex">` | None. A not-found page should not be indexed; keep it. |
| Staging Best Practices 92 (`errors-in-console`, `inspector-issues`) | The Cloudflare beacon is requested as `https://static.cloudflareinsights.com/beacon.min.js/v<token>`; the CSP names `.../beacon.min.js`, a path source that matches that exact path only, so the browser blocks it ("violates the following Content Security Policy directive") | Owner decision, not changed here (the CSP stays as is, and `check-output.sh` pins the exact entry). Either accept the console error, turn Web Analytics automatic injection off, or approve a wider beacon source (for example the `static.cloudflareinsights.com` host) in `static/_headers` and `check-output.sh` together. The blocked URL with the suffix was observed in Lighthouse's console audit on staging, 2026-11-08. |
| `render-blocking-insight` (CSS, 40 to 150 ms on mobile) | One 6 to 7 KB stylesheet is the only blocking request. Inlining it needs `style-src 'unsafe-inline'` | None. The strict CSP rules it out. It does not lower the Performance score. |
| `cache-insight` and cache lifetime | Fixed in issue 240: `static/_headers` has a second block, `/css/*`, that sets `Cache-Control: public, max-age=31536000, immutable`. Every file there is named by its own sha256 (Hugo fingerprint), proven on every build by `check-output.sh` (`immutable-unhashed`, `missing-immutable`, `headers-structure`). Fonts, brand images, post images and the pinned scripts keep unhashed names and the host default, on purpose | None. Cloudflare Pages merges the matching blocks; confirm with `curl -sI` on the staging stylesheet after the first deploy (the local test server applies `_headers` the same way, but the host is the judge). |
| `image-delivery-insight` on the post (15 KiB) | The hero is already `fetchpriority=high`, `srcset`, WebP, with dimensions | Optional: a smaller hero encode. Not a scored audit. |
| `network-dependency-tree-insight`, `lcp-discovery-insight`, `max-potential-fid` | Informational insights, score 0 with no weight in the Performance score; the web manifest and CSS are the whole chain (141 ms) | None. |
| TLS and HTTP version | Staging answers `HTTP/2` with Brotli (`content-encoding: br`) | None. |

## Full sweep of every page type (issue 248, 2026-11-08)

Goal: every Lighthouse category at 100, mobile and desktop, on every page type
the site controls. Same tooling as above (Lighthouse 13.6.0, Chrome headless,
Hugo 0.168.0, `hugo --minify --gc`, a local static server that sends the build's
own `_headers` and gzip), three runs per page and strategy, median of the three
reported. One post (`best-headphone-...`) is a draft, so it was measured from a
`hugo -D` build of the same tree.

Pages: home, posts list, a long post with four body images, a short post,
journal list, journal entry, search, a tag page (`/tags/mastodon/`; there is no
`/tags/` index page, it answers 404), about, resume, support, social, products,
privacy and 404 (Lighthouse refuses a 404 status, so it was audited through a path that serves the same file with status 200).

| Result | Before | After |
|---|---|---|
| Local, mobile, 14 indexable page types | 100/100/100/100 | 100/100/100/100 |
| Local, desktop, 14 indexable page types | 100/100/100/100 | 100/100/100/100 |
| Local 404, mobile and desktop | 100/100/100/**69** | 100/100/100/**69** |

Run to run, Performance on a loaded laptop moves 1 to 4 points (Total Blocking
Time); every median above is 100. The one category under 100 on the local build
is the 404 page's SEO score.

### 404 SEO 69 is by design

The failing audit is `is-crawlable` ("Page is blocked from indexing"): the 404
template carries `<meta name="robots" content="noindex">` and `check-output.sh`
requires it in production (`noindex-mismatch`). A not-found page should not be
indexed, so the score stays 69. No other audit on that page fails. Do not remove
the tag to chase the number.

### Public staging site, measured separately (host-injected script)

Run from this machine against `https://test-blog.chiefgyk3d.com`, read only,
three runs per page, median. Staging is `noindex` on purpose and Cloudflare
injects scripts at the edge, so these are not the production numbers.

| Pages | Mobile P/A/BP/SEO | Desktop P/A/BP/SEO |
|---|---|---|
| All 14 indexable page types | 99/100/92/69 | 100/100/92/69 |
| 404 (`/404.html`) | 99/100/92/69 | 100/100/92/69 |

- Best Practices 92 on every page: `errors-in-console` and `inspector-issues`.
  Cloudflare injects the Web Analytics beacon as
  `https://static.cloudflareinsights.com/beacon.min.js/v<token>`; the CSP names
  `.../beacon.min.js`, which matches that exact path only, so the browser blocks
  it. Host-controlled; the owner's Cloudflare task is issue 241. The CSP and
  `check-output.sh` are unchanged.
- SEO 69: staging is `noindex` by design (see the table above); production
  builds score 100 on every indexable page.
- Performance 99 on mobile: First Contentful Paint 1.6 to 1.7 s under simulated
  Slow 4G. The one render-blocking request is the stylesheet; inlining it needs
  `style-src 'unsafe-inline'`, which the CSP forbids. Not a defect, no fix.
- On posts that contain an e-mail-shaped string, Cloudflare also injects
  `/cdn-cgi/scripts/.../email-decode.min.js` (Email Address Obfuscation), which
  `cache-insight` flags for a short lifetime. Host-controlled, not in our HTML.
