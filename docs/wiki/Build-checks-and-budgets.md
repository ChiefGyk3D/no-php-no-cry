# Build checks and budgets

The site is held to its own rules by scripts that read the built files. A rule
that is not checked is a wish, so every check below has a test with a case that
must fail. A check that stopped checking would turn its test red.

All of these run in CI (see [Deploy overview](Deploy-overview.md)) and in
`scripts/gate.sh` locally. Each prints `[rule] page detail` lines (never page
content) and exits 1 on any finding.

## The checks

| Check | Reads | Fails on |
| --- | --- | --- |
| `scripts/check-hugo-version.sh` | the Hugo binary | any release other than the one in `.hugo-version`, or the extended edition |
| `scripts/check-output.sh DIR` | the built site | see the next section |
| `scripts/check-site-artifact.sh DIR` | the built site | what Cloudflare Pages would treat as code or routing: `_worker.js`, a root `functions/` folder, a `_routes.json` or `_headers` that differs from the committed one, a `_redirects` line that is not an internal 301 or 302 rule |
| `python3 -I scripts/check-budget.py DIR` | the built site | a page, image, stylesheet, font or script over its size limit (table below) |
| `python3 -I scripts/browser-gate.py DIR` | the built site, in Chrome | overflow, console errors, blocked or failed requests, axe-core violations, slow LCP, layout shift, small tap targets, bad keyboard order. See [Accessibility](Accessibility.md) and [Performance](Performance.md). |
| `scripts/check-wording.sh` | every tracked file | the short form of cryptocurrency anywhere in the repository |
| `scripts/check-license.sh` | the license files | a `LICENSE` that is not the official Apache-2.0 text, or a missing content license or brand notice |
| `scripts/check-brand-assets.sh` | `brand/approved-assets.txt` and the tree | an image or font that is not listed with a matching sha256, a listed file that is missing, a banned file name, a font without its license text |
| `python3 -I scripts/gen-tokens.py --check` | `brand/tokens.json` | `assets/css/tokens.css` that differs from a fresh generation |
| `python3 -I scripts/check-contrast.py assets/css/tokens.css` | the tokens | a text pair under 4.5:1 or a focus ring under 3:1 |
| `scripts/gen-support-qr.sh --check --decode` | `data/support.yaml` | QR files that differ from a fresh encoding, or that do not decode to the address |
| `python3 -I scripts/check-content.py` | the Markdown and images a change touches under `content/` | front matter, alt text, tags, unsafe links, TODO markers and image rules. See [Writing a post](Writing-a-post.md) |
| `python3 -I scripts/check-wiki.py` | `README.md` and `docs/wiki/` | a link or repository path that does not exist, an em dash, a private path, a plain-HTTP URL, a missing wiki page |
| `python3 -I scripts/check-launch-seo.py <dir> <host>` | a built production-mode output (run by hand before the apex cutover; `scripts/test-check-launch-seo.sh` tests it in CI) | a standalone noindex or none directive in a robots meta or in an `X-Robots-Tag` header in `_headers` (a valued directive such as `max-image-preview: none` is allowed), a `robots.txt` that disallows all (or Googlebot or Bingbot) or has no `Sitemap:` line, a sitemap or canonical on another host, a missing or repeated title or description, a page with no canonical, a missing `_redirects` map |

## What `check-output.sh` fails on

It reads the built files, not the sources. Among its rules:

- Any `<script>` element other than a page's own pinned script, any inline
  script, `javascript:` URL, `<style>` element, `style=` attribute or `on*=`
  event handler.
- A fourth script file, or a script of 1 KB gzip or more; a `/search/` page of
  40 KB gzip or more.
- Any plain-HTTP reference, any external asset in HTML, an external `@import` or
  `url()` in CSS or SVG, an `xml-stylesheet` instruction, a `<base>` element.
- A weak Content Security Policy, a `_headers` that is not the `/*` block plus
  the one `/css/*` long-cache block, a missing `nosniff`, a missing long-cache block,
  and a file under `/css/` that is not named by its own sha256.
- A file of a type that is not on the allowlist (including one with no
  extension), and a `copy.js`, `search.js` or `share.js` whose sha256 differs from its
  committed `.sha256` file.
- A feed, sitemap or `*.xml` that does not parse; a missing `_redirects`.
- Any alias in the build without its 301 line. The checker derives the alias
  list from the built pages.
- `robots.txt` and the noindex tags disagreeing, or the wrong environment for
  `EXPECT_ENV`.
- A home page, post or journal entry missing its description, canonical link,
  icon, Open Graph or Twitter card tags, or two pages sharing one description.
- An image carrying EXIF, XMP or IPTC metadata
  (`scripts/check-image-metadata.py`).
