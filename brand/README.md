# Brand spec and design tokens

The visual system for the static site. The canonical tokens are in
`brand/tokens.json`; `assets/css/tokens.css` is generated from it (do not edit
it): `python3 -I scripts/gen-tokens.py` writes it, `--check` fails on drift
(CI runs `--check`). The generator emits one dark `:root` block. This page says
what the tokens mean and what is still open. Synced to the brand kit
(`chiefgyk3d-brand`, origin/main) on 2026-11-04.
The palette follows Reach Around (`docs/design.md`,
`examples/themes/dark-hero.yaml`), so the site and the link page match.

## Principles

- Dark only (kit decision L). There is no light mode and no theme toggle in
  the brand. `:root` is the only palette, checked for WCAG AA.
- One accent: amber `#FBB03B`. Text on an amber fill is `#1A1A1A` (9.4:1).
- Effects are amber glow only (soft light behind the header, a glow on the
  accent rule and the penguin mark). They are alpha colors and never carry text.
- No color or font is written outside `tokens.css`.

## Color

| Token | Value | Use |
| --- | --- | --- |
| `--bg` | `#0F0F0F` | page (kit dark ground) |
| `--surface` | `#202020` | code blocks, cards (kit charcoal) |
| `--gray` | `#808080` | kit gray: 4.85:1 on the ground, 4.13:1 on the surface (non-text only there) |
| `--text` | `#F0F0F0` | body text |
| `--muted` | `#B5ADA2` | secondary text |
| `--accent` | `#FBB03B` | fills, rules (kit amber) |
| `--on-accent` | `#1A1A1A` | text on an accent fill |
| `--link` | `#FBB03B` | link text |
| `--focus` | `#FBB03B` | focus ring (3:1 needed, has 10.4 on the ground) |
| `--carbon-base`, `--carbon-line` | `#181818`, `#282828` | carbon-fiber ground and stripe |
| `--plate` | `#281808` | warm brown panel |
| `--accent-deep` | `#AF6A0E` | decorative edges only, never text (below 4.5:1) |
| `--rule`, `--border` | `#3A3530` | dividers (decorative, not contrast-checked) |

Retired in the kit sync (issue 78): every light-mode token, the light link and
focus color `#8A5A00`, the ghost gray `#383838` and the cream plate pair
(`--plate-light`, `--focus-on-plate`). `scripts/test-brand.sh` fails if one
returns.

`python3 -I scripts/check-contrast.py` computes every ratio and exits non-zero
below 4.5:1 (text) or 3:1 (focus ring), and on any light or `data-theme` block. `scripts/test-brand.sh` proves it
catches a bad value.

## Spacing, type, UI elements

- Space: `--space-1` to `--space-6` on a 4-point rhythm (`--space` is an alias for `--space-4`, 1rem),
  `--measure` 42rem, `--radius`, `--tap` 44 px minimum target.
- Type scale: `--text-sm` to `--text-2xl`; body is `--text-base` (1.125rem) with
  `--line-height` 1.6.
- Rules: `--rule-width` for dividers, `--rule-accent-width` for the amber bar
  (`.rule-accent`) and the focus ring.
- Chevron: `.chevron`, drawn with borders (`--chevron-size`, `--chevron-width`),
  rotated in CSS for other directions; motion stops under
  `prefers-reduced-motion`.

## Typography

- Body: Jost, an interim choice. It is self-hosted from `static/fonts/`
  (variable weight, Latin subset, SIL Open Font License 1.1, license text in
  `static/fonts/OFL.txt`). The file comes from the `@fontsource-variable/jost`
  npm package, 5.3.0; its sha256 is in `approved-assets.txt`. No font host is
  contacted and the Content-Security-Policy stays `font-src 'self'`.
- Fallback stack: `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`.
- Display: Cyber City is the logo, wordmark and display font ONLY, never body
  or long text (kit decisions Q, R, X4). It is a token (`--font-display`) with
  a Jost fallback. TODO: the font file is NOT bundled in this repo (no license
  document seen here); add it to `static/fonts/` with an `approved-assets.txt`
  line only after review. Until then the wordmark is used as an image and is
  never retyped in CSS or HTML.
- Orbitron (OFL 1.1, kit decision X1) is approved for readable display
  headings. The variable TTF (wght 400-900) is self-hosted unmodified as
  `static/fonts/orbitron-wght.ttf` with its license text in
  `static/fonts/OFL-Orbitron.txt` (both from google/fonts `ofl/orbitron`). It
  is kept as shipped because the OFL Reserved Font Name "Orbitron" forbids a
  converted copy under that name. `brand/tokens.json` lists both font faces
  (`fontFace`); the generator emits one `@font-face` each (`font-display:
  swap`), and `--font-display` is `"Cyber City", Orbitron, Jost, ...`. The CSS
  uses it for h1, h2, HUD headings and the wordmark only, never body text.
- Generated art: `scripts/gen-brand-assets.py` builds the mascot WebP set
  (128/256/512), favicons, the 1200x630 OG card and the social icons from the
  kit; see `brand/assets-build.json` and `brand/ICONS.md`.

## Mascot

The master is Renegade Tux (kit decision T): the 900 px JPEG
`masters/mascot-rifle-penguin-900.jpg` in the brand kit (sha256 in
`approved-assets.txt`), the source for any new avatar or profile art. It is not
committed here. No star variant is ever used.

Approved derivatives are committed under `static/brand/`, all star-free and
listed with sha256 in `approved-assets.txt`:

- `penguin-color.png`: full-color penguin on the dark ground (avatar source).
- `penguin-glyph.svg`: single-color glyph, used as the SVG favicon. The brand
  is dark only; this is not a light-mode asset.
- `mascot-128.webp`, `mascot-256.webp`, `mascot-512.webp`: the mascot WebP set.
- `favicon-32.png`, `favicon-192.png`, `favicon-512.png` and
  `apple-touch-icon-180.png`: the PNG favicon and touch icons.
- `og-card.png`: the 1200x630 Open Graph image, the default in `head-meta.html`.
- `icons/`: the ten social glyphs (see `ICONS.md`).

`.brand-mark` sizes the image. Third-party marks are not republished; see
`EXCLUDED.md`.

## Adding an asset

1. Open the image at full size and look for a Star of David and any
   third-party mark. If in doubt, leave it out.
2. Optimize it, copy it to `static/brand/`, and add a line to
   `approved-assets.txt` with its sha256, source path and verification.
3. Run `scripts/test-brand.sh`.
