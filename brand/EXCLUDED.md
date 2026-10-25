# Excluded brand files

Brand art is kept outside the repository, in a local import folder. These files
were considered and are not committed, and must not be added.

| File or folder | Why |
| --- | --- |
| `Personal Logo/DO NOT USE - star versions` (the whole folder) | Mascot variants with a Star of David. Public brand art uses the mascot without it. |
| `Personal Logo/Banners/Twitter V2.png` | Still contains the star. |
| Any other file where the star appears | Rejected by eye; the rule has no exceptions. |
| BSD daemon and FreeBSD logos (`freebsd-logo-*`, `kisspng-*`, `png-clipart-*`, `png-transparent-*`) | Third-party marks, not ours to republish. |
| Social and platform icons (Social_stream, the crypto and payment icons in `OBS Stream/Linux Gaming`) | Third-party marks. |
| `My Account Billing.pdf` and the OBS, Clips, Streams and Music folders | Personal or large; never part of the site. |
| Banners, business cards, DEF CON card art, emotes, Trezor and Mastodon images | Not approved in issue #2. Each needs its own by-eye star check and a manifest line before it can be used. |
| `Branding Concepts/Linux White.svg` | A plain silhouette; not part of the approved pair. |
| `Linux_A_V2.png` | A 1080x1080 poster with a baked-in background and a ghosted mascot; too large and not transparent. |

`scripts/check-brand-assets.sh` fails on any file under `static/brand/` that is
not listed in `approved-assets.txt`, and on any banned name.