- Structured data that is not a data block: the one allowed script-element form
  is `<script type="application/ld+json">`, which must be valid JSON, use the
  schema.org context and carry no personal-detail keys
  (`scripts/check-seo.py`).
- Landmark and structure problems (`scripts/check-landmarks.py`: a skip link
  first, one header, one main).

URLs are judged after character references are decoded, attributes are read
quote-aware (a `>` or `=` inside a quoted value is text), and the same rules
apply to `.svg`, `.xml` and `.xhtml` outputs.

## The size budget

`scripts/check-budget.py` measures the built site without fetching or running
anything. Text types are measured gzip -9 (the host compresses them); WebP, PNG
and fonts are measured as stored. Where the browser chooses, the upper bound
counts. To change a limit, edit `LIMITS` in the script and the table in
`docs/performance-gates.md` in one commit.

| Rule | Limit |
| --- | --- |
| `js-count`, `js-name`, `js-page` | Only the hash-pinned scripts, each only on its own page or page pattern |
| `js-size` | 1 KB gzip per script |
| `css-count`, `css-size` | One stylesheet per page, 20 KB gzip |
| `font-count`, `font-size` | At most 2 font files per page, each 30 KB transferred |
| `html-size` | 15 KB gzip per page |
| `image-size` | 120 KB per image an `<img>` loads |
| `image-file-size` | 300 KB per image file anywhere in the build |
| `page-total` | 150 KB cold transfer per page |
| `post-no-images` | 80 KB for a post page without its body images |

Details, the fixed weight every post pays and the history of each limit are in
`docs/performance-gates.md`.

## The tests of the checks

Every `scripts/test-*.sh` pairs with a check or a feature. The ones to read:

- `scripts/test-check-output.sh`: a pool of cases, each building a small site with
  one rule broken and requiring the matching finding.
- `scripts/test-check-site-artifact.sh`, `scripts/test-check-budget.sh` and
  `scripts/test-browser-gate.sh`: the same idea for the artifact, budget and
  browser checks (the browser gate test uses fixture sites from
  `scripts/fixture-site.py`).
- `scripts/test-check-content.sh`: a fixture for each post and image rule, passing and
  failing, plus hostile front matter, a huge file and non-UTF-8 input.
- `scripts/test-author.sh`: the authoring helper (`scripts/author.py`): slugs, dates,
  tags, collisions, path and symlink safety, and a created page that passes the content check.
- `scripts/test-check-wiki.sh` and `scripts/test-check-wording.sh`: the guard
  tests for the documentation checks. A guard test collects loosely, asserts
  strictly (it requires that something was found) and includes a case that
  proves the guard fails when it should.
- `scripts/test-gate.sh`: tests `scripts/gate.sh` itself.

## The other test scripts

| Script | What it proves |
| --- | --- |
| `scripts/test-pages.sh` | The Support, About and Privacy pages, the `/contact/` redirect, wallet addresses and QR files. |
| `scripts/test-comments.sh` | Archived comments from the old site (`data/comments/`) render under their posts. |
| `scripts/test-redirects.sh` | The `_redirects` file grammar and line shape. |
| `scripts/test-head.sh` | Head tags and `rel=me` links against hostile front matter. |
| `scripts/test-social-products.sh` | The Social tiles and the Products disclosure, items and affiliate links. |
| `scripts/test-resume.sh` | The Resume page and its print stylesheet. |
| `scripts/test-llms.sh` | The `/llms.txt` shape. |
| `scripts/test-featured-image.sh` | The headline image slot, see [Headline images](Headline-images.md). |
| `scripts/test-archetype.sh` | `hugo new content` makes a post that builds and passes the checks, and a missing alt text fails. |
| `scripts/test-migration.sh` | Converter output builds with this site's layouts. See [Migrating from WordPress](Migrating-from-WordPress.md). |
| `scripts/test-deploy-sparse.sh` | The deploy job's sparse checkout lists every file its scripts need. |
| `scripts/test-pin-script.sh` | The pinned-script hash tool. |
| `scripts/test-smoke-site.sh`, `scripts/test-verify-live.sh` | The post-deploy smoke check and the live-host verifier, against a local fake server. |
| `scripts/test-analytics.sh` | The page-view collector (not deployed): `node --test` and the SQL, all local. |

## Adding a check

1. Write the check and its test, with a negative case, in the same pull request.
2. Add the check to the right job in `.github/workflows/ci.yml` and the test to
   the job that runs tests.
3. Add both to `scripts/gate.sh` so the local gate stays in step with CI.
4. Never narrow, skip or weaken a check to get green. If a check is wrong, fix
   it in its own change and say so in the issue.
