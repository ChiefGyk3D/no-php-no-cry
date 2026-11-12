# Blog page-view counter: what is built, and the deploy-time steps (issue 84)

Status: built and tested locally. NOT deployed. Nothing in this pull request
creates a Cloudflare resource, changes the deploy workflow's behavior, or calls
the Cloudflare API. The steps below are for the maintainer to approve and run
later. Alpha: every default here is provisional.

## What exists

| Path | What it is |
| --- | --- |
| `functions/_middleware.js` | The Pages Functions entry for views. Calls `analytics/middleware.mjs`; the function-tree allowlist test also permits only the outbound click route and `package.json`. |
| `analytics/middleware.mjs` | Fail-open wrapper: returns the page first, writes in the background, bounded by a timer, swallows errors, logs nothing. |
| `analytics/collect.mjs` | Pure functions: path rules, referrer host, geo, ASN class, bot class, opt-outs, the row. |
| `analytics/hosting-asns.mjs` | The ASN list (data file, no CIDR). A starter list, to refresh before go-live. |
| `analytics/migrations/0001_page_views.sql` | Tables, the 5-view floor (`report_*` views) and the funnel view. |
| `analytics/migrations/0002_report_top_referrers.sql` | A per-day registry that caps stored referrer domains, and the replacement report views: top 20 referrer domains per day and class, the rest folded into "other". |
| `analytics/rollback/0002_down.sql` | Rollback for 0002 (not a migration; run by hand). Restores the 0001 views and drops the registry. |
| `analytics/maintenance.sql` | Daily rollup and retention (7 days raw, 90 days aggregates). Not scheduled yet. |
| `analytics/migrations/0005_outbound_clicks.sql` | Outbound-click raw rows, separate domain and country counters, five-click report floors, and the 25-month domain roll-up. |
| `analytics/rollback/0005_down.sql` | Idempotent rollback for the outbound-click tables and report views. |
| `analytics/public_suffix_list.dat` | Pinned, dated Public Suffix List, including its private section. |
| `analytics/site-domains.mjs` | Generated allowlist used by the click Function. Contains domains only. |
| `functions/e/c/[[domain]].js` | Empty-204 POST route for outbound pings. Re-validates the eTLD+1 and writes no URL. |
| `layouts/_markup/render-link.html` | Markdown link render hook that adds a same-origin ping for external destinations. |
| `static/analytics-domains.txt` | Generated list of outbound eTLD+1 values present in site content. |
| `analytics/wrangler.toml.example` | The D1 binding template. |
| `static/_routes.json` | Limits the Function to HTML routes: the HTML pages (including `/support/`) run it; the CSS, fonts, brand files, images and the support QR and coin SVGs (`/support/qr-*.svg`, `/support/coin-*.svg`) do not. Required in the upload; copied there by Hugo. |
| `docs/privacy-with-analytics.md` | The draft `/privacy/` text. Not live. |

## What was reused from Reach Around

