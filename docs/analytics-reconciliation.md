# Why the two counters do not match (issue 301)

The blog has two page counters: Cloudflare Web Analytics (a script beacon) and the
blog's own server-side counter (the Pages Function). They will not match, and neither
number is exact. A gap between them is expected. It is not, by itself, a bug or a leak.

## Expected causes of the mismatch

- **Script blockers.** Cloudflare's beacon runs as a script, so it misses visitors who
  block it. The blog counter runs on the server, so it also counts visitors who block
  scripts.
- **Crawlers, prefetches and link previews.** The blog counter counts crawlers in their
  own bot class. It leaves out prefetches and link previews when the request is marked as
  one, but an unmarked one can still be counted. Cloudflare may treat all of these
  differently, so the two counters can disagree in either direction.
- **Global Privacy Control and Do Not Track.** The blog counter records nothing for a
  visitor who sends either signal, so those visitors are missing from it.
- **UTC days.** The blog counter groups by UTC day. A day in another time zone or in the
  Cloudflare dashboard can start and end at different moments.
- **The 5 view floor.** The blog report hides cells with fewer than 5 views (small
  places are merged into a larger area), so small numbers are absent from the report.
- **Fail-open drops.** If the Function fails, the page still loads and that one count is
  dropped. A failure never blocks a reader.

Cloudflare's own definitions of a visit and of bot filtering were not re-read for this
note. Treat the Cloudflare side as its own vendor's definition.

## Rule of thumb

- The blog counter is the source for pages, sources and clicks.
- Cloudflare is the source for page timing.
- Neither is a billing figure.

## Report footer wording

The owner report prints this footer under every blog table. The text between the markers
is the canonical wording; `scripts/test-analytics-reconciliation.py` checks it.

<!-- report-footer:start -->
Cloudflare Web Analytics and the blog counter will not match, and neither is exact.
Script blockers, crawlers, how each counter treats prefetches and link previews, Global
Privacy Control and Do Not Track, UTC days, the 5 view floor and fail-open drops all move
the numbers. Use the
blog counter for pages, sources and clicks, and Cloudflare for page timing. Neither is a
billing figure.
<!-- report-footer:end -->
