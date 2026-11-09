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
| Staging Best Practices 92 (`errors-in-console`, `inspector-issues`) before issue 318 | The Cloudflare beacon is requested as `https://static.cloudflareinsights.com/beacon.min.js/v<token>`; the old CSP entry `.../beacon.min.js` is a path source that matches that exact path only, so the browser blocked it (and the beacon collected nothing) | Fixed in issue 318 (owner decision 2026-11-09): the entry is now `https://static.cloudflareinsights.com/beacon.min.js/`, with a trailing slash. Re-measure Best Practices on the host after the deploy; expected 100. Details: section "CSP entry for the Cloudflare beacon" below. |
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

- Best Practices 92 on every page (measured 2026-11-08, before issue 318): `errors-in-console`
  and `inspector-issues`. Cloudflare injects the Web Analytics beacon as
  `https://static.cloudflareinsights.com/beacon.min.js/v<token>`; the old CSP entry
  `.../beacon.min.js` matched that exact path only, so the browser blocked it and the beacon
  collected nothing. Issue 318 changes the entry to the path prefix
  `.../beacon.min.js/` (below); the score is re-measured after the deploy.
- SEO 69: staging is `noindex` by design (see the table above); production
  builds score 100 on every indexable page.
- Performance 99 on mobile: First Contentful Paint 1.6 to 1.7 s under simulated
  Slow 4G. The one render-blocking request is the stylesheet; inlining it needs
  `style-src 'unsafe-inline'`, which the CSP forbids. Not a defect, no fix.
- On posts that contain an e-mail-shaped string, Cloudflare also injects
  `/cdn-cgi/scripts/.../email-decode.min.js` (Email Address Obfuscation), which
  `cache-insight` flags for a short lifetime. Host-controlled, not in our HTML.

## Trust and Safety items from PageSpeed Insights (issue 259, 2026-11-08)

PageSpeed Insights on the staging host listed four unscored "Trust and Safety"
items and one render-blocking request. What was done, and what was not.

### Cross-Origin-Opener-Policy (done)

`static/_headers` now sends `Cross-Origin-Opener-Policy: same-origin`. Nothing on
the site needs a cross-origin window reference: every `target="_blank"` link in
`layouts/` carries `rel="noopener"` (the share row uses `noopener noreferrer`),
and the one script popup (`share.js`, Mastodon share) calls
`window.open(..., "noopener,noreferrer")`, so it never relied on `window.opener`.
`headers_policy_ok` in `scripts/artifact-rules.sh` accepts the header in the `/*`
block only once with exactly that value, and `headers_coop_ok` plus
`check-output.sh` (`headers-coop`) require it.

### Trusted Types (done: directive added, no policy)

`require-trusted-types-for 'script'` is now in the CSP. Reading the three pinned
scripts for the sinks that directive enforces (innerHTML, outerHTML,
insertAdjacentHTML, document.write, DOMParser, eval, setTimeout or setInterval
with a string, `new Function`, script `src`, iframe srcdoc, embed or object
URLs; source: web.dev/articles/trusted-types, read 2026-11-08): none is used.
`copy.js` builds a textarea with `createElement`, `value` and `setAttribute("readonly", "")`
(not a sink); `search.js` and `share.js` write only `textContent`, `hidden` and
`value`; `window.open` and `prompt` are not Trusted Types sinks. So no policy and
no `trusted-types` directive is needed, and `check-output.sh` rejects one
(`weak-csp`). No pinned script changed, so no `.sha256` file changed.
Risk: Cloudflare's own injected beacon is not ours to audit. If it used a Trusted
Types sink it would log a violation in the console. Observed 2026-11-09: a
parser-inserted script with `integrity` and `crossorigin=anonymous` runs under the full
policy, `require-trusted-types-for 'script'` included (stand-in test, below).

### CSP entry for the Cloudflare beacon (issue 318)

The policy carries `script-src 'self' https://static.cloudflareinsights.com/beacon.min.js/`
and `connect-src 'self'`. Cloudflare's FAQ (web-analytics/faq, "What do I need to add to my
Content Security Policy", read 2026-11-09) names the bare URL and `'self'` for automatic
injection, but the tag it injects loads `/beacon.min.js/v<token>`, which the bare entry does
not match. CSP3 section 6.7.2.12, path-part matching (w3c.github.io/webappsec-csp, read
2026-11-09): a path ending in `/` matches by prefix ("/subdirectory/" matches
"/subdirectory/file"); a path without it matches exactly.

PageSpeed flags any host allowlist in `script-src` as bypassable; a path prefix on one host is the narrowest form the CSP
syntax offers for this script.

Observed in headless Chrome, 2026-11-09, with `default-src 'none'`, `connect-src 'self'` and
`require-trusted-types-for 'script'`, six parser-inserted script tags on the real host name:

