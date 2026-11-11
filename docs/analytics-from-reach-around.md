# Analytics from Reach Around: how the blog hooks in, and how others can reuse it

Status: design only. Nothing here changes code, a workflow or a Cloudflare setting.
Refs issue 84 (blog analytics) and issue 189 (edge-mode collector). Written 2026-11-09.

## Summary for the owner

Update 2026-11-09: the owner answered the six open questions. They are recorded as
CONFIRMED decisions in section 8 and the design is made safe within them (sections 5.1
to 5.4). Three answers are less private than the first recommendation and Cloudflare Web
Analytics stays on, so the guardrails are required, not optional.

(First draft from the local model, then corrected by hand against the sources below.)

- The blog already has its own page-view counter: a server-side Pages Function plus a D1
  schema, built and tested, not deployed (`docs/analytics-deploy.md`). It reuses Reach
  Around's data rules but is a copy of the shape, not the shared Worker.
- Reach Around's shared Worker already knows about multiple sites (migration 0008) and
  counts clicks. It has no route that accepts a blog page view yet: an edge-mode site is
  rejected by the view route today (`worker/src/view.ts`). Issue 189 assumes that route
  exists. It does not.
- Smallest next step: keep the blog's own Function for views, add outbound-link click
  pings by registrable domain (rules in 5.2), and swap in the drafted privacy text in the
  same pull request that turns it on. No new script, no CSP change.
- The real decision for you is whether the blog should keep its own collector or move
  onto the shared Worker (section 3 and the questions in section 8). Both are cheap to
  start; moving later costs a migration of one table.
- Cloudflare steps that only you can do are listed in section 7. Nothing has been done.

Labels used below: **VERIFIED** (source and date read) or **INFERRED** (reasoned, not
read). Cloudflare facts were read through the Cloudflare docs search on 2026-11-09.
Placeholders: `blog.example.test` is the blog host, `links.example.test` the link page host.

## Decisions (CONFIRMED by the owner, 2026-11-09)

| Q | Decision | Where handled |
| --- | --- | --- |
| Q1 | A, converge: ship the local Function now, share the pure rules in one module | section 3, plan items 13 and 14 |
| Q2 | C: country, region and city in the aggregates | section 5.1 |
| Q3 | B: keep Cloudflare Web Analytics and describe both counters on the privacy page | section 5.4 |
| Q4 | B: every external link counted by registrable domain (open vocabulary) | section 5.2 |
| Q5 | A: closed `s` label list, referrer host as the fallback | sections 2.2, 2.3 |
| Q6 | Superseded: the blog dropped unique-visitor hashing and keeps page views only | section 5.3 |

Q2 C and Q4 B are less private than the first recommendations and Q3 B keeps two
counters. They are accepted; this page does not reopen them and lists what must be true
for them to be safe. The former Q6 B decision is retained below only as superseded design
history.

## 1. What Reach Around has that the blog can reuse

| Piece | State | Fit for a static blog |
| --- | --- | --- |
| Multi-site config: `SITES` JSON, site id slug, `hosts`, `mode` (`beacon` or `edge`), `pages` (`html-200` for edge), `link_ids`, `sources`, `geo`, `min_cell`, `raw_keep_days`. VERIFIED: `worker/src/sites.ts`, `worker/migrations/0008_sites.sql` (read 2026-11-09). | Shipped | Fits. The blog is one entry. Strict loader: a bad value disables that one site, unknown keys are rejected. |
| View route `POST /e/v/:pageId`, write-only, one uniform empty 204. VERIFIED: `worker/src/view.ts`. | Shipped for beacon mode | Does not fit as is. Line 669 returns the empty 204 for any edge-mode site, so the blog cannot use it. A static blog has too many pages for a fixed id list and wants no script. |
| Click route `POST /e/c/:linkId`, site resolved from the matched host, ids checked against that site's `link_ids`. VERIFIED: `worker/src/click.ts`, design 6.1. | Shipped | Fits. The link page uses `ping="/e/c/<id>"` on anchors with no script (VERIFIED: `src/reach_around/site/templates/_macros.html`). |
| Rollups: three marginal daily tables, no recombination of city, network and device. VERIFIED: design 3.5, migrations 0005 to 0007. | Shipped | Fits. The blog's own schema copied the same three tables. |
| Floors: `MIN_CELL`, per-site `min_cell` (default 5 for the blog). VERIFIED: design section 8. | Shipped | Fits. |
| Funnel counters `click_src_daily` and `click_country_daily`, source label in the short `s` parameter, closed `sources` list. VERIFIED: design 6.2, issue 189 owner decisions. | Shipped | Fits for the click side. The `s` label is how a bio link attributes a visit without storing anything. |
| Funnel report (`reach-around report`, period release ledger). VERIFIED: design 6.2. | Shipped, owner-run | Partly. It is a local owner command over the shared D1. A blog-only D1 needs its own read path (the `report_*` views). |
| Privacy guardrails list (issue 408). VERIFIED: Reach Around issue 408 body, read 2026-11-09. | Open | Fits, and is the source of section 2.4. |

