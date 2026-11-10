# Risks in plain language

Summary of `no-php-no-cry.threat-model.json`, written 2026-11-09 against the repository at that time. It
says what could go wrong, what is already handled, what is knowingly left, and what is still open. Open the
model for the diagrams and the full text of each threat. How to open and update it is in [README.md](README.md).

## Who we defend against

A public visitor, and a reader of released reports. The owner is a trusted operator, so a deliberate act
by the owner is out of scope. A mistake by the owner or a contributor is in scope.

## Counts

63 threats in three diagrams: 33 Mitigated, 26 Open, 3 Accepted, 1 N/A.

A threat counts as Mitigated only when a control is in this repository and the model names it by path.
`scripts/check-threat-model.py` fails the build when a named path does not exist.

## What is handled

- Script injection and header drift: the strict CSP in `static/_headers` and the build checks that read the
  built files. Only three scripts are allowed, each pinned by a hash (`docs/pinned-script.md`).
- Supply chain: actions and shared workflows pinned by commit, a locked deploy tool, a pinned Hugo,
  committed fonts, dependency review and secret scanning in CI.
- Deploy safety: a deploy runs only from the main branch after the CI green check on that exact commit; the
  one job that gets the Cloudflare credential checks out two scripts and re-checks the build folder first.
- Share panel: the Mastodon server a visitor types is checked as a plain host name, and the share link is
  always built from `https`, that host and a fixed path (`static/share.js`, `scripts/test-share.sh`).
- Redirects and links: only internal redirect lines are generated, with a test that feeds bad lines.
- Private data and secrets in commits: the content scrub list, the secret scan, and a pull request checklist.
- Analytics code (not deployed): a source guard bans address headers, cookies and logging in the Function.

## Accepted by decision

- The Cloudflare Web Analytics beacon is a third-party script that the CSP allows by name (owner decision
  Q3, `docs/analytics-from-reach-around.md`). The CSP names one path prefix on Cloudflare's script host, with a trailing slash
  (issue 318); the model records that prefix as its own accepted threat (residual risk accepted, with the integrity hash as the control).
- Page counts can be inflated by anyone who requests pages. Counts are an estimate, never used for security.

## Open, in order of how much they matter

High severity:

1. Owner account or machine taken over, and a compromised editor or helper. CI catches many bad changes but
   cannot protect against a hijacked owner. Sign-in strength is a provider setting, not read for this model.
2. Token scopes. The Cloudflare token is documented as narrow (`docs/deploy.md`), but the live permissions
   have not been read for this model. Read them, then record the date here.
3. Domain and account takeover at the provider (registrar lock, DNS signing, Cloudflare and Doppler account
   sign-in). The repository cannot show these. Read them and record the date here.
4. Syndication credentials. The job is planned (issue 11) and not in the workflows yet. Its design must keep
   the four platform tokens in Doppler only.
5. Analytics hash secret. Not built yet; it must live in Doppler only and be rotated.
6. The production promotion path (live at the apex since 2026-11-10). The site is built and deployed from a
   private repository that pins a commit of this one, so most of its controls are outside what this
   repository can show. Four threats stay Open until the owner reads them and the date is recorded here:
   the pin file as the reviewable gate (a change to it is a visible diff, and a pin revert is the
   rollback); the build job kept apart from the credentialed deploy job; the validation of the build
   output as inert data in a credential-free step before any credentialed step (the validator is
   `scripts/check-site-artifact.sh`, here and tested, but its production use is not read from here); and
   the identity claim rules at the secret manager. The claim rules are an owner-configured control at the
   provider, not something this repository enforces.

Medium and low severity:

- Analytics privacy, all of which waits on code that is not built: a small-town re-identification floor, the
  daily visitor code, report suppression, the outbound-domain flood cap, and an admission budget for the
  Function so a flood cannot burn the free daily allowance. Each is a numbered plan item in
  `docs/analytics-from-reach-around.md`. Nothing here is live until the analytics Function is deployed.
- Edge cache staleness: after a header change, unchanged static files keep their old cached headers at
  the edge until their URLs are purged (seen on staging for three unchanged scripts). The live verifier
  `scripts/verify-live.sh` checks headers only on its page list, so it does not catch this. The detection is
  a manual check of the three script URLs against `static/_headers` after a purge, with a copy-paste block in
  `docs/cutover.md` ("Checking cached script headers"); no automation does it.
- Build-step egress: the build and check jobs run the runner egress policy in audit mode, not block
  (`docs/ci-parallel.md`), so a compromised build step could send the (public) source out. Flip it to block
  once the allowed hosts are measured.
- A look-alike copy of the site. Cannot be prevented; takedown is manual.
- Syndication abuse and repeats, until the job exists.
- The database edit token for the analytics maintenance job must be dropped after the work.
- Feed identifiers: the identifier is the permalink and old addresses redirect, but no test pins an
  existing post's identifier across a slug change.
- Two analytics counters disagreeing and being misread. A reconciliation note is plan item 12.

## Items the owner should decide

1. Branch protection: main requires the CI green check and blocks force pushes (read 2026-11-09), but
   requires zero approving reviews and does not enforce rules for administrators. This is normal for a
   one-person project. Decide whether to keep it.
2. Commit signing: not required. Decide whether to ask for it.
3. After the token and domain checks above, record the dates here and move those threats to Mitigated.

## Review log

| Date | Change |
| --- | --- |
| 2026-11-09 | First version (issue 290). Provider-side settings not read. |
| 2026-11-09 | Counts corrected to 33 Mitigated and 21 Open after the GitHub secret fallbacks were removed (PR 307); numbers read from the model with `scripts/check-threat-model.py`. |
| 2026-11-09 | Counts 58 threats, 33 Mitigated, 3 Accepted: the beacon CSP entry became a path prefix (issue 318) and the model gained one threat for it, with status Accepted because its residual risk is accepted. |
| 2026-11-10 | Production promotion path (issues 242, 323): five threats added, all Open, so 63 threats, 33 Mitigated, 26 Open, 3 Accepted, 1 N/A. None is marked Mitigated because the production pipeline and the identity claim rules live outside this repository and were not read for this model. |
