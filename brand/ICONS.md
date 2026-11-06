# Social icons

Eleven glyphs from the brand kit's Simple Icons set (release 16.36.0, kit
decision AD2) are committed unmodified under `static/brand/icons/`:
Twitch, YouTube, Kick, Mastodon, Bluesky, TikTok, Instagram, Threads, Discord,
Matrix and GitHub. They are self-hosted (CSP stays `img-src 'self'`) and point to the
maintainer's own accounts only. The marks belong to their owners; the per-icon
license is UNVERIFIED (the project-level CC0 1.0 is source context only).
They are not brand masters and not logos of the maintainer.

The glyphs carry no fill, so they draw black. On the dark ground use them as a
CSS mask with a token color (or add an explicit, reviewed recolor step); do not
edit the committed files, whose hashes are pinned in `approved-assets.txt`.

Matrix was added with issue 60 (kit row `icon-matrix`, sha256 pinned in
`scripts/gen-brand-assets.py` and `brand/approved-assets.txt`).

TODO (maintainer): Pixelfed has no icon in the kit. Until one is added (with a
manifest line), the Pixelfed tile on /social/ shows a neutral CSS-drawn
placeholder (`.social-icon--placeholder` in `assets/css/pages/social.css`).
Do not draw or invent the icon.

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
