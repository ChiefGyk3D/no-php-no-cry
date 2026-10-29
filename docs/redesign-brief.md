# Redesign brief: chiefgyk3d.com

Issue: ChiefGyk3D/no-php-no-cry#41. Status: draft for maintainer approval.
Written 2026-10-29. Docs only; no site code changes.

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

1. Dark first. Light mode exists and passes the same contrast rules, but is the
   override, as in `tokens.css` today.
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
| `/about/` | new; folds in the Contact content | about |
| `/contact/` | Contact (rewrite, no form) | page, or a section of about |
| `/privacy/` | new statement (no analytics, no embeds) | page |
| `/journal/` | exists in the repo as a section | archive |
| `/tags/<tag>/`, `/categories/<c>/` | existing term pages | archive |
| `/404.html` | exists | 404 |

`/sample-page/` is dropped. The theme demo draft is dropped. The privacy draft
is replaced by a new statement.

### Primary navigation

Header, in this order: Posts, Products, Social, Support, About. Contact lives
inside About and the footer (fewer top-level items on a phone). The baseline
menu had six items; this keeps every destination but merges Home (the wordmark
links home) and Contact.

On a phone the header is a wordmark plus a native `<details>` menu. No script.
A `<nav aria-label="Main">` landmark exists on every page (the baseline found
none).

