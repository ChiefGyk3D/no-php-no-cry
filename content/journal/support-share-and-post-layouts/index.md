---
title: "Support, share and post layouts"
date: 2026-11-08T23:00:00-05:00
description: "I rebuilt the blog’s support cards, sharing controls and post layout around safer copying, progressive enhancement and measured dimensions."
slug: "support-share-and-post-layouts"
categories: ["Journal"]
tags: ["hugo", "accessibility", "security", "design"]
syndicate: false
---

The support page now collapses every cryptocurrency address to its first and last eight characters. That sounds like a small layout decision, but a shortened address can be misleading, so the interface cannot treat it as the thing a visitor should trust.

<!--more-->

## Copy the real address

Each cryptocurrency card keeps the full address in the page, while the closed view shows the first eight characters, an ellipsis and the final eight. A native details control reveals the complete value without requiring JavaScript, and the note below it tells the visitor to verify the full address before sending.

The Copy button always copies the complete address. It does not copy the collapsed display, and it does not ask the visitor to select part of a long string without making a mistake. The reveal is a native details element, so showing the full address does not need JavaScript.

I kept the Copy buttons visually obvious with a solid amber treatment. The cards sit inside dark amber panels, matching the rest of the support page without turning a financial action into a carnival game. The four support tiles use the same dark amber treatment and frame art.

That separation is deliberate: the shortened text helps with layout, the full text is the actual destination, and the verification note makes the trust boundary explicit.

## Sharing without the browser prompt

The old sharing treatment became one quiet panel with an icon grid and a separate Copy link row. Copying produces a visible “Link copied” confirmation in a live status region. If clipboard access fails, the page exposes and selects the link so the visitor can copy it manually.

Mastodon and Lemmy need an instance before the site can construct a destination. Instead of using a browser prompt, each icon opens an on-page picker with an instance field, a Remember option, Share and Cancel controls. The picker handles keyboard focus, can be closed with Escape and does not contact another site while the visitor types.

Discord and Matrix came out of the grid because neither has a share intent. Copy link already covers the useful workflow for both: copy the post address, then paste it where it belongs. Pretending every platform has the same sharing mechanism would make the panel look complete while giving visitors controls that do not actually do the job.

The sharing script has to remain under 1 KB when compressed with gzip. That budget forced the interaction to stay narrow: reveal the script-dependent controls, run the instance picker, copy the canonical link and report the result. Static share links remain ordinary anchors, and the permalink above the panel remains available when scripts are disabled.

## Put the post in reading order

I moved the post title before the featured image. The title establishes what the page is about, then the image supports it. The rest of the post keeps the date, reading time, tags and body in a predictable order.

This was also a reminder that layout work needs measurements, not a confident glance at a screenshot. My real browser viewport is about 1878 by 930, even though the display itself is 1920 by 1080. Earlier checks at the full display width missed wrapping that appeared in the space I actually use.

So the layout checks now start with the real viewport. I measured element bounds before and after the frame changes, including the hero controls, because a border that changes a box by a few pixels can turn one row into two. The frame art now sits inside the control box, which lets the visual treatment change without moving the layout around it.

## Lessons

- A collapsed cryptocurrency address is a layout aid, never the value a visitor should verify.
- Copy controls must copy the full value and leave a usable fallback when JavaScript is unavailable.
- Federated sharing needs an on-page instance picker, not a generic browser prompt.
- A platform without a share intent does not need a decorative button pretending otherwise.
- Script budgets are useful when they force an interaction to stay focused.
- I need to test the viewport I actually browse with and compare measured bounds, not eyeball the render.
