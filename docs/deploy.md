# Deploying to Cloudflare Pages

`.github/workflows/deploy.yml` publishes the site to Cloudflare Pages. It runs
on a push to `main` and on a manual run, never on a pull request. It is not a
required check: `CI green` stays the only gate, and a pull request never needs
a secret.

## How a deploy works

1. `build` installs the pinned Hugo (sha256 verified), builds, runs
   `scripts/check-output.sh`, and uploads `public/` as the `site` artifact.
2. `gate` (default branch, deploy enabled) polls the GitHub check-runs API for
   the check run named `CI green` on this commit (`scripts/wait-for-ci-green.sh`).
   Success lets the deploy continue; any other conclusion fails at once; no
   result within 25 minutes fails. Override with `WAIT_TIMEOUT_SECONDS` and
   `POLL_INTERVAL_SECONDS` (defaults 1500 and 20). It needs only
   `checks: read`.
3. `deploy` needs `build` and `gate`, and runs on the default branch only. It downloads the artifact, installs
   Wrangler from the lockfile in `deploy/` (`npm ci --ignore-scripts`, on Node
   22, which Wrangler requires) before any secret exists, fetches the
   credentials, and runs `wrangler pages deploy`. Only `deploy/` is checked out
   and no repository script runs. Dependabot bumps the lockfile weekly. It is the only job with `id-token: write`.
4. `smoke` runs `scripts/smoke-site.sh` against `SITE_URL`: HTTP 200, the
   Content-Security-Policy from `static/_headers`, and one 301 from the built
   `_redirects`.

Repository variables (Settings, Secrets and variables, Actions, Variables):

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLOUDFLARE_PAGES_PROJECT` | `no-php-no-cry` | Pages project name |
| `DEPLOY_ENABLED` | unset (deploy skipped) | Set to `true` once credentials and the Pages project exist; until then pushes build but do not deploy |
| `SITE_URL` | `https://test-blog.chiefgyk3d.com` | URL the smoke test checks |
| `DOPPLER_CLOUDFLARE_IDENTITY_ID` | none | Doppler OIDC identity UUID for the Cloudflare project (Doppler path only). Separate from `DOPPLER_IDENTITY_ID`, which the CI callers use |

The deploy job needs two values: `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID`. It takes them from Doppler when that is configured,
otherwise from GitHub Actions secrets of the same names. If neither supplies
both, the job fails with a message naming what is missing. Once
`DEPLOY_ENABLED` is `true` it never skips silently.

## Cloudflare setup (both paths)

Create the Pages project once, as a Direct Upload project (no Git connection):

1. Cloudflare dashboard, Workers & Pages, Create, Pages, Upload assets.
2. Name it `no-php-no-cry` (or set `CLOUDFLARE_PAGES_PROJECT` to your name).
3. Set the production branch to `main`. Upload anything to finish creation;
   the first workflow run replaces it.
4. Custom domain (once, by the owner): in the project, Custom domains, Set up
   a domain, enter `test-blog.chiefgyk3d.com`. If the zone is on Cloudflare
   the CNAME is created for you.

Account id: dashboard, Workers & Pages overview, right-hand column, Account ID.
It is not a secret by itself, but the workflow reads it as a credential value
so it stays out of the repository.

DNS and the custom domain are set up once by the owner in the Cloudflare
dashboard (the Pages project, Custom domains), outside CI. When the zone is on
Cloudflare, Cloudflare adds the CNAME itself. CI never touches DNS.

API token (Manage account, Account API tokens, Create token, Custom token).
Exactly one permission, limited to the one account:

- Account, Cloudflare Pages: Edit (resource: the one account).

Nothing else: no Zone permission of any kind, no DNS, no other account
resource. Set a short expiry and rotate it.

## Path A: Doppler (preferred)

Doppler holds the Cloudflare values; the workflow reads them over OIDC, so no
long-lived Doppler credential sits in GitHub.

The owner, not an agent, does all of the following. An agent never creates the
Doppler service account, the identity, or any token.

1. The Cloudflare values live in their own Doppler project, `cloudflare`,
   config `prd`, apart from the `ci` project, so repositories and jobs that do
   not deploy never hold a Cloudflare credential. Set the two secrets from a
   checkout of ChiefGyk3D/git-your-ship-together, one at a time:
   `DOPPLER_CI_CONFIG=prd scripts/doppler-ci-set.sh CLOUDFLARE_API_TOKEN cloudflare`
   and the same with `CLOUDFLARE_ACCOUNT_ID`. The config must hold only these
   two; every value in it is exported to the job.
2. Create one Doppler service account, `gha-cloudflare-pages`, with the Viewer
   role on project `cloudflare`, config `prd` only.
3. On that service account add one OIDC identity (Service Account Identities):
   issuer `https://token.actions.githubusercontent.com`, audience as Doppler
   shows it. For each deploying repository list both subject forms (plain and
   immutable), limited to `refs/heads/main`; GitHub sends one of the two, and a
   repository created after mid-2026 sends the second (Doppler accepts several
   subjects per identity). Doppler has no identity update call, so adding a
   repository means creating a new identity with the full subject list and
   repointing the variable in each repository:
   - `repo:<owner>/<repo>:ref:refs/heads/main`
   - `repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:refs/heads/main`

   Find which form yours sends with
   `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`
   (`use_immutable_subject`), and the ids with `gh api repos/<owner>/<repo>
   --jq .id` and `gh api users/<owner> --jq .id`. A mismatch fails every fetch
   with `claim "sub" does not match identity auth config`. No wildcard subject,
   and never one that matches `:pull_request`.
4. Copy the identity UUID (not a secret) into the repository variable
   `DOPPLER_CLOUDFLARE_IDENTITY_ID`.
5. Leave the `DOPPLER_CLOUDFLARE_TOKEN` secret unset, or set a read-only service
   token for `cloudflare/prd` there if you prefer the token path over OIDC. The OIDC identity wins
   when both exist.
6. Run the workflow by hand from `main` (Actions, Deploy, Run workflow).

The Doppler action fetches only on the default branch, a tag, or a schedule.

## Path B: GitHub Actions secrets (no Doppler)

For a fork or anyone without Doppler:

1. Leave `DOPPLER_CLOUDFLARE_IDENTITY_ID` unset.
2. Settings, Secrets and variables, Actions, Secrets: add `CLOUDFLARE_API_TOKEN`
   and `CLOUDFLARE_ACCOUNT_ID` with the values from the Cloudflare setup above.
3. Run the workflow by hand from the default branch.

If you fork under another name, change the OIDC subject and `SITE_URL` to match.

## Checking and rolling back

- The smoke test is the post-deploy check. To run it by hand against a build:
  `scripts/smoke-site.sh https://test-blog.chiefgyk3d.com public`.
- Roll back in the Cloudflare dashboard (project, Deployments, a previous
  deployment, Rollback to this deployment), or revert on `main` and let the
  workflow redeploy.
- Egress hardening: the `deploy` job, the only one with credentials, runs
  harden-runner in `block` mode with an explicit allow-list in
  `.github/workflows/deploy.yml` (`allowed-endpoints`). The list is unmeasured:
  it is what the steps are known to reach. If the first run fails with a
  blocked connection, nothing was sent; the harden-runner log (and the job's
  Insights tab) names the host. To add one: put `host:443` in
  `allowed-endpoints` (space-separated, no wildcards, a newline-separated list
  matches nothing), commit, and re-run. The other jobs stay in audit because
  the artifact storage host varies per run. Tracked in issue #10.
