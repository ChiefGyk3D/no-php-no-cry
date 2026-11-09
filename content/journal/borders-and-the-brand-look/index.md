---
title: "Borders and the brand look"
date: 2026-11-08T21:00:00-05:00
draft: true
description: "A green build shipped the wrong visual treatment. Fixing it meant checking the render myself, limiting where frames belong, and testing the viewport I actually use."
slug: "borders-and-the-brand-look"
categories: ["Journal"]
tags: ["design", "accessibility", "testing"]
syndicate: false
---

The borders shipped as tiny corner ticks on one or two elements, and I called that done based on agent reports and green CI. Then I opened the rendered page and compared it with the brand work it was supposed to match. It did not match. The original look uses stepped black-to-graphite brackets, amber rules, and end-cap plates. A few tiny ticks were technically border decoration, but they were not the design.

<!--more-->

## CI was green, the page was wrong

The tests did what they were built to do. I had tested the wrong category of thing. GitHub Actions can tell me that Hugo built, the checks passed, the markup followed the rules, and the expected assets exist. It cannot look at a render and decide whether the result actually carries the visual language of my brand.

I had let the implementation agents grade their own visual work, then treated their reports and CI as verification. Agents are generous when deciding something matches the reference. The coordinator has to open the render and the reference side by side before making that claim. That is now part of the job, not an optional final glance.

The next attempt was closer to the source art and still wrong for the site. It put a bright cream panel into a dark design, and I am light sensitive, so the panel hurt to read. That made the accessibility regression immediate, but the rule should have been clear before I saw it: dark mode is the default and the only mode unless a project explicitly asks for light mode. For this site, the frame sits over the approved dark amber and charcoal fills. No large cream or white panels.

## Restraint beats coverage

Once the frame looked right, I made the opposite mistake and applied it too broadly. Frames around everything made the home page noisy, and the three hero buttons stopped fitting on one line. The design was supposed to frame important objects, not compete with every object on the page.

The corrected system uses one frame in different amounts. Minimal treatment is a hairline with small amber corner ticks. The middle treatment adds the bracket layout and amber rules. The faithful treatment carries the full stepped brackets and end-cap plates, and it is limited to one major region on a page. Running text, the header, and the footer do not need busy frames. The default for buttons is minimal, with the faithful art reserved for the primary button.

That hierarchy came from a three-level study: none, minimal, and faithful. I built the study from my original assets and kept it static. The reference includes motion, but the site does not need glow or animation to prove that it belongs to the same brand.

## Measure the box

The button wrap exposed another bad assumption. I use a 1920 by 1080 screen, but I do not browse full screen. My real browser viewport is about 1878 by 930. Earlier checks used the full 1920-pixel width, so they missed the exact width where a hero button wrapped. Tests now start with the viewport I actually use.

And I am no longer accepting “looks the same” as a layout check. The frame art is drawn inside the control’s existing box, and I measure element bounding boxes before and after changing levels. Width, height, padding, margins, and border width should not move because the decoration changed. Small controls also need a reduced version of the art instead of a full frame squeezed until it becomes visual noise.

There was one more rendering detail hiding in the faithful version. A plain fill rectangle behind chamfered artwork shows through beyond the cut corners. The fix was to clip the tint to the frame’s inner outline and add a check for that relationship. It is a tiny defect, but once seen, it makes the entire frame look like a sticker placed over the wrong button.

## Lessons

- Green CI proves the checks passed. It does not prove a visual match.
- Open the render and the reference side by side before saying the work is done.
- Dark mode stays the default and only mode unless light mode is explicitly requested.
- Frame the important controls, then opt in elsewhere with restraint.
- Test the real viewport and compare bounding boxes instead of eyeballing layout.
- Clip fills to chamfered art, and use reduced art for small controls.
