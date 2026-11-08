# Search and tags

Search is a page you can use without JavaScript. The script, when it runs, only
makes it faster.

## Tags and categories

- Front matter: `categories` is one broad topic (for example `["Linux"]`),
  `tags` are a few specific words. Reuse existing ones before adding new ones.
- Both are Hugo taxonomies (`[taxonomies]` in `hugo.toml`). Each tag and each
  category gets a term page that lists its posts and journal entries, grouped by
  year, newest first, using the same archive template as `/posts/`
  (`layouts/_partials/archive.html`).
- The taxonomy index pages (`/tags/`, `/categories/`) are turned off
  (`disableKinds = ["taxonomy"]`), so nothing links to a bare list of all tags.
- A post shows its tags as `#tag` links under the title.

## The Search page

`/search/` (`layouts/search/list.html`, `content/search/_index.md`) is, first, a
browse page: every regular page of the posts and journal sections, A to Z by
title, with its date, summary and tag text. With JavaScript off that is the whole
page and it is useful as it stands. A note tells the reader that filtering needs
JavaScript.

The search box is on the page from the first paint with a visible label and a
disabled input, so enabling it moves nothing.

## Browse by tag

`layouts/_partials/tag-row.html` writes a collapsed native `<details>` ("Browse
by tag (N)"), no script. Inside: the 12 most used tags first, highest count
first, each with its count; the rest sit behind a nested "Show N more" section,
A to Z. Every tag links to its term page.

## The pinned script

`static/search.js` is ES5, has no dependencies and is under 1 KB gzip. It:

1. enables the input;
2. on each keystroke lowercases the query, splits it on whitespace and keeps an
   entry only if every word appears in its text (AND), hiding groups with no
   visible entry;
3. writes "N results", "1 result" or a short no-match message into a
   `role="status"`, `aria-live="polite"` region, and nothing for an empty query;
4. reads an initial `?q=` from the address (a link only; nothing is submitted or
   written back) and clears the box on Escape.

It makes no request, stores nothing and sets no cookie. There is no JSON index
and no `fetch`, because the list is part of the page.

### How a script is allowed

The Content Security Policy says `script-src 'self'`, and `'self'` allows every
same-origin file, not one. So the build holds the site to three reviewed scripts,
`/copy.js` (Support), `/search.js` (Search) and `/share.js` (posts and journal
entries):

- each has a committed hash file at the repository root, `search.js.sha256`,
  `copy.js.sha256` and `share.js.sha256`, and the build checks accept the script only if its sha256
  matches;
- each may appear only on its own page (`/share.js` on any post or journal
  entry), once, in the form
  `<script src=/search.js></script>`; the same tag elsewhere is
  `script-wrong-page`;
- the allowlist is `PINNED_SCRIPTS` in `scripts/artifact-rules.sh`.

To change a script: edit it, run `scripts/pin-script.sh`, and commit the script
and its hash file together. The reviewer reads the script diff, and the checks
fail if the two drift apart. The full rules are in
`docs/pinned-script.md`.

### Page budget

The Search page lists every entry, so its HTML grows with the site. It has its own
budget in `scripts/check-output.sh`: under 40 KB gzip. At the limit the build
fails with a message to revisit the approach.

## Tests

`scripts/test-pages.sh` covers the pages including Search, and
`scripts/test-check-output.sh` holds the script and hash negative cases.
`scripts/test-pin-script.sh` tests the pinning script.
