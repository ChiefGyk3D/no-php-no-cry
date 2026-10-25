# Deploying to Cloudflare Pages

`.github/workflows/deploy.yml` publishes the site to Cloudflare Pages. It runs
on a push to `main` and on a manual run, never on a pull request. It is not a
required check: `CI green` stays the only gate, and a pull request never needs
a secret.

## How a deploy works

1. `build` installs the pinned Hugo (sha256 verified), builds, runs
   `scripts/check-output.sh`, and uploads `public/` as the `site` artifact.
2. `deploy` runs on the default branch only. It downloads the artifact, installs
   Wrangler from the lockfile in `deploy/` (`npm ci --ignore-scripts`, on Node
   22, which Wrangler requires) before any secret exists, fetches the
   credentials, and runs `wrangler pages deploy`. Only `deploy/` is checked out
   and no repository script runs. Dependabot bumps the lockfile weekly. It is the only job with `id-token: write`.
3. `smoke` runs `scripts/smoke-site.sh` against `SITE_URL`: HTTP 200, the
   Content-Security-Policy from `static/_headers`, and one 301 from the built
   `_redirects`.

Repository variables (Settings, Secrets and variables, Actions, Variables):

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLOUDFLARE_PAGES_PROJECT` | `no-php-no-cry` | Pages project name |
| `DEPLOY_ENABLED` | unset (deploy skipped) | Set to `true` once credentials and the Pages project exist; until then pushes build but do not deploy |
| `SITE_URL` | `https://test-blog.chiefgyk3d.com` | URL the smoke test checks |
| `DOPPLER_IDENTITY_ID` | none | Doppler OIDC identity UUID (Doppler path only) |

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
4. Custom domain: in the project, Custom domains, Set up a domain, enter
   `test-blog.chiefgyk3d.com`. If the zone is on Cloudflare the DNS record is
   created for you.

Account id: dashboard, Workers & Pages overview, right-hand column, Account ID.
It is not a secret by itself, but the workflow reads it as a credential value
so it stays out of the repository.

API token (Manage account, Account API tokens, Create token, Custom token).
Minimum scope, limited to the one account and the one zone:

- Account, Cloudflare Pages: Edit (resource: the one account).
- Zone, DNS: Edit (resource: the one zone, `chiefgyk3d.com`).

Add nothing else. Set a short expiry and rotate it.

## Path A: Doppler (preferred)

Doppler holds the Cloudflare values; the workflow reads them over OIDC, so no
long-lived Doppler credential sits in GitHub.

The owner, not an agent, does all of the following. An agent never creates the
Doppler service account, the identity, or any token.

1. In the shared Doppler project `ci`, config `ci`, add the secrets
   `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. The config must hold only
   what CI needs; every value in it is exported to the job.
2. Create a Doppler service account with the Viewer role on project `ci`,
   config `ci` only.
3. On that service account add an OIDC identity (Service Account Identities):
   issuer `https://token.actions.githubusercontent.com`, audience as Doppler
   shows it, and a subject limited to the default branch:
   `repo:ChiefGyk3D/no-php-no-cry:ref:refs/heads/main`. No wildcard subject.
4. Copy the identity UUID (not a secret) into the repository variable
   `DOPPLER_IDENTITY_ID`.
5. Leave the `DOPPLER_TOKEN` secret unset, or set a read-only service token for
   `ci/ci` there if you prefer the token path over OIDC. The OIDC identity wins
   when both exist.
6. Run the workflow by hand from `main` (Actions, Deploy, Run workflow).

The Doppler action fetches only on the default branch, a tag, or a schedule.

## Path B: GitHub Actions secrets (no Doppler)

For a fork or anyone without Doppler:

1. Leave `DOPPLER_IDENTITY_ID` unset.
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
- Egress hardening: the three jobs run harden-runner in audit mode because the
  artifact storage host cannot be listed without a wildcard. Tightening them to
  block with a measured list is tracked in issue #10.
