---
title: "Lessons from using an AI assistant on the QCC badge post"
date: 2026-11-14T13:50:00-05:00
draft: false
description: "What I caught and corrected while using an AI assistant to write up the QCC 0x4 badge trigger, from a wrong baud rate to overclaims and a post that silently did not render."
slug: "lessons-from-the-qcc-badge-post"
categories: ["Journal"]
tags: ["ai", "verification", "writing", "firmware"]
syndicate: false
---

I used Claude Code while writing a blog post about finding a hidden Rick Roll trigger in a conference badge, and the process reinforced why I do not trust AI output on its own. It can move fast and find useful things, but I still check EVERYTHING it does because several mistakes would have made it into the post if I had treated the assistant like an authority.

<!--more-->

## What I knew versus what it assumed

The first mistake was the serial baud rate. The initial write-up said the badge’s USB serial port “printed nothing,” but the standard 9600 baud rate was not the correct setting. The firmware’s `platformio.ini` sets `monitor_speed = 115200`.

That distinction changed what I could honestly claim. Seeing nothing at the wrong baud rate does not prove the serial port printed nothing, so I reworded the post around what was actually known instead of letting a clean, confident sentence overstate the evidence.

The firmware section had the same problem at a larger scale. One version said “everything was explained” and that I had “extracted every string.” Those are VERY strong claims for work based on a string-level comparison and partial disassembly. ChatGPT caught both during a second, review-only pass, and it was right.

I changed the language to say what I actually checked, and the post now says plainly that the work is not proof of full equivalence. That does not make the finding less interesting. It makes the explanation accurate.

## A successful build can still be wrong

The draft post did not appear in the Hugo preview even though drafts were enabled. The build exited 0, so if I had stopped at the exit code, everything would have looked fine.

The post’s date was set a few hours in the future, and Hugo skips future-dated posts even when drafts are on. I only caught that because I checked the actual output instead of accepting a successful process exit as proof that the result was correct.

That is one of the more useful lessons from working with Claude Code. A green exit code proves the command completed successfully. It does not prove the thing I wanted actually happened.

## Check the media too

The photo I planned to use showed two other people’s chat handles on the badge’s little screen. I blacked those out in the copy used for the post before anything was published, while leaving the original photo untouched.

I also checked the photo for GPS and camera metadata, and it had neither. The important part is that this happened before publication. Nothing was committed or published until I reviewed it, and both posts started as drafts.

AI can help move files and inspect details, but it does not get to make the final privacy decision for me. I still need to look at the actual image and ask what information belongs to somebody else.

## Sources are not search summaries

While looking for the original meaning of “hacker,” the Jargon File host and an MIT hacks page both failed to load because of certificate errors. The agent did not bypass those errors, which was the correct call.

I also did not use search-result summaries as evidence. Those are leads, not sources. The post instead cites the Tech Model Railroad Club’s own page, which was available to read and quote directly.

That matters here because the whole story is about hacker spirit: finding a hidden function in a badge, making a device do something it was not intended to do, tinkering with it, and having fun. That kind of tinkering is a big reason I advance as fast as I do, so I wanted the historical reference to come from something I could actually inspect.

## Reviewers suggest, I decide

I gave ChatGPT review-only access for the second pass, meaning it could suggest changes but could not make them. Some suggestions caught real problems, including the firmware overclaims. Other suggestions would have put words in my mouth.

One rewrite said the work “still feels like work sometimes,” which directly contradicted what I had said. Another changed the serial-port sentence in a way that implied I later sent commands to the badge, which I had not done.

I skipped or changed those suggestions because a reviewer does not get to invent my experience just because its version reads smoothly. Claude Code and ChatGPT are both useful, but neither one was there doing the work. Reviewers suggest. The author decides.

The review also exposed a maintenance problem I now need to fix: the ChatGPT copy of my voice skill is missing a reference file listed by the Claude copy. The two copies have drifted, which means the same writing request can receive different guidance depending on which tool I use.

The assistants helped me find technical mistakes, tighten claims, check privacy, and review the post, but they also produced confident errors and plausible rewrites that were not true. That is why nothing gets committed or published until I have checked the evidence, the output, the wording, and the final draft myself.
