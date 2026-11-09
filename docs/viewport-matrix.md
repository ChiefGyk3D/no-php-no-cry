# Viewport matrix

Layout changes are measured, not eyeballed. The owner browses a 1920x1080 screen with the
browser window not in full screen, so the real viewport is about 1878 wide by 930 high (page
scrollbar plus a browser side panel). Measure at 1878x930 first.

| Viewport | Why |
| --- | --- |
| 1878x930 | the owner's real window |
| 1920x1080 | the full-screen desktop target |
| 1728x1000 | large laptop |
| 1536x860 | common laptop at 125 percent scale |
| 1440x800 | laptop |
| 1366x768 | the smallest width where the hero buttons must share one row |
| 1280x720 | small laptop |
| 390x844 | phone; the hero buttons may stack |

## What to measure

- Home hero: the three buttons (Read the latest, See my projects, Support my work) have the
  same `top` and the last right edge is inside the hero box, at every viewport from 1280 up.
  Each button stays at least 44px tall (`--tap`).
- Boxes (`.panel`, `.skill-group`, `.about-contact`, `.fact-card`): the right edge of the
  widest text line sits within about 25 percent of the box content width. The text measure in
  a box is `--box-prose-max` (100ch); page prose stays at `--prose-max` (75ch).
- Rows that wrap (`flex-wrap`, grids): a row wraps only when the items no longer fit.
- No horizontal page scroll.

Use headless Chromium with `--window-size` or CDP `Emulation.setDeviceMetricsOverride`, and read
`getBoundingClientRect()`. The Playwright MCP screenshot call times out here.

## What CI covers

Two layers, and neither replaces the other.

- Browser gate (`scripts/browser-gate.py`, the "browser gate" leg of the `ci` job, headless
  Chrome over a pipe, run on site changes). Besides its older rules it now loads every page
  template at 1878x930 and 1366x768 and fails `[hero]` when the `.hero-actions` buttons are on
  more than one row or the page scrolls sideways, and `[boxtext]` when the widest text line of
  a bordered box (`.panel`, `.skill-group`, `.about-contact`) with a wrapping paragraph ends more
  than 25 percent of the box content width short of its right edge. Its other rules run at 1440,
  1024, 768, 393 and 390 wide, and the fit rule at 1920x930. It does not run 1728, 1536, 1440x800
  or 1280 for the hero row; those are measured by hand with the matrix above. Its self-test is
  `scripts/test-browser-gate.sh` (fixture pages that break each rule).
- `scripts/test-layout.sh` is a CSS-level check with no browser or build: it guards the rules
  themselves (hero row gap and padding, the 6fr 5fr hero grid, the prose tokens and the box
  rule) and names the rule when one is edited away. If you change one of those values,
  re-measure the matrix above and update both checks in the same pull request.
