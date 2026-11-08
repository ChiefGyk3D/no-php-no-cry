# Architecture

How the pieces fit. Everything here is on `main`; paths are from the repository
root.

## The shape of it

Markdown and data go in, Hugo builds a folder of static files, scripts read that
folder and fail on anything that breaks a rule, and the folder is uploaded to
Cloudflare Pages. Nothing runs on a server per request.

```
content/ + data/ + layouts/ + assets/ + static/
        |  hugo --minify --gc  (pinned release)
        v
     public/  ---> scripts/check-output.sh, check-site-artifact.sh,
        |          check-budget.py, browser-gate.py
        v
   Cloudflare Pages (direct upload, after CI green)
```

## Repository map

| Path | What it holds |
| --- | --- |
| `hugo.toml`, `.hugo-version` | Site configuration and the pinned Hugo release. |
| `content/posts/` | Posts, one leaf page bundle each: `index.md` plus its images. |
| `content/journal/` | The work journal, a separate section. |
| `content/about/`, `content/privacy/`, `content/support/`, `content/resume/`, `content/search/`, `content/social/`, `content/products/` | The other pages. Social and Products render from `data/`. |
| `data/` | `socials.yaml` (the Social page and footer icons), `products.yaml` (Gear and tools), `support.yaml` (wallet addresses), `about.yaml`, `resume.yaml`, `comments/` (archived comments from the old site), `legacy_uploads.json` (old upload redirects). |
| `layouts/` | Templates written from scratch: `baseof.html` (the shell), `single.html` (a post or entry), `list.html` (an archive), a folder per special page, `_partials/`, `_markup/render-image.html` and the non-HTML outputs (`home.redirects`, `home.robots.txt`, `home.llms.txt`, `home.feed.xml`, `rss.xml`, `sitemap.xml`). |
| `assets/css/` | `tokens.css` (generated), `main.css`, `highlight.css`, one file per page type in `pages/`. Hugo Pipes concatenates, minifies and fingerprints them into one stylesheet per page. |
| `static/` | Files copied as they are: `_headers`, `_routes.json`, the two pinned scripts, fonts, the brand folder, the web manifest. |
| `archetypes/` | The starting files for `hugo new content`. |
| `brand/` | `tokens.json` (the design token source), the approved-asset manifest and brand notes. |
| `scripts/` | The checks, their tests and `gate.sh`. |
| `tools/wxr2hugo/` | The WordPress converter and its tests. `tools/axe/` is the vendored axe-core used by the browser gate. |
| `analytics/`, `functions/` | A page-view counter that is built and tested but not deployed. See `docs/analytics-deploy.md`. |
| `deploy/` | The lockfile that pins Wrangler for the deploy job. |
| `.github/workflows/` | `ci.yml` and `deploy.yml`. |
| `docs/` | Longer guides and the decision records. `docs/wiki/` is this wiki. |

## Outputs

`hugo.toml` asks for more than HTML. The home page publishes `html`, `rss`,
`feed`, `redirects`, `robots` and `llms`; sections publish `html` and `rss`:

- **`feed/index.xml`**: the site feed (posts and journal). The old WordPress feed
  addresses redirect to it.
- **`_redirects`**: a Cloudflare Pages redirects file built from every page's
  `aliases` front matter by `layouts/home.redirects`. The check fails any alias
  without its 301 line.
- **`robots.txt`**: follows `params.environment` (`production` or `staging`).
- **`llms.txt`**: a short index for language-model crawlers, built from front matter
  and data so it cannot rot.
- **`sitemap.xml`**: every page, with `lastmod`.

## Templates and styles

- `baseof.html` is the shell: a skip link first, one header with the main
  navigation, `<main id="main">`, and a footer. The phone menu is a native
  popover (`popover` and `popovertarget`), so it needs no script.
- Accordions (such as Browse by tag) are native `<details>`.
- One stylesheet per page: `baseof.html` concatenates tokens, main, highlight and
  every `assets/css/pages/*.css`, minifies and fingerprints it. The Home and 404
  pages append one more file for the penguin ghost so no other page pays for it.
- The Markdown image render hook and the headline-image partial are where image
  rules live. See [Images and alt text](Images-and-alt-text.md).
- `layouts/_partials/head-meta.html` writes the description, Open Graph and
  Twitter card tags, icons and structured data. `description.html` picks one
  description per page; the output check refuses duplicates.

## Environments

One parameter, `params.environment`, switches staging and production. A build
sets it without editing the file: `HUGO_PARAMS_ENVIRONMENT=staging`. Staging adds
`noindex, nofollow` to every page and a `robots.txt` that disallows everything.
`EXPECT_ENV` tells `scripts/check-output.sh` which one it should find. The apex
cutover plan is `docs/cutover.md`.

## Security model in one paragraph

`static/_headers` sets a Content Security Policy of `default-src 'none'` plus
same-origin images, styles, fonts and manifest, `script-src 'self'` (and the one
host analytics beacon injected by the host at the edge), no forms, no framing.
`'self'` allows every same-origin script, so the build holds the site to exactly
two reviewed scripts by hash, each on one page. See
`docs/pinned-script.md` and [Build checks and budgets](Build-checks-and-budgets.md).

## Where each decision is recorded

- Goals, design, budgets and the page list: `docs/redesign-brief.md`.
- Performance and accessibility gates: `docs/performance-gates.md`.
- CI jobs: `docs/ci-parallel.md`.
- Deploy and cutover: `docs/deploy.md` and `docs/cutover.md`.
- What the old site had and what is still open: `docs/parity.md`.
