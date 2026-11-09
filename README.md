# no-php-no-cry

A personal site and work journal built with [Hugo](https://gohugo.io/), no PHP,
no database and no third-party code in the repository or the built site (the
host adds its own analytics beacon at the edge, described on the Privacy page). It is the source of the
[ChiefGyk3D](https://chiefgyk3d.com) site, moved off WordPress, and it is
published as a worked example: a small static site with strict build checks, in
the open, that you can read, copy and adapt.

Staging runs at `test-blog.chiefgyk3d.com` until the site replaces the apex
domain. It deploys to Cloudflare Pages.

## Why this exists

No PHP No Cry is a static site and work journal built because of PHP2Shell and my frustration with Matt Mullenweg and his toxicity. I covered the WordPress and Matt Mullenweg situation in a few videos:

- [“Who can't drive an Automattic? The fall of Wordpress and Matt Mullenweg”](https://www.youtube.com/watch?v=FnoazrD6-Rg)
- [“The Internet at Risk: WordPress Drama and Matt Mullenweg's Petty Fight Against WP Engine”](https://www.youtube.com/watch?v=RqRZoQqKPgs)
- [“Automattic and Matt Mullenweg ‘Are Doing Open Source Dirty’”](https://www.youtube.com/watch?v=QLEzJ3cXiWI)

It aims to be fast, light, capable, better designed, and more secure. Open source so creators can use it and learn from it.

## Who it is for

- You want to leave WordPress (or any CMS) for a static site and want to see one
  done with the checks that keep it honest.
- You want a Hugo site with templates written from scratch, not a theme, and a
  strict Content Security Policy that the build enforces.
- You write posts and want a guide from an empty folder to a pull request.
- You are learning CI and want to see every check paired with a test that proves
  the check fails when it should.

## What is in it

- **Posts and a work journal.** Two sections, one page bundle per entry
  (`index.md` plus its images), tags and categories, an archive banner and a
  forward link for old posts. See [Writing a post](docs/wiki/Writing-a-post.md)
  and [Journal entries](docs/wiki/Journal-entries.md).
- **Images that cannot ship without alt text.** An image render hook makes
  responsive markup (`srcset`, dimensions, lazy loading) and fails the build on missing alt text, a remote image
  or an unsupported format. See [Images and alt text](docs/wiki/Images-and-alt-text.md).
- **Headline images.** An optional featured image shows below the title plate, as a
  small card thumbnail and as the social card. See
  [Headline images](docs/wiki/Headline-images.md).
- **Search that works without JavaScript.** `/search/` is a full A to Z index
  first; a tiny pinned script only adds filtering. Tags live in a collapsed
  section. See [Search and tags](docs/wiki/Search-and-tags.md).
- **Feeds and discovery.** RSS at `/feed/index.xml`, a sitemap, `robots.txt`
  that follows the staging or production setting, and an `/llms.txt`.
- **Pages beyond posts.** Home, About, Resume (with a print stylesheet), Social
  links, Gear and tools with an affiliate disclosure, Support with
  cryptocurrency QR codes and Copy buttons, Privacy, and a 404.
- **WordPress migration tooling.** `tools/wxr2hugo/` turns a WordPress export
  into page bundles, keeps old addresses as 301 redirects and scrubs private
  data. See [Migrating from WordPress](docs/wiki/Migrating-from-WordPress.md).
- **A page-weight and accessibility gate.** A size budget and a real-browser
  gate with axe-core run on every pull request that changes the site (a
  documentation-only pull request skips them). See
  [Build checks and budgets](docs/wiki/Build-checks-and-budgets.md),
  [Performance](docs/wiki/Performance.md) and [Accessibility](docs/wiki/Accessibility.md).

- **Share links on posts.** A Share row under each post and journal entry:
  plain links to Threads, Bluesky, Twitter, Reddit, LinkedIn, Facebook, Hacker
  News, Pinterest (posts with a headline image) and Email, plus copy-link
  buttons and a Mastodon button. See [Share links](docs/wiki/Share-links.md).

## Quick start

You need the Hugo release named in `.hugo-version` (standard edition, not
extended), `git`, Python 3 and a POSIX shell. Download that release from the
[Hugo releases page](https://github.com/gohugoio/hugo/releases), verify it
against the checksums file published with it, and put the `hugo` binary on your
`PATH`. The full walk-through, with the commands, is in
[Getting started](docs/wiki/Getting-started.md).

```sh
git clone https://github.com/ChiefGyk3D/no-php-no-cry.git
cd no-php-no-cry
hugo version                       # must match .hugo-version
hugo server --buildDrafts          # live preview, drafts shown
hugo --minify --gc                 # production build into public/
```

## Build and test

These are the commands the project runs; each was run on a clean checkout while
writing this README.

```sh
scripts/check-hugo-version.sh "$(cat .hugo-version)"    # pinned standard edition only
EXPECT_ENV=production scripts/check-output.sh public     # the output rules
scripts/check-site-artifact.sh public                   # Cloudflare Pages control files
python3 -I scripts/check-budget.py public               # the page-weight budget
scripts/check-wording.sh                                # the house wording rule
scripts/check-license.sh                                # the license files
python3 -I scripts/check-wiki.py                        # README and wiki links and paths
scripts/test-archetype.sh                               # a new post builds and passes the checks
scripts/gate.sh --fast                                  # only what your changes touch
scripts/gate.sh                                         # the whole local gate
```

`scripts/gate.sh --plan` prints every step without running it. The full list
of checks and what each one fails on is in
[Build checks and budgets](docs/wiki/Build-checks-and-budgets.md).

## Write a post

```sh
hugo new content posts/my-post-title
```

That creates `content/posts/<slug>/index.md` from the archetype, as a
draft. Fill in `description`, `categories`, `tags`, put images beside the file
with real alt text, set `draft: false`, run the checks and open a pull request.
The full guide is [docs/writing-a-post.md](docs/writing-a-post.md); the wiki
page [Writing a post](docs/wiki/Writing-a-post.md) is the short version.

## How CI checks it

`.github/workflows/ci.yml` calls reusable workflows from
[git-your-ship-together](https://github.com/ChiefGyk3D/git-your-ship-together),
pinned by commit: one shared `parallel-ci` workflow builds the site once (production and
staging) and runs the checks side by side, one workflow lints the shell scripts,
and one runs the security scans. A local job named `CI green` waits for all of
them and is the single required check. Deploys run from `main` only, after
`CI green` on the same commit. The job-by-job map is in
[docs/ci-parallel.md](docs/ci-parallel.md), and the deploy is in
[Deploy overview](docs/wiki/Deploy-overview.md).

## Security and privacy stance

- **No third-party assets in the built site.** The Content Security Policy in
  `static/_headers` allows only the site's own files, plus the one analytics
  beacon the host injects at the edge (see the Privacy page). The build fails on inline
  script, inline style, event handlers, third-party assets and plain-HTTP
  references.
- **Three small scripts, pinned by hash:** `/copy.js` on Support, `/search.js`
  on Search and `/share.js` on posts and journal entries. See [docs/pinned-script.md](docs/pinned-script.md).
- **No cookies set by the site's code and no embeds.** The host's own
  analytics are described on the site's Privacy page
  ([content/privacy/index.md](content/privacy/index.md)).
- **No secrets, no private data in the repository.** Raw WordPress exports are
  never committed, secret scanning runs in CI, and the converter stops on private
  data shapes. Security reports go through private vulnerability reporting, see
  [CONTRIBUTING.md](CONTRIBUTING.md).
- **A threat model you can open.** The publishing path, the reader path and the secrets are
  modeled in OWASP Threat Dragon, with a plain-language summary. See
  [docs/threat-model/README.md](docs/threat-model/README.md).

## Learn from this site

A reading order through the repository, with the idea each part teaches, is in
the wiki: [Home](docs/wiki/Home.md), section "Learn from this site".

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).
Every change starts from an issue. Never weaken, skip or narrow a check to get
CI green.

## The wiki

The wiki pages are written in this repository under [docs/wiki/](docs/wiki/Home.md)
and are the reference for everything above. Start at [Home](docs/wiki/Home.md).

## License

Copyright 2026 ChiefGyk3D. This section is a summary, not legal advice.

- Code (scripts, templates, configuration, tooling): Apache-2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).
- Written content (`content/`, `docs/`, including the wiki): CC BY 4.0, see [LICENSE-CONTENT](LICENSE-CONTENT).
- Brand assets (mascot, wordmark, logos): all rights reserved, not covered by either license. See [BRAND.md](BRAND.md).
- Third-party material (vendored axe-core, fonts, icons, coin marks, the five product photos in the headphones post) keeps its own terms, listed in [BRAND.md](BRAND.md).

`scripts/check-license.sh` fails the build if `LICENSE` is not the official Apache-2.0 text or if the content license or brand notice is missing.

## Credit

If you reuse the code, keep the notices in [NOTICE](NOTICE). If you reuse the
written content, credit "ChiefGyk3D", link to the license and say if you changed
it. The site footer carries a copyright line for Renegade Penguin LLC and a
"Powered by No PHP No Cry" credit link back to this repository. Please do not reuse the mascot or the brand art: those are not
licensed for reuse.
