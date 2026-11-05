# Social icons

Twelve glyphs from the brand kit's Simple Icons set (release 16.36.0, kit
decision AD2) are committed unmodified under `static/brand/icons/`:
Twitch, YouTube, Kick, Mastodon, Bluesky, TikTok, Instagram, Threads, Discord,
Matrix, GitHub and Pixelfed. They are self-hosted (CSP stays `img-src 'self'`) and point to the
maintainer's own accounts only. The marks belong to their owners; the per-icon
license is UNVERIFIED for the first eleven (the project-level CC0 1.0 is source
context only); Pixelfed is verified, see below.
They are not brand masters and not logos of the maintainer.

The glyphs carry no fill, so they draw black. On the dark ground use them as a
CSS mask with a token color (or add an explicit, reviewed recolor step); do not
edit the committed files, whose hashes are pinned in `approved-assets.txt`.

Matrix was added with issue 60 (kit row `icon-matrix`, sha256 pinned in
`scripts/gen-brand-assets.py` and `brand/approved-assets.txt`).

Pixelfed was added with issue 95 from the same Simple Icons release (16.36.0,
`icons/pixelfed.svg`, sha256 `e5a7fe7a...ae653a6`, committed unmodified). It is not
in the brand kit yet, so `scripts/gen-brand-assets.py` takes it from
`--simple-icons DIR` when the kit lacks it. License verified 2026-11-05 from the
release's own `LICENSE.md` (tag 16.36.0): CC0 1.0 Universal for the project's
icon files. The Pixelfed mark itself remains its owner's. The Pixelfed tile on
/social/ shows it beside "Coming soon" and is not a link until the account is live.

Regenerate or verify with `scripts/gen-brand-assets.py` (it checks each source
against the kit's sha256 before copying).
