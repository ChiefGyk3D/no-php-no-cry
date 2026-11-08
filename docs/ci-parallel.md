# CI: one build, checks side by side

Issue 185. `.github/workflows/ci.yml` used to run one job, `build`, with about
forty steps in a row. It now calls the shared `parallel-ci.yml` from
[git-your-ship-together](https://github.com/ChiefGyk3D/git-your-ship-together)
(GYST), pinned by commit at v1.33.0. The build runs once. The checks then run as
separate jobs, each on the build it downloads, so the wall time is the build plus
the slowest check, not the sum.

## The jobs

| Job | What it is |
| --- | --- |
| `ci / Choose the checks` | Validates the inputs and decides which checks this change needs. |
| `ci / Build` | Installs the pinned Hugo, checks the edition, builds production and staging once, uploads both. |
| `ci / Check (<name>)` | One leg per entry in the `jobs` list below. |
| `ci / CI green` | The shared workflow's own gate over its jobs. |
| `shell` | `bash-ci.yml`: shfmt, shellcheck, and the two scripts that need no Hugo. |
| `security` | `security.yml`: CodeQL (actions), gitleaks, dependency review, zizmor and the rest. |
| `CI green` | Local job in `ci.yml`. The one required check. Needs `ci`, `shell` and `security` and fails unless each is exactly `success`. |

Why `CI green` stays a local job: a called workflow's check run is named
`<caller job> / <job>`, so the shared gate shows up as `ci / CI green`. Branch
protection requires the bare name `CI green` and `deploy.yml` waits for that name
(`scripts/wait-for-ci-green.sh`). Neither is changed. A skipped `ci` leg that the
path rules chose to skip counts as passed inside `ci / CI green`; a skipped or
cancelled `ci`, `shell` or `security` makes the local `CI green` fail.

## Old step to new job

Every step of the old `Hugo build and output checks` job, mapped to exactly one
place. Legs: `output checks` (O), `output checker tests` (OT), `site tests` (S),
`tool tests` (T), `content checks` (C), `size budget` (B), `browser gate` (G).
Setup and build run in the `ci / Build` job (`setup-command`, `build-command`).

| Old step | New place |
| --- | --- |
| Install Hugo (pinned, checksum verified) | `setup-command` (Build job, and every leg with `tools`) |
| Hugo is the pinned standard edition | `build-command`, first line |
| Build | `build-command` |
| Build the staging variant | `build-command`, last line, shared as the extra output |
| Check the generated output (production) | O |
| Check the site for Pages control files (production) | O |
| Check the generated output (staging) | O |
| Check the staging site for Pages control files | O |
| Test the output checker (negative cases) | OT, and again in `shell` (needs no Hugo) |
| Test the site artifact checker | O |
| Test the page head and footer links | S |
| Test the Social and Products pages | S |
| Test the resume page and print stylesheet | S |
| Test the Support, About and Privacy pages | S |
| Test the archived comments | S |
| Test the generated `_redirects` file | S |
| Test `/llms.txt` | S |
| Test the content migration | S |
| Test the post and journal archetypes | S |
| Test that the deploy job's sparse checkout covers what it runs | T |
| Test the copy script pinning | T |
| Test the Reach Around drift check | T |
| Test the Hugo version check | T, and again in `shell` |
| Test the post-deploy smoke check | T |
| Test the live-host verifier | T |
| Test the shared robots.txt parser | T |
| Test the deploy gate wait | T |
| Test the Pages project check | T |
| Test the WordPress converter | T |
| Test the WebP conversion step | T |
| Test the page-view collector | T |
| Test the brand checks | T |
| Test the gitleaks allowlist | T |
| Check the support QR files and decode them | C |
| Check the wording rule | C |
| Check the license files | C |
| Check `tokens.css` is generated from `brand/tokens.json` | C |
| Check design-token contrast | C |
| Check the brand asset manifest | C |
| Check README and wiki links and paths (`scripts/check-wiki.py`, issue 234) | C |
| Test the README and wiki check | S |
| Size budget | B |
| Browser gate | G |

Added to the repository after the first analysis, and where they run:

- The image-metadata guard runs inside `scripts/check-output.sh`, so it is in O.
- `test-check-output.sh` (its pool of cases) is OT, a leg of its own because it is
  the longest test script. It also runs in `shell`.
- `test-social-products.sh` is in S.
- The browser gate's `[fit]` and `[tile]` rules run inside `scripts/browser-gate.py`
  and `scripts/test-browser-gate.sh`, so they are in G.
- `scripts/test-gate.sh` (tests the local gate script) was not a CI step before and
  is not one now.

Check with: every `scripts/test-*.sh` except `test-gate.sh` appears in
`.github/workflows/ci.yml`.

Which legs need what:

- `tools: true` legs (S, T) run `setup-command` first, so `hugo` is on PATH. They do
  not download the build (`build: false`) because these scripts build their own
  small sites.
- `pip-cache: true` (T, C) restores pip's download cache for the hash-pinned
  Pillow, segno and OpenCV installs (only effective once egress is `block`).
- O, OT, B and G download the production build (and O the staging build).
- G uses the Chrome that the `ubuntu-24.04` runner ships.

## Area map

On a pull request the changed paths decide which legs run:

| Area | Patterns |
| --- | --- |
| `docs` | `docs/*.md`, `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` |
| `site` | everything else (`*`) |

Only `size budget` and `browser gate` carry `areas: ["site"]`. A change confined to
the `docs` area skips those two; every other leg always runs. A push, a schedule, a
manual run, a pull request to another branch, an empty or unreadable diff, and a
path no rule matches all run every leg (fail closed). Note `.github/**` and
`scripts/**` are `site`: a workflow or script change runs everything.

## Decisions

- `egress-policy-secretless` is `audit`, as the old `build` job was. The GYST
  default is `block`. In audit mode the Hugo tarball cache and the pip cache are
  inert (a cache is only restored and saved where egress is `block`).
- `shell` and `security` stay jobs, re-pinned from v1.31.0 (`9d6825d`) to v1.33.0
  (`13f7a13`).
- `deploy.yml` and branch protection are unchanged.

## Roadmap

Flip `egress-policy-secretless` to `block`: run the workflow once, read the
harden-runner report of the `ci` jobs for the hosts they reach (the Hugo release
download and its redirect host, the Python package index and its file host), add
them as `extra-allowed-endpoints`, then switch the policy. That also turns the
tool and pip caches on.

## Verification plan

Only a real run can show these; check them on the first pull request and the first
push to main:

1. Exactly one check named `CI green` (the local job) appears next to `ci / CI
   green`, and the required-check list in branch protection is satisfied by the
   first.
2. A pull request that touches only `docs/*.md` skips `size budget` and `browser
   gate`, and `CI green` is still green. A pull request that touches a layout or a
   script runs them.
3. Break one leg on purpose (for example a failing line in a scratch test script
   added to `tool tests`): that leg, `ci / CI green` and `CI green` all turn red.
   Revert it and confirm green. Do the same with a skipped `ci` result if
   possible.
4. The artifact round trip: the production build uploaded by `ci / Build` is what
   `output checks`, `size budget` and `browser gate` check, and the staging output
   lands at the same `RUNNER_TEMP/public-staging` path in `output checks`
   (`EXPECT_ENV=staging` passes).
5. `hugo` is on PATH in `site tests` and `tool tests` (they fail at the first
   `hugo` call otherwise) and `scripts/check-hugo-version.sh` passes in the build.
6. Timings: the `ci` jobs finish in about the build plus the slowest leg (compare
   with the old single job of up to 25 minutes). Record the numbers here. If one
   leg dominates, split it.
7. `shell` and `security` run at the new pin with no change in what they check.
8. The harden-runner reports are readable for the roadmap item above.
