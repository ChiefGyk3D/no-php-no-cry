# no-php-no-cry

chiefgyk3d.com without WordPress: a static site and work journal built with Hugo.

Staging at test-blog.chiefgyk3d.com until it replaces the apex domain.

Status: scaffold. Content is synthetic placeholder text; design tokens are
placeholders (brand spec: issue #2). See issue #1 for the plan.

## Build locally

Hugo version: the one in `.hugo-version` (standard edition, not extended).
CI installs the same release and verifies its sha256 first.

Install it once under `~/.local/share/no-php-no-cry-dev/` (not as root):

```sh
V="$(cat .hugo-version)"
D="$HOME/.local/share/no-php-no-cry-dev"
mkdir -p "$D/dl" "$D/hugo-$V" && cd "$D/dl"
gh release download "v$V" -R gohugoio/hugo -p "hugo_${V}_linux-amd64.tar.gz" -p "hugo_${V}_checksums.txt" --clobber
grep " hugo_${V}_linux-amd64.tar.gz\$" "hugo_${V}_checksums.txt" | sha256sum -c -
tar -xzf "hugo_${V}_linux-amd64.tar.gz" -C "$D/hugo-$V"
ln -sfn "$D/hugo-$V/hugo" "$D/hugo"
```

Then, from the repository root:

```sh
H="$HOME/.local/share/no-php-no-cry-dev/hugo"
"$H" server                      # live preview
"$H" --minify --gc               # production build into public/
scripts/check-hugo-version.sh "$(cat .hugo-version)"   # pinned standard edition only
scripts/check-output.sh public   # see the rules below
scripts/test-check-output.sh     # negative tests for the checker
scripts/test-check-hugo-version.sh
scripts/test-wxr2hugo.sh        # unit tests for the WordPress converter
```

`check-output.sh` fails the build output on any of: a `<script>` element at all
(`script-src` is `'none'`, so a script needs a CSP change and a reviewed
allow-list first; inline scripts are also reported separately), `<style>`,
`style=` attributes, `on*=` handlers, `http://` references, external assets in
HTML, an external `@import` or `url()` (including `//host`) in CSS or SVG, an
`xml-stylesheet` instruction in a feed or SVG, a missing `_redirects`, feed or
`_headers`, a weak CSP, and any alias in the build without its 301 line.

`shellcheck` and `shfmt -i 4 -ci` must pass on `scripts/*.sh`.

## Layout

```
.hugo-version            pinned Hugo release
hugo.toml                site config, output formats (RSS, _redirects)
content/posts/           posts, one leaf page bundle each (index.md + images)
content/journal/         work journal, a separate section
assets/css/              tokens.css (placeholders) and main.css, via Hugo Pipes
layouts/                 templates written from scratch
layouts/_markup/         image render hook (srcset, width/height, lazy, alt required)
layouts/home.redirects   builds public/_redirects from page aliases
static/_headers          Cloudflare Pages headers (strict CSP)
scripts/                 check-output.sh, check-hugo-version.sh and their tests
tools/wxr2hugo/         WordPress export to Hugo page bundles, with a scrub pass
.github/workflows/ci.yml build job, shared shell and security workflows, CI green gate
```

Front matter on every page: `title`, `date`, `draft`, `slug`, `categories`,
`tags`, `syndicate` (boolean, default true). Old WordPress permalinks go in
`aliases`; the build writes a 301 line for each into `public/_redirects`
(Cloudflare Pages), and Hugo's meta-refresh pages cover GitHub Pages. A
directory-style alias (`/2023/02/10/sample-post/`) gets two lines, with and
without the trailing slash; an alias ending in `.html` (`/sample-post.html`)
gets exactly one. The checker derives the alias list from the built pages, so
a missing line fails the build.

Images go beside `index.md` in the bundle and are referenced with Markdown
(`![alt text](file.png)`). Alt text is required, JPEG and PNG only.

## Raw WordPress material is never committed

Exports, database dumps, crawls, `wp-config*`, unscrubbed drafts and commenter
data stay outside the repository. `.gitignore` blocks the usual names
(`import/`, `raw/`, `*.wxr`, `*.sql`, archives), but the rule is the rule even
where the ignore list has no pattern: only scrubbed, reviewed content is added
under `content/`.

## Converting the WordPress export

`tools/wxr2hugo/` turns a WXR export into page bundles (Python 3 standard
library only). The export, the terms file and the output stay outside the
repository, and the tool refuses a path inside it.

```sh
python3 -I tools/wxr2hugo/convert.py --wxr PATH/export.xml --out DIR \
    [--scrub-terms FILE] [--site-url URL] [--media DIR]
```

It writes `posts/<slug>/index.md`, `pages/<slug>/index.md` (images and
`comments.json` beside them), `permalink-map.json` and `decision-log.json`
(every `amzn.to` link, kept, no disclosure added). Drafts get `draft: true`.
Only approved comments are kept, and ActivityPub items are dropped. Links to the
old temporary Bluehost domain are rewritten to `--site-url`; builder pages take
their text from the builder JSON.

The scrub pass checks the output for callsign and grid-square shapes, plus the
`employer`, `hostname` and `serial` terms from `--scrub-terms` (one
`category:term` per line; `allow:TOKEN` exempts a false positive). A finding
prints its category, file and line only, exits 3 and writes nothing. Exit 2 is a
refused path or bad terms file.