| Source in script-src | Blocked | Allowed |
| --- | --- | --- |
| `.../beacon.min.js` (the old entry) | `/beacon.min.js/v<token>`, `/beacon.min.jsx`, `/other.js`, `/beacon.min.js/vABC/extra.js`, `/beacon.min.js/../evil.js` (the browser resolves it to `/evil.js`) | `/beacon.min.js` |
| `.../beacon.min.js/` (the new entry) | `/beacon.min.js`, `/beacon.min.jsx`, `/other.js`, `/evil.js` | `/beacon.min.js/v<token>`, `/beacon.min.js/vABC/extra.js` |
| the host `https://static.cloudflareinsights.com` (not used) | nothing | everything |

So the narrow entry allows the versioned path and nothing outside `/beacon.min.js/` on that
host. It no longer allows the bare `/beacon.min.js`; the injected tag does not use it.

Subresource integrity: the injected tag carries `integrity="sha512-..."` and
`crossorigin="anonymous"` (observed in the staging HTML, 2026-11-09). The policy and the hash are
separate checks. In a stand-in test (a local server on a second port, with the same tag shape,
`Access-Control-Allow-Origin: *`, the hash of its own bytes), under the new entry the script ran;
with a wrong hash it did not run and no policy violation was reported; with the old bare entry
the policy blocked it. Not tested here: the real script (TLS to that host failed on this machine)
and Cloudflare's CORS header on it (INFERRED to be sent, since the docs describe automatic
injection with an integrity attribute; the post-deploy check below proves it).

Every place that pins the entry changed together: `static/_headers`, `scripts/check-output.sh`
(`csp_scripts_ok`, the `weak-csp` substitution), `scripts/check-site-artifact.sh`,
`scripts/smoke-site.sh`, and the mutants in `scripts/test-check-output.sh`,
`scripts/test-smoke-site.sh` and `scripts/test-share.sh`. The old bare entry, the host alone, a
wildcard, a deeper path, another host and a second third-party source all fail `weak-csp`.

After the deploy (the host is the judge):

1. `curl -sI https://test-blog.chiefgyk3d.com/` shows the new `script-src` entry in the
   `Content-Security-Policy` header.
2. Open any page in a browser with the console open: no CSP violation for the beacon, and in
   the network panel a `POST` to `/cdn-cgi/rum` answers 2xx (a `GET` answers 405 by design,
   Cloudflare changelog 2026-05-13).
3. Run Lighthouse on the host: Best Practices 100 (`errors-in-console` and `inspector-issues`
   pass). SEO stays 69 while the host is staging.
4. After a day, the Web Analytics page for the project shows page views. The dashboard path is
   UNVERIFIED; read Cloudflare's current Web Analytics docs first.

### HSTS preload (not enabled: owner decision)

Requirements, from https://hstspreload.org/ (read 2026-11-08): a valid
certificate; HTTP redirects to HTTPS on the same host; every subdomain served
over HTTPS, nested and internal ones included (and `www` if it has a DNS
record); on the base domain the header
`Strict-Transport-Security` with `max-age` of at least 31536000, `includeSubDomains`
and `preload`, redirects included. Inclusion is hard to undo: removal can take
months to reach users through a Chrome release, other browsers promise nothing,
and the requirements must be kept indefinitely.

The site sends `max-age=31536000; includeSubDomains` today. That header applies
only to the host that sent it and its descendants: on `test-blog.chiefgyk3d.com`
it pins that host's subtree for a year for visitors who loaded it, and does not
touch the apex or siblings such as `shop.chiefgyk3d.com`. The preload list works
per registrable domain. Preloading `chiefgyk3d.com` would make browsers refuse
plain HTTP for every subdomain (the links host, instance hosts, Matrix, Discord
redirect, shop, anything else under the zone, current and future), for everyone,
with no expiry. The preload header must also come from the apex
`chiefgyk3d.com`, not from this blog host alone.

Decision needed from the owner: (1) do not preload (recommended until every
`*.chiefgyk3d.com` host, including internal ones, is audited as HTTPS-only);
(2) audit the zone's DNS records first, then preload; (3) preload now. Nothing
is filed for this.

### Render-blocking stylesheet (stays)

`/css/site.min.<hash>.css` (8.7 KiB) is the only blocking request. Inlining it
would need `style-src 'unsafe-inline'` (or a hash per page), which the strict CSP
and `check-output.sh` forbid. A preload hint for a stylesheet the head already
links gives no gain (the parser finds it first thing), and the long immutable
cache (issue 240) makes repeat views free. The audit's 140 ms estimate does not
lower the local Performance score. No change, no check loosened.

### Staging noindex (unchanged, still enforced)

The "blocked from indexing" finding is staging by design. `check-output.sh`
decides the environment from `robots.txt`: staging (`Disallow: /`) must have
`noindex` on every page, production must have none except the 404
(`noindex-mismatch`, `bad-robots`, `env-mismatch`). Both shapes are covered by
`scripts/test-check-output.sh`. Nothing in this change touches either.