Footer: Contact, Privacy, RSS, the `rel="me"` identity row, a link to Reach
Around ("link page"), and the media kit link that points out to Reach Around.
Two-way link with Reach Around (#12): this site links to it from the header of
the social hub and the footer; Reach Around links back to the blog.

Journal: the repo has a `journal` section and a nav item today. The baseline has
no journal content. See open question 3.

## 4. Page templates

Each template uses the same shell: `baseof.html`, the header, the footer, the
token stylesheet. Specific needs:

| Template | Needs |
|---|---|
| Home | Hero (wordmark image, mascot, tagline, two buttons: Latest post, Social). Latest 5 posts with date and a 2-line summary. A social strip using the icon set. A ghosted mascot layer at low opacity. No carousel. |
| Post | Single column at `--measure`. Title, date, reading time, tags. Optional `archive` front matter shows a dated archive banner (used for the TikTok letter: original date and "this is a record, not a current view"). Optional `supersededBy` front matter shows a forward link (twitch-and-toot to Stream Daemon). Code blocks use the existing highlight classes. A syndication row (section 5). Previous/next. |
| Archive | Posts list with year grouping, tag filter links (plain term pages), RSS link. Reuse for journal and term pages. |
| Products | Disclosure block first, above the fold, in a bracket frame: plain statement that links earn a commission and what that means. Items grouped by the old posts' topics (audio, 3D printing and PC repair, air quality). Each item: name, one line, price note ("price checked on <date>", no live prices), outbound link with `rel="sponsored noopener"`. The old prose stays in the posts, which link here. |
| About | Short bio, mascot, current projects with GitHub links, how to reach the maintainer without a form (links, not an email form; address policy in open question 6). |
| Socials hub | A tile grid, one tile per network in section 5. Tile = icon, network name, handle or room name, a short role line. The Matrix tile names the community room. Same data file drives the footer `rel="me"` row and the home strip. |
| Support | Link list (tips, shop) in the same tile style, with each link rechecked before publish. |
| Privacy | Plain text: no analytics, no embeds, no cookies, no third-party requests; outbound links leave the site. |
| 404 | Mascot, one line, links to Posts and Social. |

The plan keeps raw HTML in Markdown off (`unsafe = false`), so products and
socials render from data files (`data/socials.yaml`, `data/products.yaml`) and
partials, not from hand-written HTML in content.

## 5. Social integration

Constraint: `default-src 'none'`, `script-src 'none'`, `img-src 'self'`,
`frame-ancestors 'none'`. No embedded timelines, no widgets, no share buttons
that load a vendor script. Every integration below works with plain links and
build-time data.

### Networks (hub, footer row, home strip)

Bluesky, Mastodon, Matrix, Discord, GitHub, YouTube, Twitch, Kick. TikTok is on
the live hub today and is not on this list; see open question 1. X/Twitter is
out. Support links (Ko-fi, StreamElements, shop) live on the support page, not
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
  with the canonical one fetched from the blog repo's default branch by raw
  GitHub URL pinned to a commit. Bumping is a deliberate re-pin PR in Reach
  Around. Per the standing rule that anything two repos need goes to GYST, the
  check is a candidate for a GYST reusable check; the first version can be a
  local script and move to GYST when the second repo adopts it.
- The shared icon set is Reach Around's `static/icons/` (Simple Icons, CC0).
  The blog copies the eight needed icons and records them in
  `approved-assets.txt` with the source hash.

### Palette (proposed canonical values)

Keep the blog's current values as canonical, since they were chosen with the
contrast check and the warm-neutral light mode, and move Reach Around to them
in a follow-up issue there. Additions for the redesign (new tokens, dark mode):

| Token | Value | Use |
|---|---|---|
| `--carbon-base` | `#181818` | carbon-fiber ground |
| `--carbon-line` | `#282828` | carbon-fiber stripe |
| `--plate` | `#281808` | warm brown panel, circuit fill |
| `--accent-deep` | `#AF6A0E` | shading, decorative edges only (not text) |
| `--ghost` | `#383838` | ghosted mascot layer |

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
| `#8A5A00` on cream plate | 5.25 | pass |
| `#AF6A0E` on bg | 4.50 | at the threshold; decorative use only |
| `#888888` on bg | 5.45 | pass (secondary icon use) |
| `#585858` on bg | 2.71 | fail as text; ghost layer only |
| accent `#FBB03B` on light bg `#FAF7F2` | 1.73 | fail; light mode keeps `#8A5A00` (5.55) |

The check script must grow with each new token pair (`carbon-line` on text,
`plate` on text, muted on carbon), or the new tokens ship unchecked. Proposed
issue: extend `PAIRS` in `check-contrast.py` and read the generated tokens.
Focus ring stays 3:1 minimum against every surface it can sit on.

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
| Wordmark (SVG or PNG, white on transparent) | Extract the wordmark region from the 6600x1650 banner (1584x396 master) and clean or trace it locally; strip the baked halo so CSS owns the glow | The surrounding banner has a Twitter bird and TikTok mark; take only the wordmark region. A black-on-transparent variant for light mode. |
| Mascot WebP derivatives (hero 640 px, favicon 32/180/512) | resize of the approved PNG | Lossless or q90, star-free file as source |
| OG card 1200x630 | compose locally from wordmark, mascot and carbon background; one default plus per-post via a Hugo image pipeline is optional | Replaces the 512 px square; keep under 120 KB |
| Circuit-trace pattern | trace or recreate as simple SVG | under 6 KB |
| Eight network icons | copy from Reach Around's CC0 set | record hash in the manifest |

### Needs paid generation

Nothing in this plan requires paid image generation. If the maintainer wants
alternatives (for example a per-post OG background set, or a wider hero
illustration), the estimate is below for approval. These are estimates and have
not been measured against any provider price list.

| Optional item | Images | Estimate | Cap |
|---|---|---|---|
| Hero background variants for the home page | 4 | about $0.20 to $0.40 | under the $2 per job cap |
| OG card backgrounds (3 post categories) | 3 | about $0.15 to $0.30 | under the $2 per job cap |

No generation call is made by this brief. Anything generated would also need the
by-eye star check and a manifest line.

### Alt text

The baseline found 55 of 56 media items with no alt text. Plan: only images used
by a retained post migrate; each gets alt text written at migration (a
reviewable list per post). Decorative art uses `alt=""` in the template and CSS
backgrounds. The mascot in the hero gets a short descriptive alt.

## 10. Performance budget and CSP

Budgets (a build gate in CI measures them):

| Item | Budget |
|---|---|
| JavaScript | 0 bytes |
| CSS (all, minified, one file) | 20 KB gzip, under 12 KB target; today 8.3 KB raw |
| Fonts | 1 file, under 30 KB (Jost is 26.6 KB) |
| Home page HTML | under 15 KB gzip |
| Home page total transfer, cold | under 150 KB including images |
| Post page, no inline images | under 80 KB |
| Largest image on any page | under 120 KB |
| Third-party requests | 0 |
| LCP on a mid-range phone, 4G | under 2.0 s (measure in a browser run; the baseline did not measure Lighthouse) |
| CLS | under 0.05; image dimensions always declared |

Constraints from `static/_headers`, kept as is:

- `default-src 'none'; img-src 'self'; style-src 'self'; font-src 'self';
  script-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors
  'none'`.
- No inline `<script>`, `<style>` or `style=` attributes; `check-output.sh`
  fails the build on each. No `data:` images. No forms (so no contact form).
- Mobile menu, accordions and the theme behave with native elements
  (`<details>`) and CSS only. There is no theme toggle button in the plan
  (needs script); the theme follows `prefers-color-scheme`.
- Outbound links never auto-load anything (no preconnect to third parties).
- A new CSP source needs its own issue and an explicit decision; the header
  comment already says embeds are added one provider at a time.

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
| 1 | Approve this brief (decisions on the open questions) | S | none |
| 2 | Token source: `brand/tokens.json`, generator script, regenerate `tokens.css`, add new tokens and extend `check-contrast.py` pairs | M | 1 |
| 3 | Reach Around (that repo): vendor the token file with a hash pin, map to `--ra-*`, align surface/text/border/light-bg drift, link to the blog | M | 2 |
| 4 | Drift check: local script in both repos; propose moving it to GYST as a reusable check | S | 2, 3 |
| 5 | Assets, part 1: wordmark (dark and light), mascot WebP derivatives, favicon set, approved-assets manifest lines, by-eye star check | M | 1 |
| 6 | Assets, part 2: circuit SVG, network icons from the shared set, default 1200x630 OG card | S | 5 |
| 7 | Shell: base layout, header and `<details>` nav, footer, landmarks, skip link, print and `forced-colors` styles | M | 2, 5 |
| 8 | HUD component CSS: bracket frame, divider, carbon surface, glow, tile, button | M | 2, 7 |
| 9 | Templates: home (hero, latest posts, social strip) | M | 7, 8 |
| 10 | Templates: post (archive banner, superseded note, syndication row, prev/next), archive and term pages | M | 7, 8 |
| 11 | Data files and the socials hub page, `rel="me"` row from the same data, add YouTube, leave X out | M | 7, 8 |
| 12 | Products page and template with disclosure at the top; move the 22 affiliate links from the 3 posts | M | 7, 8 |
| 13 | About, Contact (no form), Support, Privacy pages | M | 7, 8 |
| 14 | Migrate content: 10 posts, 15 aliases to `_redirects`, alt text for retained images, WebP conversion, TikTok archive note, Stream Daemon forward link | L | 10, 12 |
| 15 | Head and SEO: per-page descriptions, `summary_large_image` card, sitemap line check, tune `check-output.sh` for new tags | S | 6, 10 |
| 16 | Performance and accessibility gates: size budget script in CI, browser run for LCP and CLS, keyboard and zoom pass per template | M | 9 to 14 |
| 17 | Syndication contract: `syndicate` and `syndicated` front matter in templates; hand-off to #11 | S | 10 |
| 18 | Cutover checklist run: staging to apex per `docs/cutover.md`, redirects verified on the live host | M | 14, 16 |
| 19 | Optional: build-time "latest on Mastodon" list from the maintainer's public RSS | M | 11, 18 |

Issue 3 and part of 4 belong in the Reach Around repo; the rest are here. The
syndicate deploy job itself stays in #11.

## 13. Open questions for the maintainer (max 8)

1. TikTok on the hub. The live hub lists TikTok; you named YouTube in and X out
   and did not mention TikTok. Recommendation: keep it on the hub (it is in the
   live site and in the banners) unless the account is inactive, in which case
   drop it like X.
2. Wordmark source file. The only in-hand art is the raster banner (6600x1650).
   Recommendation: trace the wordmark region locally to an SVG; if the trace
   looks wrong, use a transparent PNG cut. No designer license issue arises
   because it is your own artwork and stays an image.
3. Journal section. The repo has a journal nav item and no journal content.
   Recommendation: hide it from the nav until the first entry exists, keep the
   template.
4. Light mode. Keep a full light palette (existing) or go dark only?
   Recommendation: keep light; it costs one token block and the contrast check
   already covers it. Remove the idea of a toggle (needs script).
5. Which token file is canonical when the two repos disagree today. The blog
   and Reach Around differ on surface, text, border and light background.
   Recommendation: the blog values win (warm neutrals, pass the check), and
   Reach Around adopts them in issue 3.
6. Contact path without a form. Options: a mailto link (address visible to
   scrapers), a Matrix or Discord link, or an obfuscated address. Recommendation:
   link to Matrix and Discord plus a text-only address you approve for public
   posting; no form.
7. Per-post OG cards. One default card, or a generated card per post at build
   time? Recommendation: one default now; per-post cards only if Hugo's image
   pipeline does it with no new dependency.
8. Optional paid hero art. Spend up to about $0.60 on generated backgrounds, or
   none? Recommendation: none; the CSS composition plus the existing mascot
   covers the home page, and a generated image would need its own star and
   third-party-mark check.

## 14. Constraints recap

- No analytics, no embeds, no third-party requests; strict CSP unchanged.
- American English throughout.
- Public repo: no callsign, grid square, employer, hostname, serial or secret
  in any file or asset; asset paths in the manifest are relative import paths.
- Every new image passes the star check and gets a manifest line first.
