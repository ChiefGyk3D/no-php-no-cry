# Social icons

Twelve Simple Icons glyphs (release 16.36.0) are committed unmodified under
`static/brand/icons/`: Twitch, YouTube, Kick, Mastodon, Bluesky, TikTok,
Instagram, Threads, Discord, Matrix, GitHub and Pixelfed. The first eleven are
assets of the brand kit (kit decision AD2). Pixelfed is not in the kit; it is
sourced separately from Simple Icons 16.36.0, whose icon files are CC0 1.0. They are self-hosted (CSP stays `img-src 'self'`) and point to the
maintainer's own accounts only. The marks belong to their owners; the per-icon
license is UNVERIFIED for the first eleven (the project-level CC0 1.0 is source
context only); Pixelfed is verified, see below.
They are not brand masters and not logos of the maintainer.

The glyphs carry no fill, so they draw black. On the dark ground use them as a
CSS mask with a token color (or add an explicit, reviewed recolor step); do not
edit the committed files, whose hashes are pinned in `approved-assets.txt`.

Matrix was added with issue 60 (kit row `icon-matrix`, sha256 pinned in
`scripts/gen-brand-assets.py` and `brand/approved-assets.txt`).

Pixelfed was added with issue 95 from the same Simple Icons release (16.36.0,
`icons/pixelfed.svg`, sha256 `e5a7fe7a...ae653a6`, committed unmodified). It is not
in the brand kit yet, so `scripts/gen-brand-assets.py` takes it from
`--simple-icons DIR` when the kit lacks it. License verified 2026-11-05 from the
release's own `LICENSE.md` (tag 16.36.0): CC0 1.0 Universal for the project's
icon files. The Pixelfed mark itself remains its owner's. The Pixelfed tile on
/social/ shows it beside "Coming soon" and is not a link until the account is live.

Regenerate or verify with `scripts/gen-brand-assets.py` (it checks each source
against the kit's sha256 before copying).

# Coin marks in the support QR codes

`static/support/coin-<coin>.svg` are drawn in the middle of each QR code
(`scripts/gen-support-qr.py`) and beside each coin on /support/. Each is a
64-unit square SVG, self-hosted, no script or link. The cleared square under the
mark covers at most 12 percent of the code area; the codes use error correction
level H and every one is decoded back to the exact address (see
`scripts/gen-support-qr.sh --check --decode`).

| Coin | File | Source and license | Checked |
|---|---|---|---|
| Bitcoin | coin-btc.svg | Wikimedia Commons `File:Bitcoin.svg` (Grayliptrot), the orange disc and white B copied unmodified. Commons license: Public domain (PD textlogo, with-trademark note) | 2026-11-05 via the Commons API |
| Ethereum | coin-eth.svg | Wikimedia Commons `File:Ethereum-icon-purple.svg`, the six facets copied unmodified and scaled onto a dark disc drawn here. Commons license: Public domain (PD textlogo, with-trademark note) | 2026-11-05 via the Commons API |
| Monero | coin-xmr.svg | NOT the Monero mark. A neutral letter badge (amber M on a dark disc), drawn here as plain strokes. The official mark's license is unclear: Commons says public domain, Simple Icons records CC-BY-SA-4.0 for the press-kit logo | 2026-11-05 |
| Solana | coin-sol.svg | NOT the Solana mark. A neutral letter badge (amber S on a dark disc), drawn here. Solana publishes brand guidelines only, no clear free license | 2026-11-05 |

The marks belong to their owners and are used only to say which coin an address
is for. If a license for Monero or Solana is confirmed, replace the badge, update
this table and run `scripts/gen-support-qr.sh`.
