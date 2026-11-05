# Excluded brand files

Brand art is kept outside the repository, in a local import folder. These files
were considered and are not committed, and must not be added. Synced to the
brand kit (`chiefgyk3d-brand`, `assets/MANIFEST.md`, decisions C, T, V1 and
AD2) on 2026-11-04.

| File or folder | Why |
| --- | --- |
| `Personal Logo/DO NOT USE - star versions` (the whole folder) | Mascot variants with a Star of David. Public brand art uses the mascot without it. |
| `Personal Logo/Banners/Twitter V2.png` | Still contains the star. |
| `Twitter.png`, `Soundcloud.png`, `Soundcloud V2.png`, `Tinker_Preview.jpg` and the OBS Stream copy of `Linux A V2.png` | Star versions, retired (kit decision C). No star variant is ever approved. |
| `Linux Penguin.stl` | Whether the 3D model carries the star is unconfirmed (kit decision C); not used. |
| Any other file where the star appears | Rejected by eye; the rule has no exceptions. |
| BSD daemon and FreeBSD logos (`freebsd-logo-*`, `kisspng-*`, `png-clipart-*`, `png-transparent-*`) | Third-party marks, not ours to republish. |
| Social and platform icons other than the ten below: the Social_stream, cryptocurrency and payment icons in `OBS Stream/Linux Gaming`, and the kit's `icons/simple-icons/matrix.svg` | Third-party marks, not brand masters, license unverified per icon (kit decision AD2). Matrix and Pixelfed are not shipped; see `brand/ICONS.md`. |
| Not excluded since 2026-11-04 (maintainer ruling, issue 53): the kit's Simple Icons glyphs for Twitch, YouTube, Kick, Mastodon, Bluesky, TikTok, Instagram, Threads, Discord and GitHub | Committed unmodified under `static/brand/icons/`, self-hosted, listed in `approved-assets.txt`. They point to the maintainer's own accounts only; the marks belong to their owners and the per-icon license stays UNVERIFIED (kit AD2). |
| `My Account Billing.pdf` and the OBS, Clips, Streams and Music folders | Personal or large; never part of the site. |
| Banners, business cards, DEF CON card art, Trezor and Mastodon images | Not approved in issue #2. Each needs its own by-eye star check and a manifest line before it can be used. |
| The kit emote masters (`masters/emotes/`: PenguinRIP, PenguinHype, DealWithIt, BanHammer, Beasty) | Approved in the kit for Twitch emote use, not for the site. Each needs a manifest line here before use. |
| `masters/mascot-rifle-penguin-900.jpg` (Renegade Tux, the 900 px master) | The approved master, listed in `approved-assets.txt` as the source for new art. It is not committed here; `scripts/gen-brand-assets.py` reads it from outside the repo and commits only the derivatives (WebP 128/256/512, favicons, OG card). |
| Cyber City font files (`Cyber City.otf` and any copy) | The font is for the logo, wordmark and display role only (kit decisions Q, R, X4). The file is never stored in the repo; only the `--font-display` token exists. `scripts/check-brand-assets.sh` bans any file name containing `cyber`. Orbitron (kit decision X1, OFL) is the self-hosted display font instead; see `approved-assets.txt`. |
| `Branding Concepts/Linux White.svg` | A plain silhouette; not part of the approved pair. |
| `Linux_A_V2.png` | A 1080x1080 poster with a baked-in background and a ghosted mascot; too large and not transparent. |

`scripts/check-brand-assets.sh` fails on any file under `static/brand/` that is
not listed in `approved-assets.txt`, and on any banned name.
