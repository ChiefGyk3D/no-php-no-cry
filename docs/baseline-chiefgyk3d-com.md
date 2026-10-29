# Baseline inventory: chiefgyk3d.com (WordPress)

Issue: ChiefGyk3D/no-php-no-cry#40. Measured 2026-10-29 from the public site
(read-only GETs, about one request per second, no logins, no forms) and from a
local crawl of 2026-10-24. Live REST totals matched the crawl: every page and
post has the same modified date, nothing new, nothing removed.

Hardening findings about the live site are tracked privately. This file lists
none.

## Summary

| Item | Count |
|---|---|
| Public pages | 6 |
| Public posts | 10 (2023-02-06 to 2025-11-05) |
| Drafts (not public, not inventoried) | 2 |
| Media library items | 56 (41 PNG, 14 JPEG, 1 WebP; about 21 MB) |
| Media with no alt text | 55 of 56 |
| Categories / tags | 3 / 16 |
| Approved comments | 4 (1 more dropped at import) |
| Authors | 1 |
| Affiliate links in posts | 22 (all Amazon short links, no disclosure on the page) |
| Sitemaps | 1 index, per-type child sitemaps (AIOSEO) |

Word counts are visible text only. Proposals are for the maintainer to accept
or change.

## Pages

| Title | URL path | Date | Words | Proposal | Reason |
|---|---|---|---|---|---|
| Front Page | `/` | 2023-02-01 | 0 (builder layout) | Rewrite | Hero and link grid come from the page builder; rebuild as the Hugo home. |
| Blog | `/blog/` | 2023-02-01 | 0 | Drop (redirect) | A list page; Hugo's posts list replaces it. |
| Sample Page | `/sample-page/` | 2023-02-01 | 155 | Drop | WordPress default text. |
| Contact | `/contact/` | 2023-02-06 | 39 | Rewrite | Links and a form; replace the form with a static contact path. |
| Social Media Links | `/social-media/` | 2023-02-06 | 39 | Rewrite | Link hub; add the missing networks (see Social links). |
| Support My Work | `/support-me/` | 2023-02-06 | 59 | Rewrite | Tip and shop links; keep, refresh, recheck each link. |

The two drafts are a privacy-policy page and a theme demo page. Proposal: write
a new privacy statement for the static site (it has no analytics or embeds);
drop the demo.

## Posts

| Title | URL path | Date | Words | Aff. links | Proposal | Reason |
|---|---|---|---|---|---|---|
| Stream Daemon: The Secure, Open-Source Stream Automation Engine for Modern Creators | `/stream-daemon-the-secure-open-source-stream-automation-engine-for-modern-creators/` | 2025-11-05 | 796 | 0 | Keep | Newest and on-brand; refresh against the project README. |
| Why I Use Multiple Phones: A Personal Dive into Device Diversification | `/why-i-use-multiple-phones-a-personal-dive-into-device-diversification/` | 2023-09-22 | 449 | 0 | Keep | Personal essay, still valid. |
| Improving Indoor Air Quality with UV Sanitation Systems and High-Quality Filters | `/improving-indoor-air-quality-with-uv-sanitation-systems-and-high-quality-filters/` | 2023-04-10 | 602 | 3 | Rewrite | Product pitch with affiliate links and no disclosure. |
| Best Headphone & Microphone Combo for Office, Gaming, and Music for Under $100 | `/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/` | 2023-04-01 | 803 | 6 | Rewrite | Prices stale, affiliate links need disclosure; one WebP image needs conversion. |
| Open Letter to President Biden about the Possible Ban of Tiktok | `/open-letter-to-president-biden-about-the-possible-ban-of-tiktok/` | 2023-03-16 | 748 | 0 | Keep as archive | Dated opinion piece; add a date banner. Maintainer call. |
| Must-Have Tools for 3D Printing and PC Repair: My Recommended Starter Kit | `/must-have-tools-for-3d-printing-and-pc-repair-my-recommended-starter-kit/` | 2023-03-13 | 934 | 13 | Rewrite | On-topic, but link-heavy; disclose or move to the products page. |
| Building a Strong Online Community: A Guide to Automating Your Social Media Communications | `/building-a-strong-online-community-a-guide-to-automating-your-social-media-communications/` | 2023-02-11 | 444 | 0 | Keep | Evergreen; update tool names. |
| Boosting Your Mastodon Server's Visibility: A Guide to Federation and Relays | `/boosting-your-mastodon-servers-visibility-a-guide-to-federation-and-relays/` | 2023-02-08 | 399 | 0 | Keep | Useful; recheck relay and directory links. |
| Discovering the Magic of Mastodon: A Journey into the Decentralized Social Networking World | `/discovering-the-magic-of-mastodon-a-journey-into-the-decentralized-social-networking-world/` | 2023-02-06 | 1416 | 0 | Keep | Longest post; core fediverse content. |
| Introducing Twitch-and-toot: The Open-Source Solution for Mastodon Stream Alerts | `/introducing-twitch-and-toot-the-open-source-solution-for-mastodon-stream-alerts/` | 2023-02-06 | 517 | 0 | Keep with note | Superseded by Stream Daemon; link forward. |

Totals: 7 keep (including keep-as-archive and keep-with-note), 3 rewrite, 10
posts in all. Pages: 4 rewrite, 2 drop, 6 pages in all. Posts are in category
Uncategorized (9 of 10, the other two categories hold one each: Audio and
Hardware).

## Menus

One primary menu, repeated in the header and a mobile copy (six items, so the
front-end HTML holds it twice):

1. Home (points at the temporary hosting address, not the real domain)
2. Blog
3. Social Media Links
4. Recommended Products (external, a separate `links.` subdomain)
5. Support My Work
6. Contact

