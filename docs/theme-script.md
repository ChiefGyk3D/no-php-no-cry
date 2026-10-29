# The theme script is pinned by hash

`/theme.js` is the only script the site ships (`script-src 'self'`, under 1 KB
gzip, built from `static/theme.js`). `'self'` allows every same-origin response,
so the build is held to one reviewed file instead of an inspection of its code:

- The committed file `theme.js.sha256` (repository root) holds one line, the
  sha256 of the script in `sha256sum` format: `<64 lowercase hex>  theme.js`.
- `scripts/check-output.sh`, `scripts/check-site-artifact.sh` and the post-deploy
  `scripts/smoke-site.sh` accept `/theme.js` only if its sha256 equals that
  line. The smoke check also hashes the bytes the live site serves.
- With no `theme.js.sha256`, no script is allowed: any `<script>` element and
  any `.js`, `.mjs` or `.cjs` file fails the build.
- The script must stay under 1 KB gzip, appear once per page as
  `<script src=/theme.js></script>`, and the build may hold only the listed
  non-script file types (`scripts/artifact-rules.sh`). `_headers` must be one
  `/*` block with no removal directive and exactly one `nosniff`.

## Changing the script

1. Edit `static/theme.js`.
2. Run `scripts/pin-theme.sh`. It refuses a script of 1 KB gzip or more and
   writes `theme.js.sha256`. (`scripts/pin-theme.sh --check` verifies it.)
3. Commit both files in the same pull request. The hash change is what a
   reviewer reads: the diff of `static/theme.js` is the reviewed code, and the
   checks fail if the two drift apart.
