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
