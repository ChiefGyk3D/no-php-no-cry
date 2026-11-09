# Go-live checklist (issue 323)

One ordered list for the production launch. Written 2026-11-09 from this
repository at that date. It does not replace `docs/cutover.md` (the Cloudflare
call table, the redirect facts and the rollback detail stay there); it orders
every open item around it so the site is never invisible and never broken.

How to read it:

- **Owner** steps are done by the site owner with the owner's own credentials.
  **Agent** steps are repository changes: a pull request the owner reviews and
  merges. Agents never touch DNS, Cloudflare, WordPress, tokens or secrets, and
  never read a secret store.
- **VERIFIED (date)** means the text or value was read on that date, from the
  repository, the GitHub API or the vendor's documentation. **INFERRED** means
  it follows from something verified but has not been seen on the live system.
  An owner step that depends on an inferred fact says so; read the result back
  before moving on.
- Every owner command is complete. A command that needs a Cloudflare token reads
  it once into the shell from a hidden prompt (step 0.2); the token is never put
  in a file, a shell history line or a repository.
- Order is the point: phase 1 and 2 change nothing live. Phase 3 prepares the
  safety net. Phase 4 is the only phase that moves traffic. Do not reorder.

Open issues this list absorbs: 199, 200, 201, 202, 203, 204, 205, 206, 207, 208,
209, 210, 211, 212, 241, 300, 318, 322, 323 (status read with `gh issue list`,
2026-11-09). Pull requests 320 (SEO metadata), 321 (launch check) and 314
(announcement draft) were open on 2026-11-09.

## Phase 0: owner decisions and shell setup (nothing changes)

### 0.1 Record the decisions (Owner)

Write each answer in issue 200 before phase 3. A step below names the decision
it needs.

| ID | Decision | Default in `docs/cutover.md` | Needed by |
|---|---|---|---|
| D1 | Cutover date and time window (a low-traffic hour; WordPress frozen from T0) | none | 3.1 |
| D2 | Does `www` exist, and does it redirect to the apex | read first (step 3.2) | 4.4 |
| D3 | The staging host: 301 to the apex, or its own Pages project (issue 201) | 301 to the apex | 4.5 |
| D4 | Web Analytics beacon: see step 2.3 | none; conflicting, see below | 2.3 |
| D5 | HSTS preload: leave off for launch | off (`docs/performance.md`, read 2026-11-09) | 4.8 |
| D6 | Old `/?p=ID` shortlinks: accept as lost or add a rule (issue 203) | not decided | 3.4 |
| D7 | Two hidden-draft permalinks and their uploads: redirect or 404 (issue 199) | not decided | 3.4 |
| D8 | Fediverse Move from the old WordPress actor (issue 210, optional) | not decided | 3.1 |

- **Verify:** each answer is a comment in issue 200.
- **Rollback:** a decision is a comment; edit it in a new comment.
- Status: VERIFIED (2026-11-09) that the issues exist and are open; the default
  column is quoted from `docs/cutover.md` and `docs/performance.md`, read
  2026-11-09.

### 0.2 Open one terminal for the Cloudflare reads and writes (Owner)

Create a user API token with exactly the union in the `docs/cutover.md` call
table: Zone Read, DNS Edit, Single Redirect Edit, Cloudflare Pages Edit, Cache
Purge (the cache purge only if step 5.3 needs it). Short expiry. Delete it when
phase 5 ends (step 5.6). Then, in one terminal that you keep open for the whole
cutover, paste:

```sh
read -rs -p 'Cloudflare API token: ' CF_TOKEN; echo; export CF_TOKEN
CF() { curl -sS --max-time 20 -H "Authorization: Bearer $CF_TOKEN" -H 'Content-Type: application/json' "$@"; }
API=https://api.cloudflare.com/client/v4
ZONE=$(CF "$API/zones?name=chiefgyk3d.com" | jq -r '.result[0].id'); test -n "$ZONE" -a "$ZONE" != null && echo "zone found"
ACCT=$(CF "$API/zones?name=chiefgyk3d.com" | jq -r '.result[0].account.id'); test -n "$ACCT" -a "$ACCT" != null && echo "account found"
PROJ=no-php-no-cry
mkdir -p ~/golive-private && chmod 700 ~/golive-private && echo "private folder ready"
```

- **Verify:** it prints `zone found`, `account found` and `private folder
  ready`, and prints no id.
- **Rollback:** `unset CF_TOKEN ZONE ACCT`, then revoke the token in the
  Cloudflare dashboard.
- Status: the project name `no-php-no-cry` is the default in `docs/deploy.md`
  (VERIFIED 2026-11-09). The zone and account lookups use `GET /zones?name=`
  from `docs/cutover.md` call (a) (VERIFIED 2026-11-09 as written there; the
  response field `result[0].account.id` is INFERRED from the Cloudflare API
  shape and is checked by the `account found` line).

## Phase 1: repository changes (Agent, nothing live changes)

Each item is a pull request with `CI green`, reviewed and merged by the owner.
Merge one at a time and re-check the others for conflicts after each merge.

