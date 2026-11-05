# Social icons

Ten glyphs from the brand kit's Simple Icons set (release 16.36.0, kit
decision AD2) are committed unmodified under `static/brand/icons/`:
Twitch, YouTube, Kick, Mastodon, Bluesky, TikTok, Instagram, Threads, Discord
and GitHub. They are self-hosted (CSP stays `img-src 'self'`) and point to the
maintainer's own accounts only. The marks belong to their owners; the per-icon
license is UNVERIFIED (the project-level CC0 1.0 is source context only).
They are not brand masters and not logos of the maintainer.

The glyphs carry no fill, so they draw black. On the dark ground use them as a
CSS mask with a token color (or add an explicit, reviewed recolor step); do not
edit the committed files, whose hashes are pinned in `approved-assets.txt`.

TODO (maintainer): Pixelfed has no icon in the kit. Matrix does have one in the
kit (`icons/simple-icons/matrix.svg`) but was left out of this set on request;
add it, with a manifest line, when the site links a Matrix account. Do not draw
or invent either icon.

Regenerate or verify with `scripts/gen-brand-assets.py` (it checks each source
against the kit's sha256 before copying).