What does not fit a static blog:

- The beacon view route and `view.js`. They need a script on every page. The blog's rule
  is a strict CSP and a short allowlist of pinned scripts (INFERRED from
  `static/_headers` and `docs/analytics-deploy.md`: a fourth script is a separate change
  to the allowlist, hash files and checks).
- The fixed `PAGE_IDS` list. Hugo emits many paths; the design's answer is `html-200`
  with a path-shape rule (design 3.2).
- Unique-visitor hashing. The blog's built collector leaves it out, as
  `analytics/collect.mjs` states. The 2026-11-09 Q6 decision to add it was later dropped.
  Section 5.3 keeps that design history clearly labeled as superseded.
- Window-size letter. It needs a script; edge mode has none.

Important finding (VERIFIED, blog repo `docs/analytics-deploy.md`, read 2026-11-09): the
blog does not wait on the shared Worker. `functions/_middleware.js`, `analytics/*.mjs`
and `analytics/migrations/0001_page_views.sql` exist, with a separate D1 database
(`wrangler.toml.example`). Issue 84 and issue 189 were written before that code and ask
for "the blog calls Reach Around's collector". The two designs have drifted and section 3
resolves it.

## 2. Smallest integration for a static Hugo site on Cloudflare Pages

### 2.1 How a view is reported

Server side, no script. A Pages Function (`functions/_middleware.js`) awaits the page,
returns the unchanged response, and after that counts one row in the background, bounded
by a timer, failing open. It counts only a `GET` answered `200` with `text/html`. This is
what exists today. VERIFIED: `analytics/middleware.mjs`.

Cloudflare facts (VERIFIED, developers.cloudflare.com, read 2026-11-09):

- Pages Functions requests are billed as Workers requests; on the free plan they share
  the 100,000 requests per day Workers allowance (`/pages/functions/pricing/`, updated
  2026-09-08).
- Static asset requests that do not invoke Functions are free and unlimited on both
  plans (same page). `_routes.json` decides which requests invoke the Function; at least
  one include rule, at most 100 rules, at most 100 characters each
  (`/pages/functions/routing/`).
- If the free Functions allowance runs out, the project can be set to "fail open" so
  static assets keep being served (`/pages/functions/routing/`, Settings > Runtime).
- A Pages Function can use a D1 binding or a service binding to a Worker
  (`/pages/functions/bindings/`).
- `request.cf` carries `country`, `regionCode`, `region`, `asn` and `asOrganization` for
  all plans (`/workers/runtime-apis/request/`). `request.cf.city` is used in a Cloudflare
  example (`/durable-objects/examples/durable-object-in-memory-state/`); city was not in
  the excerpt of the property list, so treat city as INFERRED until the spike (section 6).
  INFERRED: a Pages Function sees the same `request.cf` because Cloudflare describes a
  Function as a Worker (`/pages/how-to/use-worker-for-ab-testing-in-pages/`).

### 2.2 How a click is reported

Outbound link click, no script: a `ping` attribute on the anchor, as the link page does.

- A Hugo render hook (for example `layouts/_markup/render-link.html`) adds
  a `ping` to the click route for every external link, carrying the registrable domain of
  the destination (decision Q4 B, 2026-11-09: an open vocabulary). The domain rules, the
  per-day cap with an `other` bucket and the built-site membership check are in 5.2.
- `/e/c/<id>` is a second Function file (a `POST` route) that applies the click rules:
  closed id, `Ping-From` host noise filter, hour-rounded time, an optional closed `s`
  source label, country only in an aggregate counter, never on the raw row (design 6.1
  and 6.2). The current repo test says `functions/` holds only `_middleware.js`; that
  test changes with this work.