### 1.1 Merge the SEO metadata pull request (320) (Agent PR, Owner merges)

Adds BreadcrumbList, `og:locale`, Twitter title and description, card alt text,
and distinct tag and category titles.

- **Verify:** after merge, `gh pr view 320 --repo ChiefGyk3D/no-php-no-cry --json state,mergedAt`
  shows `MERGED`.
- **Rollback:** `git revert` of the merge commit in a new pull request.
- Status: VERIFIED (2026-11-09) that PR 320 is open, not draft, and describes
  these changes. Its local Lighthouse claim (SEO and Best Practices 100) is the
  PR author's report, not re-run here (INFERRED until step 2.4).

### 1.2 Merge the launch check (321) (Agent PR, Owner merges)

Adds `scripts/check-launch-seo.py`, run by hand on a build made for the apex. It
fails on noindex pages, a disallow-all `robots.txt`, a missing `Sitemap:` line,
off-host sitemap or canonical URLs, missing or repeated titles and descriptions,
and a missing WordPress redirect map. Merge 320 first: the PR body says the
check reports one duplicate title on current main, which 320 fixes.

- **Verify:** `gh pr view 321 --repo ChiefGyk3D/no-php-no-cry --json state,mergedAt`
  shows `MERGED`, and `ls scripts/check-launch-seo.py` finds the file on main.
- **Rollback:** revert the merge commit.
- Status: VERIFIED (2026-11-09) from the PR body and the script header on the
  PR branch (usage: `python3 -I scripts/check-launch-seo.py <output-dir> <host>`).

### 1.3 Publish the six migrated drafts (issue 322) (Agent PR, Owner decides and merges)

Owner decision 2026-11-09 (issue 322): publish all six. Today these are still
`draft: true` on main, so their old addresses would 404 at cutover. The six
(VERIFIED 2026-11-09 by reading front matter on main):
best-headphone-microphone-combo, building-a-strong-online-community,
improving-indoor-air-quality, must-have-tools-for-3d-printing,
open-letter-to-president-biden, why-i-use-multiple-phones. All six already have
`syndicate: false`; keep it that way so nothing is re-posted.

Per issue 322 the pull request audits each post (personal data, links, images,
dates and slugs against the old URLs, alt text, wording), flips `draft` to
`false`, adds that post's rows from `docs/migration-uploads.md` to
`data/legacy_uploads.json` in the same pull request, and runs the full checks.
Twitch-and-Toot and Stream Daemon are already published on main (they have no
`draft` line); the "flip together" note in `docs/cutover.md` therefore no longer
applies and can be removed in this pull request (INFERRED: the converter note
was written when both were drafts).

- **Verify:** `grep -L '^draft: true' content/posts/*/index.md | wc -l` counts
  the published posts and `grep -l '^draft: true' content/posts/*/index.md`
  prints nothing for the six; `scripts/test-redirects.sh` passes; the redirect
  crosscheck in step 2.5 finds no 404.
- **Rollback:** revert the merge commit; the posts go back to drafts and the
  upload rows return to documentation only.
- Status: pull request not opened as of 2026-11-09 (VERIFIED: no PR 322 exists;
  `gh issue view 322` is an issue). Not part of this: the announcement post and
  the journal drafts wait for the owner's read-through.

### 1.4 Announcement post ready to flip (issue 235, pull request 314) (Agent PR, Owner flips)

The draft is `content/posts/new-site-no-php/index.md` with `draft: true` and
`syndicate: false` (VERIFIED 2026-11-09 from the PR body). Syndication stays off
for launch: the post publishes without announcing itself anywhere (see 4.9).
Open items before the owner flips it:

- **Hero image.** PR 314 changes one file only (`index.md`), so no headline image
  exists yet (VERIFIED 2026-11-09 from the PR file list). Issue 235 requires a
  headline image with alt text. Agent: add `featured.*` and the required
  `imageAlt` in a follow-up commit to PR 314. Owner: approve the image.
- **Publish date.** Set `date:` to the cutover day in the flip commit, not
  before, so it does not sort as a post from the staging period. Owner picks the
  date (D1).
- **Wording tied to the host.** The PR says the post names no test host and that
  it states "Cloudflare Web Analytics is enabled at the host"; that sentence must
  match the decision in 2.3.
- **Verify:** `scripts/author.py check` passes (named in the PR body; the exact
  invocation is in `docs/authoring-helper.md`), the post builds in the production
  build of step 2.1, and it appears in `/sitemap.xml`.
- **Rollback:** set `draft: true` again in a pull request; the page leaves the
  next build (it is not removed from caches until step 5.3 if one was made).

### 1.5 Cutover pull request, prepared and not merged (Agent PR, Owner merges at 4.3)

Per `docs/cutover.md` step 2: `baseURL` in `hugo.toml` to `https://chiefgyk3d.com/`
(canonical links, feed, sitemap, Open Graph and the `Sitemap:` line follow it);
in the deploy workflow's build job set `HUGO_PARAMS_ENVIRONMENT` and `EXPECT_ENV`
to `production`; update `scripts/test-head.sh` and any test that hardcodes the
staging host. Open it as a draft pull request and do not merge it until 4.3.

