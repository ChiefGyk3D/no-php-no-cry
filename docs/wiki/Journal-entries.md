# Journal entries

The journal is the second section of the site: short notes on what is being
built, tested and figured out, newest first. It lives in `content/journal/`,
separate from posts, and has its own list page at `/journal/`.

## How it differs from a post

| | Post | Journal entry |
| --- | --- | --- |
| Folder | `content/posts/<slug>/` | `content/journal/<slug>/` |
| Archetype | `archetypes/posts/index.md` | `archetypes/journal/index.md` |
| Length | An article | A short work note |
| Announcement | `syndicate: false` in the archetype; set `true` to announce | `syndicate: false` in the archetype, with a comment that entries are not announced unless you say so |
| Affiliate field | In the archetype | Not in the archetype; add it only if the entry has affiliate links |
| Navigation | Previous and next under "More posts" | Previous and next under "More journal entries" |

Both are leaf page bundles, use the same front matter, the same image rules and
the same checks. Both appear in the site feed, in the sitemap and on
[the Search page](Search-and-tags.md).

## Create one

```sh
hugo new content journal/my-note
```

Fill in `description`, `categories` and `tags`, add images with real alt text
(see [Images and alt text](Images-and-alt-text.md)), set `draft: false`, run the
checks in [Writing a post](Writing-a-post.md) and open a pull request.

## The Journal link in the menu

The main navigation shows a Journal link only when the section has at least one
published entry. With none, the link is not rendered. The repository ships one
synthetic entry, `content/journal/sample-entry/`, so the section is never empty
in a fresh clone; delete it when you add your own.

## Good journal entries

- Say what you did, what happened and what you would do next time.
- Keep private data out: no real callsign, grid square, employer, hostname or
  serial number. Placeholders are listed on [Writing a post](Writing-a-post.md).
- One idea per entry. If it grows into an article, move it to a post.
