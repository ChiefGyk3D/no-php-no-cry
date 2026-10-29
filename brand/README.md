# Brand spec and design tokens

The visual system for the static site. The canonical tokens are in
`brand/tokens.json`; `assets/css/tokens.css` is generated from it (do not edit
it): `python3 -I scripts/gen-tokens.py` writes it, `--check` fails on drift
(CI runs `--check`). The generator emits the light palette for the system
preference and for `:root[data-theme="light"]`, and pins dark under
`:root[data-theme="dark"]`. This page says what the tokens mean and what is
still open.
The palette follows Reach Around (`docs/design.md`,
`examples/themes/dark-hero.yaml`), so the site and the link page match.

## Principles

- Dark first. `:root` is the dark palette; `prefers-color-scheme: light`
  overrides it. Both modes are checked for WCAG AA.
- One accent: amber `#FBB03B`. Text on an amber fill is `#1A1A1A` (9.4:1).
- Effects are amber glow only (soft light behind the header, a glow on the
  accent rule and the penguin mark). They are alpha colors and never carry text.
- No color or font is written outside `tokens.css`.

## Color

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `--bg` | `#0E0E0E` | `#FAF7F2` | page |
| `--surface` | `#181716` | `#F0EBE3` | code blocks, cards |
| `--text` | `#F0F0F0` | `#1A1A1A` | body text |
| `--muted` | `#B5ADA2` | `#5C554C` | secondary text |
| `--accent` | `#FBB03B` | same | fills, rules |
| `--on-accent` | `#1A1A1A` | same | text on an accent fill |
| `--link` | `#FBB03B` | `#8A5A00` | link text |
| `--focus` | `#FBB03B` | `#8A5A00` | focus ring (3:1 needed, has 10.5 and 5.5) |
| `--carbon-base`, `--carbon-line` | `#181818`, `#282828` | n/a | carbon-fiber ground and stripe (dark only) |
| `--plate` | `#281808` | n/a | warm brown panel (dark only) |
| `--ghost` | `#383838` | n/a | ghosted mascot layer (dark only, no controls) |
| `--plate-light` | `#FFEFD9` | same | cream plate; focus and links use `--focus-on-plate` |
| `--focus-on-plate` | `#8A5A00` | same | focus ring and link text on the cream plate |
| `--accent-deep` | `#AF6A0E` | same | decorative edges only, never text (below 4.5:1) |
| `--rule`, `--border` | `#3A3530` | `#D9D1C5` | dividers (decorative, not contrast-checked) |

Amber is too light to be text on the light page (1.7:1), so light mode uses the
darker `#8A5A00` for links and the focus ring.

`python3 -I scripts/check-contrast.py` computes every ratio and exits non-zero
below 4.5:1 (text) or 3:1 (focus ring). `scripts/test-brand.sh` proves it
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
- Wordmark: the font is not known (it came from a designer). OPEN: confirm the
  font name and license with the designer. Until then the wordmark is used only
  as an image and is never retyped in CSS or HTML. No wordmark image is
  committed yet.

## Mascot

Two approved files, both star-free and checked by eye (details in
`approved-assets.txt`):

- `static/brand/penguin-color.png`: full-color penguin, use on dark.
- `static/brand/penguin-glyph.svg`: black glyph with a white edge, use on light.

Pick between them with `<picture>` and `prefers-color-scheme`, which needs no
script and no inline style. `.brand-mark` sizes the image. Third-party marks
are not republished; see `EXCLUDED.md`.

## Adding an asset

1. Open the image at full size and look for a Star of David and any
   third-party mark. If in doubt, leave it out.
2. Optimize it, copy it to `static/brand/`, and add a line to
   `approved-assets.txt` with its sha256, source path and verification.
3. Run `scripts/test-brand.sh`.
