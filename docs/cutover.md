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

## Ruling and status

Owner ruling (2026-11-06): the cutover from WordPress to this site happens only
after both Reach Around and no-php-no-cry are done. The site is alpha now. Until
the owner says go: no Cloudflare writes, no DNS changes, no WordPress login or
writes (read-only GETs of public pages are fine). Everything below is a plan to
run later, in this order. Steps marked OWNER-APPROVED WRITE change a live
system and need the owner's own message approving that step.

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

Staging today, through a public resolver address because the laptop's resolver
may return nothing for the name (look the address up with
`dig +short @1.1.1.1 test-blog.chiefgyk3d.com`):

```sh
scripts/verify-live.sh test-blog.chiefgyk3d.com --resolve-ip 104.21.3.60
```

The test `scripts/test-verify-live.sh` runs it against a local fake server with
a negative case per check (CI step "Test the live-host verifier"). It cannot show
what Cloudflare itself adds to a response (see "Verified and inferred").

## Pre-flight (nothing here writes to Cloudflare or WordPress)

1. Owner decisions recorded in the issue: cutover date and time window;
   whether `www.chiefgyk3d.com` exists and where it should go; fold or keep
   `support.chiefgyk3d.com` (the plan below assumes a 301 to `/support/`);
   what happens to `test-blog.chiefgyk3d.com` (cutover step 5); Pixelfed and
   Instagram links. Contact is Matrix and Discord only for now (owner ruling
   2026-11-06); an email address may be added later and does not block.
2. Reach Around is done and merged, and its link to the blog works through the
   apex or the redirect.
3. Content: the real WordPress content is imported (today `content/` holds only
   sample pages). Follow `docs/scrub-terms.md`: replace the inert `employer` and
   `serial` placeholder lines with real terms first (until then those two
   categories are not checked), then run `tools/wxr2hugo/convert.py` with the
   real terms on stdin and `--require-terms`; it must exit 0.
4. Content review by the owner: every page and post read once; drafts either
   published or dropped on purpose; affiliate links only on `/products/` with
   the disclosure; each retained image has real alt text (the importer flags the
   ones that do not).
5. If anything was published on WordPress after the 2026-10-25 export, the
   owner makes a fresh read-only export and the difference is imported.
6. On the cutover commit: `scripts/check-wording.sh` and the full gate pass, and
   the production build passes `EXPECT_ENV=production scripts/check-output.sh`.
7. Rehearse the verifier on staging (command above) and keep the output.

## WordPress freeze

1. Announce the window. From the owner's go (T0) nothing is published or edited
   on WordPress. The owner does this inside WordPress; no agent logs in.
2. Keep the WordPress site and its hosting running and untouched for at least 30
   days after cutover. It is the rollback target.
3. After that, keep a final export offline (not in this repository; it holds
   private material).

## Gates before the cutover (parity audit, #104)

`docs/parity.md` is the feature-by-feature table. These are the items it marks
planned that change this runbook. Each step names its actor: AGENT means a
repository change (a pull request the owner reviews and merges, nothing live
touched); OWNER-ONLY means a Cloudflare, DNS, secret, live-store or WordPress
action that agents never perform and that needs the owner's own message.

