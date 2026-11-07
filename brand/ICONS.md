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
/social/ is a live link to https://pics.chiefgyk3d.com/ChiefGyk3D (issue 106) with
rel="me", and the footer row carries it like the other profiles.

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
| Monero | coin-xmr.svg | The official Monero symbol (orange and grey M in a circle), redrawn as plain vector shapes from the press-kit PNG `monero-symbol-1280.png` (getmonero.org/press-kit/symbols/, the maintainer's copy), geometry and colors (#FF6600, #4C4C4C) matched to the pixel (1.7 percent RMSE against the PNG after antialiasing). The press kit offers PNG and .ai only, no SVG. The press-kit page states no license; the repo uses the mark by the maintainer's explicit instruction, only to say which coin an address is for. License UNVERIFIED | 2026-11-07 |
| Solana | coin-sol.svg | The official Solana Foundation logomark (three-bar S, gradient #9945FF to #19FB9B), from https://solana.org/branding (file `/pages/branding/logomark/logomark.svg`, fetched 2026-11-07, source sha256 `212da615...f25216`). Paths and gradient stops are unmodified; the 72x64 canvas is padded to a 72x72 square (a 4.18 unit vertical offset) so it fits the square-viewBox rule. Terms on that page: use the logos when promoting the Solana Foundation in marketing communications; do not add shadows, add outlines, stretch, apply in low resolution, use as a frame for imagery, or place on low-contrast colors. The page footer says all rights reserved and gives no open license. The mark is shown uniformly scaled on a white square, with no effect added, and says only which coin an address is for | 2026-11-07 |

The marks belong to their owners and are used only to say which coin an address
is for. If a license for any mark is found to forbid this use, replace it, update
this table and run `scripts/gen-support-qr.sh`.
