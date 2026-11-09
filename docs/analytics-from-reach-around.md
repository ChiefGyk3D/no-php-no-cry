# Analytics from Reach Around: how the blog hooks in, and how others can reuse it

Status: design only. Nothing here changes code, a workflow or a Cloudflare setting.
Refs issue 84 (blog analytics) and issue 189 (edge-mode collector). Written 2026-11-09.

## Summary for the owner

(First draft from the local model, then corrected by hand against the sources below.)

- The blog already has its own page-view counter: a server-side Pages Function plus a D1
  schema, built and tested, not deployed (`docs/analytics-deploy.md`). It reuses Reach
  Around's data rules but is a copy of the shape, not the shared Worker.
- Reach Around's shared Worker already knows about multiple sites (migration 0008) and
  counts clicks. It has no route that accepts a blog page view yet: an edge-mode site is
  rejected by the view route today (`worker/src/view.ts`). Issue 189 assumes that route
  exists. It does not.
- Smallest next step: keep the blog's own Function for views, add outbound-link click
  pings from a closed list of destinations, and swap in the drafted privacy text in the
  same pull request that turns it on. No new script, no CSP change.
- The real decision for you is whether the blog should keep its own collector or move
  onto the shared Worker (section 3 and the questions in section 8). Both are cheap to
  start; moving later costs a migration of one table.
- Cloudflare steps that only you can do are listed in section 7. Nothing has been done.

Labels used below: **VERIFIED** (source and date read) or **INFERRED** (reasoned, not
read). Cloudflare facts were read through the Cloudflare docs search on 2026-11-09.
Placeholders: `blog.example.test` is the blog host, `links.example.test` the link page host.

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
- Unique-visitor hashing. The blog's built collector leaves it out on purpose; the owner
  decision of 2026-11-08 says no unique or returning visitors for the funnel report
  (design 6.2). Keep it out.
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
  `ping="/e/c/<id>"` only when the destination host is on a closed list kept in a data
  file (`data/outbound.yaml`: destination host to short id such as `support` or
  `github`). A host not on the list gets a plain link and no ping. This keeps the id
  space closed and the cardinality bounded, the same rule as `link_ids`.
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

- Clicks: "when you follow an outbound link from a short list, I count the click once,
  with the name of the destination and nothing about you." No country on the raw click
  row; country appears only inside an aggregate counter.
- Source label: if a `?s=` label is on the address and is on the closed list, it is
  counted; any other value is counted as "other" and discarded.
- Cloudflare Web Analytics: the live page says it is on. If it stays on, the page must
  describe both systems and say they are separate. Issues 241 (blog) and 405 (Reach
  Around) already track turning it off; the cleaner state is one counter, ours.
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
| Yes or no: hosting or VPN network class | Per-visitor network detail |
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

Cross-site funnel (issue 325): D-A4 says no cross-site unique count. A cross-site view of
"link page to blog" is possible only through the `s` label and the `hop` idea in the
owner decisions of 2026-11-08, never an identifier.

## 4. How someone else would reuse it

The pattern is configuration, not code, so another static-site owner changes two things:

1. A site entry (the JSON in 2.3): `id`, `hosts`, `mode`, `pages`, `link_ids`, optional
   `sources`, `geo`, `min_cell`, `raw_keep_days`. Every owner value (host, destination ids,
   source labels) comes from this entry or from `data/outbound.yaml`. Nothing about the
   author is in code.
2. A snippet: the Hugo render hook that adds `ping` for listed destinations, the
   `_routes.json` and `_headers` lines, and the privacy text template that is built from
   the same config (design 9 item 12: the text cannot say less than the code does).

Documentation to ship (phase 4): a short "add analytics to your Hugo site" page with the
config, the snippet, the privacy template, the preview-first deploy order, and the
owner-only account steps as a checklist. Docs-only; no tokens, no account ids.

