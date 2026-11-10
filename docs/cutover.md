# Cutover to the apex domain

Done record. The site has been live at the apex, `chiefgyk3d.com`, since 2026-11-10, and
WordPress is no longer the origin. This file used to be the plan; it now records what was
done, what was learned, and the checks and rollback that stay useful. The public
repository keeps its dev host, `test-blog.chiefgyk3d.com`, which stays out of search
results. One parameter, `params.environment` (`staging` or `production`, default
`production`), controls both.

| | staging | production |
|---|---|---|
| every page | `<meta name="robots" content="noindex, nofollow">` | no robots meta |
| `robots.txt` | `User-agent: *` and `Disallow: /`, no sitemap | `Allow: /` and a `Sitemap:` line |

`scripts/check-output.sh` reads the environment from `robots.txt` and fails a
build that mixes the two (`missing-robots`, `bad-robots`, `noindex-mismatch`).
With `EXPECT_ENV=staging` or `EXPECT_ENV=production` it also fails a build of
the wrong environment (`env-mismatch`).


## State after the cutover

- Production is built and deployed from a private repository. It pins one commit of this
  public repository, validates the build output as inert data in a separate step that
  holds no credentials, and only then runs a credentialed step that deploys to its own
  Pages project. The pipeline itself is not described here beyond that; see
  `docs/deploy.md` for the split between it and this repository's dev deploy.
- This repository's deploy workflow still builds with `HUGO_PARAMS_ENVIRONMENT: staging`
  and `EXPECT_ENV: staging` and publishes the dev host. CI builds and checks both
  environments on every run.
- WordPress is retired as the origin. Its old addresses (feed, categories, date
  archives, `/page/N/` and uploads) answer with redirects, listed below. The `support.`
  host was left unchanged and is not redirected.
- Mail records in DNS were not touched.

## What was done

This record keeps to what is known; the private pipeline and the zone settings are not
described beyond it.

1. The production tier got its own service account, identity and Pages project. Nothing is
   shared with the dev deploy.
2. The apex was attached to the production Pages project and pointed at it. Done meant the
   domain status was active and the public address served the site, not the 200 of the
   attach call.
3. `www.chiefgyk3d.com` redirects to the apex (see "The www redirect rule").
4. The legacy WordPress addresses answer with redirects (see "Feed and legacy URLs").
5. Mail records in DNS were not touched.
6. After a CSP change, staging served stale headers on three unchanged scripts until their
   URLs were purged (see "Lessons").

## The www redirect rule

`www.chiefgyk3d.com` redirects to the apex with a zone redirect rule. `_redirects` cannot
do this, because it matches paths and not hosts. A zone rule only sees traffic that passes
through Cloudflare, so the `www` record has to stay proxied. When you write a redirect
ruleset through the API, read the existing rules first: a PUT replaces the whole list.

## Lessons

- Verify through the public address, not the API's answer. An attached domain is done when
  its status is active and the page serves; a 200 from the attach call is not enough.
- Production changes by a pin, so rollback is small: revert the pin in the private
  repository (a reviewable diff) and let the pipeline redeploy. Touch DNS only if the
  domain itself is at fault.
- Unchanged static files keep their cached headers at the edge after a header change.
  Staging deploys served stale headers on three unchanged scripts until their URLs were
  purged. After any CSP or other header change, purge the URLs of the unchanged files
  (`/copy.js`, `/search.js`, `/share.js`) and then fetch each one and compare its headers with
  `static/_headers`. `scripts/verify-live.sh` does not do this: it checks headers only on
  its own list of pages, so it can pass while a cached script still carries the old policy.
  See "Checking cached script headers" below. The purge needs only the cache purge
  permission on that zone, granted for the task and dropped after.
- Mail records were left alone. A web cutover (apex record, redirect rule) does not need
  them; read them before and after to prove it.
- Keep the old and the new tier on separate identities. The production service account and
  identity are not the dev ones, so a dev compromise cannot deploy to the apex. The claim
  rules on that identity are configured by the owner at the provider, not enforced by this
  repository (see `docs/threat-model/RISKS.md`).

## Rollback

Trigger: the verifier fails and the cause is not fixed within minutes, or the owner calls
it.

1. Revert the pin file in the private repository to the previous commit and let the
   pipeline redeploy. This is the normal rollback and needs no DNS change.
