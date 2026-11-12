# Draft: /privacy/ text for when the page-view counter is live (issue 84)

NOT PUBLISHED. The live `/privacy/` page (`content/privacy/index.md`) still says
the site collects nothing, and it stays that way until the counter is deployed
and running. Swap this in in the same pull request that turns the collector on
(see `docs/analytics-deploy.md`, step "Go live"). That pull request also changes
the sentence that `scripts/test-pages.sh` asserts (`privacy()` in the asserter
and the `good_privacy` fixture near it), or CI fails on purpose.

Everything below the line is the proposed page. It follows the front matter of
the current page. Check every sentence against `analytics/` before publishing:
the page must say exactly what the code does, no more and no less.

---

```markdown
---
title: "Privacy"
description: "What this site counts, what it does not, and how to opt out."
date: 2026-11-05
draft: false
syndicate: false
---

This site counts page views. That is all it does. Here is exactly what I keep.

## What I record

When a page loads, I save one small row:

- The hour. Not the minute.
- The page address on this site.
- The site you came from, by name only. If you clicked a link on example.org, I
  keep "example.org". I never keep the full link or anything after it.
- Your country, state or region, and city. Cloudflare works this out from your
  connection. It is a rough guess and it can be wrong.
- A yes or no on whether your connection belongs to a hosting company or a VPN
  network. This is a match against a list of network numbers. I do not keep the
  number.
- A yes or no on whether the visit looks like a bot. Bots are counted on their
  own and left out of the numbers about people.

## Outbound link clicks

When you follow a link from this site to another site, I keep the destination
site, by domain name only, along with the hour and your country. I never keep
the full destination address, its path, or its query. I count the click without
keeping an ID that could connect it to you or to a page view.

Individual click rows: 7 days. Daily destination and country totals: 90 days.
Monthly destination totals: 25 months. After that they are deleted.

## What I do not record

- Your IP address.
- Your browser's name, version or any other detail about your device.
- Your language settings.
- Anything that follows you from one visit to the next. No cookies. No
  fingerprinting. No ID of any kind. I cannot tell that two visits came from the
  same person, and I do not try.

There is no script on these pages. The counting happens on the server when the
page is sent. Your browser is not asked to do anything.

## How it works, and what I see for a moment

To count a visit my code looks at your connection's network number and your
browser's identification string. It uses them to decide the two yes or no
answers above and then throws them away. They are never saved or logged.

## Opting out

Turn on Do Not Track or Global Privacy Control in your browser. If either is on,
I record nothing for that visit.

## Small numbers

I never look at a group smaller than 5 visits. If fewer than 5 visits share a
city, that count is merged into its region, then its country, then "other" until
the total is at least 5. If only one place would be hidden, the next smallest is
hidden with it. Pages and sources also hide groups smaller than 5. On a small
audience, someone who knows who reads the blog might still infer a town with a
few readers. The floor reduces that risk, but does not remove it.

## How long I keep it

- Individual rows: 7 days.
- Daily totals: 90 days.

After that they are deleted.

## Who sees it

Only me. I do not sell it or share it. There is no ad network and no third-party
analytics service.

## The host

This site runs on Cloudflare. Like any host, Cloudflare handles your request to
send you the page, and its own privacy policy covers what it keeps. My counter
does not add anything to that.

Questions: use the contact details on the [About](/about/#contact) page.
```