Rules that keep it reusable: no hard-coded owner value, host or account id in any
committed file; closed vocabularies for every free-text field; the privacy text generated
or tested from the stored fields; per-site kill switch; every default in config with a
ceiling.

## 5. Privacy and threat model, short

Adversaries (in scope): public visitors who can send any request to the collector, and
readers of released reports. The owner is a trusted operator on his own machine
(design 6.2). Out of scope: an operator editing his own files; Cloudflare itself.

| Threat | Prerequisite | Guardrail | Check |
| --- | --- | --- | --- |
| Path flood grows storage | Any client | Count only origin-confirmed 200 HTML; path shape rule; page cap with an `other` fold | Random-path and cap tests |
| Click and source forgery | HTTP client | Closed ids and labels; `Ping-From` is a noise filter only; per-site budgets; dashboard says estimate | Forged-header test |
| Edge amplification burns the daily free quota | Flood of real pages | Background write with timeout; budget check before the database; kill switch; fail open | Load test with budget spent |
| Small-audience re-identification (rare city plus path plus time) | Read access to raw rows, or a report | Hour rounding; 5-view floor with complementary suppression; short raw window; city only in 7-day raw rows | Small-cell test (issue 408) |
| Profile built from the hosting or VPN flag | D1 read access | Class lives only in its own marginal table in aggregates | Schema guard |
| Report leaks a suppressed value by subtraction | Reader of released reports | Marginal pairs only; remainder row per destination; joint suppression with totals | Matrix test (issue 408) |
| Raw address or user agent reaches a table or log | Code bug | Locals of one function; no logging in the handler; sentinel test on every route | Sentinel test |
| Collector exposed as a public data API or with permissive CORS | Knowing the route | Write-only, uniform empty answer, no `Access-Control-Allow-*`, no GET that returns rows | Header test |
| Config drift: site added without a privacy change | Mistaken change | Strict loader; privacy-coverage test in CI | Negative-case test |

Detail of any hardening beyond this list stays in the private tracker until fixes merge
(owner rule); this public page records scope only.

## 6. Phased plan and issues to file

Sizes are agent hours as a guess. Epic for the blog-side work is no-php-no-cry#1 (static
site migration); shared work belongs to Reach-Around#325 (One site system) or
Reach-Around#245 (Analytics funnel and owner report). Each item below is to be filed with
its epic, Kind and Effort on the board before work starts (not filed by this PR).

