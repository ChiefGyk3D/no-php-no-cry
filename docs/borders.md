# Border system

One frame, in three amounts. It is the button frame from the Twitch panels:
stepped corner brackets that split at mid edge, thin amber rules, and (at the
top level only) angled end-cap plates and a faint glow under the bottom rule.
The site is dark only, so there is one set of colors. Calm is the goal: one
frame per region, never a frame inside a framed parent.

Colors come from the tokens in `assets/css/tokens.css` (the frame ones, `frame-edge`, `frame-dark` and `frame-mid`, live in `brand/tokens.json`); the frame files hold no hex color.

Files: `assets/css/borders.css` (all of it), `layouts/_partials/frame.html`
(the one partial that emits a frame), `scripts/test-borders.sh` (the build
test), and the `multiple-l3` rule in `scripts/check-output.sh`.

## Levels

| Level | Draws | Markup | Used on |
| --- | --- | --- | --- |
| L1 whisper | hairline and four 10 by 2 px amber corner ticks | none, pure CSS: the classes `panel`, `tile`, `btn` and `l1` | buttons (including the Menu button), tiles elsewhere than /support/, the post share panel, panels, post cards, the previous and next post links, home network chips (hairline only) |
| L2 classy | the same bracket layout, one chamfer per bracket, a corner dash, two thin amber rules, translucent amber fill, no glow | `class="bx l2"` plus the partial | the page title block: a post title and the archive titles (Posts, Journal, tag pages) |
| L3 faithful | the full traced button frame: stepped gradient brackets, end-cap plates, dashes, long and short rules, the faint glow under the bottom rule | `class="bx l3"` plus the partial | ONE per page: the Home hero. The four /support/ tiles are not L3: they are solid amber with the faithful button art at tile size (`frame-faithful-tile*.svg`, issue 285), so /support/ carries none |

Not framed, on purpose: the header and footer (hairline rules only), tag links
on a post, the footer credit, running text. A frame on every element is the
failure this system exists to avoid.

## Adding a frame

1. Pick the level. Default to L1. Use L2 only for the one title that matters on
   a page, and L3 only if the page has no L3 yet.
2. L1: give the element the class `l1` (or use `.panel`, `.tile`, `.btn`). Set
   `--fill` or `--tick` on a state (hover) rather than writing new rules.
3. L2 or L3: add `bx l2` or `bx l3` to the element and put
   `{{ partial "frame.html" (dict "level" 2) }}` as its first child. The element
   needs room for the brackets (the CSS adds padding) and at least about 60 px of
   height. The scale is the CSS variable `--s` (0.24 is the Twitch panel size;
   `s18` is 0.18); change it in CSS, never in the markup.
4. Run `scripts/test-borders.sh`. It fails if a page has two L3 frames.

## Accessibility

- The frame is an `aria-hidden` inline SVG with no focus and no pointer events.
  Nothing carries meaning by the frame alone; a link or button is still a link
  or button with a real text label.
- Text on a frame is `--text` (cream) or `--on-accent` (on an amber fill). Amber
  lettering is not used: amber text on a light ground is 1.66 to 1 and fails.
  Amber is a line color here.
- Hover swaps a control's fill to amber with `--on-accent` text. Focus is an
  outline drawn on the element itself, outside the frame, so no frame clips it.
- Tap targets stay at least 44 px (`--tap`); the browser gate measures them.
- No animation by default. The L3 glow may breathe only on an element with the
  class `live`, only inside `prefers-reduced-motion: no-preference`. Nothing uses
  that class yet.
- Forced colors and print hide the SVG and the rule and glow layers, and fall back to a plain border (print also drops the backgrounds).

## Weight

No image, no font. The CSS is about 6 KB before minifying; an L2 frame is about 0.8 KB
of markup and an L3 frame about 1.8 KB, identical at every use so gzip folds the
repeats. The page budget in `docs/performance-gates.md` is unchanged.

## Button levels (issue 283)

Only buttons have a level setting; every other element keeps the look it has
above. That includes panels (`.panel`) and tiles (`.tile`), which keep last night's
light L1 frame (hairline and four ticks) on purpose: the owner decided on
2026-11-09 to keep every non-button element exactly as it was on Nov 8. Stripping
them is a possible later pass. The setting lives in one place, `params.frames` in `hugo.toml`:

| Level | Look |
| --- | --- |
| `minimal` (default on every button except the primary) | the L1 look: a graphite hairline and four amber ticks |
| `faithful` | the owner's button art, `static/brand/frame-faithful-button.svg` (`-amber` on amber), over the button's fill |
| `none` | the pre-frame button: an amber border, no ticks |

The shipped default is `level = "minimal"` with `btn-primary = "faithful"`: the primary buttons (Read the latest, Start over) wear the faithful art and every other button the minimal frame. `level` is the default for every button; `[params.frames.classes]` overrides one
button class (`btn-primary`, `btn-ghost`, and the specific `nav-toggle`,
`copy-btn`, `product-btn`), the most specific entry winning. An unknown level
fails the build. `layouts/_partials/btn-frame.html` turns the setting into a
`bf-none` or `bf-faithful` class (minimal adds no class).

The frame is drawn inside the button's own box. Width, height, padding, margin
and border width never change with the level, so the three hero buttons stay on
one line at every level (measured: bounding boxes of every element on the Home and
404 pages at 1920, 1280 and 390 wide are identical at every level). Fills are the
existing ones: amber on primary, the translucent amber tint on ghost, amber on
hover. No cream or white fill anywhere; the primary hover stays amber. The art
is generated by `scripts/gen-frame-art.py`; `scripts/test-borders.sh` checks it
is current.