From `ChiefGyk3D/Reach-Around`, `docs/analytics-design.md` (PR #222) and
`worker/migrations/0005` to `0007`, `worker/src/view.ts`, `viewrollup.ts`,
`viewretention.ts`:

- The raw table shape (`view_events`) and its closed value sets: source kinds
  `d i r o`, bot classes `h a`, network class names (`hosting-datacenter`,
  `vpn-proxy`, `tor`, `unknown`).
- The three marginal daily tables (`view_daily`, `view_geo_daily`,
  `view_dim_daily`), so cities and networks are never recombined into a profile.
- The path rules (design 3.2), the hour rounding (design 3.3, decision D-A1),
  referrer cut to host, `Sec-GPC` and Do Not Track honored, bots counted in
  their own rows, and the retention numbers (7 days raw, 90 days aggregates).
- The 5-view floor (Reach Around calls it `MIN_CELL`).

Left out on purpose, to match the brief and keep this slice small: the
unique-visitor hash and its secret (nothing derived from an address is kept),
the site column (this database is the blog's alone), browser/OS/language/window
columns, UTM labels, the per-hour abuse budgets, the watermark-based rollup
state. Instead the rollup recomputes the last 6 UTC days idempotently; see the
invariant at the top of `analytics/maintenance.sql`. The collector is a Pages
Function in this repository, not the shared Reach Around Worker. Moving to the
shared collector is an open question for later (design section 5.2).

## Why the artifact rules changed

| Rule | Change | Why |
| --- | --- | --- |
| `artifact_name_ok` (`scripts/artifact-rules.sh`) | `_routes.json` is allowed (and, see the check below, required) at the root of the upload, like `_headers` and `_redirects`. Any other `.json` and any nested `_routes.json` is still rejected. | Pages reads `_routes.json` from the upload directory. |
| `check-site-artifact.sh`: `_routes.json` reserved name | Removed from the reserved list. Replaced by three checks: the file must exist in the upload (`routes-missing`; with the Function enabled, no file would leave nothing limiting execution to HTML routes), it must be byte for byte `static/_routes.json`, and that expected file must pass `routes_policy_ok` (exactly `version` 1, `include`, `exclude`; rules start with `/`, at most 100 characters each, at most 100 rules in all; no duplicate keys). | A routing file cannot add code, but a loose one could send every asset request through the Function and burn the free request quota. Pinning it like `_headers` keeps it a reviewed change. |
| `check-site-artifact.sh`: `functions` reserved name | Not loosened. A `functions/` directory inside the upload is still rejected. | The Functions source is not in the upload directory. Wrangler compiles `functions/` from the project root. The upload (`public/` or the `site` artifact) never needs it, so allowing it there would only widen what the check lets through. Deviation from the brief wording; see the PR. |
| `check-deploy-sparse.py`, `deploy.yml` sparse list | `static/_routes.json` added, because the artifact check now reads it before any secret exists. | The sparse test fails CI if a file a script needs is not checked out. |
| `static/_headers`, CSP | Unchanged. | The collector is server side. No script is added to any page. |

`check-output.sh` needed no edit: it uses `artifact_name_ok`, so the new root
file is accepted there and everything else stays rejected.

## Deploy-time steps (nothing here has been run)

### Access: the union, asked once

| Scope | Why | When |
| --- | --- | --- |
| Account, Cloudflare Pages, Edit | Deploy with Functions and the D1 binding. The deploy token already has it. | Step 4 |
| Account, D1, Edit | Create the database, apply the migration, run the daily maintenance file. New scope on the token (or a second token used only by the scheduled job). | Steps 1, 2, 6 |

Nothing else. No Workers Scripts scope (the scheduled cleanup below is a GitHub
Actions job, not a Worker), no Analytics read, no zone or DNS scope, no secret
for hashing (the collector has none). When the work ends, drop the D1 scope from
the deploy token if the cleanup runs under its own token.

### Steps

1. Create the database (maintainer approval needed):
   `wrangler d1 create no-php-no-cry-analytics`. Note the printed id.
2. Copy `analytics/wrangler.toml.example` to `wrangler.toml` at the repository
   root and fill in `database_id`. Apply the migration, remote:
   `wrangler d1 migrations apply no-php-no-cry-analytics --remote`.
3. Change `.github/workflows/deploy.yml` so the deploy job (a) checks out
   `/functions/`, `/analytics/` and `/wrangler.toml` in its sparse list, and
   (b) runs Wrangler from the repository root, which it already does
   (`wrangler pages deploy site` runs where `functions/` is). Add
   `scripts/test-deploy-sparse.sh` coverage for the new entries. Direct upload
   compiles `functions/` only through Wrangler, not the dashboard (per the
   research; confirm on the deploy page before relying on it).
4. Verify on a preview deployment (a non-production branch): the Function runs
   only on HTML routes, and a page still loads with the database binding
   removed (fail open). Run `wrangler pages functions build` once locally to see
   the `_routes.json` it generates and compare with `static/_routes.json`.
5. Check these, which this slice could not (all marked UNVERIFIED):
   - The `/*.css` style glob is valid in `_routes.json`. Verified in the Pages routing docs (developers.cloudflare.com/pages/functions/routing/, page dated 2026-09-18): wildcards match any number of path segments, `exclude` takes priority over `include`, at least one `include` rule, at most 100 rules combined, at most 100 characters per rule. Inferred, not shown on that page: a mid-pattern `*` such as `/*.css` or `/support/qr-*.svg` behaves the same way.
   - `request.cf` is present in Pages Functions on the free plan, and `T1` is
     the Tor pseudo-country in `cf.country`.
   - Whether a static asset or a cached HTML page still runs the Function, and
     what that costs in the 100,000 requests per day shared Workers/Functions
     quota (excluded paths in `_routes.json` are free).
   - The Function bundle size with the ASN list.
   - That `wrangler d1 execute --file` stops at the first failing statement.
6. Schedule `analytics/maintenance.sql` daily (recommended: a GitHub Actions
   `schedule:` job calling `wrangler d1 execute no-php-no-cry-analytics --remote
   --file analytics/maintenance.sql`, built from the GYST pattern, with the D1
   scope token). It is safe to run twice. A missed run is fine for up to 5 days.
7. Go live: swap `docs/privacy-with-analytics.md` into
   `content/privacy/index.md`, update `scripts/test-pages.sh`, and update
   `docs/privacy-and-analytics.md`, all in one pull request with the first
   deploy that has `DB` bound. Until `DB` is bound the middleware records
   nothing, so shipping the Function before the binding is harmless.
8. Refresh `analytics/hosting-asns.mjs` from a source the maintainer picks
   (open: which list, how often) before step 7.

Rollback: set `ANALYTICS_OFF=1` as a plain variable (records nothing at once),
or remove the `DB` binding, or revert the deploy. To delete data:
`DELETE FROM view_events; DELETE FROM view_daily; DELETE FROM view_geo_daily;
DELETE FROM view_dim_daily;`.

## Limits to know about

- D1 free plan: about 100,000 row writes a day and a hard failure past the cap.
  One view is one row write (no index, no autoincrement table), and the daily
  maintenance writes a few hundred rows. The Function swallows the failure, so
  past the cap views are lost, pages are not. Estimate and measure; if the cap
  nears, the sink can change (Analytics Engine) with the same row shape.
- Cardinality is bounded because only 200 `text/html` responses count, and each
  path is checked for shape. A real page is the only way to add a path.
- Reading the numbers: query the `report_*` views only, for example
  `wrangler d1 execute no-php-no-cry-analytics --remote --command "SELECT * FROM report_funnel_daily ORDER BY day DESC LIMIT 50"`.
  There is no public endpoint that returns data.
- City plus path at low traffic can point at a person. The 5-view floor hides
  small groups in the reports. The raw rows (7 days) hold the city and are
  readable only with the D1 token.
- Referrer domains: the Referer header is forged freely, so nothing can tell a
  real domain from a forged one. Two controls. (1) At write time the collector
  stores at most 300 distinct referrer domains per UTC day (`REFERRER_DAILY_CAP`
  in `analytics/collect.mjs`); a later new domain is stored as "other". This
  bounds the 90 day `view_daily` rows and the six-day maintenance recompute,
  which grow with distinct domains. It is first come within a day: a requester
  who sends 300 forged names early can make real domains that first appear
  later that day count as "other" for that day, at a cost of 300 requests a day
  and without losing a view. The registry insert and the event insert go to D1
  as one `batch()`, which D1 runs as a single transaction (Cloudflare D1
  `D1Database::batch` docs, read 2026-11-10), so a failure or timeout between
  them leaves neither a registered domain without its event nor the reverse;
  the event reads the registry in the same batch, so a lost last-slot race
  stores "other". (2) At report time migration 0002 lists the 20
  domains with the most views per day and class and folds the rest into "other".
  Residual risk, proposed as Low and awaiting the owner's acceptance in the
  threat model: partitioning by class does not stop a forged domain from being
  classified likely human (without Bot Management an ordinary browser
  User-Agent gets that class), so a requester who sends more views than a real
  domain can outrank it in the listing. The test suite pins this limit.
  Hardening tracked in #72.
- The 5-view floor is a display floor, not a privacy bound across reports. Each
  report hides its own small cells, but the reports share totals: a total from
  one report minus the published cells of another can reveal a suppressed cell
  (the suite pins an example). Do not read the floor as k-anonymity across
  reports, and treat the raw rows (7 days) and the aggregate tables as private
  to the D1 token. Report semantics are unchanged here. Hardening tracked in #72.
- Migration 0002 safety. Verified (Cloudflare D1 docs, read 2026-11-10):
  `D1Database::batch` statements run as one SQL transaction that rolls back on
  failure, and an imported SQL file must not contain BEGIN or COMMIT. Not
  stated in the docs, so inferred and not relied on: that wrangler applies a
  whole migration file atomically. The file therefore has no transaction of its
  own; it creates the additive registry first, drops the funnel view before the
  view it reads, and creates the replacements back to back. Rehearse it on a
  local database first (`wrangler d1 migrations apply <db> --local`). If a
  remote run stops part way, run the rollback by hand:
  `wrangler d1 execute <db> --remote --file analytics/rollback/0002_down.sql`.
  It restores the exact 0001 view text, drops the registry, and tolerates a
  partial state. Deploy the pre-0002 collector before rolling back (the new
  insert reads the registry). The test suite applies 0002, a deliberately broken
  0002 and the rollback to an in-memory database and compares the views with
  0001. Whether the platform leaves a failed run's earlier statements applied
  was not tested against D1.
- The egress check (`analytics/test/fixtures/egress-probe.mjs`) is a regression
  test, not a proof. It runs the Function with outbound and logging entry points
  trapped, driving a table of methods, paths, hosts, statuses, header names and
  values. It cannot show that no input at all reaches an outbound call; the
  source scan is a lint on top. Pages Functions have no platform switch that
  removes outbound access, so review of the small collector source stays part of
  the control.
- Not done here: a dashboard, a per-client rate cap, a Bot Management feed
  (`cf.botManagement` is used only if the zone has it), UTM sources.