| Phase | Issue to file | Epic | Size |
| --- | --- | --- | --- |
| 0 Decide | Decision: where the blog's edge code lives (L, S or C) and whether city stays on blog views | #1 | XS |
| 0 Decide | Decision record: Cloudflare Web Analytics on or off (links existing no-php-no-cry#241, Reach-Around#405) | #1 | XS |
| 1 Spike | Close the UNVERIFIED items on a preview deployment: city in `request.cf`, cached HTML invoking the Function, `ping` on the supported browsers, bundle size with the ASN list | #1 | S |
| 2 Views live | Turn the existing Function on: bind the database, privacy page swap, test update, ASN refresh, daily maintenance job from the GYST pattern (existing no-php-no-cry#84, #189) | #1 | M |
| 2 Views live | Reach-Around: threat model entries for the blog site (extends Reach-Around#333) | R#325 | S |
| 3 Clicks | Blog outbound click ping: render hook, `data/outbound.yaml`, POST route, tests, privacy text | #1 | M |
| 3 Clicks | Guardrail tests for the blog: sentinel, schema guard, small-cell (reuses Reach-Around#408) | #1 | M |
| 4 Converge | Extract the shared rules (path, referrer, bot, closed vocabularies) into one module used by both sites | R#325 | M |
| 4 Converge | Edge ingest entry in the shared Worker plus service binding (only if option S or C chosen) | R#325 | L |
| 5 Report | Blog report views and a funnel section for site `blog` in the owner report | R#245 | M |
| 6 Reuse | Public how-to: add this to your own Hugo site (config, snippet, privacy template, checklist) | #1 | S |

Dependencies: 1 before 2; 2 before 3; phase 4 can start after 2 and does not block 3;
5 needs 3. The owner-only gates are in section 7. Cutover (no-php-no-cry#67) waits on
phase 2, per the maintainer ruling of 2026-11-04 (stated in issue 84). A waiver for the
go-live gate is recorded in no-php-no-cry#207.

## 7. Owner-only Cloudflare steps

Nothing here was run. Wording was read from the Cloudflare docs on 2026-11-09 unless
marked UNVERIFIED; the dashboard paths can change, so re-read before use.

| Step | Why | Wording / source |
| --- | --- | --- |
| Create a D1 database for the blog (or a preview one plus a production one) | Holds the counter tables | `wrangler d1 create ...` per `docs/analytics-deploy.md` step 1 (that page's own plan; D1 docs not re-read here, UNVERIFIED) |
| Bind it to the Pages project: Workers & Pages > project > Settings > Bindings > Add > D1 database > pick it > redeploy | The Function sees `env.DB` | VERIFIED: `/pages/functions/bindings/#d1-databases` |
| Token scope for D1 edit (deploy token or a second one used only by the scheduled maintenance job) | Apply migration, run daily rollup | `docs/analytics-deploy.md` access table; drop the scope after the work. Scope names UNVERIFIED against the token docs |
| Optional, option S only: service binding from the Pages project to the shared Worker (Settings > Bindings > Add > Service binding > pick Worker > redeploy) | Edge ingest without a public route | VERIFIED: `/pages/functions/bindings/#service-bindings` |
| Review Settings > Runtime > Fail open / closed; keep "fail open" | A spent free daily allowance must not take pages down | VERIFIED: `/pages/functions/routing/` |
| Turn off Cloudflare Web Analytics auto-injection (existing no-php-no-cry#241) | One counter, smaller CSP (drop the beacon script URL) | Dashboard wording not read, UNVERIFIED; then remove the beacon entries from `static/_headers` |
| Decide Workers Free versus Standard after a week of real request counts | The 100,000 per day free allowance is shared by Functions and Workers | VERIFIED limit above; the decision is yours |
| Worker route in front of the Pages custom domain | Alternative to a Function | UNVERIFIED. Pages known issues say a custom domain cannot be added to a Pages project while a Worker is already routed on that domain (`/pages/platform/known-issues/`, read 2026-11-09); the reverse order was not read. Not needed for options L, S or C. |

## 8. Open questions (recommended option first)

1. Where does the blog's edge code live?
   - A (recommended): converge. Ship the existing local Function now, share the pure
     rules in one module, decide about the shared Worker after real numbers.
   - B: shared Worker via service binding now (matches issue 189 as written; largest).
   - C: local only, no convergence (smallest; two copies of the privacy code).
2. How much place detail on blog views?
   - A (recommended): country and region in aggregates; city only in the 7-day raw rows
     (what issue 84 asks and the draft privacy text says).
   - B: country only (strongest for a small audience).
   - C: country, region and city in aggregates too (most detail; highest re-identification risk).
3. Cloudflare Web Analytics?
   - A (recommended): turn it off once our counter is live (one counter, smaller CSP).
   - B: keep both and describe both on the privacy page.
4. Which outbound destinations get a click ping?
   - A (recommended): a short closed list: the support page, code hosting, and the link
     page, nothing else.
   - B: every external link by registrable domain (open vocabulary, needs a cap).
5. Source attribution on blog pages?
   - A (recommended): the closed `s` label list from the owner decision of 2026-11-08,
     referrer host as the fallback.
   - B: referrer host only, no `s`.
6. Unique visitors on the blog?
   - A (recommended): none, matching the 2026-11-08 funnel decision and design D-A4.
   - B: a daily keyed hash as issue 84 first described (needs a secret and `visitor_seen`).
