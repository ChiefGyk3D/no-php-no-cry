# FAQ

## Can I reuse this for my own site?

Yes. The code (templates, scripts, configuration, tooling) is Apache-2.0 and the
written content, including this wiki, is CC BY 4.0. Credit "ChiefGyk3D", link to
the license and say if you changed the content. The mascot, wordmark and logos
are all rights reserved and are not licensed for reuse. Replace them, and the
files listed in `brand/approved-assets.txt`, with your own. See
[BRAND.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/BRAND.md).

## Why Hugo, and why that exact version?

Hugo builds a folder of files with no runtime. The release is pinned in
`.hugo-version` and CI verifies its checksum, so a build today and a build next
year are the same build. `scripts/check-hugo-version.sh` also refuses the extended
edition, which the site does not need. See [Getting started](Getting-started.md).

## Why does the build fail on a new image?

Because a rule was broken: no alt text, the `TODO alt text` placeholder, an image
outside the post's folder, an unsupported format, EXIF data, a file over the
size limit, or an image not listed in `brand/approved-assets.txt`. The failing
line names the rule. See [Images and alt text](Images-and-alt-text.md).

## Why can't I embed a video or a tweet?

The Content Security Policy allows only the site's own files and raw HTML in
Markdown is off. An embed would need a third-party frame or script. Link to it
instead. A new source needs its own issue and an explicit decision.

## Why only two scripts?

Each script is a risk and a cost. The policy says `script-src 'self'`, which
allows any same-origin file, so the build pins the two reviewed scripts by hash
and lets each load on one page only. See [Search and tags](Search-and-tags.md)
and, for a pending proposal to add a third, [Share links](Share-links.md).

## Does the site track visitors?

The site's own code sets no cookies and embeds nothing. The host's analytics are
turned on at the host and described on the site's Privacy page. A server-side
page-view counter exists in `analytics/` and `functions/` with its tests, but it
is not deployed; `docs/analytics-deploy.md` and `docs/privacy-with-analytics.md`
hold the plan and the draft privacy text.

## How do old WordPress addresses keep working?

Each old permalink becomes an `aliases` entry and a 301 line in `_redirects`,
and the build fails if a line is missing. See
[Migrating from WordPress](Migrating-from-WordPress.md).

## Can I use it without Cloudflare Pages?

The build output is plain static files, so any static host serves them. The
`_headers` and `_redirects` files and the deploy workflow are written for
Cloudflare Pages. Hugo's alias pages carry a meta refresh for hosts that ignore
`_redirects`. The checks that read Cloudflare control files would need to be
adapted. Not verified: a deployment to another host.

## Where do the numbers in the budget come from?

From `docs/redesign-brief.md` (section 10) and the measurements recorded in
`docs/performance-gates.md`. To change a limit, change the script and the table
together. See [Performance](Performance.md).

## Why is there no light theme?

The brand is dark only. A theme toggle was planned and dropped; the browser
gate has a dormant toggle rule that runs only if a theme script ever ships.

## What does `CI green` mean?

A local job in `.github/workflows/ci.yml` that needs the build and checks, the
shell lint and the security scans, and fails unless each is a success. It is the
one required check, and the deploy waits for it. See
[Deploy overview](Deploy-overview.md).

## Where do I ask a question or report a bug?

Open an issue. For a security problem, do not open a public issue; see
[Contributing](Contributing.md).