- **Verify (before merge):** the build in step 2.1 with the same changes passes
  `scripts/check-launch-seo.py`.
- **Rollback:** close the draft pull request. After merge, see 4.3.
- Status: `baseURL` is the staging host and `params.environment` is
  `production` on main (VERIFIED 2026-11-09, `hugo.toml` lines 1 and 60); the
  deploy workflow sets staging in its build job (VERIFIED, `docs/cutover.md`
  "Today"). The repository variable `SITE_URL` (smoke job) is set in step 4.2,
  not in the pull request (VERIFIED, `docs/deploy.md` variable table).

## Phase 2: staging checks (Agent runs read-only checks; Owner reads results)

### 2.1 Production-mode build and the launch check (Agent)

```sh
HUGO_PARAMS_ENVIRONMENT=production hugo --minify --gc --baseURL https://chiefgyk3d.com/ --destination out
python3 -I scripts/check-launch-seo.py out chiefgyk3d.com; echo "exit=$?"
EXPECT_ENV=production scripts/check-output.sh out; echo "exit=$?"
```

- **Verify:** both print `exit=0` (the launch check prints nothing else when it
  passes). Run it on the build that includes 1.1 to 1.4 and 1.5.
- **Rollback:** none needed; it only writes `out/`. Delete `out/` afterward.
- Status: usage VERIFIED from the script header (2026-11-09). The
  `check-output.sh` argument form is INFERRED from `docs/cutover.md`; use the
  form the script's own header gives if it differs.

### 2.2 Verify the staging host as it is today (Agent runs, read-only)

```sh
scripts/verify-live.sh test-blog.chiefgyk3d.com --env staging --resolve-ip "$(dig +short @1.1.1.1 test-blog.chiefgyk3d.com | head -1)"; echo "exit=$?"
```

- **Verify:** `exit=0`. The verifier is read-only (GET requests, 10 s connect and
  15 s total timeouts) per `docs/cutover.md`, read 2026-11-09.
- **Rollback:** none (read-only).
- Status: the 45-check pass on staging is the earlier observation recorded in
  `docs/cutover.md` (VERIFIED as recorded there, 2026-11-06); not re-run for this
  document.

### 2.3 Decide the Web Analytics beacon (Owner decision D4)

Two records disagree and the owner must pick one (VERIFIED 2026-11-09):

- Issue 241 (owner ruling 2026-11-08): turn off Cloudflare's automatic injection
  rather than loosen the CSP, because the injected script requests a versioned
  path that the CSP does not match, so the browser blocks it (staging Best
  Practices 92).
- Issue 300 and the analytics design (owner decisions confirmed 2026-11-09,
  Q3 B): keep Web Analytics on for the blog, with no new CSP entry, and close or
  relabel 241 as not applying.

With the current `static/_headers` (script source is the exact path
`https://static.cloudflareinsights.com/beacon.min.js`, `connect-src 'self'`) the
injected versioned URL is blocked on staging (observed 2026-11-08,
`docs/performance.md`), so "keep it on with no new CSP entry" yields a blocked
beacon: no data and a console error. Cloudflare's FAQ ("What do I need to add to
my Content Security Policy", last updated 2026-07-14, read 2026-11-09) names the
two entries now in `_headers` and does not mention the versioned path
(INFERRED: whether the versioned path matches on the apex is not shown by the
docs). Options:

| Option | Effect | Change |
|---|---|---|
| A. Keep on and fix the CSP | beacon works, data flows | Owner approves a wider script source (for example the beacon host) in `static/_headers` and `check-output.sh` together; an Agent PR |
| B. Turn injection off (issue 241) | no beacon, Best Practices 100, privacy text must say no Cloudflare beacon | Owner step below, then an Agent PR deleting the beacon URL from `script-src` (list in `docs/performance.md`, "CSP host allowlist") |
| C. Keep on, accept the blocked beacon | console error, Best Practices 92, no beacon data | Nothing; the privacy page must not claim the beacon runs |

Measure the current state before deciding (Owner or Agent, read-only):

```sh
curl -sS --max-time 15 https://test-blog.chiefgyk3d.com/ | grep -o 'static.cloudflareinsights.com[^" ]*' | sort -u
```

- **Verify:** option B: the command prints nothing after the toggle and the next
  deploy. Options A and C: it prints the beacon URL; then load the page in a
  browser with the console open and confirm no CSP error (A) or the known error
  (C).
- **How to turn injection off, if B:** Cloudflare dashboard, Web Analytics,
  Manage site, for the hostname, choose the disable option (the changelog entry
  dated 2025-02-25, read 2026-11-09, says to open Web Analytics, select Manage
  Site, and choose the enablement option; the exact label of the off choice was
  not read, so UNVERIFIED: read the screen). A zone Configuration Rule with
  `"disable_rum": true` also turns it off for matching requests (Cloudflare Rules
  docs, "Configuration Rules settings", last updated 2026-10-07, read 2026-11-09).