| # | Step | Actor | Done when |
|---|---|---|---|
| N1 | Public site name is ChiefGyk3D everywhere it shows (#126) | AGENT | `title` in `hugo.toml` changed and the old name gone from every shown surface: page titles, feed, Open Graph, JSON-LD, the footer, the 404 page, `robots.txt`, `llms.txt` and `static/site.webmanifest` (today it still names the old project). `scripts/test-head.sh` (which today hardcodes the old name) is updated to expect the new one, and `scripts/check-output.sh` (rule `old-site-name`, which reads html, xml, svg, txt, json and webmanifest files) passes on the production and staging builds |
| N2 | Analytics go-live pull request (#84): swap `docs/privacy-with-analytics.md` into `content/privacy/index.md`, update `scripts/test-pages.sh` (the `privacy()` asserter and `good_privacy` fixture), update `docs/privacy-and-analytics.md`, refresh `analytics/hosting-asns.mjs`. The privacy text and the collector change in the same pull request, never apart | AGENT | the pull request is merged with the gate green; the collector records nothing while no `DB` is bound |
| N3 | Analytics deploy (steps in `docs/analytics-deploy.md`): create the D1 database, apply the migration, bind `DB` to the Pages project, add the D1 scope to the token that runs the daily maintenance, schedule it. The binding is what turns counting on | OWNER-ONLY | first, a page view after the deploy shows one new row in the raw `view_events` table (`wrangler d1 execute`, owner token). Then five matching views plus one run of the scheduled maintenance produce a row in the `report_*` views: those views are filled only by `analytics/maintenance.sql` and hide every bucket under the 5-view floor, so one view never appears there. `ANALYTICS_OFF=1` stops counting at once |
| N4 | Syndication on deploy (#11): a deploy-time job that announces each new post once to Bluesky, Mastodon, Discord and Matrix, with durable dedupe and per-platform failure isolation. Built and tested; it runs only after cutover, never against staging posts | AGENT | #11 acceptance criteria pass in tests with the clients faked |
| N5 | Syndication credentials for the four platforms, stored as Actions secrets or Doppler entries | OWNER-ONLY | the job's first real run posts once and a rerun posts nothing |
| N6 | Reach Around pointer: a footer or About link to Reach Around and its media kit (the `links.` subdomain pages stay as they are), and Reach Around's link back to the blog | AGENT for this site; OWNER-ONLY for the other repository's deploy | both links work through the apex or the redirect |
| N7 | Shop alignment (#79): a read-only survey of the store's theme options and a short spec of what can match the brand tokens. Copy and spec only | AGENT | the spec is merged. Applying any of it to the live store is OWNER-ONLY and needs the owner's own override message |
| N8 | The four old comments quoted in their three posts (#121), display name only | AGENT | the posts show them; no email or IP anywhere in the repository |
| N9 | Posts: the owner reads each of the ten and flips it to `draft: false`; Twitch-and-Toot and Stream Daemon in the same pull request; that post's `data/legacy_uploads.json` entries in the same pull request | OWNER-ONLY decision, AGENT prepares the pull request | `scripts/test-redirects.sh` passes and no forward link leads to a 404 |
| N10 | Device matrix QA (#131) passes on three engines | AGENT runs, OWNER-ONLY sign-off | the QA report is attached to the cutover issue |

Order: N1, N2, N4, N6, N7, N8 can all merge before the owner's go. N3 (analytics
go-live, required before cutover, #84) and N9 and N10 must be complete before the
cutover pull request in "Cutover (ordered)" is merged and before any production
traffic: N2 puts the analytics wording on the privacy page, and N3 is what makes
it true (the `DB` binding). N5 (syndication credentials) is an owner step taken
when the owner chooses; N4's job runs only after cutover, so N5 is needed by the
first post published after cutover, not before the cutover pull request. No agent runs anything
marked OWNER-ONLY, and none of this changes the freeze rules in "Ruling and
status".

## Cutover (ordered)

Cloudflare calls, listed once with the permission each needs. This is the union
for the whole job. No token is requested here; the owner decides how access is
granted (`docs/deploy.md` has the account-wide caveat), and the grant is dropped
when the job ends.

| # | Call (Cloudflare API v4) | Permission | Why |
|---|---|---|---|
| a | `GET /zones?name=chiefgyk3d.com` | Zone: Zone Read | find the zone id |
| b | `GET /zones/{zone}/dns_records` | Zone: DNS Read (DNS Edit covers it) | snapshot every record before a change; this is the rollback record |
| c | `GET /accounts/{acct}/pages/projects/{project}/domains` | Account: Cloudflare Pages Read | see which domains the project already has |
| d | `POST .../pages/projects/{project}/domains` with the apex name | Account: Cloudflare Pages Edit | attach the apex to the Pages project |
| e | `GET .../domains/{apex}` until `active` | Cloudflare Pages Read | done means `active` and the public URL serving, not the 200 of the attach call |
| f | create or update the apex DNS record: proxied CNAME to `{project}.pages.dev` | Zone: DNS Edit | route the apex to Pages; an API-attached domain gets no record on its own (`docs/deploy.md`) |
| g | the same for `www`, only if the owner decided it exists | DNS Edit | same |
| h | `GET /zones/{zone}/rulesets/phases/http_request_dynamic_redirect/entrypoint` | Zone: Single Redirect Read (Edit covers it) | read the rules already there before writing, because a PUT replaces the whole list |
| i | `PUT` the same entrypoint with the existing rules plus the new ones | Zone: Single Redirect Edit | the `support.` 301 and the `test-blog.` decision |
| j | `POST /zones/{zone}/purge_cache` for the apex host only | Zone: Cache Purge | only if the verifier shows old WordPress pages cached at the edge (inferred risk) |

Nothing else is needed: no Zone Settings, no WAF, no Workers, no Access. If a
step turns out to need more, stop and ask; do not widen the grant on the way.

Steps:

1. Reads only (calls a, b, c, h). Save the DNS snapshot and the redirect
   entrypoint in a private place, not in this repository, and write down the
   apex record's current type, content and proxy flag.
2. Prepare the cutover pull request (no Cloudflare write; merge it when step 4
   is ready):
   - `hugo.toml`: change `baseURL` to the apex. Canonical links, the feed, the
     sitemap, Open Graph URLs and the `Sitemap:` line all follow it.
   - `.github/workflows/deploy.yml`, build job: set `HUGO_PARAMS_ENVIRONMENT` and
     `EXPECT_ENV` to `production` (or delete both: production is the default).
   - Repository variable `SITE_URL` (used by the deploy smoke job) set to the
     apex, and `SITE_HOST` for `scripts/check-output.sh` where it differs from
     the default (`test-blog.chiefgyk3d.com`).
3. OWNER-APPROVED WRITE (d, e): attach the apex to the Pages project. Wait for
   `active`.
4. OWNER-APPROVED WRITE (f, g): point the apex at Pages. This is the moment
   traffic moves. Merge the cutover pull request so the production build
   deploys, in the order the owner chooses (deploy first, then DNS, is the
   safer one).
5. OWNER-APPROVED WRITE (i): the test host. One Pages project serves every
   custom domain attached to it, so after step 2 the test-blog host would serve
   the production build and become an indexable duplicate. Either remove the
   test-blog domain from the project and 301 it to the apex with a redirect
   rule, or keep a separate staging project. Default plan: a redirect rule from
   test-blog to the apex (path preserved); the record stays proxied.
6. OWNER-APPROVED WRITE (i): `support.chiefgyk3d.com`, see the section below.
7. Verify (see "Post-cutover verification"). If anything fails and cannot be
   fixed in minutes, roll back.
8. Fetch `/robots.txt` on the apex by hand once: it allows all and names the
   sitemap, and a page has no robots meta (the verifier checks both).
9. The owner submits the sitemap to the search consoles.

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

The ten migrated posts are drafts, so `data/legacy_uploads.json` stays `[]`
until they are published: a draft's page bundle is not built in production, and
a redirect to it would land on a 404. `docs/migration-uploads.md` lists, per
post, the entries to add back (the file is documentation, the build ignores it).
Flip a post to `draft: false` and add that post's entries in the same pull
request, then run `scripts/test-redirects.sh`.

**Flip these two posts together.** The Twitch-and-Toot post carries
`supersededBy` pointing to the Stream Daemon post. If Twitch-and-Toot goes live
while Stream Daemon is still a draft, its forward link leads to a 404. Publish
Stream Daemon first, or both in the same pull request.

A bad entry (source outside `/wp-content/uploads/`, a space, a splat, an
external target) fails the Hugo build. The test `scripts/test-redirects.sh`
checks each rule and that every upload target is a file the build publishes.

## support.chiefgyk3d.com

The old support site is a separate single page. The plan is one 301 from
`https://support.chiefgyk3d.com/*` to `https://chiefgyk3d.com/support/` as a
Single Redirect rule (call i). The `support` DNS record stays as it is and
proxied, since a zone rule only sees traffic that passes through Cloudflare.
`_redirects` cannot do this (it matches paths, not hosts). After the change:

```sh
curl -sSI https://support.chiefgyk3d.com/ | sed -n '1p;/^[Ll]ocation/p'
```

must show `301` and `location: https://chiefgyk3d.com/support/`. The
`support-me` repository stays the source of the wallet addresses; the new page
must match it before cutover. Retire the old project only after the owner
confirms; that is a separate approved step.

## Post-cutover verification

On the apex, with the `site` artifact of the deploy run (or any build of the
cutover commit):

```sh
scripts/verify-live.sh chiefgyk3d.com --env production
```

It must exit 0. Run it again about 5 minutes later (edge caches). Then by hand:
open the home page and one post in a browser and check the favicon and `/support/`; confirm `test-blog.chiefgyk3d.com` redirects (or is still
staging, checked with `--env staging`). The verifier follows the build's
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

## Rollback

Trigger: the verifier fails and the cause is not fixed within the owner's chosen
window, or the owner calls it. Each step is an OWNER-APPROVED WRITE:

1. Restore the apex (and `www`) DNS records from the snapshot taken in step 1
   (call f in reverse). WordPress is still running because of the freeze.
2. Restore the redirect entrypoint saved in step 1 (call i in reverse).
3. Purge the cache for the apex host if stale responses persist (call j).
4. Check the old site by hand; unfreeze WordPress only after the owner confirms
   it is serving.
5. The Pages deployment can stay (it is no longer on the apex). Revert the
   `baseURL` change only if the production flag must be kept off the staging host.

Pages deployments can also be rolled back on their own (`docs/deploy.md`,
"Checking and rolling back").

## Verified and inferred

Verified (observed in this work):

- `scripts/verify-live.sh` ran read-only against `https://test-blog.chiefgyk3d.com`
  with `--resolve-ip`; all 45 checks passed (output in the pull request).
- The Rulesets API redirect calls need `Zone > Single Redirect > Edit`, and
  `Cloudflare Pages Edit` is a listed permission (Cloudflare docs, "Create a
  redirect rule via API" and the API token permissions reference, fetched
  2026-11-06).
- An API-attached Pages domain gets no DNS record (`docs/deploy.md`, measured
  earlier on the staging host).
- `_redirects` matches paths only (`layouts/home.redirects`).

Inferred, to confirm before the owner approves the matching step:

- That a Pages project serves all of its custom domains from one deployment (so
  the test-blog host needs step 5).
- That a zone redirect rule fires for a proxied record whatever its target is.
- What the zone's Single Redirect entrypoint holds today (call h answers it).
- That old WordPress responses may sit in the edge cache (call j).
- That Cloudflare adds no second `Strict-Transport-Security` or other header on
  the apex (a zone setting could). The verifier reports `header-duplicate` or
  `header-wrong` if so; the fix would be a zone setting, not a repository change.
- That the `support` record is proxied and the old project is Git-connected
  Pages (from `support-me`'s commit check run, not from the API).
- The `www` host was not read; it is an owner decision in pre-flight.
