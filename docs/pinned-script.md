# The two pinned scripts

(The theme toggle script is gone: the brand is dark only. Issue 82 decided to
keep `script-src 'self'` while a script ships; `'none'` follows if the last one is
dropped. Issue 119 added the second script, for search, on the owner's ruling of
2026-11-06: two pinned scripts, each on its own page only.)

(Issue 220 added the third, for the share links under posts, on the owner's
ruling of 2026-11-08: it loads on posts and journal entries, which the allowlist
names as patterns.)

The site ships exactly three scripts:

| Script | Page | What it does |
| --- | --- | --- |
| `/copy.js` | `/support/` (`layouts/support/single.html`) | Reveals the Copy buttons (hidden without script), copies the address text with `navigator.clipboard` or a textarea fallback, and writes "Copied" into a `role=status` region. The address stays visible, selectable text either way. |
| `/search.js` | `/search/` (`layouts/search/list.html`) | Enables the search box (its input is disabled without script) and filters the page's own list in place. See "Search" below. |
| `/share.js` | Every post and journal entry (`layouts/_partials/share.html`; `posts/*/index.html` and `journal/*/index.html`, one path segment for `*`) | Un-hides the share buttons that need script (copy a link; Mastodon, whose server is per user), copies with `navigator.clipboard`, and for Mastodon asks for the server once and keeps it in `localStorage`. See `docs/share-links.md`. |

`/copy.js` and `/search.js` make no network request, store nothing, set no
cookie and read nothing beyond their own page. `/share.js` makes no request
either and sets no cookie; its one exception to "stores nothing" is the
Mastodon server name the visitor types, kept in `localStorage` under
`mastodonServer` on this site only and never sent anywhere by this site. The
allowlist, script -> its allowed page(s), is `PINNED_SCRIPTS` in
`scripts/artifact-rules.sh`; the build checks read it, so a fourth script, or
any script on another page, fails the build.

`script-src 'self'` allows every same-origin response, so the build is held to
these reviewed files instead of an inspection of their code:

- Each script has a committed hash file at the repository root, one line, the
  sha256 of the script in `sha256sum` format: `copy.js.sha256` holds
  `<64 lowercase hex>  copy.js` and `search.js.sha256` holds
  `<64 lowercase hex>  search.js`.
- `scripts/check-output.sh`, `scripts/check-site-artifact.sh` and the post-deploy
  `scripts/smoke-site.sh` accept a script only if its sha256 equals the line in
  its own hash file. The smoke check also hashes the bytes the live site serves.
- With no hash file for a script, that script is not allowed: its `<script>`
  element and its file fail the build. Any other `<script>` element and any other
  `.js`, `.mjs` or `.cjs` file fails too.
- Each script must stay under 1 KB gzip, appear at most once and only on its own
  page, as `<script src=/copy.js></script>` or `<script src=/search.js></script>`
  (the form Hugo's minifier writes). The same tag on any other page is
  `script-wrong-page`. The build may hold only the listed non-script file types
  (`scripts/artifact-rules.sh`). `_headers` must be one `/*` block with no
  removal directive and exactly one `nosniff`.
- The CSP carries `script-src 'self' https://static.cloudflareinsights.com/beacon.min.js` and `connect-src 'self'`, exactly: the beacon URL and `'self'` are the only entries Cloudflare's Web Analytics FAQ requires for automatic injection (issue 159). The beacon is injected at the edge, never in built HTML, so the allowlist above is unchanged and any other `<script>` element still fails. No `unsafe-inline`, no wildcard, no other host.
  No inline script, no event-handler attribute, no `style` attribute, and no
  `<form>` (`form-action 'none'`): the search box is a `<div role="search">`.

## Search

`/search/` is a plain browse page first. Hugo renders every regular page of
`posts` and `journal`, A to Z by title, as `<li>` entries (link, date, summary,
tag text) plus the tag link row also used on `/posts/`. With JavaScript off that
is the whole page, and it is useful as it stands.

`static/search.js` (ES5, no dependencies, under 1 KB gzip; the readable source is
the reviewed code) then:

1. enables the input of the `<div role="search">`, which is on the page from first paint with a visible label and a disabled input, so enabling it moves nothing (without script a note says filtering needs JavaScript);
2. on each keystroke lowercases the query, splits it on whitespace and requires
   every token to appear in an `<li>`'s text (AND); `li.hidden` is toggled and a
   group with no visible entry is hidden;
3. writes "N results" (or "1 result", or a short no-match message that suggests another word or a tag) into a `role=status`,
   `aria-live=polite` region, and nothing for an empty query;
4. reads an initial `?q=` from the address (a link only; nothing is ever
   submitted or written back), and Escape clears the box.

No storage, no cookies, no network. Because the list is part of the page, there
is no JSON index and no `fetch`.

The search page's HTML has its own budget, `search-page-budget` in
`scripts/check-output.sh`: under 40 KB gzip. It lists every entry, so it grows
with the site; at the limit the build fails with a message to revisit the
approach (for example, paginate the list, or move to an index file, which would
need `connect-src 'self'` and a new decision). Today the page is a fraction of
that.

## Changing a script

1. Edit `static/copy.js`, `static/search.js` or `static/share.js`.
2. Run `scripts/pin-script.sh` (both scripts) or `scripts/pin-script.sh
   static/search.js` (one). It refuses a script of 1 KB gzip or more and writes
   `<name>.sha256`. (`scripts/pin-script.sh --check` verifies them.)
3. Commit the script and its hash file in the same pull request. The hash change
   is what a reviewer reads: the diff of the script is the reviewed code, and the
   checks fail if the two drift apart.

## Adding another script

Not without a new owner decision. It is: an entry in `PINNED_SCRIPTS`, a hash
file (named in the sparse list of the deploy job in
`.github/workflows/deploy.yml`; `scripts/test-deploy-sparse.sh` reads the
allowlist and fails if it is missing), fixtures in `scripts/test-check-output.sh`,
`scripts/test-check-site-artifact.sh` and `scripts/test-smoke-site.sh`, and this
page. A page field with `*` or a comma list is a set of patterns; `*` is exactly
one path segment (`pinned_script_on_page` in `scripts/artifact-rules.sh`).