- **Rollback:** turn the setting back on; Pages adds the beacon again on the next
  deployment (per `docs/privacy-and-analytics.md`, citing the Pages Web Analytics
  how-to, 2026-04-21).
- Status: the privacy page, the CSP and the announcement post must all match the
  chosen option before cutover (the privacy test rejects claims that disagree).

### 2.4 Lighthouse on staging and on a local production build (Agent)

Record the scores in `docs/performance.md`. Expected on staging: SEO 69 because
staging is noindex by design (VERIFIED 2026-11-09, `docs/performance.md`).
Expected on a local production build: 100 SEO and Best Practices (PR 320 report).
A production-host re-measure happens in step 5.2.

- **Verify:** numbers in the document with the date.
- **Rollback:** none.

### 2.5 Redirect map crosscheck (Agent)

Run `scripts/test-redirects.sh` and `scripts/verify-live.sh` redirect checks
against staging (done in 2.2). Issue 202 asks for a read-only crosscheck of every
crawled WordPress URL against the expected map (`scripts/crosscheck-redirects.sh`);
that script does not exist on main (VERIFIED 2026-11-09, `ls scripts`). Agent PR
adds it, from the URL list of a read-only crawl of the old site's public pages
(GET only; no WordPress login).

- **Verify:** the crosscheck reports every old URL as 301 to a 200 page, or a
  documented decision (D6, D7).
- **Rollback:** none (read-only).
- Redirect facts (feed, category, date archives, `/page/N/`, uploads, limits of
  2,000 static and 100 dynamic rules in a `_redirects` file) are in
  `docs/cutover.md` "Feed and legacy URLs" (VERIFIED 2026-11-09, citing the
  Pages docs fetched 2026-11-06). The redirects page ("Redirects", last updated
  2026-08-25) and the Pages limits page (last updated 2026-09-05) were read again
  2026-11-09 and give the same limits.

### 2.6 Feed GUID and contact anchor checks (Agent; issues 211 and 212)

Compare the feed identifiers the old site publishes with the permalinks the new
feed uses for the migrated posts, and check that `/contact/` keeps its anchor.

- **Verify:** a written table in the pull request: same identifier or a
  documented difference; `curl -sI` of the old contact address shows the redirect
  and the anchor target exists on the new page.
- **Rollback:** none.
- Status: both issues open, no work product on main (VERIFIED 2026-11-09).

## Phase 3: safety net (Owner, read-only reads and prepared writes; nothing moves traffic)

### 3.1 Announce the window and freeze WordPress (Owner)

From T0 (D1) nothing is published or edited on WordPress (`docs/cutover.md`,
"WordPress freeze"). The owner does this inside WordPress; no agent logs in.
Take a final backup and record where it lives, offline (issue 209). Decide D8.

- **Verify:** the freeze notice is posted where followers see it, and the backup
  file exists (the owner records its size, not its path, in issue 209).
- **Rollback:** lift the freeze. Keep WordPress hosting running for at least 30
  days after cutover (VERIFIED, `docs/cutover.md`).

### 3.2 Snapshot DNS and the redirect rules, and read `www` (Owner, reads only)

Run in the terminal from step 0.2:

```sh
CF "$API/zones/$ZONE/dns_records?per_page=500" > ~/golive-private/dns-before.json
CF "$API/zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint" > ~/golive-private/redirects-before.json
CF "$API/accounts/$ACCT/pages/projects/$PROJ/domains" > ~/golive-private/pages-domains-before.json
jq -r '.result[] | select(.name=="chiefgyk3d.com" or .name=="www.chiefgyk3d.com") | [.type,.name,.content,.proxied] | @tsv' ~/golive-private/dns-before.json
```

- **Verify:** the last command lists the current apex (and `www`) records; keep the
  three files. They are the rollback record and stay out of the repository.
- **Rollback:** none (reads).
- Status: calls (a), (b), (c), (h) from `docs/cutover.md` (VERIFIED as listed
  there, 2026-11-09). What the apex record is today (A, AAAA or CNAME, proxied or
  not) and whether the redirect entrypoint is empty are UNKNOWN until this runs.

### 3.3 Policy items from the threat model (Owner decisions and reads)

From `docs/threat-model/RISKS.md` (read 2026-11-09): the open High items are
owner and provider settings the repository cannot show. Do these before cutover
and record the date in `RISKS.md` (an Agent PR moves the threats to Mitigated).

1. **Branch protection and approvals.** Read today:

   ```sh
   gh api repos/ChiefGyk3D/no-php-no-cry/branches/main/protection --jq '{checks:.required_status_checks.contexts, approvals:.required_pull_request_reviews.required_approving_review_count, admins_enforced:.enforce_admins.enabled, signed:.required_signatures.enabled, force_push:.allow_force_pushes.enabled}'
   ```

   Result VERIFIED 2026-11-09: required check `CI green`, zero required approvals,
   administrators not enforced, signatures not required (force-push value not in
   that read; `RISKS.md` says force pushes are blocked). Zero approvals is normal
   for a one-person project; keep or change is the owner's decision. Raising to one
   approval blocks the owner's own merges unless administrators bypass (INFERRED
   from how GitHub applies the rule).
