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

LinkedIn was added with issue 195 as a footer-only icon (`footer_only: true` in
`data/socials.yaml`; it is not on /social/, the Home chips, the rel=me links,
sameAs or llms.txt). The official LinkedIn marks are trademarked brand assets,
so the glyph is the `linkedin` icon of Bootstrap Icons instead: release tag
v1.13.2 (commit `afbfcbcb9bea79ea9923fa9ef82ea03d7ee6c01f`), `icons/linkedin.svg`,
committed unmodified, sha256 `ddcbb273...c71e2df`. License verified 2026-11-08
from the repository's own `LICENSE` at that tag: MIT, Copyright (c) 2019-2024 The
Bootstrap Authors; the license text is kept in `brand/LICENSE-bootstrap-icons.txt`.
The glyph is `fill="currentColor"` on a 16x16 viewBox; used as a CSS mask image
it draws black like the Simple Icons glyphs and the mask scales it to the same
box. The LinkedIn name and mark remain their owner's.

Regenerate or verify with `scripts/gen-brand-assets.py` (it checks each source
against the kit's sha256 before copying).

# Coin marks in the support QR codes

`static/support/coin-<coin>.svg` are drawn in the middle of each QR code
(`scripts/gen-support-qr.py`) and beside each coin on /support/. Each is an
SVG with a square viewBox (any size, the generator scales it), self-hosted, no script or link. The cleared square under the
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

# Portrait

`static/brand/portrait-640.webp` and `portrait-320.webp` are the owner's portrait
(face and shoulders in front of a network rack), shown on /about/ and /resume/
(issue 179). They are published copies only: the original photo is **not stored in
this repository** and must never be committed, in any form (no JPEG, no larger
WebP, no copy under `content/` or `assets/`).

Processing, from a square owner-supplied photo (no crop was needed):

1. `convert <original> -auto-orient -strip -filter Lanczos -resize NxN -define webp:method=6 -quality 80 portrait-N.webp`
   for N = 640 and 320. `-strip` removes every profile and tag.
2. Metadata proof with `exiftool -a -G1 <file>`: only the file-system, RIFF and
   image-size tags remain. No EXIF, XMP, IPTC, GPS, camera, serial or date tags, and
   no embedded thumbnail; each file is a single VP8 RIFF chunk.
3. The build keeps it that way: `scripts/check-image-metadata.py` (run by
   `scripts/check-output.sh`, rule `image-metadata`) fails on any EXIF with tags, XMP or
   IPTC in a published image, and `scripts/test-pages.sh` re-checks the portrait files and
   proves the check bites with a fixture carrying a GPS tag.

| File | Size | sha256 |
|---|---|---|
| portrait-640.webp | 640x640, 23222 bytes (cap 60 KB) | `5900d215afdb50775edf59c7abdd8c8ef228749ceb84e22f6aa281e644070134` |
| portrait-320.webp | 320x320, 9468 bytes (cap 25 KB) | `1cd96fd8089a516d8ce9a752e4d5e1b0bdf1234e014ec6e551d893c5dad16c93` |

Both are served from this site (CSP `img-src 'self'` is unchanged). To replace the
portrait, repeat the steps from a new original kept outside the repository, update
the hashes here and in `approved-assets.txt`, and keep the alt text.