- INFERRED, to confirm in the spike: browsers send `ping` as a `POST` with `Ping-From`
  and `Ping-To` headers; the CSP `connect-src` directive covers `ping` targets (the blog
  has `connect-src 'self'`, so a same-origin ping needs no CSP change); some browsers
  ship with `ping` off, so the click count is a floor, not a total. Design 6 already
  says this for the link page.

### 2.3 Site id and host mapping

One site id, `blog`, set by the collector from the matched host and never from the
client. Synthetic config (this is the shape of a Reach Around `SITES` entry, and the
blog's local config would carry the same keys):

```json
{
  "blog": {
    "hosts": ["blog.example.test"],
    "mode": "edge",
    "pages": "html-200",
    "link_ids": { "support": "*", "github": "*" },
    "sources": ["bluesky", "mastodon", "newsletter"],
    "geo": "city",
    "min_cell": 5
  }
}
```

Staging and production are two different hosts and must be two different `hosts`
entries or two databases, never one site with both (a duplicate host disables both sites,
`sites.ts`). INFERRED: use a separate preview database so test traffic never lands in
production numbers.

### 2.4 Privacy page additions

The draft text already exists in `docs/privacy-with-analytics.md`. It must change in the
same pull request that turns the counter on (rule from issue 84 and 189), together with
the sentence `scripts/test-pages.sh` asserts. Additions this design needs on top of it:

- Clicks: "when you follow an outbound link, I count the click once, by the name of the
  destination's site only, never the full address, and nothing about you." No country on the raw click
  row; country appears only inside an aggregate counter.
- Source label (VERIFIED against `clickSource` in Reach-Around `worker/src/click.ts`,
  read 2026-11-09): exactly one `s` value that is syntactically valid and on the site's
  list is counted as itself; exactly one that is syntactically valid but not on the list
  is counted as `other` and its text is dropped; a missing, repeated or malformed `s` is
  ignored and the visit stays in the no-source (`direct`) case. A site with no `sources`
  list never reads `s`. The blog's own click route must implement exactly these cases and
  have one test per case.
- Cloudflare Web Analytics: CONFIRMED to stay on (Q3, 2026-11-09). The page names both
  counters and says they are separate (section 5.4). Issues 241 and 405, which tracked
  turning it off, no longer apply to the blog.
- Retention in numbers from config: raw rows 7 days, aggregates 90 days, click funnel
  cells 90 days then monthly sums for 25 months (design section 7; the blog's own
  retention is 7 and 90 today).
- Say plainly: no deletion on request, because nothing identifies a person.

What is and is not collected (the page states both):

| Collected | Not collected |
| --- | --- |
| Page path of a successful HTML page | IP address, whole or partial, anywhere |
| Referrer host only (or a listed `s` label) | Full referrer URL, query string, fragments |
| Time rounded to the hour | Minute or second precision |
| Country, region, city (views); country only in aggregate counters (clicks) | Coordinates, postal code, ASN number, organization |
| Network class, one closed value per view: `hosting-datacenter`, `vpn-proxy`, `tor` or `unknown` (VERIFIED: `netClass` in `analytics/collect.mjs`; `tor` comes from the Tor pseudo-country, whose presence in `cf.country` is UNVERIFIED) | Per-visitor network detail, the ASN number, the network owner name |
| Yes or no: likely bot | User-agent string, TLS or HTTP fingerprint |
| Click on a listed destination | Cookie, localStorage, sessionStorage, IndexedDB value used to recognize a visitor |
| | Any cross-visit, cross-site or third-party identifier; any join to an email, account, handle, donation |

### 2.5 What must NOT be collected

From issue 408 (VERIFIED) and the blog draft: raw or partial IP in any table, log,
cache, queue or export; user-agent text; fingerprint signals; cross-site identifiers;
cookie or storage identifiers; joins to a person; coordinates, postal code, ASN, organization;
full referrer URL or query; per-visitor network detail. Also: no source-by-country pair,
no country-by-device pair, no city with clicks, and no handler that logs a request.
Enforce with the schema guard (a column named like an address fails CI), a sentinel test
(synthetic documentation-range addresses go through every route, then every table and log
is dumped and searched), and a privacy-coverage test (every stored column has a phrase on
the page).

## 3. Edge mode versus beacon mode for a static site (issue 189)

| | Edge mode (server counts as it serves) | Beacon mode (script posts after load) |
| --- | --- | --- |
| New script, CSP change | None | One pinned script, hash files, build checks; CSP unchanged if same origin (INFERRED) |
| Works with scripts blocked, GPC on | Counts the load; must still honor `Sec-GPC` and DNT by recording nothing | Misses blocked scripts; script can honor GPC itself |
| Real referrer and `s` label | Yes, from the request | Yes, from `document.referrer` and the address |
| Bots and prefetch | Sees them all; classifier separates them | Mostly blind to bots that do not run script |
| Window size | No | Yes (not wanted) |
| Cost | One Function invocation per HTML view, counted against 100,000 per day on free; VERIFIED rule above. Cached pages: INFERRED that Pages Functions run before cache, as the design assumes for Workers; UNVERIFIED for Pages, settled by the spike. | Collector cost only for pages that run the script |
| Site id source | Matched host (cannot be forged by a client) | Route plus `Origin`, a noise filter only (threat A1) |
| Fit to the blog's rules | Fits: no script, strict CSP unchanged | Conflicts with "works with no JavaScript" and the pinned-script allowlist |

Recommendation: edge mode, as the design already says (D-A3). Beacon stays a documented
fallback only, for someone whose host cannot run a Function.

Where the edge code lives is the real fork, because the Reach Around Worker has no edge
ingest route:

- Option L (local): keep the blog's Pages Function and its own D1 database. Done and
  tested. Cost: a second implementation of the same rules, two places to fix a privacy bug.
- Option S (shared): the Function derives closed categories and calls the shared Worker
  through a service binding (VERIFIED possible, `/pages/functions/bindings/`). The Worker
  gets a new internal-only edge ingest entry (no public route), the blog drops its own D1.
  Matches issue 189 and the consolidation rule. Cost: new Worker work (L size), the free
  plan counts the Function and the Worker CPU time, and a shared outage touches the blog's
  numbers (not its pages: the Function fails open).
- Option C (converge): ship L now, move the pure functions (`collect.mjs` rules, ASN list
  format, path rules, closed vocabularies) into one shared module that both call, and move
  to S only if a cross-site report is wanted. INFERRED: cheapest in agent hours, keeps one
  place for privacy code, and each step ships on its own.

Owner decision Q1 (2026-11-09): option C, converge.

Cross-site funnel (issue 325): D-A4 says no cross-site unique count. A cross-site view of
"link page to blog" is possible only through the `s` label and the `hop` idea in the
owner decisions of 2026-11-08, never an identifier.

## 4. How someone else would reuse it

The pattern is configuration, not code, so another static-site owner changes two things:

1. A site entry (the JSON in 2.3): `id`, `hosts`, `mode`, `pages`, `link_ids`, optional
   `sources`, `geo`, `min_cell`, `raw_keep_days`. Every owner value (host, source
   labels, any listed destinations) comes from this entry or a data file. Nothing about the
   author is in code.
2. A snippet: the Hugo render hook that adds `ping` for external links, the
   `_routes.json` and `_headers` lines, and the privacy text template that is built from
   the same config (design 9 item 12: the text cannot say less than the code does).

Documentation to ship (phase 4): a short "add analytics to your Hugo site" page with the
config, the snippet, the privacy template, the preview-first deploy order, and the
owner-only account steps as a checklist. Docs-only; no tokens, no account ids.

Rules that keep it reusable: no hard-coded owner value, host or account id in any
committed file; closed vocabularies for every free-text field; the privacy text generated
or tested from the stored fields; per-site kill switch; every default in config with a
ceiling.

## 5. Consequences and required guardrails for the confirmed decisions

### 5.1 Q2 C: city in the aggregates

Consequence: a place cell can now name a small town in a daily table that lives 90 days.
For a small blog, a rare city plus a page can point at one reader (design threat B4).

Required:
- The floor applies per place granularity, not once. A city cell below the floor (5
  views, the blog's `min_cell`) is withheld and its count rolled up into its region; a
  region cell below the floor rolls up to its country; a country cell below the floor
  folds into `other`. The roll-up happens at report time (the same remainder rule as
  the funnel counters, design 6.2), so no released view holds a sub-floor city.
- Complementary suppression: if exactly one cell in a group is withheld, the next smallest
  is withheld too, so a subtraction from a printed total cannot recover it (small-cell
  test from issue 408).
- City stays in a marginal table by itself. It is never joined to network class, device,
  source or clicks; no city-with-click pair.
- What the code does today (VERIFIED, `analytics/migrations/0001_page_views.sql` and
  `analytics/maintenance.sql`, read 2026-11-09): the daily rollup copies country, region
  and city from the raw rows into `view_geo_daily` (key: day, country, region, city, bot
  class), kept 90 days. The reader view `report_view_geo_daily` applies one floor of 5:
  a cell under 5 is dropped from the listing and the dropped cells of that day and class
  are summed into one `other` row, shown only if that sum is at least 5. So city in the
  aggregate already exists, which matches decision Q2 C, but there is no roll-up of a
  withheld city into its region or country, and the stored table still holds sub-floor
  cities (readable with the D1 token, not through the report view).
- What must change (plan item 4): new report views with a per-level floor (city cells
  under 5 summed into their region, region cells under 5 into their country, country
  cells under 5 into `other`, each level shown only if its sum is at least 5), the
  complementary-suppression rule, and a small-cell test that enumerates datasets per
  level. The migration is a new view (and a stored-fold option if the owner wants
  sub-floor cities never stored); the rollup SQL needs no change for the view-only
  version. The earlier statement that city exists only in 7-day raw rows is withdrawn.
- Stored-fold decision for issue 294: use the view-only option. Sub-floor cities remain
  in the place-only aggregate table for its 90-day lifetime and are protected by the
  report views. They are not folded at write time.
- City aggregates share the 90 day ceiling (as the current retention SQL does); raw rows keep 7 days.
- Residual risk, stated plainly here and on the privacy page: on a small audience a town
  with a few readers can still be inferred by someone who knows who reads the blog. The
  floor reduces this, it does not remove it.
- Privacy page: country, region and city are kept in daily totals; places with fewer than
  5 visits are merged into the larger area; a rough location can be wrong.

### 5.2 Q4 B: every external link by registrable domain

Consequence: an open vocabulary. Anyone who can put a link on the site (a guest post, a
contributor) adds new destination values, and a long tail of domains grows the table.

Required:
- Reduce the destination at build time, not at click time: the Hugo render hook derives
  the registrable domain (eTLD+1) of each external link and writes it into the ping
  address. The Function re-validates it: lower case, `[a-z0-9.-]`, at most 63 characters,
  at least one dot, parsed against the Public Suffix List, and equal to an eTLD+1 (no
  subdomain, no port, no IP literal, no userinfo).
- Public suffix handling: ship a pinned copy of the Public Suffix List with a dated
  version, refreshed by a scheduled job. A value that is itself a public suffix or does
  not parse is counted as `other`. Private-section suffixes (hosting platforms) are
  treated as suffixes, so a platform's tenants are not separate cells unless listed.
- Strip paths, queries, fragments and ports at build time and again in the Function. No
  full URL is ever stored, logged or shown; a raw row carries at most the domain.
- Cap: at most 150 distinct domains stored per day, the rest folded into `other` (budget
  and abuse resistance), with the pool-and-overflow rule of design 6.2: reserved cells,
  an hourly slice of new cells so a flood in one hour cannot spend the day, existing
  cells keep counting.
- Only domains present in the built site are admitted by name: the build emits the list of
  registrable domains that appear in the site and the Function checks membership, so a
  forged ping naming a made-up domain counts as `other`. The vocabulary is open for
  authors and closed for attackers.
- Floors and monthly roll-up follow the funnel counters. Country on clicks stays in an
  aggregate counter only; no domain-by-country pair.
- Privacy page: outbound clicks are counted by the destination's site name only, never the
  full address, and the count is a floor because some browsers do not send the ping.

### 5.3 Q6: unique-visitor hashing was dropped

Current decision: the blog records page-view counts without a unique-visitor hash. As
the existing finding above states, "The blog's built collector leaves it out," and
`analytics/collect.mjs` explicitly implements no unique-visitor hash or secret. There is
no `VIEW_HASH_SECRET`, daily visitor code, or `visitor_seen` table to create, retain,
export, rotate, or purge.

Superseded design history: Q6 B briefly proposed a daily keyed hash for unique visitors,
with a secret and a short-lived table. That proposal was never implemented and is not
scheduled. It remains summarized here so the decision change is visible instead of
silently deleting the earlier design.

### 5.4 Q3 B: two counters

Consequence: the same visit is counted by Cloudflare Web Analytics and by the blog's own
counter, under different rules.

Rationale: keep Cloudflare Web Analytics because it supplies page timing independently
of the blog's server-side page, source and click counts. That operational signal remains
useful when the blog counter is not deployed or drops a count, and the two counters are
not joined. The privacy page must continue to describe Cloudflare's collection separately.

Required:
- The privacy page names both counters (Cloudflare Web Analytics, with the dated quote
  already on the live page, and the blog's own server-side counter) and says they are
  independent, and what each does and does not collect.
- CSP additions already in `static/_headers` stay: `script-src` includes the Cloudflare
  beacon URL and `connect-src 'self'`. VERIFIED from the repository file read on
  2026-11-09. No new CSP entry is needed for the server-side counter or for same-origin
  pings (pings: INFERRED, confirm in the spike). Nothing else is added.
- Owner Cloudflare step: keep Web Analytics enabled for the Pages project. The post-deploy
  smoke test checks that one configured beacon is injected on the home page after every
  deploy. Issues no-php-no-cry#241 and Reach-Around#405, which tracked turning it off, do
  not apply to the blog and should be closed or labeled accordingly by the owner.
- Reconciliation note, for the docs and the report footer. The counters will not match.
  Expected causes: Cloudflare's beacon runs as a script, so it misses visitors who block
  it; the blog counter runs server side, so it also counts visitors who block scripts, and
  counts crawlers (kept in their own bot class), prefetches and link previews; the blog
  counter records nothing for Global Privacy Control or Do Not Track; the blog counts UTC
  days; the 5-view floor hides small cells in the blog report; a Function failure fails
  open and drops one count. INFERRED: Cloudflare's own definitions of a visit and of bot
  filtering were not re-read here. Rule of thumb to document: the blog counter is the
  source for pages, sources and clicks; Cloudflare is the source for page timing; neither
  is a billing figure.

## 6. Privacy and threat model, short

Adversaries (in scope): public visitors who can send any request to the collector, and
readers of released reports. The owner is a trusted operator on his own machine
(design 6.2). Out of scope: an operator editing his own files; Cloudflare itself.

| Threat | Prerequisite | Guardrail | Check |
| --- | --- | --- | --- |
| Path flood grows storage | Any client | Count only origin-confirmed 200 HTML; path shape rule; page cap with an `other` fold | Random-path and cap tests |
| Click and source forgery | HTTP client | Destination checked against the built-site domain list; `s` closed list; `Ping-From` is a noise filter only; per-site budgets | Forged-header and forged-domain tests |
| Destination domain flood (open vocabulary, Q4) | Any client sending pings | Public suffix check, build-time membership, 150 per day cap with reserved cells and an hourly slice, one overflow row | Flood, suffix and cap tests |
| Edge amplification burns the daily free quota | Flood of real pages | Background write bounded by a timer, kill switch (`ANALYTICS_OFF`), fail open, and a local per-deployment per-hour admission budget before D1. The skipped counter has no request details. Untrusted request hostnames do not create counters. The limit applies per Function isolate, so concurrent isolates can each admit their own budget. | Concurrent load test with the budget spent |
| Small-place re-identification (city in aggregates, Q2) | Reader of a report or D1 | Per-granularity floor, roll up to region then country, complementary suppression, city in its own marginal table | Small-cell test per granularity |
| Profile built from the network class (hosting, VPN or proxy, Tor) | D1 read access | Class lives only in its own marginal table | Schema guard |
| Report leaks a suppressed value by subtraction | Reader of released reports | Marginal pairs only; remainder row; joint suppression with totals; applies only to page-view counts because Q6 superseded unique counts | Matrix test (issue 408) |
| Visitor code linked across days or to a person (superseded Q6) | A unique-visitor hash exists | Not applicable: the blog dropped visitor hashing, and `analytics/collect.mjs` creates no visitor code or secret | Collector and schema review |
| Hash key leak (superseded Q6) | A visitor hashing key exists | Not applicable: the blog has no visitor hashing secret | Collector and configuration review |
| Two counters disagree and get misread as a bug or a leak | Reader of both | Reconciliation note in docs and report footer | Doc test |
| Raw address or user agent reaches a table or log | Code bug | Locals of one function; no logging in the handler; sentinel test on every route | Sentinel test |
| Collector exposed as a public data API or with permissive CORS | Knowing the route | Write-only, uniform empty answer, no `Access-Control-Allow-*`, no GET that returns rows | Header test |
| Config drift: site added without a privacy change | Mistaken change | Strict loader; privacy-coverage test in CI | Negative-case test |

Detail of any hardening beyond this list stays in the private tracker until fixes merge
(owner rule); this public page records scope only.

## 7. Phased plan, issues to file, and owner-only steps

Sizes are agent hours, a guess. The epic for blog-side work is no-php-no-cry#1 (static site
migration); shared work belongs to Reach-Around#325 (One site system) or Reach-Around#245
(Analytics funnel and owner report). Each item is filed with its epic, Kind and Effort on
the board before work starts (this PR files nothing).

| # | Phase | Issue to file | Epic | Kind | Size |
| --- | --- | --- | --- | --- | --- |
| 1 | 0 Decide | Record decisions Q1 to Q5 and the superseded Q6 unique-visitor proposal (board and docs) | #1 | Task | XS |
| 2 | 1 Spike | Close the UNVERIFIED items on a preview deployment: city in `request.cf`, cached HTML invoking the Function, `ping` support and CSP, bundle size with the ASN list and the suffix list | #1 | Task | S |
| 3 | 2 Views live | Turn the existing Function on: bind the database, privacy page swap, test update, ASN refresh, daily maintenance job from the GYST pattern (existing no-php-no-cry#84, #189) | #1 | Feature | M |
| 4 | 2 Views live | City in aggregates with per-granularity floor, roll-up to region then country, complementary suppression and the small-cell test (Q2) | #1 | Feature | M |
| 5 | 2 Views live | Superseded: no work. The blog dropped unique-visitor hashing and has no visitor table or hashing secret | #1 | Feature | M |
| 6 | 2 Views live | Reach-Around: threat model entries for the blog site, with the Q2 and Q4 rows and the dropped Q6 proposal recorded (extends Reach-Around#333) | R#325 | Task | S |
| 7 | 3 Clicks | Open-vocabulary outbound click ping: render hook with eTLD+1 reduction, built-site domain list, POST route, cap and `other` fold, pinned Public Suffix List with refresh job, tests (Q4) | #1 | Feature | L |
| 8 | 3 Clicks | Closed `s` source label list with referrer-host fallback on blog pages (Q5) | #1 | Feature | S |
| 9 | 3 Clicks | Guardrail tests for the blog: sentinel, schema guard, small-cell, forged domain (reuses Reach-Around#408) | #1 | Task | M |
| 10 | 3 Privacy | Privacy page rewrite covering both counters, city, domain clicks, floors and the reconciliation sentence, with the test change in the same PR | #1 | Feature | S |
| 11 | 3 Privacy | Cloudflare Web Analytics kept: update docs and CSP notes; require the beacon in the post-deploy smoke test; close or relabel no-php-no-cry#241 and Reach-Around#405 for the blog (Q3) | #1 | Task | XS |
| 12 | 3 Docs | Counter reconciliation note and report footer wording (Q3) | #1 | Task | XS |
| 13 | 4 Converge | Extract the shared rules (path, referrer, bot, closed vocabularies) into one module used by both sites (Q1). The Q6 visitor-code derivation is superseded and is not part of this work | R#325 | Feature | M |
| 14 | 4 Converge | Edge ingest entry in the shared Worker plus service binding, only if the owner later wants a cross-site report | R#325 | Feature | L |
| 15 | 5 Report | Blog report views and a funnel section for site `blog` in the owner report, floors applied. Needs item 18 first | R#245 | Feature | M |
| 17 | 2 Views live | Per-site per-hour admission budget in the Function (sample or skip before the D1 insert once spent, flagged in a counter), and the load test (closes the gap in the threat table) | #1 | Feature | M |
| 18 | 5 Report | Report input for the blog database: how the owner report reads the blog's separate D1. Options: read the `report_*` views through a scoped read-only token from the owner's machine (no public endpoint), or a periodic export of the aggregate views only (never raw rows); a service binding does not help because the owner report runs locally. Decide, then build | R#245 | Feature | M |
| 16 | 6 Reuse | Public how-to: add this to your own Hugo site (config, snippet, privacy template, checklist), with the less private choices flagged as options | #1 | Docs | S |

Dependencies: 15 needs 7 and 18; 18 needs 3 (the database must exist); if plan item 14 is ever built and the blog moves to the shared database, 18 is replaced by the shared read path. 1 before everything; 2 before 3; 3 before 4, 5, 7 and 8; 10 ships with the
first deploy that turns counting on; 13 can start after 3 and does not block 7; 17 can ship with 3.
Cutover (no-php-no-cry#67) waits on phase 2, per the maintainer ruling of 2026-11-04. A
waiver for the go-live gate is recorded in no-php-no-cry#207.

### Owner-only Cloudflare and Doppler steps

Nothing here was run. Wording was read from the Cloudflare docs on 2026-11-09 unless marked
UNVERIFIED; dashboard paths can change, so re-read before use.

| Step | Why | Wording / source |
| --- | --- | --- |
| Create a D1 database for the blog (preview and production) | Holds the page-view counter tables; no visitor hash table is planned | `wrangler d1 create ...` per `docs/analytics-deploy.md` step 1 (D1 docs not re-read here, UNVERIFIED) |
| Bind it to the Pages project: Workers & Pages > project > Settings > Bindings > Add > D1 database > pick it > redeploy | The Function sees `env.DB` | VERIFIED: `/pages/functions/bindings/#d1-databases` |
| Token scope for D1 edit (the deploy token or a second token used only by the maintenance job) | Apply migrations, run the daily roll-up and purge | `docs/analytics-deploy.md` access table; drop the scope after the work. Scope names UNVERIFIED against the token docs |
| Keep Cloudflare Web Analytics enabled for the Pages project (Q3) | Second counter, kept by choice | The post-deploy smoke test checks the injected beacon; the CSP entries are in `static/_headers` |
| Review Settings > Runtime > Fail open / closed; keep "fail open" | A spent free daily allowance must not take pages down | VERIFIED: `/pages/functions/routing/` |
| Decide Workers Free versus Standard after a week of real request counts | The 100,000 per day free allowance is shared by Functions and Workers | VERIFIED limit; the decision is the owner's |
| Optional, only for plan item 14: service binding from the Pages project to the shared Worker | Edge ingest without a public route | VERIFIED: `/pages/functions/bindings/#service-bindings` |
| Worker route in front of the Pages custom domain | Alternative to a Function | UNVERIFIED. Pages known issues say a custom domain cannot be added while a Worker is already routed on it (`/pages/platform/known-issues/`, read 2026-11-09); not needed here |

### Privacy page change list (one pull request with the first deploy that counts)

1. Replace the "collects nothing" and "no analytics" sentences; update `scripts/test-pages.sh`.
2. Name both counters, keeping the dated Cloudflare quote.
3. Views: hour, path, referrer host, country, region and city (rough, can be wrong), a network class (hosting provider, VPN or proxy, Tor, or unknown; a rough guess from a list of network numbers), a bot class.
4. Places under 5 visits are merged into the larger area.
5. Unique visitors: state that the blog does not create a visitor hash or daily code.
6. Clicks: outbound links counted by destination site name only; a floor, not a total; optional `s` label.
7. What is not collected (the table in 2.4); retention in numbers from config.
8. Global Privacy Control and Do Not Track honored by the blog counter.
9. Link to the public do-not-collect list (issue 408 acceptance).
10. One sentence on why the two counters differ.

## 8. Decision record (CONFIRMED 2026-11-09)

Recorded from the owner's answers in PR #287.

- Q1 A converge: ship the local Function now, share the pure rules in one module.
- Q2 C: country, region and city in aggregates (guardrails in 5.1).
- Q3 B: keep Cloudflare Web Analytics and describe both counters (5.4).
- Q4 B: every external link by registrable domain (5.2).
- Q5 A: closed `s` label list, referrer host as the fallback.
- Q6 B was a daily keyed hash proposal for unique visitors. It was later dropped for the
  blog and never implemented. The current collector has no unique or returning visitor
  figure, visitor code, visitor table, or hashing secret (5.3).
