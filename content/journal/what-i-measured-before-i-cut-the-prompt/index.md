---
title: "What I Measured Before I Cut the Prompt"
date: 2026-11-27T12:00:00-05:00
description: "My notes on the token spend baseline, local model recall tests, and what I still need to measure after replacing a duplicate instruction file."
slug: "what-i-measured-before-i-cut-the-prompt"
categories: ["Journal"]
tags: ["ai","agents","tokens","workflow"]
draft: true
syndicate: false
---

I asked for a yardstick before making changes. The read-only weekly report on my own sessions put 37.4 percent of weighted Claude spend on the lead and 62.6 percent on spawned agents. Median first turn for a spawned agent was 40,225 tokens before it did any work. For the lead, 83.7 percent of weighted spend was cache reads, and 84.2 percent of spend came after turn 200. I want both cuts of that report when I rerun it because a shorter session could also change what I spend getting the next session caught up.

## Local model checks

I’d noticed that the local model had dropped out of calls I expected it to handle. The report showed 256 of 7,007 dispatches went to the local model server, or 3.6 percent. I’d check the dispatch counts earlier next time. A recall test can tell me whether a model can handle the prompt I give it. I still need the dispatch count to know whether the workflow sends it that prompt in the first place.

The small model was set to 8K and silently kept the last 4,098 tokens on longer inputs. The larger model should have been at 128K. It recalled cleanly up to about 80k in tests, at about 0.75 ms per prompt token. Next time I’d test recall with material near the front of the input before I route long prompts to either model. The small model can give me an answer with the front of the prompt gone.

## Changes and checks

The second instruction file was 97.8 percent identical to the first and added about 5.4k tokens to every implementer’s first turn. The controlled test moved from 34.6k to 39.9k with the duplicate. I replaced the second copy with a 508-byte pointer on November 26. I still need the first-turn measurement with the pointer and a spend comparison across sessions.

I checked the board cleanup by comparing before and after snapshots in code. The comparison showed 190 closed cards corrected, 268 cards given a Kind, and zero changes outside the plan. A flaky test that compared CPU time ratios now counts work done. The automated security review found a Medium hardening gap in an existing runner check, and the fix was written test-first. The adversarial review is pending.

## Next measurement

Over 14 days, the untyped or general-purpose agent took 940 of 1,855 dispatches, or 50.7 percent. Its median first turn was 59.5k tokens, compared with 35.2k for the implementer. I’d take a job that went to the general-purpose agent and run it through the implementer too, then look at what both actually did. The medians alone leave me guessing about how much of the difference comes from the kind of job each agent gets.

The local server alone has an estimated savings of about 1 to 3 percent. Shorter-lived lead sessions have an estimated savings of 8 to 17 percent. The estimate for trimming fixed prefixes is about 8 percent. I still need an after measurement for spend. I’d measure the pointer change before changing session length or routing, so when the spend moves I have a better chance of knowing which change did it.
