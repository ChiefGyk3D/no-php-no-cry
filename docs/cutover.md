# Cutover to the apex domain

The site is staging at `test-blog.chiefgyk3d.com` until it replaces the apex.
Staging must stay out of search results; the apex must be indexable. One
parameter, `params.environment` (`staging` or `production`, default
`production`), controls both.

| | staging | production |
|---|---|---|
| every page | `<meta name="robots" content="noindex, nofollow">` | no robots meta |
| `robots.txt` | `User-agent: *` and `Disallow: /`, no sitemap | `Allow: /` and a `Sitemap:` line |

`scripts/check-output.sh` reads the environment from `robots.txt` and fails a
build that mixes the two (`missing-robots`, `bad-robots`, `noindex-mismatch`).
With `EXPECT_ENV=staging` or `EXPECT_ENV=production` it also fails a build of
the wrong environment (`env-mismatch`).

## Today

The deploy workflow's build job sets `HUGO_PARAMS_ENVIRONMENT: staging` and
`EXPECT_ENV: staging`. CI builds and checks both environments on every run.

## At the apex cutover

Do these in one pull request, after the apex DNS and Pages custom domain are
ready:

1. `hugo.toml`: change `baseURL` to the apex. Canonical links, the feed, the
   sitemap, Open Graph URLs and the `Sitemap:` line all follow it.
2. `.github/workflows/deploy.yml`, build job: set `HUGO_PARAMS_ENVIRONMENT` to
   `production` and `EXPECT_ENV` to `production` (or delete both: production is
   the default).
3. CI sets `SITE_HOST` for `scripts/check-output.sh` where it differs from the
   default (`test-blog.chiefgyk3d.com`); set it to the apex host.
4. After the deploy, fetch `/robots.txt` on the apex and confirm it allows all
   and names the sitemap, and that a page has no robots meta.
5. Keep the test-blog host staging (or redirect it to the apex); do not serve a
   production build there, or both hosts become indexable duplicates.

`static/_headers` is not part of this change.

## Feed and legacy URLs

The WordPress site served its RSS feed at `/feed/`, and feed readers keep that
address, so the cutover keeps it working. Cloudflare Pages facts below come from
the Pages docs "Redirects", "Headers" and "Serving Pages" pages, fetched
2026-11-06 (verified); anything marked inferred has not been seen on a live
Pages deployment.

The feed is a real file, `/feed/index.xml` (full post bodies, the atom self link
on that address). Every page's `<head>` advertises it and the footer RSS link
points at it. `/index.xml` (the home feed, same content) is still published.

| Old WordPress address | After cutover |
|---|---|
| `/feed/`, `/feed` | 301 to `/feed/index.xml` |
| `/feed/atom/`, `/feed/atom` | 301 to `/feed/index.xml` (a reader that asked for Atom gets RSS) |
| `/comments/feed/`, `/comments/feed` | 301 to `/feed/index.xml` (the comments are gone) |
| `/category/<name>/` | 301 to `/categories/<name>/` when a post uses that category; `/category/uncategorized/` and any other category go to `/posts/` |
| `/YYYY/` and `/YYYY/MM/` | 301 to `/posts/`, only for years and months that hold a published post |
| `/page/N/` | 301 to `/posts/` |
| `/wp-content/uploads/...` | 301 to the page-bundle file, only for images the migrated posts show (below) |

Why `/feed/` is a redirect and not the feed itself: Pages serves
`/feed/index.html` at `/feed/` but has no directory index for XML (verified:
"Serving Pages" names only HTML). Serving the XML at `/feed/` would take a
`200` rewrite in `_redirects` plus a `Content-Type` block in `_headers`, and
`scripts/check-site-artifact.sh` forbids both on purpose (`_headers` must be
the one `/*` block, `_redirects` internal 301/302 lines only). That is a
decision for the site owner, not a side effect of the feed work. Until then
the file is served with the type Pages derives from `.xml` (inferred,
`application/xml`), which feed readers accept, and a reader that follows the
permanent redirect stores the new address.

Limits relied on (Pages docs, verified): 2,000 static and 100 dynamic redirects
per file, the top-most matching rule wins, static rules go before dynamic ones,
one splat per rule, and redirects run before headers. The file has two dynamic
rules (`/category/*`, `/page/*`). Date archives are static lines per real month
on purpose: a placeholder such as `/:year/:month/` matches any one-segment path
and would capture `/posts/<slug>/`. `layouts/home.redirects` fails the build
above 2,000 static rules.

Not verified, because the site is alpha and nothing was written to Cloudflare:
after the first deploy to the staging host, run
`curl -sI https://test-blog.chiefgyk3d.com/feed/` (expect `301` with
`location: /feed/index.xml`), `curl -sI https://test-blog.chiefgyk3d.com/feed/index.xml`
(expect `200` and an XML content type), and the same for `/feed/atom/`,
`/comments/feed/`, `/category/uncategorized/`, a real `/YYYY/MM/` and `/page/2/`.

### Old image addresses

`data/legacy_uploads.json` is a list of `{"from": "/wp-content/uploads/...",
"to": "/posts/<slug>/<file>"}` entries and ships empty (`[]`) because the
migrated posts are private drafts until published. The converter writes the real
list, only for images the migrated posts show, as `legacy-uploads.json` beside
its page bundles in the (private) output directory. Steps, after the WebP step
so the targets carry the final names:

1. `python3 -I tools/wxr2hugo/convert.py ...` (writes `legacy-uploads.json`).
2. `python3 -I tools/wxr2hugo/webp.py <out dir>` rewrites each `to` to the
   `.webp` that now exists.
3. Copy `legacy-uploads.json` to `data/legacy_uploads.json` together with the
   bundles it points at, in the same pull request. The file holds public URL
   paths only, no private text.

A bad entry (source outside `/wp-content/uploads/`, a space, a splat, an
external target) fails the Hugo build. The test `scripts/test-redirects.sh`
checks each rule and that every upload target is a file the build publishes.
