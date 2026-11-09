# Border system

The button frame from the owner's Twitch, Kick and YouTube art, used on every
control and container of the blog. Stepped graphite corner brackets with a
mid-edge split and an amber stub, angled end-cap plates top and bottom with a
window and a dash, long thin amber rules, a cream plate with ink lettering, and
a soft amber bloom. The site is dark only.

## How it is drawn

No markup per frame: a frame is the class `fx` (one class on the element, which
is the whole markup cost). `assets/css/borders.css` draws it from three SVG files
under `static/brand/` (`img-src 'self'`, each listed with its sha256 in
`brand/approved-assets.txt`):

| File | Used for |
| --- | --- |
| `frame-corners.svg` | the four brackets (with the amber dash), as a `border-image` nine-slice; slices are in original pixels so they scale with height, not width |
| `frame-plates-top.svg`, `frame-plates-bottom.svg` | the end-cap plates, a background layer centered on the top and bottom edge |

The rules, the mid-edge stubs, the cream plate and the glow are CSS (gradients
and a box shadow). Colors come from the tokens (`frame-cream`, `frame-ink`,
`frame-edge` in `brand/tokens.json`); the bracket gradient (010101 to 4B4B4B to
2B2B2B) is in the SVG art.

## Scale

`--s` is the scale of the 318 px tall original (the Donate button is 1332 by
318). The corner bars are 20 px at the original size, so about 6 percent of the
frame height at every `--s`, never a hairline. `min-height` is 318 times `--s`
so the two brackets never touch. Steps: `sm` 0.14 (chips, nav, section
banners), default 0.18 (buttons, tiles, cards), `lg` 0.22 (the hero card and the
resume head), `xl` 0.28 (page title banners). Scale is chosen by class, never by
inline style.

## Two kinds, and plates

- `fx`: the faithful frame, a cream plate with ink lettering (`--frame-ink`), for
  things you act on and for headings: buttons, tiles, cards, chips, the search
  input, the Menu button, title and section banners, the hero card, accordion
  summaries.
- `fx dk`: the lighter related frame, the same brackets (same art, never lightened) on the dark
  surface with normal text colors, for containers that hold running text, code or tables: the
  About bio and cards, the contact card, the archive notice, the coin cards, the
  nav list, the footer container, post images and the headline image, and
  `pre`, `table` and `blockquote` in a post (selected in CSS, no class needed).
- `pl` adds the glow tiers, and with `lg` or `xl` the end-cap plates and the short
  outer rules (the hero, the page titles, the resume head). The plates need an
  element at least 1228 times `--s` wide; below 30rem the large scales step down
  to 0.18 so they still clear the brackets. At the small scales the plates would
  be a few mushy pixels, so smaller frames keep the brackets, long rules, stubs,
  plate and glow.

Inside a cream plate every descendant is ink (a muted or amber text color would
fail contrast on cream); links keep their underline and the social icons turn
ink. Hover fills the plate with amber, the ink stays.

## Glow and rule thickness

Rules are 6 px at the original size and never thinner than 3 px at small
scales. The bloom hugs the rules: a `pl` frame has a blurred copy of its rule layers
behind the content (a pseudo-element with a blur filter), 5 px of falloff on a
card or banner and about 20 px with extra brightness on the hero and title
banners (`lg`, `xl`), as in the camera border. Small controls carry no bloom
until hover or focus, so a page of chips costs no extra paint time. There is no
element-wide shadow. The short outer rules above and
below the plate are drawn only with the plates; a small control has the
long inner rules only, so nothing floats outside its box.

## Rules

- A frame never contains another frame. A coin card is a frame and its Copy
  button is a second frame beside it, not inside it. `scripts/test-borders.sh`
  parses every built page and fails on a frame inside a frame.
- There is no per-page limit on frames; every page with a `main` element must
  carry frames, and Home, Support, Social, Products, Search, About and Resume
  must carry at least five (the test asserts it).
- No frame on running text, inline links or the footer credit line; the footer
  container carries the dark kind.
- No inline svg, no `style` attribute, no script. Hover, focus and scale are
  CSS. `scripts/check-output.sh` fails a page with an inline frame svg
  (`inline-frame`).
- Focus is an outline on the element itself, offset 5 px, outside the frame.
- Forced colors and print drop the art and the glow and fall back to a plain
  border (print also drops the fills).
- Tap targets stay at least 44 px: the smallest scale gives a 44.5 px frame.

## Motion

The static look is the exact ON state (every rule lit, full bloom). An opt-in
layer, only under `prefers-reduced-motion: no-preference` and only on an
element with the class `live`, reproduces the owner's camera border: the long
top bar switches off and on with 0.3 second ramps on a 4 second cycle and
settles slowly while lit; the bottom rule stays steady. It animates the
opacity of one pseudo-element, so nothing shifts and LCP and CLS are
unaffected. `live` is set only on the Home hero card and on the page title
banner, so at most one frame per page moves; many moving glows at once are too
much motion and cost paint time. The dash blinks and the side-rule flicker of the
video are not reproduced.

## Adding a frame

1. Put `fx` on the element (plus `dk` for a container with running text, `pl`
   if it is wide enough, a scale class if the default does not fit).
2. If the element needs its own padding, set `--py` and `--px` on it, not
   `padding`, so the brackets keep their room.
3. Run `scripts/test-borders.sh`.

## Weight

No new font and no raster image. The three SVG files are about 2 KB together; the
CSS is about 4 KB before minifying. The page budget in
`docs/performance-gates.md` is unchanged (the largest page rose by about 1.5 KB).
