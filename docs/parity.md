# WordPress parity: chiefgyk3d.com versus this site

Issue: ChiefGyk3D/no-php-no-cry#104 (epic: Redesign plan, #41). Written
2026-11-06 for the question "can the new site replace WordPress with 1:1
features and content?". State is `origin/main` at `0a943ac`. Nothing here came
from a new crawl of the live site: the WordPress side is
`docs/baseline-chiefgyk3d-com.md` (measured 2026-10-29), the new-site side is
the code and docs on main, and the rulings are the owner's, dated below.

Verdicts:

- **parity**: the new site does the same job, verified as stated.
- **gap**: WordPress does it, the new site does not yet, and it is not a drop.
- **planned**: a gap with an issue and a cutover step; it must land before the
  cutover.
- **dropped**: intentionally not carried over. Each one has a ruling.

Short answer: not yet. Structure, URLs, feed, SEO basics, search, `llms.txt`,
privacy and the security posture are at parity or better. The cutover waits on
the items marked planned, the owner's reading of the ten draft posts, device QA
and the owner-only steps in `docs/cutover.md`.

## Owner rulings

Every ruling the table cites. "Accepted" means the owner accepted the drop; the
wording is recorded as given.

| Date | Ruling | Issue |
|---|---|---|
| 2026-11-04 | Analytics (basic, non-invasive: city, state or country, VPN flag where possible, referrer, funnel) is required before cutover. | #84 |
| 2026-11-04 | The site doubles as the page linked from the owner's resume: a short About and a full Resume, no employer names. | #86 |
| 2026-11-06 | The public site name is ChiefGyk3D. `no-php-no-cry` is the project name only (repo, docs, internal comments). | #126 |
| 2026-11-06 | Add search: a static page and a pinned script, no third parties. | #119 |
| 2026-11-06 | Keep `llms.txt`. | #120 |
| 2026-11-06 | Archive the 4 old comments in-post, display name only. | #121 |
| 2026-11-06 | `/feed/` stays a 301 to `/feed/index.xml`. | #105 |
| 2026-11-06 | The ActivityPub actor is dropped. `rel="me"` is kept. Syndication on deploy (#11) is built before cutover. | #11 |
| 2026-11-06 | Litecoin is replaced by Solana, and Twitter/X is not listed: accepted 2026-11-06. | #98 |
| 2026-11-06 | Contact is Matrix and Discord only for now. An email address may come later. | #118 |
| 2026-11-06 | Shop alignment happens before cutover, but only as a copy and a spec. The live store is untouched without the owner's own override. | #79 |
| 2026-11-06 | No cookie banner, no dark-mode toggle, no WordPress admin on the new site. | #82 |
| 2026-11-06 | The ten migrated posts stay drafts until the owner reads each one and flips it. Twitch-and-Toot and Stream Daemon go together. | #63 |
| 2026-11-06 | Device QA gates the cutover. | #131 |
| 2026-11-06 | The cutover happens only after both Reach Around and this site are done. Until the owner says go: no Cloudflare writes, no DNS changes, no WordPress login or writes. | #67 |

## Parity table

"Verified by" names the check that fails if the claim stops being true; where it
says "owner review" or "device QA", no script can prove it.

### Content and pages

| Feature | WordPress | New site on main | Verdict | Ruling | Verified by |
|---|---|---|---|---|---|
| Home page | Page-builder hero and link grid | Hugo home: hero, latest posts, social strip (`layouts/home.html`) | parity | | `scripts/test-pages.sh`; device QA (#131) |
| Blog list `/blog/` | A list page | `/posts/`; `/blog/` is a 301 alias | parity | | `scripts/test-redirects.sh` |
| Sample Page | WordPress default text | Not carried; `/sample-page/` 301s to the home page | dropped | baseline proposal "Drop" | `scripts/test-redirects.sh` |
| Contact page | Links plus a form | `/about/#contact`: Matrix and Discord links, no form; `/contact/` is a 301 | parity | 2026-11-06 contact is Matrix and Discord only, email later | `scripts/test-pages.sh`; the fragment surviving the redirect is unverified until the staging check (`docs/cutover.md`) |
| Contact form | Forminator form | None. The CSP has `form-action 'none'` and the build rejects forms | dropped | 2026-11-06 same ruling | `scripts/check-output.sh` |
| Social Media Links | Link hub, YouTube missing | `/social/` tile grid from `data/socials.yaml`, YouTube added, 12 networks | parity (better) | | `scripts/test-social-products.sh` |
| Support My Work | Tip and shop links | `/support/` with QR codes and Copy buttons; `/support-me/` is a 301 | parity | | `scripts/test-pages.sh`, `scripts/gen-support-qr.sh --check` |
| Recommended Products | External `links.` subdomain | `/products/`, affiliate disclosure once, after the last group (owner ruling 2026-11-08), each item labeled Amazon or Direct, `rel="sponsored noopener"` | parity (better) | | `scripts/test-social-products.sh` |
| Media kit | Lives on the `links.` subdomain | Not on this site. The About page names Reach Around only as a project tile | planned | The media kit stays with Reach Around; this site points to it (cutover step N6) | owner review of the link target |
| About and Resume | Not on WordPress | `/about/` (owner-approved bio, plus At a glance and Hardware and homelab sections drawn from the owner's public GitHub profile text, kept in `data/about.yaml`, facts only: no hostnames, addresses or serial numbers) and `/resume/` (printable), no employer names | parity (new) | 2026-11-04 resume ruling (#86); bio approved 2026-11-06 (#125); profile-sourced sections 2026-11-08 (#196) | `scripts/test-resume.sh`, `scripts/check-wording.sh` |
| Privacy | A draft page, never public | `/privacy/` says the site collects nothing. That sentence becomes false the day analytics goes live | planned | 2026-11-04 analytics before cutover | `scripts/test-pages.sh`; the swap is cutover step N2 |
| Cookie banner | WPConsent | None. The site sets no cookie and stores nothing | dropped | 2026-11-06 no cookie banner | `scripts/check-output.sh` (no inline script, no third party) |
| Dark-mode plugin | WP Dark Mode rewrites colors at runtime | Dark only, by design; no toggle | dropped | 2026-11-06 no dark-mode toggle | `scripts/check-contrast.py`, `scripts/gen-tokens.py --check` |
| The 10 posts | Published | Present as page bundles with `draft: true`; nothing is published | planned | 2026-11-06 stay drafts until the owner reads and flips each | `scripts/test-migration.sh` |
| Post order constraint | n/a | Twitch-and-Toot links forward to Stream Daemon; flip both together | planned | 2026-11-06 | `docs/cutover.md` |
| Affiliate links in posts | 22 Amazon links, no disclosure | Disclosure on `/products/`; the posts that carry the links are drafts | planned | | owner review |
| Image alt text | 55 of 56 missing | Importer flags images with no alt text; retained images need real alt text | planned | | `tools/wxr2hugo` flags; owner review |
| The 4 approved comments | Shown under 3 posts | Not shown yet; will be quoted in-post, display name only, never emails or IPs | planned | 2026-11-06 archive in-post (#121) | owner review after the posts exist |
| Comments (new ones) | Open comments, Akismet | None; no way to post | dropped | 2026-11-06 archive only | `scripts/check-output.sh` (no forms) |
| Open letter post | Published opinion piece | Draft with a dated archive banner | planned | baseline "keep as archive" | owner review |

### URLs, feeds and SEO

| Feature | WordPress | New site on main | Verdict | Ruling | Verified by |
|---|---|---|---|---|---|
| Old post permalinks | `/<slug>/` | 301 aliases for each, with and without the slash | parity | | `scripts/test-redirects.sh` |
| RSS at `/feed/` | The main feed | `/feed/` is a 301 to the real file `/feed/index.xml`; full bodies; every page advertises it | parity | 2026-11-06 stays a 301 | `scripts/verify-live.sh` (`redirect`, `feed`) |
| `/feed/atom/`, `/comments/feed/` | Atom and comments feeds | 301 to `/feed/index.xml` | parity | | `scripts/test-redirects.sh` |
| Category, tag, date and `/page/N/` URLs | WordPress archives | 301 to the matching term page or `/posts/` | parity | | `scripts/test-redirects.sh` |
| `/wp-content/uploads/` images | Direct image URLs | 301 to the page-bundle file, only for images the migrated posts show; the list is empty until a post is published | planned | | `scripts/test-redirects.sh` |
| `wp-sitemap.xml` | Redirects to `sitemap.xml` | 301 to `sitemap.xml`, one line in `_redirects`; `sitemap.xml` is published and named in `robots.txt` at production | parity | | `scripts/test-redirects.sh` |
| Sitemap | AIOSEO index with child sitemaps | One `sitemap.xml` with `lastmod` | parity | | `scripts/check-output.sh`, `scripts/verify-live.sh` |
| `robots.txt` | Provider boilerplate, crawl delay, no sitemap line | Environment-aware: staging disallows all, production allows and names the sitemap | parity (better) | | `scripts/check-output.sh` |
| `llms.txt` | Generated by the SEO plugin | `/llms.txt` built from front matter and data | parity | 2026-11-06 keep | `scripts/test-llms.sh`, `scripts/check-output.sh` |
| Titles, descriptions, canonical, Open Graph, Twitter card | AIOSEO plus a duplicate theme set | One set per page, branded OG card, JSON-LD Person and WebSite | parity (better) | | `scripts/check-seo.py`, `scripts/test-head.sh` |
| Site name | ChiefGyk3D's Blog | `hugo.toml` still sets `title = "no-php-no-cry"`, so the header, titles, feed and Open Graph show the project name | planned | 2026-11-06 the public name is ChiefGyk3D (#126) | `scripts/test-head.sh` once the name changes |
| Unknown URLs | 301 to a post (soft 404) | A real 404 page with `noindex` | parity (better) | | `scripts/verify-live.sh` (`not-found`) |
| Search | WordPress search | `/search/`: a static list, filtered by a pinned script, works with JavaScript off | parity | 2026-11-06 add search | `scripts/test-pages.sh`, `scripts/check-output.sh` |
| Search-console properties | Existing property | Apex property and sitemap submission after cutover | planned | | owner action (cutover step 9) |

### Social, identity and integrations

| Feature | WordPress | New site on main | Verdict | Ruling | Verified by |
|---|---|---|---|---|---|
| Identity links (`rel="me"`) | Mastodon header link | Footer row from `data/socials.yaml`: Mastodon, Pixelfed and GitHub carry `rel="me"` | parity | 2026-11-06 kept | `scripts/test-social-products.sh`; the remote side can verify only once the apex serves the link |
| ActivityPub actor | The ActivityPub plugin | None | dropped | 2026-11-06 | n/a |
| Share on Mastodon, Zapier | Posts announced through plugins | Share links under each post (issue 220, `docs/share-links.md`). The "Discuss on" links are gone (they did not work). No job announces anything yet | planned | 2026-11-06 build #11 before cutover | `scripts/test-share.sh`; the acceptance criteria in #11 |
| Twitter/X | Contact page link and card metadata | Not listed | dropped | accepted 2026-11-06 | `scripts/check-wording.sh` |
| Litecoin address | On the support page | Replaced by Solana (Bitcoin, Monero, Ethereum and Solana are listed) | dropped | accepted 2026-11-06 | `scripts/gen-support-qr.sh --check` |
| Shop link and look | Links to the store | Header "Shop" and the footer Support row link to it. Matching the store's look is a copy and a spec only | planned | 2026-11-06 live store untouched without the owner's override (#79) | owner review of the spec |
| Reach Around | Not linked | Tile on `/about/` and a Resume entry; the footer link and the reverse link are cutover work | planned | 2026-11-06 cutover after Reach Around is done | `docs/cutover.md` |

### Analytics, privacy and security

| Feature | WordPress | New site on main | Verdict | Ruling | Verified by |
|---|---|---|---|---|---|
| Traffic metrics | Google Analytics, Site Kit, Jetpack stats, Tag Manager | Built and tested locally, not deployed: an edge count with no script, city and country, bot and VPN flags, referrer host, 5-view floor, no raw IP. Needs the D1 binding | planned | 2026-11-04 required before cutover (#84) | `scripts/test-analytics.sh`; live behavior unverified |
| Third-party requests | Google Fonts, Tag Manager, Jetpack stats | None: fonts, icons and scripts are same-origin | parity (better) | | `scripts/verify-live.sh` (`third-party`) |
| Response headers | Provider defaults (tracked privately) | One strict `/*` block with a CSP of `script-src 'self'` and pinned scripts | parity (better) | | `scripts/check-site-artifact.sh`, `scripts/verify-live.sh` (`header-*`) |
| Admin and login | WordPress admin, plugins, REST API | None. Static files only | dropped | 2026-11-06 no WordPress admin | n/a |
| Page weight | 317 KB to 406 KB HTML, 35 script tags | Size budget enforced in CI, three small pinned scripts, each only on its own page or page pattern. Since the snapshot above, `scripts/check-budget.py` reads the pinned-script table from `scripts/artifact-rules.sh`, so `/search.js` is counted (#132, merged in #135); before that fix the step failed on main | parity (better) | | `scripts/check-budget.py`, `scripts/test-check-budget.sh` |
| Accessibility | No `<main>` or `<nav>` landmark, 55 of 56 images without alt | Landmarks, skip link, contrast and axe checks in CI | parity (better) | | `scripts/check-landmarks.py`, `scripts/browser-gate.py`, `scripts/check-contrast.py` |
| Device matrix | Not tested | Pending | planned | 2026-11-06 gates the cutover (#131) | #131 |
| License | None stated | None yet; the repo is public | gap | owner decision needed (#109), not a cutover gate | n/a |

## What blocks the cutover

In order of who can unblock it:

1. **Agent work, no live system touched:** #126 (site name), #121 (comments),
   #11 (syndication job and its tests), the analytics go-live pull request (#84),
   the Reach Around and media-kit pointer, the shop spec (#79), the real content
   import and the `legacy_uploads.json` entries per published post.
2. **Owner reading and ruling:** each of the ten posts read and flipped to
   `draft: false`, alt text on retained images, the decision on `www` and
   `support.`, the device QA result (#131).
3. **Owner-only live steps:** every Cloudflare, DNS, secret and live-store
   action. The numbered list is in `docs/cutover.md`; agents never perform it.

## Not covered

- Hardening findings about the live WordPress site are tracked privately and
  appear nowhere in this file.
- Nothing here was checked against the live site again; if WordPress changed
  after 2026-10-29, the baseline must be refreshed first.
