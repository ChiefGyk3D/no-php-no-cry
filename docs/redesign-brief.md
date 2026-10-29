# Redesign brief: chiefgyk3d.com

Issue: ChiefGyk3D/no-php-no-cry#41. Status: maintainer decisions recorded 2026-10-29 (section 13); the issue list
in section 12 awaits approval. Written 2026-10-29. Docs only; no site code changes.

Inputs: the baseline (`docs/baseline-chiefgyk3d-com.md`, PR #43), the stream
asset review (images viewed by eye, kept outside the repo), the Reach Around
design doc and `dark-hero` preset, this repo's layouts, tokens, headers and
checks, and the decisions on #2, #11, #12 and #40.

## 0. Decisions already made (not reopened here)

- Baseline keep/rewrite/drop proposals accepted (#40).
- Affiliate links move to one products page with a disclosure at the top;
  posts keep their prose.
- The TikTok open letter stays as a dated archive: original date kept, short
  note that it is a record.
- YouTube is added to the social hub. X/Twitter is left out.
- One shared token file for colors and type, shared with Reach Around. The blog
  and Reach Around link to each other. The media kit stays only in Reach Around;
  the blog links out to it (#12).
- Jost stays the interim body font. The wordmark is built from the existing
  artwork as an image, not a webfont (#2).
- Accent `#FBB03B`, dark first.
- The eight answers of 2026-10-29 are recorded in section 13 and applied through
  the rest of this brief. The theme toggle (decision 4) changes the CSP, which
  this brief earlier kept unchanged.

## 1. Goals and audience

Goals, in order:

1. The site reads as the same brand as the stream, the banners and Reach Around
   within one second of landing: orange on near-black, the mascot, HUD frames.
2. Replace WordPress with a static site that makes zero third-party requests
   (baseline: 35 scripts, Google Fonts, Tag Manager and Jetpack stats today).
3. Make the person findable: every network in one place, verifiable identity
   links, posts that announce themselves on the networks (#11).
4. Keep the writing front and center. The 10 posts are the content; the design
   frames them and does not compete.

Audience, from the baseline content and the maintainer's platforms:

- Stream and community regulars arriving from Twitch, Kick, YouTube or Discord
  who want links and the schedule-adjacent facts. Mostly phones.
- Fediverse and Bluesky readers following a post link. They arrive on a single
  article and judge the site by its reading view.
- Open-source and security peers checking projects (Stream Daemon and the
  others). They look at GitHub and read the technical posts.
- Search visitors landing on the three older gear posts. They need the products
  page and its disclosure to be obvious, not hidden.

The primary device is a phone. Design at 360 px first, then widen.

## 2. Brand principles (from the assets)

Observed in the reviewed files (palette numbers measured, not estimated):

- Orange `#FBB03B` on near-black. The accent is the exact modal saturated pixel
  in the mascot and matches Reach Around. Shade `#AF6A0E` appears in shading.
- Black is deep (banners are `#080808`; the web page stays `#0E0E0E`, warmer and
  already in the tokens, see section 6).
- Carbon-fiber: fine diagonal stripes on charcoal (`#181818` to `#383838`).
- HUD frames: chamfered angular corner brackets with thin orange inner rules and
  dash accents; a divider bar with an orange line and angular end caps.
- Amber halo: soft glow behind the wordmark and mascot, and a dark ring behind
  centered art.
- A faint circuit-trace pattern in warm brown on black (chat panel art).
- A giant ghosted gray mascot cropped off-canvas behind small colored content.
- Shapes are hard and chamfered. No rounded corners except the mascot's sticker
  outline. Rules are 2 to 3 px orange lines or glow, never thick boxes.

Tone: hacker, tactical, anti-authoritarian, gamer-HUD, punchy, irreverent. The
copy can be dry and funny; the layout stays calm so long posts stay readable.

Rules for the site:

1. Dark first. Dark is the default; light follows the system setting when it
   says light, and a manual toggle overrides both (section 10). Light mode
   passes the same contrast rules.
2. One accent. Orange marks interaction and emphasis; it does not decorate
   every block.
3. HUD brackets frame a few key objects (hero, social tiles, products
   disclosure, archive banner). Body text never sits inside a busy frame.
4. Effects are CSS and tiny assets, and they never carry text.
5. The mascot appears in the hero, as the favicon, as a ghost layer, and in the
   footer. Only the no-star files from the approved manifest.

Avoid:

- Heavy glow and halo on every element (the banners do this; a web page cannot).
- Typing body copy or headings in the stencil wordmark face. It is logo art only.
- Third-party platform icons baked into banners, and the Twitter bird and TikTok
  mark that appear in the 1584x396 banner. Icons come from the shared CC0 set.
- The cream button plate as a general pattern. It is a one-off; light-on-dark
  stays the default. If used, it is the "light plate" variant of a bracket frame.
- Raster banners copied straight in (1 to 6 MB, low contrast for small text).
- Anything with a Star of David (excluded list in `brand/EXCLUDED.md` and the
  review notes). The rule has no exceptions.
- Callsign, grid square, hostnames or machine identifiers in any asset or text.

## 3. Information architecture and navigation

Starting point is the baseline page inventory (6 pages, 10 posts, accepted).

### Sitemap

| URL | Source | Template |
|---|---|---|
| `/` | Front Page (rewrite) | home |
| `/posts/` | Blog (dropped; the Hugo posts list replaces it, 301 from `/blog/`) | archive |
| `/posts/<slug>/` | 10 posts, with the 15 legacy aliases redirected | post |
| `/products/` | Recommended Products (was external `links.` subdomain) plus the 22 affiliate links from posts | products |
| `/social/` | Social Media Links (rewrite, adds YouTube) | social hub |
| `/support/` | Support My Work (refresh, recheck links) | page (link list) |
| `/about/` | new; folds in the Contact content as a `#contact` section | about |
| `/contact/` | not a page: 301 to `/about/#contact` (check on staging that the host keeps the fragment; if not, redirect to `/about/`) | redirect |
| `/privacy/` | new statement (no analytics, no embeds) | page |
| `/journal/` | exists in the repo as a section | archive |
| `/tags/<tag>/`, `/categories/<c>/` | existing term pages | archive |
| `/404.html` | exists | 404 |

`/sample-page/` is dropped. The theme demo draft is dropped. The privacy draft
is replaced by a new statement.

### Primary navigation

Header, in this order: Posts, Products, Social, Support, About. Contact is the
`#contact` section of `/about/`, not a page of its own; the footer links to
`/about/#contact` (fewer top-level items on a phone). The baseline
menu had six items; this keeps every destination but merges Home (the wordmark
links home) and Contact.

On a phone the header is a wordmark plus a native `<details>` menu. No script.
A `<nav aria-label="Main">` landmark exists on every page (the baseline found
none).

Footer: Contact (`/about/#contact`), Privacy, RSS, the `rel="me"` identity row, a link to Reach
Around ("link page"), and the media kit link that points out to Reach Around.
Two-way link with Reach Around (#12): this site links to it from the header of
the social hub and the footer; Reach Around links back to the blog.

Journal: the repo has a `journal` section and a nav item today. The baseline has
no journal content. See decision 3: the nav item is hidden until the first entry exists, and the
template stays.

## 4. Page templates

Each template uses the same shell: `baseof.html`, the header, the footer, the
token stylesheet. Specific needs:

| Template | Needs |
|---|---|
| Home | Hero (wordmark image, mascot, tagline, two buttons: Latest post, Social). Latest 5 posts with date and a 2-line summary. A social strip using the icon set. A ghosted mascot layer at low opacity. No carousel. |
| Post | Single column at `--measure`. Title, date, reading time, tags. Optional `archive` front matter shows a dated archive banner (used for the TikTok letter: original date and "this is a record, not a current view"). Optional `supersededBy` front matter shows a forward link (twitch-and-toot to Stream Daemon). Code blocks use the existing highlight classes. A syndication row (section 5). Previous/next. |
| Archive | Posts list with year grouping, tag filter links (plain term pages), RSS link. Reuse for journal and term pages. |
| Products | Disclosure block first, above the fold, in a bracket frame: plain statement that links earn a commission and what that means. Items grouped by the old posts' topics (audio, 3D printing and PC repair, air quality). Each item: name, one line, price note ("price checked on <date>", no live prices), outbound link with `rel="sponsored noopener"`. The old prose stays in the posts, which link here. |
| About | Short bio, mascot, current projects with GitHub links, then a `#contact` section (heading with `id="contact"`): how to reach the maintainer without a form (Matrix and Discord links plus one text-only public address, decision 6). This is the only contact page; there is no `/contact/` template. |
| Socials hub | A tile grid, one tile per network in section 5 (nine, TikTok included). Tile = icon, network name, handle or room name, a short role line. The Matrix tile names the community room. Same data file drives the footer `rel="me"` row and the home strip. |
| Support | Link list (tips, shop) in the same tile style, with each link rechecked before publish. |
| Privacy | Plain text: no analytics, no embeds, no cookies, no third-party requests; outbound links leave the site. States the one stored item: the theme choice, kept in the browser's local storage only when the visitor uses the toggle, never sent anywhere. |
| 404 | Mascot, one line, links to Posts and Social. |

The plan keeps raw HTML in Markdown off (`unsafe = false`), so products and
socials render from data files (`data/socials.yaml`, `data/products.yaml`) and
partials, not from hand-written HTML in content.

## 5. Social integration

Constraint: `default-src 'none'`, `script-src 'self'` (one small theme file,
section 10), `img-src 'self'`, `frame-ancestors 'none'`. No embedded timelines,
no widgets, no share buttons that load a vendor script. Every integration below works with plain links and
build-time data.

### Networks (hub, footer row, home strip)

Bluesky, Mastodon, Matrix, Discord, GitHub, YouTube, Twitch, Kick, TikTok.
TikTok stays on the hub (decision 1). X/Twitter is out. Support links (Ko-fi, StreamElements, shop) live on the support page, not
the hub.

One data file, `data/socials.yaml`, with `name`, `icon` (slug), `url`, `handle`,
`rel_me` (bool), `blurb`. Handles in this file are the public handles only.

### Feeds versus links

- Links only at launch. No live feed is embedded. A third-party feed would break
  the zero-request promise and the CSP.
- The site's own RSS (home, posts, journal) stays the feed of record.
- Later option, not in the first phases: a build-time "latest on Mastodon" list
  fetched in CI from the public RSS of the maintainer's own account and written
  to a data file. It adds no runtime request, but it makes the build depend on
  a network call and publishes other people's replies if filtered badly.
  Proposed as an optional last-phase issue.

### rel=me and identity

- Footer renders `<a rel="me">` for every network that supports verification
  (the mechanism exists in `baseof.html` with `params.me`; it requires
  `https://`). Mastodon verifies a profile link by finding a `rel="me"` link
  back to the profile, and the profile must link to the site. Bluesky can use
  the domain as handle (DNS or `.well-known`); that is a separate account-side
  step, not site code.
- Replace `params.me` with a loop over `data/socials.yaml` so there is one
  source.

### Share

- No share buttons with scripts. Each post shows its canonical permalink and,
  once syndicated, links to its announcements ("Discuss on Mastodon, Bluesky").
- A plain "Share" link set is rejected: Mastodon share needs the visitor's
  instance and the others add tracking parameters.
- Open Graph and Twitter card tags exist (`head-meta.html`). Cards change from
  `summary` with a 512 px square to `summary_large_image` with a 1200x630 card
  (section 9).

### Syndication hook for #11

The deploy job in #11 announces new posts. The site's side of the contract:

- Front matter `syndicate: true|false` (default true). The deploy job reads it.
- Front matter `syndicated:` map, written back after announcing:
  `bluesky`, `mastodon`, `discord`, `matrix` keys with the announcement URL.
  The post template renders them as "Discuss" links when present.
- Where the dedupe state lives is #11's decision. The brief recommends not
  committing back to `main` from CI (branch protection and `CI green`); a state
  file on a dedicated branch or in the Doppler or Cloudflare side is the #11
  choice. The template only needs the `syndicated` map at build time, so a
  later build picks it up.
- Announcement text uses the post title, the summary and the canonical URL.
  It reuses the Open Graph description, so one writing step feeds both.

## 6. Design tokens plan (shared with Reach Around)

### Current state and measured drift

This repo's `assets/css/tokens.css` uses unprefixed names (`--bg`, `--accent`).
Reach Around's `site.css` uses `--ra-*` names. Both claim the same palette, and
they already differ (read from both sources 2026-10-29):

| Role | Blog (dark) | Reach Around (dark) |
|---|---|---|
| bg | `#0E0E0E` | `#0e0e0e` (same) |
| surface | `#181716` | `#1b1b1b` |
| text | `#F0F0F0` | `#ffffff` |
| border | `#3A3530` | `#333333` |
| accent, on-accent | `#FBB03B`, `#1A1A1A` | same |
| bg (light) | `#FAF7F2` | `#f4f1ec` |
| font | Jost, system-ui | Jost, system-ui |

The `dark-hero` example preset uses a different accent (`#ff8a3c`). It is a
preset, not the default, and must not be treated as the brand value.

### Proposal

- One canonical file: `brand/tokens.json` in this repo (the blog is the brand's
  home and holds the approved-assets manifest). It lists colors per mode, type
  families, the type scale, spacing, radius, tap size. Plain JSON so Python and
  shell can read it without a package manager.
- A small script (`scripts/gen-tokens.py`, stdlib only) generates
  `assets/css/tokens.css` here and a theme preset for Reach Around from it.
  Generated files carry a header saying so.
- Reach Around vendors a copy of `tokens.json` plus a recorded sha256, the same
  mechanism the Jost font already uses (`approved-assets.txt` notes the hash
  matches the copy in Reach Around). Its build maps the values onto its
  `--ra-*` tokens, so Reach Around keeps its names and the blog keeps its own.
- Drift check: both repos run a check that compares the vendored file's sha256
  with the canonical one fetched from the blog repo by a raw GitHub URL pinned to a
  commit SHA (`raw.githubusercontent.com/<owner>/<repo>/<full-sha>/brand/tokens.json`).
  The unpinned default-branch form (`.../main/...`) is not used: it moves, so the
  check would not be reproducible. Bumping is a deliberate re-pin PR in Reach
  Around that changes the SHA and the recorded sha256 together. Per the standing rule that anything two repos need goes to GYST, the
  check is a candidate for a GYST reusable check; the first version can be a
  local script and move to GYST when the second repo adopts it.
- The shared icon set is Reach Around's `static/icons/` (Simple Icons, CC0).
  The blog copies the nine needed icons and records them in
  `approved-assets.txt` with the source hash.

### Palette (proposed canonical values)

The blog's current values are canonical (decision 5), since they were chosen
with the contrast check and the warm-neutral light mode. Reach Around adopts
them through the checksum-vendored `brand/tokens.json` (issue 4). Additions for the
redesign (new tokens, dark mode):

| Token | Value | Use |
|---|---|---|
| `--carbon-base` | `#181818` | carbon-fiber ground |
| `--carbon-line` | `#282828` | carbon-fiber stripe |
| `--plate` | `#281808` | warm brown panel, circuit fill |
| `--accent-deep` | `#AF6A0E` | shading, decorative edges only (not text) |
| `--ghost` | `#383838` | ghosted mascot layer |
| `--plate-light` | `#FFEFD9` | the cream "light plate" variant (section 2); text and focus use `#8A5A00` on it |

### Contrast, computed

Computed with the repo's own formula (same math as `scripts/check-contrast.py`)
on 2026-10-29. The existing script run on today's tokens passes all 32 pairs.
New pairs, dark mode unless noted:

| Pair | Ratio | Verdict |
|---|---|---|
| text `#F0F0F0` on bg `#0E0E0E` | 16.94 | pass (existing) |
| link/accent `#FBB03B` on bg `#0E0E0E` | 10.46 | pass (existing) |
| link/accent on surface `#181716` | 9.70 | pass (existing) |
| link/accent on `#080808` | 10.85 | pass |
| accent on carbon `#282828` | 7.99 | pass |
| muted `#B5ADA2` on carbon `#282828` | 6.64 | pass |
| text on carbon `#282828` | 12.94 | pass |
| `#1A1A1A` on accent (button) | 9.43 | pass (existing) |
| `#1A1A1A` on cream plate `#FFEFD9` | 15.42 | pass |
| `#8A5A00` on cream plate `#FFEFD9` | 5.25 | pass |
| `#AF6A0E` on cream plate `#FFEFD9` | 3.80 | fail as text; decorative only |
| `#FBB03B` on cream plate `#FFEFD9` | 1.64 | fail; never on the cream plate |
| `#AF6A0E` on bg `#0E0E0E` | 4.4959 (shows as 4.50 rounded) | fail as text (below 4.5); decorative use only |
| `#888888` on bg | 5.45 | pass (secondary icon use) |
| `#585858` on bg | 2.71 | fail as text; ghost layer only |
| accent `#FBB03B` on light bg `#FAF7F2` | 1.73 | fail; light mode keeps `#8A5A00` (5.55) |

Every number in this section was recomputed on 2026-10-29 in a script that
imports `ratio()` from `scripts/check-contrast.py`, not copied from a tool or an
earlier draft. `#AF6A0E` (`--accent-deep`) is below 4.5 on every surface listed
here (bg 4.50 rounded down from 4.4959, surface 4.17, carbon 3.43, plate 3.99,
cream 3.80), so it stays out of text and out of the checker's text pairs.

The toggle adds no colors: its two states (forced dark, forced light) use the
same two token sets, so the existing 32 pairs (16 per mode, rerun 2026-10-29
with `scripts/check-contrast.py`, all pass) cover them. The toggle control
itself is new UI. Computed with the same formula:

| Toggle pair | Ratio | Verdict |
|---|---|---|
| control border/icon `#FBB03B` on bg `#0E0E0E` (dark) | 10.46 | pass, needs 3:1 |
| control border/icon `#8A5A00` on bg `#FAF7F2` (light) | 5.55 | pass, needs 3:1 |
| control label text on bg, dark / light | 16.94 / 16.29 | pass |
| `#1A1A1A` on accent (pressed fill, either mode) | 9.43 | pass |
| focus ring on bg, dark / light | 10.46 / 5.55 | pass, needs 3:1 |

The token generator emits the light set twice from one source: once under
`@media (prefers-color-scheme: light)` for `:root:not([data-theme])`, and once
under `:root[data-theme="light"]`; `:root[data-theme="dark"]` pins dark. The
contrast script must read all three blocks, or a hand-edited copy could drift.

The check script must grow with each new token pair (`carbon-line` on text,
`plate` on text, muted on carbon), or the new tokens ship unchecked. Proposed
issue: extend `PAIRS` in `check-contrast.py` (including the toggle pairs above, the focus pairs for carbon, plate and cream plate, and the
`data-theme` blocks) and read the generated tokens.
Focus ring stays 3:1 minimum against every surface it can sit on. Today's
`PAIRS` check `focus` only against `bg` and `surface`, so the additions below are
required, not optional. Same formula, 2026-10-29:

| Focus pair (need 3:1) | Ratio | Verdict |
|---|---|---|
| focus `#FBB03B` on `--carbon-base` `#181818` (dark) | 9.62 | pass |
| focus `#FBB03B` on `--carbon-line` `#282828` (dark) | 7.99 | pass |
| focus `#FBB03B` on `--plate` `#281808` (dark) | 9.29 | pass |
| focus `#FBB03B` on `--ghost` `#383838` (dark) | 6.35 | pass (no control sits on the ghost layer; listed so none can) |
| focus `#8A5A00` on cream plate `#FFEFD9` | 5.25 | pass |
| focus `#FBB03B` on cream plate `#FFEFD9` | 1.64 | fail |
| focus `#8A5A00` (light) on carbon `#181818` / `#282828` / plate `#281808` | 3.00 / 2.49 / 2.89 | fail or marginal |

Rules that follow: carbon and plate are dark-mode surfaces only (the light set
does not render them), and the cream plate always uses `#8A5A00` for its focus
ring and link text in either mode. The checker gets `focus` on `carbon-base`,
`carbon-line`, `plate` and `ghost` (dark) and a `focus-on-plate` pair of
`#8A5A00` on `#FFEFD9` (new token `--plate-light`), all at 3.0. A control on a
surface with no checked pair is a build failure, not a judgment call.

## 7. Typography

- Body: Jost, self-hosted variable woff2, 26.6 KB, `font-display: swap`, CSP
  `font-src 'self'`. Interim, per #2. Keep the system fallback stack.
- Headings: Jost at heavier weight and tight tracking for h1 and h2; an
  uppercase, letter-spaced label style for nav, tile labels and meta. Uppercase
  Jost with wide tracking approximates the terminal-gag banners without a new
  font.
- Mono: `ui-monospace` stack for code, `<time>` and meta lines, to carry the
  hacker tone at no cost.
- Wordmark: an image. It is the white block-letter logo with orange cut-out
  accents, taken from existing artwork (section 9). Never retyped in HTML or
  CSS. The text "ChiefGyk3D" stays in the DOM as the link's accessible name and
  as the `<title>` text.
- Scale: reuse the Reach Around scale (1.25 ratio, `clamp()` for large steps)
  so type moves together across both. Body is 1.125rem at 1.6 line height in
  the blog; Reach Around uses 1.5. Pick the blog value for long reading and let
  each repo keep its own line height; only family, scale ratio and weights are
  shared.
- Measure: 42rem (about 70 characters), exists as `--measure`.
- A designer font for the wordmark is a future license decision (#2); a swap
  must not change layout, so the wordmark image has fixed aspect ratio tokens.

## 8. Effects: CSS-only versus raster

CSP matters here. `img-src 'self'` blocks `data:` URIs, so an inline SVG
data-URI background will not load. Every pattern is either pure CSS gradients or
a small same-origin file.

| Effect | Approach | Cost |
|---|---|---|
| Amber glow behind header | existing radial gradient on `body` (tokens `--glow`) | none |
| Carbon-fiber stripes | `repeating-linear-gradient` at 45 degrees, `--carbon-base` and `--carbon-line`, low opacity | none |
| HUD corner brackets | `clip-path: polygon()` chamfers plus a 2 px orange border or pseudo-element rules; no rounded corners | none |
| HUD divider | one `<hr>` styled with a gradient and chamfered end caps (clip-path) | none |
| Circuit-trace pattern | a small repeatable SVG file (`static/brand/circuit.svg`, under 6 KB), used as a background at 5 to 8 percent opacity; not a data URI | one tiny file |
| Ghosted mascot | the approved color mascot at low opacity, fixed, cropped by the viewport; cost is the existing 62 KB PNG, or a lighter WebP derivative | reuse |
| Icons | `mask-image` of same-origin SVG files, colored by `currentColor` | about 1 KB each |
| Wordmark | image, SVG preferred (sharp at any size, small) | one file |
| Hero art | CSS composition of the above; no photo | none |

Rules: every effect sits behind a `prefers-reduced-motion` and
`prefers-contrast` guard. Motion is limited to hover, focus and menu open;
nothing autoplays. Glow is a `box-shadow` or `filter: drop-shadow` on at most the
wordmark, the mascot and focused controls. On `forced-colors` the frames fall
back to a plain 2 px border.

## 9. Asset plan

Source for the first column is the stream-asset review notes. The files stay
outside the repo; each new file enters through the approved-assets manifest after
a by-eye Star of David check.

### Reuse (already clean)

| Asset | Use |
|---|---|
| `static/brand/penguin-color.png` (committed, 62 KB) | favicon source, avatar, ghost layer, footer on dark |
| `static/brand/penguin-glyph.svg` (committed, 15 KB) | light-mode mascot, SVG favicon |
| Jost woff2 (committed) | body |

### Reference only (rebuild in CSS or SVG; do not ship the file)

| Reference | Rebuild as |
|---|---|
| bio About and bio Socials plates | CSS bracket frame, chamfers, 2 px orange border, optional cream "light plate" variant |
| Chat_Camera panel | circuit-trace SVG pattern plus bracket frame |
| 0927 YouTube banner composition | ghosted mascot behind small content |
| Carbon-fiber backgrounds | repeating gradient |

### Must be rebuilt (new file, built locally at no cost)

| New asset | How | Notes |
|---|---|---|
| Wordmark (SVG or PNG, white on transparent) | Trace the wordmark region of the 6600x1650 banner (1584x396 master) to SVG locally (decision 2); fallback is a transparent PNG cut. Strip the baked halo so CSS owns the glow | The surrounding banner has a Twitter bird and TikTok mark; crop them away and take only the wordmark region. Star check by eye on the result. A black-on-transparent variant for light mode. |
| Mascot WebP derivatives (hero 640 px, favicon 32/180/512) | resize of the approved PNG | Lossless or q90, star-free file as source |
| OG card 1200x630 | compose locally from wordmark, mascot and carbon background; one default now (decision 7); per-post cards later only through Hugo's own image pipeline with no new dependency | Replaces the 512 px square; keep under 120 KB |
| Circuit-trace pattern | trace or recreate as simple SVG | under 6 KB |
| Nine network icons (eight plus TikTok) | copy from Reach Around's CC0 set; confirm the TikTok icon is in it, else add it from the same CC0 source | record hash in the manifest |

### Needs paid generation

No paid hero art now (decision 8). Nothing in this plan requires paid image
generation. The maintainer is open to spending later; each set then goes
through the paid gate (2 USD per job cap, 10 USD monthly ceiling, fresh approval
for each job) and the star and third-party-mark check. The estimates below are
for that later case. They are estimates and have not been measured against any
provider price list.

| Optional item | Images | Estimate | Cap |
|---|---|---|---|
| Hero background variants for the home page | 4 | about $0.20 to $0.40 | under the $2 per job cap |
| OG card backgrounds (3 post categories) | 3 | about $0.15 to $0.30 | under the $2 per job cap |

No generation call is made by this brief. Anything generated also needs the
by-eye star check, the third-party-mark check and a manifest line.

### Alt text

The baseline found 55 of 56 media items with no alt text. Plan: only images used
by a retained post migrate; each gets alt text written at migration (a
reviewable list per post). Decorative art uses `alt=""` in the template and CSS
backgrounds. The mascot in the hero gets a short descriptive alt.

## 10. Performance budget and CSP

Budgets (a build gate in CI measures them):

| Item | Budget |
|---|---|
| JavaScript | one same-origin file (`/theme.js`), under 1 KB gzip, target under 600 bytes; no other script, no third-party script |
| CSS (all, minified, one file) | 20 KB gzip, under 12 KB target; today 8.3 KB raw |
| Fonts | 1 file, under 30 KB (Jost is 26.6 KB) |
| Home page HTML | under 15 KB gzip |
| Home page total transfer, cold | under 150 KB including images |
| Post page, no inline images | under 80 KB |
| Largest image on any page | under 120 KB |
| Third-party requests | 0 |
| LCP on a mid-range phone, 4G | under 2.0 s (measure in a browser run; the baseline did not measure Lighthouse) |
| CLS | under 0.05; image dimensions always declared |

Constraints from `static/_headers` (one change, below):

- Today: `default-src 'none'; img-src 'self'; style-src 'self'; font-src
  'self'; script-src 'none'; base-uri 'none'; form-action 'none';
  frame-ancestors 'none'`.
- Changed by decision 4: `script-src 'self'` replaces `script-src 'none'`.
  Everything else stays. No inline script, no `unsafe-inline`, no
  `unsafe-eval`, no third-party script source, no hashes or nonces needed.
- No inline `<script>`, `<style>` or `style=` attributes; `check-output.sh`
  fails the build on each. No `data:` images. No forms (so no contact form).
- `check-output.sh` today fails on any `<script` element and on
  `script-src` other than the strict form. New expectations: the only allowed
  script element is `<script src="/theme.js">` (same origin, no `http(s)://`
  src, no inline body); the CSP must contain exactly `script-src 'self'`
  (`none` is rejected once the toggle ships so the header and the template
  cannot drift apart; also reject `*`, any `http(s):` source, `unsafe-inline`,
  `unsafe-eval`, `data:` and `blob:` in script-src). `test-check-output.sh`
  fixtures change to `'self'` and gain negative cases: inline script, external
  script, a second script file, `script-src 'unsafe-inline'`, and
  `script-src https:`. The comment in `static/_headers` is rewritten to say
  `script-src` is `'self'` for the theme file only.
- Mobile menu and accordions use native elements (`<details>`) and CSS only.
- Theme (decision 4): dark is the default; the CSS follows
  `prefers-color-scheme` (light only when the system says light, dark when it
  is unknown), so the no-script path is correct on CSS alone. With script, a
  toggle adds a manual override. `/theme.js` is loaded from `<head>` as a
  blocking tag so the stored choice is applied before first paint (no flash,
  no CLS). It reads and writes one key through a guarded access: reads and
  writes sit in `try`/`catch` (storage can throw when blocked), only the exact
  values `light` and `dark` are accepted, anything else is ignored, and a
  failure falls back to the CSS default with the toggle still working for the
  page view. It sets `data-theme` on `<html>`, builds the button in the DOM (no
  dead control without script), and uses no `eval`, no `innerHTML` of stored
  data and no network call.
- Outbound links never auto-load anything (no preconnect to third parties).
- A new CSP source needs its own issue and an explicit decision; the header
  comment already says embeds are added one provider at a time. The
  `script-src 'self'` change is that decision for the theme file and covers
  nothing else.

## 11. Accessibility requirements (WCAG 2.2 AA)

- Contrast: 4.5:1 for text, 3:1 for UI and focus, checked by the script in both
  modes, extended for new tokens.
- Landmarks: one `<header>`, `<nav aria-label>`, `<main>`, `<footer>` on every
  page; skip link first.
- One `<h1>` per page, no skipped levels.
- Focus: a visible 3 px focus ring on every control, never removed; focus is not
  hidden by sticky headers (2.4.11); targets at least 24 px, and 44 px on touch
  (existing `--tap`); a dragging gesture is never required (2.5.7).
- Images: every informative image has alt text; decorative ones have `alt=""`.
  Wordmark link has the accessible name "ChiefGyk3D, home". Icon-only links
  carry a text label (visually hidden if needed).
- Links: every outbound link names its destination; identical link text points to
  identical targets; link color is not the only cue in body text (underline).
- Theme toggle: a real `<button>` reachable by Tab in header order, with a
  visible text or icon-plus-text label that names the action ("Light theme" /
  "Dark theme"), at least 44 px on touch and never below 24 px. State is
  exposed with `aria-pressed` (pressed means the light theme is on), and the
  accessible name does not change with state, so a screen reader announces the
  name plus "pressed" or "not pressed". Operable with Enter and Space (native
  button, no custom key handling). The 3 px focus ring and the 3:1 contrast
  above apply. Switching does not animate under `prefers-reduced-motion`
  (and the CSS applies no transition to color on the root either way). The
  control is created only when script runs, so there is no inert button.
- Motion and contrast preferences: `prefers-reduced-motion`,
  `prefers-contrast: more` (raise border and glow contrast), and `forced-colors`
  fallbacks.
- Reflow: no horizontal scroll at 320 px and at 400 percent zoom; text sized in
  rem and spacing resilient to user overrides (1.4.12).
- Language: `lang` set; the archived letter keeps one language.
- Disclosure: the products disclosure is real text in the DOM, not an image.
- Verification: an automated pass (the scan tooling) plus a keyboard and
  zoom pass on each template before launch. Automated checks cannot prove
  conformance; the final pass is human.

## 12. Phased work breakdown (proposed issues, build order)

Sizes: S under half a day, M about a day, L two or more days. Each issue gets a
board card before work starts. Repo is this one unless noted.

| # | Proposed issue | Size | Depends on |
|---|---|---|---|
| 1 | Approve this brief and the issue list (decisions are recorded in section 13) | S | none |
| 2 | Token source: `brand/tokens.json`, generator script (emits the system-light and `data-theme` blocks), regenerate `tokens.css`, add new tokens and extend `check-contrast.py` pairs. Acceptance: `PAIRS` gains `focus` (3.0) on `carbon-base`, `carbon-line`, `plate` and `ghost`, `#8A5A00` focus on `--plate-light` `#FFEFD9` (3.0), muted and text on carbon and plate (4.5), and the toggle pairs; a test fixture with a focus color below 3:1 on a new surface makes the script exit 1 | M | 1 |
| 3 | CSP change for the theme script: `script-src 'self'` in `static/_headers` (comment rewritten), `check-output.sh` allows only the one same-origin theme script and requires the exact policy, `test-check-output.sh` fixtures and negative cases, performance-budget line for the one JS file | S | 1 |
| 4 | Reach Around (that repo): vendor the token file with a hash pin, map to `--ra-*`, align surface/text/border/light-bg drift, link to the blog | M | 2 |
| 5 | Drift check: local script in both repos; propose moving it to GYST as a reusable check | S | 2, 4 |
| 6 | Assets, part 1: wordmark (traced SVG, PNG fallback; dark and light; third-party marks cropped), mascot WebP derivatives, favicon set, approved-assets manifest lines, by-eye star check | M | 1 |
| 7 | Assets, part 2: circuit SVG, nine network icons from the shared set, default 1200x630 OG card | S | 6 |
| 8 | Shell: base layout, header and `<details>` nav, footer, landmarks, skip link, print and `forced-colors` styles; journal nav item hidden until the first entry exists | M | 2, 6 |
| 9 | Theme toggle: `/theme.js` (guarded storage, head-loaded, builds the button), button styles and the `data-theme` CSS hooks, keyboard and screen-reader pass, reduced-motion behavior, privacy-page wording for the stored choice | M | 2, 3, 8 |
| 10 | HUD component CSS: bracket frame, divider, carbon surface, glow, tile, button | M | 2, 8 |
| 11 | Templates: home (hero, latest posts, social strip) | M | 8, 10 |
| 12 | Templates: post (archive banner, superseded note, syndication row, prev/next), archive and term pages | M | 8, 10 |
| 13 | Data files and the socials hub page (nine networks, TikTok kept), `rel="me"` row from the same data, add YouTube, leave X out | M | 8, 10 |
| 14 | Products page and template with disclosure at the top; move the 22 affiliate links from the 3 posts | M | 8, 10 |
| 15 | About with its `#contact` section (no form or script: Matrix and Discord links plus one text-only public address, alias supplied by the maintainer and not blocking), the `/contact/` to `/about/#contact` redirect, Support, Privacy pages | M | 8, 10 |
| 16 | Migrate content: 10 posts, 15 aliases to `_redirects`, alt text for retained images, WebP conversion, TikTok archive note, Stream Daemon forward link | L | 12, 14 |
| 17 | Head and SEO: per-page descriptions, `summary_large_image` card with the one default OG card, sitemap line check, tune `check-output.sh` for new tags | S | 7, 12 |
| 18 | Performance and accessibility gates: size budget script in CI (one JS file allowed), browser run for LCP and CLS, keyboard and zoom pass per template, toggle checks | M | 9, 11 to 16 |
| 19 | Syndication contract: `syndicate` and `syndicated` front matter in templates; hand-off to #11 | S | 12 |
| 20 | Cutover checklist run: staging to apex per `docs/cutover.md`, redirects verified on the live host | M | 16, 18 |
| 21 | Optional: build-time "latest on Mastodon" list from the maintainer's public RSS | M | 13, 20 |

Twenty-one issues (the first brief had nineteen; the CSP change and the toggle
are the two added by decision 4). Issue 4 and part of 5 belong in the Reach
Around repo; the rest are here. The syndicate deploy job itself stays in #11.
Per-post OG cards (decision 7) and paid hero art (decision 8) are deliberately
not issues yet.

## 13. Decisions (maintainer answers, 2026-10-29)

The eight open questions are answered. The same text is in the comments on
issue #41. Each answer is applied in the section named.

1. TikTok stays on the socials hub (largest platform). Nine networks; the icon
   comes from the shared CC0 set. Applied in sections 4, 5, 9 and issue 13.
2. Wordmark: trace the banner region to SVG locally; fallback is a transparent
   PNG cut. Crop away the third-party marks, then star-check the result by eye.
   It stays an image. Applied in sections 7, 9 and issue 6.
3. Journal: hide the nav item until the first entry exists; keep the template.
   Applied in section 3 and issue 8.
4. Theme: dark default; follow the system setting when it says light; dark
   fallback when unknown; plus a manual toggle. This replaces the earlier
   no-toggle recommendation. Consequences: the toggle needs one small
   same-origin script, so the CSP changes `script-src` from `'none'` to
   `'self'` (no inline script, no third-party script); the no-script path stays
   correct through `prefers-color-scheme` CSS; the stored choice uses guarded
   storage access. Applied in sections 2, 6 (contrast), 10 (CSP, budget,
   `check-output.sh` and test expectations), 11 (accessibility) and issues 2, 3,
   9 and 18.
5. Blog token values win. Reach Around adopts them through the shared
   `brand/tokens.json`, vendored with a recorded checksum. Applied in section 6
   and issues 2, 4 and 5.
6. Contact: Matrix and Discord links plus one text-only public address the
   maintainer approves. No form, no script. The alias comes from the maintainer
   later and does not block the build; the page ships with the two links and
   gains the address when it is supplied. Applied in sections 3, 4 and issue 15 (Contact is a section of About).
7. One default OG card now. Per-post cards come later only through Hugo's own
   image pipeline with no new dependency. Applied in section 9 and issue 17.
8. No paid hero art now. Open to spending later; each set goes through the paid
   gate (2 USD per job cap, 10 USD monthly ceiling, fresh approval each job) and
   the star and third-party-mark check. Applied in section 9.

## 14. Constraints recap

- No analytics, no embeds, no third-party requests; strict CSP, with one change:
  `script-src 'self'` for the theme script only (decision 4).
- American English throughout.
- Public repo: no callsign, grid square, employer, hostname, serial or secret
  in any file or asset; asset paths in the manifest are relative import paths.
- Every new image passes the star check and gets a manifest line first.
