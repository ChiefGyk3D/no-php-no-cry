# Token drift between this blog and Reach Around

The blog is the source of truth for the shared design tokens. `brand/tokens.json`
here is canonical. Reach Around vendors a copy at `vendor/brand/tokens.json` and
pins it in `vendor/brand/tokens.lock.json` (source repo, source commit, sha256).
Reach Around maps the values onto its own `--ra-*` names; the blog generates
`assets/css/tokens.css` with `scripts/gen-tokens.py`.

Drift can go either way, so each repo has its own check.

## Check from this side

```
scripts/check-reach-around-drift.sh
```

It reads Reach Around's vendored `tokens.json` and lock from its default branch
through the GitHub REST contents API (public repo, no token, 20 second limit,
`--timeout SECS` to change it). It prints the blog commit Reach Around is pinned
to, then every token key added, removed or changed on that side (`token:<name>`,
`fontFace:<family>`, `version`), and whether Reach Around's own sha256 pin
matches its file. Exit 0 is no drift, 1 is drift, 3 is a fetch or parse error.

`--offline` skips the check with a message and exits 0. Use it wherever the
network is not available. A failed fetch without `--offline` is exit 3, never a
pass. `scripts/test-check-reach-around-drift.sh` tests the check with fixture
copies and no network.

The check is not part of CI: it depends on another repository's live state, so
it could turn this repository's required check red for a change made elsewhere.
Run it by hand before changing a token and after Reach Around re-vendors.

## Check from the Reach Around side

`python3 -I scripts/check-token-drift` there verifies the vendored file against
its pinned sha256 and that the generated theme matches. It does not look at this
repository, so a blog change shows up only when this script is run here.

## Re-vendor (a blog token changed)

In Reach Around, on a branch:

1. Copy this repo's `brand/tokens.json` over `vendor/brand/tokens.json`.
2. In `vendor/brand/tokens.lock.json` set `source.commit` to the blog commit the
   file came from and `sha256` to `sha256sum vendor/brand/tokens.json`.
3. `python3 -I scripts/gen-brand-theme.py`, then `python3 -I scripts/check-token-drift`.
4. Open a pin-only PR that links the blog issue.

Then run `scripts/check-reach-around-drift.sh` here and expect exit 0.

## Propose a token change from the Reach Around side

Do not edit `vendor/brand/tokens.json` by hand: the next re-vendor would erase
it, and the pin check would fail. Instead:

1. Open an issue in this repo naming the token key, the old and new value and
   why Reach Around needs it.
2. Change `brand/tokens.json` here, run `python3 -I scripts/gen-tokens.py` and
   `python3 -I scripts/check-contrast.py assets/css/tokens.css`, and merge.
3. Re-vendor on the Reach Around side as above.

A value that only Reach Around needs stays in its own theme or `--ra-*` mapping
and does not go into the shared file.