2. **Commit signing.** Not required today (VERIFIED above). To require it:

   ```sh
   gh api -X POST repos/ChiefGyk3D/no-php-no-cry/branches/main/protection/required_signatures --jq .enabled
   ```

   The endpoint is INFERRED from the GitHub REST API (not read for this
   document); read the GitHub docs page first. Every commit that lands on main
   must then be signed, which includes commits made by agents with plain `git`
   (unsigned). Decide that tradeoff before enabling. Rollback:
   `gh api -X DELETE repos/ChiefGyk3D/no-php-no-cry/branches/main/protection/required_signatures`.
3. **Cloudflare token scope.** The documented deploy token is one permission,
   Pages: Edit, account-wide (`docs/deploy.md`, VERIFIED 2026-11-09). The live
   permissions have not been read (`RISKS.md`). Read them with the deploy
   token in the dashboard (My Profile, API Tokens), and confirm no
   Zone, DNS or other permission is on it. The cutover token from step 0.2 is
   separate, short-lived and deleted in 5.6. Record the read date.
4. **DNS and registrar protection.** Check, read-only:

   ```sh
   dig +short DS chiefgyk3d.com @1.1.1.1; whois chiefgyk3d.com | grep -i 'status'
   ```

   A DS record means DNSSEC is signed at the registry; a `clientTransferProhibited`
   status means the registrar transfer lock is on (INFERRED meaning of those
   standard outputs; the whois field format varies by registry). Cloudflare's
   DNSSEC page ("DNSSEC", linked from the DNS docs home, last updated 2026-08-14)
   was found but its setup steps were not read: read them before enabling.
5. **Sign-in strength.** The owner confirms hardware-key or passkey sign-in on the
   GitHub, Cloudflare, Doppler and registrar accounts, and recovery codes stored
   offline. Provider screens vary: UNVERIFIED, read each provider's current docs
   page when you do it.