2. A Pages deployment can also be rolled back on its own (`docs/deploy.md`, "Checking
   and rolling back").
3. If the domain itself is at fault, restore the apex (and `www`) records and the
   redirect rules from a snapshot taken before the change, one owner-approved write at a time.
   Read the zone's records and rules and keep them privately before any write.
4. Purge the cache for the apex host if stale responses persist.
5. Check the public address by hand before calling it recovered.

## Checking a deployed host: scripts/verify-live.sh

```sh
scripts/verify-live.sh HOST [--resolve-ip IP] [--public DIR] [--env staging|production]
```

Read-only: GET requests through curl, each bounded by a 10 s connect and a 15 s
total timeout, nothing written anywhere but a throwaway directory under `tmp/`.
It compares the host with a build (default: it builds this repository with the
`hugo` on PATH; `--public DIR` uses a build you already have, for example the
`site` artifact of a deploy run). Exit 0 means every check passed, 1 means a
check failed (each failure is a `FAIL: rule: detail` line), 2 means bad input.

| Check | What it asserts |
|---|---|
| `redirect` | every rule of the built `_redirects` answers 301 with the expected Location |
| `status` | the home page and one page per template answer 200 |
| `not-found` | a missing path answers 404 with the noindex 404 page |
| `header-*` | every header of `static/_headers` (the CSP string exactly) is on each page once, equal |
| `sitemap`, `feed` | `/sitemap.xml` and the feed (`/feed/index.xml`, read from the build's alternate link) are well-formed XML that name only this host |
| `robots`, `robots-meta`, `env-mismatch` | `robots.txt` and the page robots meta fit the environment; `--env` pins the expected one |
| `copy-js` | the served `/copy.js` has the bytes of the build (`/search.js` is checked by the post-deploy smoke test) |
| `third-party` | no page, the sitemap, the feed or the stylesheet loads from another host |

Dev host, through a public resolver address because the laptop's resolver
may return nothing for the name (look the address up with
`dig +short @1.1.1.1 test-blog.chiefgyk3d.com`):

```sh
scripts/verify-live.sh test-blog.chiefgyk3d.com --resolve-ip 104.21.3.60
```

For the apex, build the site with the apex base URL and production parameters first.
Without `--public`, the verifier builds this repository with the dev base URL from
`hugo.toml`, and its sitemap, feed and canonical checks would not match the apex. Pass the
build with `--public`, name the apex, and pin `--env production`; no `--resolve-ip` is
needed when the resolver answers:

```sh
HUGO_PARAMS_ENVIRONMENT=production hugo --minify --gc --baseURL https://chiefgyk3d.com/ --destination tmp/apex-build
scripts/verify-live.sh chiefgyk3d.com --public tmp/apex-build --env production
```

(The production pipeline pins a commit of this repository, so build that same commit.)

The test `scripts/test-verify-live.sh` runs it against a local fake server with
a negative case per check (CI step "Test the live-host verifier"). It cannot show
what Cloudflare itself adds to a response (see "Verified and inferred").


## Checking cached script headers

After a header change and a purge, check the three pinned scripts by hand. The block
compares the Content-Security-Policy each script is served with against the value in
`static/_headers` (run it from the repository root; read-only GET requests):

```sh
host=chiefgyk3d.com   # or the dev host
want=$(sed -n 's/^  Content-Security-Policy: //p' static/_headers | head -1)
for f in copy.js search.js share.js; do
  got=$(curl -sSI --max-time 15 "https://$host/$f" | tr -d '\r' | sed -n 's/^[Cc]ontent-[Ss]ecurity-[Pp]olicy: //p')
  if [ "$got" = "$want" ]; then echo "ok $f"; else echo "STALE $f: ${got:-none}"; fi
done
```

Any `STALE` line means that URL still has cached headers: purge it again. The other
headers of `static/_headers` (`X-Content-Type-Options`, `Strict-Transport-Security` and the
rest) can be compared the same way with `curl -sSI` and a read of the output.

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
the `/*` block plus the one `Cache-Control` block for `/css/*`, `_redirects` internal 301/302 lines only). That is a
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
when the file would pass 2,000 lines in all (the header and the two dynamic
rules count, so 1,997 static rules is the most), the limit
`scripts/check-site-artifact.sh` enforces.

To check them by hand, run
`curl -sI https://test-blog.chiefgyk3d.com/feed/` (expect `301` with
`location: /feed/index.xml`), `curl -sI https://test-blog.chiefgyk3d.com/feed/index.xml`
(expect `200` and an XML content type), and the same for `/feed/atom/`,
`/comments/feed/`, `/category/uncategorized/`, a real `/YYYY/MM/` and `/page/2/`.

### Old image addresses

`data/legacy_uploads.json` is a list of `{"from": "/wp-content/uploads/...",
"to": "/posts/<slug>/<file>"}` entries. It holds 23 entries now that six migrated
posts are published (issue 322); a post still in draft contributes none. The converter writes the real
list, only for images the migrated posts show, as `legacy-uploads.json` beside
its page bundles in the (private) output directory. Steps, after the WebP step
so the targets carry the final names:

1. `python3 -I tools/wxr2hugo/convert.py ...` (writes `legacy-uploads.json`).
2. `python3 -I tools/wxr2hugo/webp.py <out dir>` rewrites each `to` to the
   `.webp` that now exists.
3. Copy `legacy-uploads.json` to `data/legacy_uploads.json` together with the
   bundles it points at, in the same pull request. The file holds public URL
   paths only, no private text.

Six migrated posts were published in issue 322, so `data/legacy_uploads.json`
now holds 23 entries (the posts' old upload addresses, 3 for the
community-automation post and 20 for the headphone post; the other four have
none). A draft's page bundle is not built in production and a redirect to it
would land on a 404, so a post still in draft contributes no entries.
`docs/migration-uploads.md` lists, per post, the entries to add (the file is
documentation, the build ignores it). Flip a post to `draft: false` and add
that post's entries in the same pull request, then run
`scripts/test-redirects.sh`.

**Flip these two posts together.** The Twitch-and-Toot post carries
`supersededBy` pointing to the Stream Daemon post. If Twitch-and-Toot goes live
while Stream Daemon is still a draft, its forward link leads to a 404. Publish
Stream Daemon first, or both in the same pull request.

A bad entry (source outside `/wp-content/uploads/`, a space, a splat, an
external target) fails the Hugo build. The test `scripts/test-redirects.sh`
checks each rule and that every upload target is a file the build publishes.

## support.chiefgyk3d.com

Left unchanged at cutover (owner decision, 2026-11-10). No redirect rule was added for
this host, and its DNS record was not touched. It keeps serving its own site, a separate
single page. The apex serves its own `/support/` page, which must keep matching the
`support-me` repository, the source of the wallet addresses. If the owner later decides
to fold the host into the apex, that is a new, separate approved step: one Single
Redirect rule, because `_redirects` matches paths and not hosts.

## Post-cutover verification

On the apex, against a build of the deployed commit:

```sh
scripts/verify-live.sh chiefgyk3d.com --public DIR --env production
```

(`DIR` is the `site` artifact or the apex build from "Checking a deployed host" above.) It must exit 0. Run it again about 5 minutes later (edge caches). Then by hand:
open the home page and one post in a browser and check the favicon and `/support/`; confirm `test-blog.chiefgyk3d.com` is still the noindex dev host (checked with `--env staging`). The verifier follows the build's
`_redirects`: each static rule must answer with its declared status and
Location (including the `/feed/` 301 to `/feed/index.xml`), the two splat rules
(`/category/*`, `/page/*`) are tested with one probe path each, and the feed
itself is fetched at the path the build advertises in its alternate link
(`/feed/index.xml`). The deploy workflow's smoke job also runs
`scripts/smoke-site.sh` against `SITE_URL`.

## Links hand-off

After the apex is verified, the owner updates every place that links to the old
WordPress site or the staging host. Nothing here is scripted or checked by this
repository:

- Profile and bio links on the networks listed in `data/socials.yaml`, and the
  Mastodon profile link verification (`rel="me"`), which can only verify once
  the apex serves the link.
- The GitHub profile and the READMEs of the owner's repositories (including the
  `support-me` signature block).
- Reach Around's link to the blog.
- The `links.` (products, media kit) and `social.` (Mastodon) subdomains are
  separate services and stay as they are; their pages should link to the apex.
- Search consoles: add the apex property and submit the sitemap.

## Verified and inferred

Verified:

- The site is live at the apex since 2026-11-10 and WordPress is no longer the origin.
- Unchanged static files kept cached headers at the edge after a header change, on three
  scripts on the staging host, until their URLs were purged.
- An API-attached Pages domain gets no DNS record (`docs/deploy.md`, measured on the dev
  host).
- `_redirects` matches paths only (`layouts/home.redirects`).

Not recorded here, because the production pipeline and the zone settings live outside this
repository: the production job layout, the pin review rule and the identity claim rules.
The threat model lists them as Open until the owner reads and dates them.
