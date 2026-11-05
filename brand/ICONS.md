# Social icons

Eleven glyphs from the brand kit's Simple Icons set (release 16.36.0, kit
decision AD2) are committed unmodified under `static/brand/icons/`:
Twitch, YouTube, Kick, Mastodon, Bluesky, TikTok, Instagram, Threads, Discord,
Matrix and GitHub. They are self-hosted (CSP stays `img-src 'self'`) and point to the
maintainer's own accounts only. The marks belong to their owners; the per-icon
license is UNVERIFIED (the project-level CC0 1.0 is source context only).
They are not brand masters and not logos of the maintainer.

The glyphs carry no fill, so they draw black. On the dark ground use them as a
CSS mask with a token color (or add an explicit, reviewed recolor step); do not
edit the committed files, whose hashes are pinned in `approved-assets.txt`.

Matrix was added with issue 60 (kit row `icon-matrix`, sha256 pinned in
`scripts/gen-brand-assets.py` and `brand/approved-assets.txt`).

TODO (maintainer): Pixelfed has no icon in the kit. Until one is added (with a
manifest line), the Pixelfed tile on /social/ shows a neutral CSS-drawn
placeholder (`.social-icon--placeholder` in `assets/css/pages/social.css`).
Do not draw or invent the icon.

Regenerate or verify with `scripts/gen-brand-assets.py` (it checks each source
against the kit's sha256 before copying).
