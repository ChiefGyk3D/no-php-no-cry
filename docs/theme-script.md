# The theme script allowlist

`/theme.js` is the only script the site ships (`script-src 'self'`, under 1 KB
gzip). `theme_capability_bad` in `scripts/artifact-rules.sh` accepts it only if
it is plainly a theme toggle, by allowlist:

- ASCII only; no backslash, backtick, `[`, or comment (`//`, `/* */`).
- After a dot, only these names: `documentElement body head dataset classList
  add remove toggle contains getItem setItem matches matchMedia
  addEventListener getAttribute removeAttribute setAttribute createElement
  appendChild textContent type hidden title className querySelector
  getElementById preventDefault target currentTarget document localStorage`.
  Any name after `dataset.` is free.
- `createElement` only with `"button"`; `setAttribute` only with `data-theme`,
  `aria-pressed`, `aria-label`, `type`, `title`, `class` or `hidden`.
- A bare name is a keyword or one of `document window localStorage matchMedia`,
  or at most three characters (a local such as `t`).

Anything else fails `theme-capability`. To use another API, add its name to the
lists in `scripts/artifact-rules.sh` in a reviewed change with a test, and to
this page.