- **Verify:** each item gets a dated line in `RISKS.md` (Agent PR from the
  owner's words) and `scripts/check-threat-model.py` passes.
- **Rollback:** revert any setting changed in items 1 and 2 with the commands
  shown.

### 3.4 Redirect decisions applied to the map (Agent PR)

Apply D6 (shortlinks) and D7 (hidden-draft permalinks): the `/?p=ID` form needs
a query match, which `_redirects` cannot express (it matches paths only,
VERIFIED in `docs/cutover.md`), so it would be a Single Redirect rule in 4.6 or
accepted as lost.

- **Verify:** the crosscheck of step 2.5 reports no unexplained 404.
- **Rollback:** revert the pull request.

### 3.5 Links hand-off list and `support.` page ready (Agent PR, Owner)

Issue 205: prepare the list of places that link to the old site or the staging
host (profile bios in `data/socials.yaml`, GitHub profile README and repository
READMEs, `rel="me"` on Mastodon, the `links.` and `social.` subdomain pages,
Reach Around's link). The list is made now; the changes are made in 5.5. The
`/support/` page must match the `support-me` repository before cutover
(`docs/cutover.md`, VERIFIED 2026-11-09).

- **Verify:** the list is in issue 205 with one checkbox per place.
- **Rollback:** none.

### 3.6 Inventory the old host (Owner; issue 204)

List what else runs on the old WordPress host (other sites, mail, cron, files)
before it is ever cancelled. Cancellation is after the 30-day freeze, not part
of this launch.

## Phase 4: the cutover (Owner, in this order; Agent verifies)

Start only when phases 1 to 3 are done, the window (D1) is open and the owner
says go in the issue. Steps 4.2 and 4.3 can run before the window; 4.4 is the
moment traffic moves.

### 4.1 Pre-flight (Agent)

Run 2.1 once more on main (with 1.1 to 1.5 merged except the cutover pull
request) and confirm `CI green` on the head commit.

- **Verify:** `exit=0` for each command in 2.1.
- **Rollback:** none.

### 4.2 Point the smoke job at the apex (Owner)

```sh
gh variable set SITE_URL --repo ChiefGyk3D/no-php-no-cry --body https://chiefgyk3d.com && gh variable list --repo ChiefGyk3D/no-php-no-cry | grep SITE_URL
```

- **Verify:** the second command prints `SITE_URL` with the apex.
- **Rollback:** `gh variable set SITE_URL --repo ChiefGyk3D/no-php-no-cry --body https://test-blog.chiefgyk3d.com`.
- Status: variable and default VERIFIED (`docs/deploy.md` table, 2026-11-09). If
  the build also needs `SITE_HOST` for `scripts/check-output.sh`, the cutover
  pull request sets it (`docs/cutover.md` step 2; INFERRED need).

### 4.3 Merge the cutover pull request, deploy the production build (Owner merges)

The deploy workflow runs after `CI green` on main and publishes the build
(VERIFIED, `docs/deploy.md`). Until DNS moves in 4.4 the apex still serves
WordPress, so nothing breaks. A Pages project serves every custom domain
attached to it from one deployment (INFERRED), so from this deploy the staging
host serves the production build, which is indexable: do 4.5 immediately after
4.4, or accept D3's second option (own project) to avoid this window.

- **Verify:** the deploy run is green (`gh run list --repo ChiefGyk3D/no-php-no-cry --workflow deploy.yml --limit 1`),
  and on the project's own address (not the apex yet):

  ```sh
  curl -sS --max-time 15 https://no-php-no-cry.pages.dev/robots.txt
  ```

  prints `Allow: /` and a `Sitemap:` line naming the apex. (INFERRED: the
  default project address is `<project>.pages.dev`, as `docs/deploy.md` says for
  the CNAME target.)
- **Rollback:** revert the merge commit in a new pull request; the next deploy
  restores the staging build. No DNS has moved, so no visitor was affected.

### 4.4 Attach the apex to the Pages project and move DNS (Owner; this moves traffic)

Attach the domain, wait for `active`:

```sh
CF -X POST "$API/accounts/$ACCT/pages/projects/$PROJ/domains" --data '{"name":"chiefgyk3d.com"}' | jq '{success,errors,status:.result.status}'
for i in $(seq 1 30); do s=$(CF "$API/accounts/$ACCT/pages/projects/$PROJ/domains/chiefgyk3d.com" | jq -r '.result.status'); echo "status=$s"; test "$s" = active && break; sleep 20; done
```

An API-attached domain gets no DNS record on its own and stays `pending` until
one exists (VERIFIED, `docs/deploy.md`, measured earlier on the staging host), so
the status loop above can stay `pending` until the next command. Point the apex
at Pages by changing the single existing apex record (stops if there is not
exactly one, in which case do not continue; read `dns-before.json` and decide):

```sh
ID=$(jq -r '[.result[]|select(.name=="chiefgyk3d.com" and (.type=="A" or .type=="AAAA" or .type=="CNAME"))]|if length==1 then .[0].id else empty end' ~/golive-private/dns-before.json); test -n "$ID" && echo "$ID" > ~/golive-private/apex-id.txt && jq -c --arg id "$ID" '.result[]|select(.id==$id)|{type,name,content,proxied,ttl}' ~/golive-private/dns-before.json > ~/golive-private/apex-original.json && CF -X PUT "$API/zones/$ZONE/dns_records/$ID" --data '{"type":"CNAME","name":"chiefgyk3d.com","content":"no-php-no-cry.pages.dev","proxied":true,"ttl":1}' | jq '{success,errors}'
```

Then, if D2 says `www` exists and redirects, handle it in 4.6 with a rule; a
`www` record is only needed if one does not exist (a proxied record is required
for a zone rule to fire, Cloudflare Workers custom domains docs, read
2026-11-09).

- **Verify:** the status loop prints `status=active`; then
  `curl -sSI --max-time 15 https://chiefgyk3d.com/ | sed -n '1p;/^[Ll]ocation/p;/^[Ss]erver/p'`
  shows `200` and a Cloudflare server header, and
  `curl -sS --max-time 15 https://chiefgyk3d.com/robots.txt` shows `Allow: /`.
  Done means `active` and the public URL serving the new site, not the success
  flag of an API call.
- **Rollback (do this at once if verification fails and cannot be fixed in
  minutes):**

  ```sh
  CF -X PUT "$API/zones/$ZONE/dns_records/$(cat ~/golive-private/apex-id.txt)" --data @$HOME/golive-private/apex-original.json | jq '{success,errors}'
  ```

  This restores the apex record to what it was before; WordPress is still
  running because of the freeze. Visitors who already received the new records
  may take up to the record's old TTL to switch back (INFERRED).
- Status: calls (d), (e), (f) are in the `docs/cutover.md` table (VERIFIED
  2026-11-09). That a PUT may change a record's type and that CNAME flattening is
  applied at the apex: flattening is VERIFIED (Cloudflare DNS docs, "CNAME
  flattening", last updated 2026-06-24, read 2026-11-09: it is what lets a root
  custom domain work with Pages); the PUT type change is INFERRED, so read the
  record back with `CF "$API/zones/$ZONE/dns_records/$(cat ~/golive-private/apex-id.txt)" | jq '.result|{type,content,proxied}'`.

### 4.5 Staging host redirect (Owner, immediately after 4.4)

Skip if D3 chose a separate Pages project (issue 201). Otherwise add the
redirect from step 4.6 (the staging rule is in that command).

### 4.6 Redirect rules: staging host, support host, www (Owner)

One command writes the existing rules plus these rules; a PUT replaces the whole
list, so the first line reads what is there. Run only the rules you decided on:
the `www` rule belongs only if D2 says so.

```sh
CF "$API/zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint" > ~/golive-private/redirects-now.json
NEW=$(jq -n '[
 {"description":"support host to /support/","expression":"(http.host eq \"support.chiefgyk3d.com\")","action":"redirect","action_parameters":{"from_value":{"status_code":301,"target_url":{"value":"https://chiefgyk3d.com/support/"},"preserve_query_string":false}}},
 {"description":"staging host to apex","expression":"(http.host eq \"test-blog.chiefgyk3d.com\")","action":"redirect","action_parameters":{"from_value":{"status_code":301,"target_url":{"expression":"concat(\"https://chiefgyk3d.com\", http.request.uri.path)"},"preserve_query_string":true}}}
]')
BODY=$(jq -n --argjson old "$(jq -c '(.result.rules // []) | map(del(.id,.version,.last_updated,.ref))' ~/golive-private/redirects-now.json)" --argjson new "$NEW" '{rules: ($old + $new)}')
CF -X PUT "$API/zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint" --data "$BODY" | jq '{success,errors,rules:(.result.rules|length)}'
```

- **Verify:**
  `curl -sSI --max-time 15 https://support.chiefgyk3d.com/ | sed -n '1p;/^[Ll]ocation/p'` shows `301` and
  `location: https://chiefgyk3d.com/support/`; and
  `curl -sSI --max-time 15 https://test-blog.chiefgyk3d.com/posts/ | sed -n '1p;/^[Ll]ocation/p'` shows `301`
  and `location: https://chiefgyk3d.com/posts/`.
- **Rollback:** restore the saved list:
  `jq -c '{rules: ((.result.rules // []) | map(del(.id,.version,.last_updated,.ref)))}' ~/golive-private/redirects-before.json > ~/golive-private/redirects-restore.json && CF -X PUT "$API/zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint" --data @$HOME/golive-private/redirects-restore.json | jq '{success,errors}'`.
- Status: the rule shape (`from_value`, `status_code`, `target_url.value` or
  `.expression`, `preserve_query_string`) is INFERRED from the Rulesets API
  structure; the Cloudflare page "Create a redirect rule via API" (last updated
  2026-08-25) was found, and its body was not read for this document. Read it
  before running; the `success` flag and the two `curl` checks are the proof.
  The permission needed is Single Redirect Edit (VERIFIED, `docs/cutover.md`).
  The `support` and `test-blog` records must be proxied for a zone rule to see
  the traffic (VERIFIED requirement, Cloudflare redirects docs, "Single Redirects
  and Bulk Redirects require that you proxy the DNS records", read 2026-11-09;
  that they are proxied today is INFERRED, read in 3.2).

### 4.7 Verify the apex end to end (Agent runs, Owner reads)

```sh
scripts/verify-live.sh chiefgyk3d.com --env production; echo "exit=$?"
```

Run it again about five minutes later (edge caches, `docs/cutover.md`). Run the
launch check against the live site's own pages by building the cutover commit
(2.1). Then by hand: open the home page and one post in a browser, check the
favicon, `/support/`, `/feed/index.xml`, and the old feed address
`curl -sSI https://chiefgyk3d.com/feed/` (301 to `/feed/index.xml`).

- **Verify:** `exit=0` twice, quote the output in issue 200.
- **Rollback:** 4.4 rollback, then 4.6 rollback.
- Status: the verifier's checks are listed in `docs/cutover.md` (VERIFIED
  2026-11-09). Whether Cloudflare adds a second `Strict-Transport-Security`
  header on the apex is INFERRED-unknown; the verifier reports it if so.

### 4.8 HSTS decision (D5)

The header is already served: `Strict-Transport-Security: max-age=31536000;
includeSubDomains` (VERIFIED 2026-11-09, `static/_headers`), without `preload`.
`includeSubDomains` on the apex makes browsers refuse plain HTTP for every
subdomain (`links.`, `social.`, `support.`, any other). Confirm each answers over
HTTPS before launch:

```sh
for h in links social support www; do printf '%s: ' "$h"; curl -sSI --max-time 15 -o /dev/null -w '%{http_code}\n' "https://$h.chiefgyk3d.com/" || echo unreachable; done
```

- **Verify:** every subdomain that exists prints a status code (a missing `www`
  prints `unreachable`, which is acceptable if D2 says no `www`).
- **Rollback:** the header comes from the repository; a pull request lowering
  `max-age` helps only for browsers that have not yet cached the old value. Do
  not add `preload` at launch (hstspreload.org removal can take months,
  `docs/performance.md`, read 2026-11-09).

### 4.9 Publish the announcement post (Owner flips, after 4.7 passes)

Merge the one-line pull request that sets `draft: false` and the publish date on
`content/posts/new-site-no-php/index.md` (1.4). `syndicate` stays `false`.

- **Verify:** after the deploy,
  `curl -sS --max-time 15 https://chiefgyk3d.com/sitemap.xml | grep -c new-site-no-php` prints `1`, and
  `curl -sS --max-time 15 https://chiefgyk3d.com/feed/index.xml | grep -c new-site-no-php` prints at least `1`.
- **Rollback:** set `draft: true` again in a pull request.
- Status: syndication is not deployed (`docs/cutover.md` N4 and N5; issue 208
  says the first post after cutover is the live test for syndication). Because
  syndication is off for this launch, announce the post by hand if wanted. Turn
  syndication on later as its own change, using the next post as the test.

## Phase 5: verify, hand off, first-day monitoring

### 5.1 Search engines (Owner)

Add the apex property in each search console and submit `https://chiefgyk3d.com/sitemap.xml`
(`docs/cutover.md`, "Links hand-off"). Provider screens vary: UNVERIFIED, read
each console's current docs page first.

- **Verify:** each console reports the sitemap as read.
- **Rollback:** remove the sitemap submission.

### 5.2 Production-host Lighthouse (Agent)

Re-measure the home page and one post against the apex (mobile and desktop) and
record the numbers and date in `docs/performance.md`, replacing the staging
caveats (VERIFIED 2026-11-09 that the document holds staging figures only).

- **Verify:** SEO 100 on indexable pages; Best Practices per D4.
- **Rollback:** none.

### 5.3 Cache purge, only if old pages appear (Owner)

If the verifier or a browser shows old WordPress pages on the apex (INFERRED
risk, `docs/cutover.md` call j):

```sh
CF -X POST "$API/zones/$ZONE/purge_cache" --data '{"hosts":["chiefgyk3d.com"]}' | jq '{success,errors}'
```

- **Verify:** rerun 4.7.
- **Rollback:** none needed; a purge only forces a refetch.
- Status: needs the Cache Purge permission from 0.2. The `hosts` form of the
  body is INFERRED; read the Cloudflare purge docs if the call is rejected.

### 5.4 First-day monitoring (Owner, with Agent checks)

Run at +15 minutes, +1 hour, +4 hours and +24 hours after DNS moved:

1. `scripts/verify-live.sh chiefgyk3d.com --env production; echo "exit=$?"` (Agent).
2. Feed readers still resolve: `curl -sSI https://chiefgyk3d.com/feed/` and
   `curl -sSI https://chiefgyk3d.com/feed/atom/` both 301 to `/feed/index.xml`.
3. A sample of old URLs from the crosscheck (2.5) all land on a 200.
4. Not-found rate: in the Cloudflare dashboard, Analytics, the 404 count on the
   apex (UNVERIFIED path: read the screen); investigate any old WordPress address
   that is 404.
5. Web Analytics (option A or C of D4): confirm page views arrive in the
   dashboard the next day. If B, confirm there is no beacon request.
6. Search consoles: coverage and sitemap errors at +24 hours.
7. Certificate: `curl -sSI https://chiefgyk3d.com/` succeeds without `-k`.
8. The deploy history: `gh run list --repo ChiefGyk3D/no-php-no-cry --workflow deploy.yml --limit 3` is green.

- **Verify:** quote each result in issue 200 with the time (Eastern).
- **Rollback:** if a failure cannot be fixed in minutes, run the rollback of 4.4
  and 4.6, then investigate with WordPress serving.

### 5.5 Links hand-off (Owner)

Work through the list from 3.5 (issue 205): social bios, the GitHub profile and
repository READMEs, the `support-me` signature block, `rel="me"` on Mastodon,
Reach Around's link, the `links.` and `social.` pages.

- **Verify:** each link opens the apex; Mastodon shows the `rel="me"` link as
  verified.
- **Rollback:** edit the link back.

### 5.6 Close out (Owner and Agent)

- Delete the cutover API token in the Cloudflare dashboard; run `unset CF_TOKEN ZONE ACCT` in the terminal.
- Move the private files in `~/golive-private/` to the owner's offline store
  (they hold DNS contents) or delete them after 30 days.
- Agent PRs: update `docs/cutover.md` (the status and ruling sections, N3 waiver
  per issue 207, the staging examples), record the production Lighthouse numbers,
  record the dates in `docs/threat-model/RISKS.md`.
- Keep WordPress hosting untouched for 30 days (to 2026-12-09 if cutover is
  2026-11-09; move the date with D1), then decide retention (issue 209) and the
  old-host inventory (3.6).
- **Rollback:** not applicable after the 30 days.

## Steps that need the owner

0.1, 0.2, 2.3 (decision and the toggle if B), 3.1, 3.2, 3.3 (all five), 3.5
(hand-off list changes later), 3.6, 4.2, 4.3 (merge), 4.4, 4.5, 4.6, 4.8, 4.9,
5.1, 5.3 (if needed), 5.5, 5.6. Everything else is a repository change or a
read-only check an agent runs.

## Sources read for this document (2026-11-09)

Repository: `docs/cutover.md`, `docs/deploy.md`, `docs/performance.md`,
`docs/privacy-and-analytics.md`, `docs/analytics-deploy.md`,
`docs/migration-uploads.md`, `docs/threat-model/RISKS.md`, `static/_headers`,
`hugo.toml`, front matter of the ten migrated posts, issues 199 to 212, 235, 241,
300, 318, 322, 323, and pull requests 314, 320 and 321. Cloudflare docs (search
tool): Web Analytics FAQ (CSP entries, last updated 2026-07-14), Configuration
Rules settings (last updated 2026-10-07), Pages redirects (2026-08-25), Pages
limits (2026-09-05), CNAME flattening (2026-06-24), Redirects overview (2026-08-14),
Workers custom domains (www and root redirects). GitHub: branch protection read
with the GitHub API on 2026-11-09.
