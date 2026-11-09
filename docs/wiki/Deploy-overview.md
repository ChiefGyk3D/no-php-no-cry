# Deploy overview

A high-level map of how a change becomes a deployed page. The full procedure,
with every variable and credential, is in
[docs/deploy.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/deploy.md);
the CI job map is [docs/ci-parallel.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/ci-parallel.md).
Nothing here needs a secret to read or to run a pull request.

## CI on every pull request

`.github/workflows/ci.yml` has four jobs:

| Job | What it is |
| --- | --- |
| `ci` | The shared `parallel-ci` workflow from [git-your-ship-together](https://github.com/ChiefGyk3D/git-your-ship-together), pinned by commit. It installs the pinned Hugo (checksum verified), builds production and staging once, then runs the checks side by side as separate jobs on that build: output checks, output checker tests, site tests, tool tests, content checks, size budget and browser gate. |
| `shell` | The shared `bash-ci` workflow: `shfmt`, `shellcheck`, and the tests that need no Hugo. |
| `security` | The shared `security` workflow: CodeQL for the workflow files, secret scanning, dependency review and more. |
| `CI green` | A local job that needs the three above and fails unless each one is exactly `success`. It is the single required check on `main`. |

The commands each job runs are this repository's own scripts; the shared
workflows supply the plumbing (checkout, caching, hardening, reporting). A change
confined to documentation skips only the size budget and browser gate. Any
other change, a failed diff and every push run everything.

A reusable workflow's own gate shows up as `ci / CI green`. The local job keeps
the bare name `CI green` because branch protection and the deploy workflow name
it exactly.

## Deploy on `main`

`.github/workflows/deploy.yml` runs on a push to `main` and by hand, never on a
pull request, and is not a required check.

1. **build** installs the pinned Hugo, builds, runs
   `scripts/check-output.sh` and `scripts/check-site-artifact.sh`, and uploads
   `public/` as an artifact.
2. **gate** waits for the `CI green` check run on the same commit
   (`scripts/wait-for-ci-green.sh`). Only a success continues; a newer failure
   always beats an older success; no result within 25 minutes fails.
3. **deploy** downloads the artifact, installs Wrangler from the lockfile in
   `deploy/` with install scripts off, re-checks the artifact, and only then
   fetches the Cloudflare credentials and runs `wrangler pages deploy`. This is
   the only job with credentials. Cloudflare Pages is used as a direct upload of
   a prebuilt folder, and the project is created by CI if it does not exist
   (`scripts/ensure-pages-project.sh`).
4. **smoke** runs `scripts/smoke-site.sh` against the live address: the expected
   status, exactly one Content Security Policy equal to the committed one and
   `nosniff` on one page per template, the pinned scripts against their hashes,
   and one 301 from the built `_redirects`.

The deploy job is skipped until the repository variable `DEPLOY_ENABLED` is
`true`; until then pushes build but do not deploy. After that it never skips
silently.

## Staging versus production

While the site lives on a staging host, the build sets
`HUGO_PARAMS_ENVIRONMENT=staging`: every page is noindex and `robots.txt`
disallows everything. CI builds and checks both environments on every run.
`scripts/verify-live.sh` checks a deployed host read-only (GET requests only).
The apex cutover plan, gates and rollback are in
[docs/cutover.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/docs/cutover.md).

## Credentials

The deploy job needs `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. It reads
them from the secrets manager over OIDC and from nowhere else: no GitHub
repository secret is read or recommended. The token is a user token with exactly
one permission (Cloudflare Pages: Edit). Never put either value in the
repository, in an issue or in a log. If you fork, change the OIDC subject and
`SITE_URL` to match your repository.

## Roll back

Roll back in the Cloudflare dashboard (the project's Deployments list), or revert
the change on `main` and let the workflow redeploy.

## Related

- [Build checks and budgets](Build-checks-and-budgets.md): what runs before this.
- [Architecture](Architecture.md): what is in the artifact.
- `docs/analytics-deploy.md` records the page-view counter, which is not part of
  this deploy.
