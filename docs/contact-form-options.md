# Contact form options (issue 329, proposal only, the form is not built)

The old WordPress site had a contact form at `/contact/`. Decision (2026-11-09,
issue 329): `/contact/` is now a real page that lists email, Discord and Matrix,
and the form is deferred; it moves to the Reach Around media kit later, gated for
business inquiries. Before issue 329 `/contact/` was a 301 to `/about/#contact`.
Nothing below is built. This page compares ways to bring a form back. Read 2026-11-09 from
Cloudflare's docs unless marked INFERRED; no account ids, hostnames of private
environments or tokens appear here, and none belong in this repository.

## What the site constrains

- CSP (`static/_headers`): `default-src 'none'`, `script-src 'self'` plus the one
  Web Analytics beacon, `connect-src 'self'`, `form-action 'none'`, no `frame-src`.
- Pinned scripts: the only scripts in a build are `/copy.js` and `/search.js`,
  each hash-pinned and each on its own single page (`docs/pinned-script.md`,
  `scripts/check-output.sh`). No inline script, no third-party script.
- Dark mode only. Tokens from `assets/css/tokens.css`; frames from the border
  system (`docs/borders.md`): one frame per region, at most one L3 per page.

## Option (a): a Worker endpoint, Turnstile, rate limits, no stored data

A same-origin Worker route receives a POST, checks it, and forwards the message to
the mailbox. Nothing is stored: no database, no log of bodies.

- Flow: form posts to a same-origin path; the Worker validates fields and size,
  verifies the spam check, then sends one email to a verified destination with the
  Workers `send_email` binding and returns a plain confirmation page.
  Sends to a verified destination address are free on all plans (Email Service
  pricing, Oct 2026). The binding can be restricted to one destination
  (`destination_address`) and needs Email Routing enabled with a verified address
  (Wrangler configuration, "Email bindings").
- Turnstile: the widget needs Cloudflare's `api.js` from
  `challenges.cloudflare.com`, fetched from that exact URL, never proxied or cached
  (Turnstile, client-side rendering; VERIFIED). Its iframe must be able to load
  (client-side error 200500; VERIFIED). INFERRED: this means a `script-src` entry,
  a `frame-src` entry and a rule change that allows a third script on one page.
  Server-side Siteverify is mandatory; tokens are single use and expire after 300
  seconds (VERIFIED).
- No-JS variant (no CSP change beyond `form-action 'self'`): replace Turnstile with
  a honeypot field, a signed time token and a rate limit by a Cloudflare rate
  limiting rule on the route (INFERRED, to verify before building). Weaker against
  a targeted bot, strong enough for a low-traffic personal site.
- Privacy: the Worker sees the sender's address and message for the length of the
  request; the mailbox keeps the copy. Turnstile processes only what it needs for
  the check (Turnstile overview). Say so on the page and in `/privacy/`.
- Abuse: spam relay is avoided by a fixed destination and fixed sender; reply-to is
  the visitor's address, and header injection is blocked by rejecting CR and LF.
- Cost: Workers free tier covers a personal contact form (INFERRED, check current
  limits); Turnstile has a free tier (INFERRED); sending to a verified destination
  is free.
- Cost to the site's design: a new repository directory for the Worker, a deploy
  path, secrets in the secret manager (never the repository), tests with a fake
  Turnstile server, and a threat-model entry.

## Option (b): mailto plus PGP only (today, with the issue 329 fix)

No server, no script, no third party. The address is plain text between
`email_off` markers (readable without JavaScript), the PGP key is linked. Spam
exposure: a scraper can read the address from the HTML. Mitigation already in
place: business-only wording, PGP, and the optional image variant (below). Cost:
none. Weakness: a visitor with no mail client set up has no easy path; the
Matrix and Discord links stay as the casual route.

## Option (c): a hosted form

A form service (or an embed) hosts the form and the storage. Fastest to ship, worst
fit: the embed or a redirect needs `frame-src`/`form-action` exceptions or sends
visitors off the site; message content and sender data sit with a third party under
its retention terms; free tiers carry limits and branding; most need a script. It
also breaks the "nothing from other sites" statement on `/privacy/`.

## The image variant of the address (shipped as an option, off by default)

`params.emailAsImage = true` (or `HUGO_PARAMS_EMAILASIMAGE=true` for one build) shows
the address as a PNG (`assets/contact/email-address.png`, drawn by
`scripts/gen-email-image.py`) inside the mailto link. The link's accessible name is
the fixed alt text "email address image, open your mail client to write to me",
which never contains the address. Limits, stated plainly: the mailto link still
carries the address in its `href`, so a scraper that reads links still finds it; a
visitor cannot copy the address from the image; the image does not scale with
browser text size. It is a fallback, not the default.

## On-brand design (for options a and b)

- Page: a `/contact/` page of its own, not a redirect, with the title plate (L2) as
  the one framed title, the form in a single L1 `panel` (no frame inside a frame),
  and no L3 unless the page has no other.
- Fields: Name (optional), Reply address (required), Message (required), one
  honeypot. Labels above fields, visible focus ring in `--focus`, inputs on
  `--surface` with `--rule` borders, text `--text`, error text with an icon and
  words, never color alone. Targets at least `--tap` high.
- Dark only: no light fills; the submit button is the existing `btn` with
  `--accent` and `--on-accent` text.
- States: a no-JS confirmation page and a plain error page, both in the site
  template; the Matrix and Discord links stay beside the form as the casual route.
- Short page: fits 1920x1080 without scrolling; checked by `scripts/browser-gate.py`.

## Recommendation

Keep (b) as the live state now, fixed by this issue. If a form is still wanted
after the key cycle (issue 332), build (a) in its no-JS variant first
(honeypot, signed time token, rate limit, verified-destination send, same-origin
POST, `form-action 'self'`): it keeps the CSP and the pinned-scripts rule intact.
Add Turnstile only if the no-JS variant draws spam, and then as a separate decision
because it needs a third-party script on one page. Avoid (c).

Note (2026-11-09): the form is not being built for this site now. It moves to the Reach Around media kit later, gated for business inquiries. The /contact/ page lists email, Discord and Matrix instead (issue 329).
