# no-php-no-cry

chiefgyk3d.com without WordPress: a static site and work journal built with Hugo.

Staging at test-blog.chiefgyk3d.com until it replaces the apex domain.

Status: scaffold. Content is synthetic placeholder text; design tokens are
placeholders (brand spec: issue #2). See issue #1 for the plan.

## Build locally

Hugo version: the one in `.hugo-version` (standard edition, not extended; no
WebP). CI installs the same release and verifies its sha256 first.

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
scripts/check-output.sh public   # fails on inline script/style, third-party refs, missing _redirects/feed/_headers
scripts/test-check-output.sh     # negative tests for the checker
```

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
scripts/                 check-output.sh and its negative test
.github/workflows/ci.yml build job, shared shell and security workflows, CI green gate
```

Front matter on every page: `title`, `date`, `draft`, `slug`, `categories`,
`tags`, `syndicate` (boolean, default true). Old WordPress permalinks go in
`aliases`; the build writes a 301 line for each into `public/_redirects`
(Cloudflare Pages), and Hugo's meta-refresh pages cover GitHub Pages.

Images go beside `index.md` in the bundle and are referenced with Markdown
(`![alt text](file.png)`). Alt text is required, JPEG and PNG only.

## Raw WordPress material is never committed

Exports, database dumps, crawls, `wp-config*`, unscrubbed drafts and commenter
data stay outside the repository. `.gitignore` blocks the usual names
(`import/`, `raw/`, `*.wxr`, `*.sql`, archives), but the rule is the rule even
where the ignore list has no pattern: only scrubbed, reviewed content is added
under `content/`.
