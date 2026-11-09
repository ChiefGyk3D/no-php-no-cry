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

## CI guard

A browser is not available in CI, so `scripts/test-layout.sh` asserts the CSS rules behind the
measurements (hero row gap and padding, the 6fr 5fr hero grid, the prose tokens and the box
rule) and runs a self-test that breaks each rule and requires a failure. If you change one of
those values, re-measure the matrix above and update the test in the same pull request.