There is no footer menu and no `<nav>` landmark on the front page. The Hugo
site should keep the same six destinations unless the maintainer prunes them.
The `links.` subdomain (products, media kit) and `social.` subdomain (Mastodon)
are separate services and stay as external links.

## Theme and plugin footprint (front end)

- WordPress 7.1.4, theme `teluro` on the Colibri page builder.
- Visible on the page: AIOSEO 4.9.1.1, Site Kit by Google 1.166.0, MonsterInsights
  (Google Analytics), WP Dark Mode, WPConsent cookie banner, a hosting-provider
  plugin, Jetpack stats, LiteSpeed cache behind Cloudflare.
- REST namespaces also show: ActivityPub, Forminator (forms), Redirection, Share
  on Mastodon, Zapier, Akismet, All-in-One WP Migration, and many hosting
  vendor modules.
- Third-party requests on the home page: Google Fonts, Google Tag Manager,
  Jetpack stats (`stats.wp.com`). The Hugo site makes none of these.
- 35 script tags, 4 stylesheet links, 17 inline scripts on the home page.

## Social links

Present in the live site (Social Media Links and Contact pages, plus the
Mastodon header link):

| Network | Present | Where |
|---|---|---|
| Mastodon | Yes | Social page, Contact, home |
| Bluesky | Yes | Social page |
| Kick | Yes | Social page |
| Matrix | Yes | Social page (community room) |
| Discord | Yes | Social page, Contact |
| GitHub | Yes | Social page |
| Twitch | Yes | Social page, Contact |
| YouTube | Contact page only | Missing from the Social Media Links page |
| TikTok | Yes | Social page, Contact |
| Twitter/X | Contact page only | Account handle is also in the SEO card metadata |
| Ko-fi, StreamElements, shop | Yes | Support page |
| LinkedIn, Instagram, Facebook | No | Not linked anywhere |

Gap: YouTube is the only requested network absent from the hub page. Hugo has
the footer `rel="me"` identity-link mechanism (see `hugo.toml`) but no links
are configured yet.

## SEO basics

- Titles: pattern `Page - ChiefGyk3D's Blog`; the home title is just the site
  name. All 16 public URLs have a title, meta description, canonical link,
  `og:image` and Twitter card. The site description is only the site name on
  the home page.
- Open Graph defaults to a 512 px square logo, not a social card.
- Two competing sets of OG tags on the home page (AIOSEO and the theme), the
  second with an empty description and a relative `og:url`.
- Single `<h1>` on every page.
- `robots.txt`: provider boilerplate, `Crawl-delay: 10`, no `Sitemap:` line.
  `sitemap.xml` is advertised by `<link>` and `wp-sitemap.xml` redirects to it.
- `llms.txt` is published (generated by the SEO plugin).
- RSS feed at `/feed/`, comments feed present.
- Unknown URLs return a 301 to a post, not a 404 (soft-404 behavior).
- Old permalinks end in a slash; the import log lists 15 aliases for the Hugo
  `_redirects` file.

## Performance (single cold-ish fetch from one location, indicative only)

- HTML size 317 KB to 406 KB uncompressed per page, Brotli on the wire.
- Total time per page: 0.7 s to 1.9 s when cached, 5.8 s to 6.7 s on the
  uncached posts.
- Home page: 35 script tags, 3 images, one web font family.
- A few image URLs on the home page still use the temporary hosting address
  and plain `http://`, which is also an HTTPS mixed-content risk.
- Not measured: Lighthouse, Core Web Vitals (need a browser run).

## Accessibility (static checks of the home page)

- `lang="en-US"` and a skip link exist.
- No `<main>` landmark and no `<nav>` landmark.
- 3 images on the home page, all with empty alt text (logo images, decorative
  by intent, but the hero photo is not). Media library: 55 of 56 items have
  no alt text.
- Cookie banner adds extra headings ("Cookie Consent", "Cookie Preferences")
  and a dark-mode plugin rewrites colors at runtime.
- Not measured: contrast, keyboard order, screen reader checks.

## HTTP security headers

Hardening tracked privately.

## Gap list versus the Hugo site

Already in Hugo (repo as of `26ad376`):

- Layouts for home, list, single, journal, 404, RSS, `robots.txt`, image
  rendering, a `_redirects` generator from front-matter aliases.
- Staging noindex plus apex production switch (`docs/cutover.md`), strict
  response headers file, CSP-safe code highlighting, brand tokens and assets.
- The `tools/wxr2hugo` converter and its test; import output (10 posts, 8
  pages, 2 drafts, localized images) lives outside the repo and is not
  committed.

Not yet in Hugo:

- Real content: `content/` holds only a sample post and a sample journal entry.
  None of the 6 pages or 10 posts has been committed.
- The 15 `_redirects` aliases (need front matter on migrated pages).
- Social and identity links configured (`hugo.toml` has the mechanism only).
- YouTube link and any link-hub page.
- Contact path without a form; a new privacy statement.
- Affiliate disclosure and rewrites for 3 posts.
- Alt text for retained images (55 of 56 missing), and conversion of the one
  WebP image the importer flagged.
- A sitemap line in `robots.txt` at production (handled by the cutover switch).
- Per-page social cards (OG image) and meta descriptions.
- Comments: 4 approved comments dropped to none; static site has no comments.

## Decisions for the maintainer

1. Accept or change each keep/rewrite/drop proposal above.
2. Affiliate links: disclose, remove, or move to the products page.
3. Open letter post: keep as a dated archive, or drop.
4. Which retained images need alt text first (55 are missing).
5. Add YouTube to the hub and decide on Twitter/X.
