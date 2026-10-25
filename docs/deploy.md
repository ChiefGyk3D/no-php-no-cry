# Deploying to Cloudflare Pages

`.github/workflows/deploy.yml` publishes the site to Cloudflare Pages. It runs
on a push to `main` and on a manual run, never on a pull request. It is not a
required check: `CI green` stays the only gate, and a pull request never needs
a secret.

## How a deploy works

1. `build` installs the pinned Hugo (sha256 verified), builds, runs
   `scripts/check-output.sh` and `scripts/check-site-artifact.sh`, and uploads
   `public/` as the `site` artifact. The artifact check fails on anything
   Cloudflare Pages treats as code or routing (`_worker.js`, `_routes.json`, a
   root `functions/` directory, any name beginning `_worker`), on a `_headers`
   that differs byte for byte from `static/_headers`, and on a `_redirects`
   line that is not an internal `/from /to 301|302` rule (or more than 2000
   lines). CI runs it too.
2. `gate` (default branch, deploy enabled) polls the GitHub check-runs API for
   the check run named `CI green` on this commit (`scripts/wait-for-ci-green.sh`).
   Only check runs of the GitHub Actions app count, and the newest one (by
   start time, then id) decides: success lets the deploy continue, any other
   conclusion fails at once, a newest run still queued or running keeps
   waiting, and an older success never outweighs a newer failure. Once the newest run is
   complete, its check suite must be the default branch's own (branch name,
   no pull request, same commit); otherwise the gate fails without falling
   back to an older run. No result
   within 25 minutes fails. Override with `WAIT_TIMEOUT_SECONDS` and
   `POLL_INTERVAL_SECONDS` (defaults 1500 and 20). It needs only
   `checks: read`.
3. `deploy` needs `build` and `gate`, and runs on the default branch only. It
   downloads the artifact, installs Wrangler from the lockfile in `deploy/`
   (`npm ci --ignore-scripts`, on Node 22, which Wrangler requires) and runs
   `scripts/check-site-artifact.sh` on the download, all before any secret
   exists. Then it fetches the credentials and runs `wrangler pages deploy`.
   Checked out: `deploy/`, `static/_headers` and two scripts. Repository code
   before the credentials load: `check-site-artifact.sh`. Repository code after:
   `scripts/ensure-pages-project.sh` only (two curl calls, the token and other
   inputs validated first, no package loaded). Dependabot bumps the lockfile
   weekly. It is the only job with `id-token: write`.
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

The Pages project is created by CI, not by hand. The deploy job runs
`scripts/ensure-pages-project.sh` before publishing: it looks the project up by
name and creates it (a Direct Upload project, production branch `main`) when it
is missing, and does nothing when it exists. No dashboard step creates it. The
token below carries the permission for this (Pages: Edit). To use another name,
set `CLOUDFLARE_PAGES_PROJECT`. The script refuses a token that is not 20 to 300
characters of letters, digits, `_`, `.` and `-`, and sends it as an
Authorization header from stdin, never as curl configuration.

Custom domain (once, by the owner): on the Pages project, Workers & Pages, the
project, Custom domains, Set up a domain, and add `test-blog.chiefgyk3d.com`
(per Cloudflare's Pages documentation; the dashboard layout changes, so follow
what you see). A domain attached through the API does NOT create the DNS record.
Whichever way it is attached, make sure the zone has a proxied CNAME from the
hostname to `<project>.pages.dev`; without it Cloudflare shows error 1016.

Account id: dashboard, Workers & Pages overview, right-hand column, Account ID.
It is not a secret by itself, but the workflow reads it as a credential value
so it stays out of the repository. Docs and tests use placeholders for ids.

CI never touches DNS or custom domains.

### API token

Create a USER API token at My Profile, API Tokens, Create Token (Custom token).
Do not use an account-owned token for the Doppler rotation: Doppler's rotation
uses two user tokens. Exactly one permission, limited to the one account:

- Account, Cloudflare Pages: Edit (resource: the one account).

Nothing else: no Zone permission of any kind, no DNS, no other account
resource. Set a short expiry and rotate it.

What that permission means, plainly:

- Pages: Edit is account-wide. It covers every Pages project in the account,
  not just this site, and cannot be narrowed to one project.
- Rotation keeps two such tokens valid at once (that is how it avoids a gap),
  so a leak of either is a live credential.
- On suspected compromise, revoke BOTH tokens immediately, then rotate.
- The real isolation is a dedicated Cloudflare account for this site, so the
  token can reach nothing else. That is an owner decision; until then, treat
  the token as account-wide.

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
   two. The Doppler action exports the whole config, so every secret in it is
   visible to every later step in the job and to post-run hooks. Until the
   scoped mode lands (tracking:
   ChiefGyk3D/git-your-ship-together#207) keep exactly these two values in it.
2. Create one Doppler service account, `gha-cloudflare-pages`, with the Viewer
   role on project `cloudflare`, config `prd` only.
3. On that service account add one OIDC identity (Service Account Identities):
   issuer `https://token.actions.githubusercontent.com`, audience as Doppler
   shows it. GitHub emits only the one subject form that the repository's OIDC
   customization selects. Check which with
   `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`
   (`use_immutable_subject`) and register only that form, limited to
   `refs/heads/main`, not both. This repository uses the immutable form
   (`use_immutable_subject` is true):
   - immutable: `repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:refs/heads/main`
   - plain, only for a repository that selects it:
     `repo:<owner>/<repo>:ref:refs/heads/main`

   Find the ids with `gh api repos/<owner>/<repo> --jq .id` and
   `gh api users/<owner> --jq .id`. Doppler has no identity update call, so
   adding a repository means creating a new identity with the full subject list
   and repointing the variable in each repository. A mismatch fails every fetch
   with `claim "sub" does not match identity auth config`. No wildcard subject,
   and never one that matches `:pull_request`.
4. Copy the identity UUID (not a secret) into the repository variable
   `DOPPLER_CLOUDFLARE_IDENTITY_ID`.
5. Leave the `DOPPLER_CLOUDFLARE_TOKEN` secret unset. A read-only Doppler
   service token for `cloudflare/prd` is an EMERGENCY-ONLY fallback, for when
   OIDC is broken: give it a short expiry (hours, not days), set it only for the
   incident, and revoke it and remove the secret the moment OIDC works again.
   It is a long-lived bearer credential sitting in GitHub while it exists. The
   OIDC identity wins when both exist.
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
