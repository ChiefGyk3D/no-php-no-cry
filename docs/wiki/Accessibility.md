# Accessibility

The target is WCAG 2.2 AA. The requirements are written in
`docs/redesign-brief.md` (section 11); the checks are in
`docs/performance-gates.md`. This page says what is built in, what a script
checks on pull requests that change the site, and what no script can prove.

## Built in

- **Skip link first,** then one header, a main navigation with an accessible
  name, one `<main id="main">` and one footer on every page
  (`layouts/baseof.html`). `scripts/check-landmarks.py` fails a built page that
  breaks this.
- **Native controls.** The phone menu is a popover button and accordions are
  `<details>`, so keyboard and assistive technology behavior comes from the
  browser. No script is needed to open anything.
- **Alt text is required** for every informative image, and the build fails
  without it. See [Images and alt text](Images-and-alt-text.md). Card thumbnails
  next to a title link are decorative and have empty alt text.
- **Language is set** on the `<html>` element.
- **Dark-only, high-contrast tokens.** One palette with amber on near-black.
  `scripts/check-contrast.py` computes the ratios of the token pairs from
  `assets/css/tokens.css` and fails below 4.5:1 for text and 3:1 for the focus
  ring.
- **Visible focus** on every control, in the accent color.
- **Frames are decoration.** Corner brackets and rules are CSS backgrounds and
  border images from four small SVG files, drawn outside the focus ring, with
  real text on every control, light lettering on the dark fills and dark lettering on amber (checked at 4.5:1
  by `scripts/check-contrast.py`) and no amber lettering. See `docs/borders.md`.
- **Large targets.** Controls are at least 44 by 44 CSS pixels, with the WCAG
  inline-text-link exception.
- **Motion and forced colors.** The stylesheet has `prefers-reduced-motion` and
  `forced-colors` rules.
- **Search works without script.** The page is a full index first, and the
  filter message is a polite live region. See [Search and tags](Search-and-tags.md).
- **Real text in the DOM** for disclosures, not images of text.

## Checked on site-changing pull requests

The browser gate is skipped for a pull request that only changes documentation
(`docs/*.md`, `docs/wiki/*.md`, `README.md`); see `docs/ci-parallel.md`.

`scripts/browser-gate.py` loads each template in headless Chrome and fails on:

| Rule | What it catches |
| --- | --- |
| `axe` | Any axe-core violation with the tags wcag2a, wcag2aa, wcag21a, wcag21aa, wcag22aa or best-practice. axe-core is vendored in `tools/axe/` with its hash pinned and is never loaded from the network. |
| `overflow` | A horizontal scroll bar, at 1440, 1024, 768, 393 and 390 pixels, at 200 percent zoom and at 320 CSS pixels (WCAG reflow). |
| `target` | A control under 44 by 44 pixels. |
| `tab` | The first Tab stop is not the skip link; a `tabindex` above 0; focus order different from document order; a control that is off screen or has no focus ring; at phone widths, a Menu button that does not open with Enter, close with Escape and return focus. |
| `fit` | A short page that does not fit 1920 by 930 without scrolling (Home, Social, Support, Privacy, 404). |
| `console`, `network` | Console errors, CSP violations, failed requests. |

`scripts/test-browser-gate.sh` runs the gate against fixture sites, each broken
in one way, so a rule that stopped working is caught.

## What no script proves

Be honest about the limits. From `docs/performance-gates.md`:

- axe cannot decide color contrast where text sits on the page's background
  gradient. The token pairs are checked by script and the worst case was
  calculated by hand.
- No screen reader is run. Names, roles and states are checked by axe only.
- Forced colors and print are not exercised by the gate.
- The Chrome on the runner is not pinned.

Automated checks cannot prove conformance. A keyboard and zoom pass by a person
on each template is still required before a launch.

## For authors

- Write alt text for every image and describe what it shows.
- One `<h1>` per page (the title) and no skipped heading levels.
- Link text should name its destination. Do not use "click here".
- Do not rely on color alone, and do not embed content that the Content Security
  Policy would block anyway.
