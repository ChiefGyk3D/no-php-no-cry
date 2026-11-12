# no-php-no-cry wiki

no-php-no-cry is the source of a personal site and work journal built with Hugo:
no PHP, no database, no third-party scripts, and a build that fails when it
breaks its own rules. It replaced a WordPress site, and it is published so
others can read it, learn from it and reuse it.

These pages are written in the repository under `docs/wiki/`, so they change in
the same pull request as the code they describe. The README is the short
version: [README](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/README.md).

## Pages

| Page | What it covers |
| --- | --- |
| [Getting started](Getting-started.md) | Install the pinned Hugo, preview, build, run the checks. |
| [Architecture](Architecture.md) | How the repository, templates, data and output fit together. |
| [Writing a post](Writing-a-post.md) | From an empty folder to a pull request. |
| [Journal entries](Journal-entries.md) | The work journal section and how it differs from posts. |
| [Images and alt text](Images-and-alt-text.md) | The image render hook and every rule it enforces. |
| [Headline images](Headline-images.md) | The optional featured image, thumbnail and social card. |
| [Share links](Share-links.md) | The Share row under a post, its targets and its one script. |
| [Search and tags](Search-and-tags.md) | The no-JavaScript search page, its pinned script and tags. |
| [Build checks and budgets](Build-checks-and-budgets.md) | Every check, what it fails on and the size budget. |
| [Deploy overview](Deploy-overview.md) | CI, the deploy gate, the dev deploy versus the production pipeline. |
| [Migrating from WordPress](Migrating-from-WordPress.md) | The converter, redirects and the scrub pass. |
| [Performance](Performance.md) | Page weight, fonts, images and the browser measurements. |
| [Privacy-first analytics for Hugo](Privacy-first-analytics-for-Hugo.md) | A preview-first guide to the configuration, Hugo hook, Cloudflare files, privacy text and owner account steps. |
| [Accessibility](Accessibility.md) | What is built in, what is checked and what is not proven. |
| [Contributing](Contributing.md) | Issues, pull requests and the rules that never bend. |
| [FAQ](FAQ.md) | Short answers to common questions. |

## Learn from this site

The repository is meant to be read in an order. Each stop names the idea it
teaches. Paths are relative to the repository root.

| # | Read | The idea it teaches |
| --- | --- | --- |
| 1 | `.hugo-version`, `scripts/check-hugo-version.sh` | Pin the toolchain and check the pin, so every build is the same build. |
| 2 | `hugo.toml` | Site configuration as the contract: output formats, taxonomies, one environment switch for staging versus production. |
| 3 | `layouts/baseof.html`, `layouts/single.html`, `layouts/list.html` | Templates written from scratch instead of a theme: one stylesheet per page, native HTML for the menu and accordions. |
| 4 | `layouts/_markup/render-image.html`, `layouts/_partials/featured-image.html` | Make bad input a build error. An image without alt text cannot be published. |
| 5 | `archetypes/posts/index.md`, `scripts/test-archetype.sh` | Guardrails for authors: the starting file explains itself, and a test proves a post made from it builds. |
| 6 | `static/_headers` | A Content Security Policy that allows only the site's own files. |
| 7 | `scripts/check-output.sh`, `scripts/artifact-rules.sh` | Turn the policy into a checker that reads the built files. |
| 8 | `scripts/test-check-output.sh` | Negative tests: every rule has a case that must fail, so a check that stopped checking is caught. |
| 9 | `scripts/check-budget.py`, `scripts/browser-gate.py` | Measure page weight and run a real browser with an accessibility engine in CI. |
| 10 | `brand/tokens.json`, `scripts/gen-tokens.py`, `scripts/check-contrast.py` | Generate the stylesheet tokens from one source and compute the contrast ratios. |
| 11 | `.github/workflows/ci.yml`, `docs/ci-parallel.md` | Reusable workflows pinned by commit, one required check named `CI green`. |
| 12 | `.github/workflows/deploy.yml`, `scripts/wait-for-ci-green.sh`, `scripts/check-site-artifact.sh` | Deploy a prebuilt folder only after the checks passed on that exact commit. |
| 13 | `tools/wxr2hugo/` | Migrate from WordPress with a scrub pass that stops on private data. |
| 14 | `scripts/gate.sh`, `scripts/test-gate.sh` | One local command that runs what CI runs, and a test of that command. |
| 15 | `analytics/`, `functions/`, `docs/analytics-deploy.md` | A privacy-first page-view counter that is built and tested but not deployed, and why. |
| 16 | `docs/threat-model/`, `scripts/check-threat-model.py` | A threat model that opens in a free tool, and a check that keeps it honest: every control it names must exist. |

If you only have an hour, read steps 4, 6, 7 and 8: they show the whole idea
(rules in the build, with tests that prove the rules bite).

## Status

The site is live at the apex since 2026-11-10 and WordPress is retired as the
origin. This repository keeps a noindex dev host for its own deploy. Features that exist only in an open pull request are marked
"lands with PR" on their page, and that note is removed when the pull request
merges.

## Licenses

Code is Apache-2.0, written content including this wiki is CC BY 4.0, and the
brand art is all rights reserved. See the
[BRAND.md notice](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/BRAND.md).
