# The copy script is pinned by hash

(This was the theme script until issue 95. No theme toggle exists, so the one
allowed-script slot now holds the /support/ Copy-button script. Issue 82 may
still tighten `script-src` to 'none' if that script is ever dropped.)

`/copy.js` is loaded by `/support/` only (`layouts/support/single.html`). It
reveals the page's Copy buttons (hidden without script), copies the address text
with `navigator.clipboard` or a textarea fallback, and writes "Copied" into a
`role=status` region. The address stays visible, selectable text either way.

`/copy.js` is the only script the site ships (`script-src 'self'`, under 1 KB
gzip, built from `static/copy.js`). `'self'` allows every same-origin response,
so the build is held to one reviewed file instead of an inspection of its code:

- The committed file `copy.js.sha256` (repository root) holds one line, the
  sha256 of the script in `sha256sum` format: `<64 lowercase hex>  copy.js`.
- `scripts/check-output.sh`, `scripts/check-site-artifact.sh` and the post-deploy
  `scripts/smoke-site.sh` accept `/copy.js` only if its sha256 equals that
  line. The smoke check also hashes the bytes the live site serves.
- With no `copy.js.sha256`, no script is allowed: any `<script>` element and
  any `.js`, `.mjs` or `.cjs` file fails the build.
- The script must stay under 1 KB gzip, appear once per page as
  `<script src=/copy.js></script>`, and the build may hold only the listed
  non-script file types (`scripts/artifact-rules.sh`). `_headers` must be one
  `/*` block with no removal directive and exactly one `nosniff`.

## Changing the script

1. Edit `static/copy.js`.
2. Run `scripts/pin-script.sh`. It refuses a script of 1 KB gzip or more and
   writes `copy.js.sha256`. (`scripts/pin-script.sh --check` verifies it.)
3. Commit both files in the same pull request. The hash change is what a
   reviewer reads: the diff of `static/copy.js` is the reviewed code, and the
   checks fail if the two drift apart.
