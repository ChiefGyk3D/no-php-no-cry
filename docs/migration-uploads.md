# Old upload redirects per post

`data/legacy_uploads.json` holds 23 redirects, for the two published posts whose old images are listed below (3 for the community-automation post, 20 for the headphone post). The other four migrated posts published in issue 322 have no old upload entries. A draft's page bundle is not built in production, so a 301 to its image would land on a 404: when a post is flipped to `draft: false`, add that post's entries to `data/legacy_uploads.json` in the same pull request (a JSON list of `{"from", "to"}` objects), then run `scripts/test-redirects.sh`. This file is documentation only: the build does not read it.

The Twitch-and-Toot post points at the Stream Daemon post with `supersededBy`; see the note in `docs/cutover.md`.


## building-a-strong-online-community-a-guide-to-automating-your-social-media-communications

| from | to |
| --- | --- |
| `/wp-content/uploads/2023/02/Social-Media-Sharing-1-300x166.png` | `/posts/building-a-strong-online-community-a-guide-to-automating-your-social-media-communications/Social-Media-Sharing-1.webp` |
| `/wp-content/uploads/2023/02/Social-Media-Sharing-1-768x426.png` | `/posts/building-a-strong-online-community-a-guide-to-automating-your-social-media-communications/Social-Media-Sharing-1.webp` |
| `/wp-content/uploads/2023/02/Social-Media-Sharing-1.png` | `/posts/building-a-strong-online-community-a-guide-to-automating-your-social-media-communications/Social-Media-Sharing-1.webp` |

## best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100

| from | to |
| --- | --- |
| `/wp-content/uploads/2023/04/51aoLEfu1JS._AC_SL1500_-1024x568.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/51aoLEfu1JS._AC_SL1500_-1024x568.webp` |
| `/wp-content/uploads/2023/04/51aoLEfu1JS._AC_SL1500_-300x166.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/51aoLEfu1JS._AC_SL1500_-1024x568.webp` |
| `/wp-content/uploads/2023/04/51aoLEfu1JS._AC_SL1500_-768x426.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/51aoLEfu1JS._AC_SL1500_-1024x568.webp` |
| `/wp-content/uploads/2023/04/51aoLEfu1JS._AC_SL1500_.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/51aoLEfu1JS._AC_SL1500_-1024x568.webp` |
| `/wp-content/uploads/2023/04/91hjiNjEy-L._AC_SL1500_-1004x1024.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/91hjiNjEy-L._AC_SL1500_-1004x1024.webp` |
| `/wp-content/uploads/2023/04/91hjiNjEy-L._AC_SL1500_-294x300.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/91hjiNjEy-L._AC_SL1500_-1004x1024.webp` |
| `/wp-content/uploads/2023/04/91hjiNjEy-L._AC_SL1500_-768x783.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/91hjiNjEy-L._AC_SL1500_-1004x1024.webp` |
| `/wp-content/uploads/2023/04/91hjiNjEy-L._AC_SL1500_.jpg` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/91hjiNjEy-L._AC_SL1500_-1004x1024.webp` |
| `/wp-content/uploads/2023/04/AKG_k240_studio-1024x1024.webp` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/AKG_k240_studio-1024x1024.webp` |
| `/wp-content/uploads/2023/04/AKG_k240_studio-150x150.webp` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/AKG_k240_studio-1024x1024.webp` |
| `/wp-content/uploads/2023/04/AKG_k240_studio-1536x1536.webp` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/AKG_k240_studio-1024x1024.webp` |
| `/wp-content/uploads/2023/04/AKG_k240_studio-300x300.webp` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/AKG_k240_studio-1024x1024.webp` |
| `/wp-content/uploads/2023/04/AKG_k240_studio-768x768.webp` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/AKG_k240_studio-1024x1024.webp` |
| `/wp-content/uploads/2023/04/AKG_k240_studio.webp` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/AKG_k240_studio-1024x1024.webp` |
| `/wp-content/uploads/2023/04/image-2-205x300.png` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/image-2.webp` |
| `/wp-content/uploads/2023/04/image-2.png` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/image-2.webp` |
| `/wp-content/uploads/2023/04/image-3-1024x999.png` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/image-3-1024x999.webp` |
| `/wp-content/uploads/2023/04/image-3-300x293.png` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/image-3-1024x999.webp` |
| `/wp-content/uploads/2023/04/image-3-768x749.png` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/image-3-1024x999.webp` |
| `/wp-content/uploads/2023/04/image-3.png` | `/posts/best-headphone-microphone-combo-for-office-gaming-and-music-for-under-100/image-3-1024x999.webp` |
