# Border system

One frame, in three amounts. It is the button frame from the Twitch panels:
stepped corner brackets that split at mid edge, thin amber rules, and (at the
top level only) angled end-cap plates and a faint glow under the bottom rule.
The site is dark only, so there is one set of colors. Calm is the goal: one
frame per region, never a frame inside a framed parent.

Files: `assets/css/borders.css` (all of it), `layouts/_partials/frame.html`
(the one partial that emits a frame), `scripts/test-borders.sh` (the build
test), and the `multiple-l3` rule in `scripts/check-output.sh`.

## Levels

| Level | Draws | Markup | Used on |
| --- | --- | --- | --- |
| L1 whisper | hairline and four 10 by 2 px amber corner ticks | none, pure CSS: the classes `panel`, `tile`, `btn` and `l1` | buttons (including the Menu button and share buttons), tiles, panels, post cards, the previous and next post links, home network chips (hairline only) |
| L2 classy | the same bracket layout, one chamfer per bracket, a corner dash, two thin amber rules, translucent amber fill, no glow | `class="bx l2"` plus the partial | the page title block: a post title and the archive titles (Posts, Journal, tag pages) |
| L3 faithful | the full traced button frame: stepped gradient brackets, end-cap plates, dashes, long and short rules, the faint glow under the bottom rule | `class="bx l3"` plus the partial | ONE per page: the Home hero and the first support link on /support/ |

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
- Forced colors and print hide the SVG and fall back to a plain border.

## Weight

No image, no font. The CSS is about 4 KB minified; an L2 frame is about 0.8 KB
of markup and an L3 frame about 1.8 KB, identical at every use so gzip folds the
repeats. The page budget in `docs/performance-gates.md` is unchanged.
