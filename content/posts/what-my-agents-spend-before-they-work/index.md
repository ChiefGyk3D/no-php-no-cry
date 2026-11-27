---
title: "My Agents Were Eating 40,225 Tokens Before They Did Any Work"
date: 2026-11-26T23:00:00-05:00
description: "I spent a day measuring my agent workflow, found a duplicate instruction file and silent context truncation, and came away with a baseline I can actually check."
slug: "what-my-agents-spend-before-they-work"
categories: ["Blog"]
tags: ["ai","agents","tokens","workflow"]
draft: true
syndicate: false
---

The median first turn for an agent in my workflow was 40,225 tokens before it did any work. I wanted a yardstick before changing anything, so I pulled a read-only weekly spend report from my own agent sessions. The lead session accounted for 37.4 percent of weighted Claude spend. The agents it spawned accounted for 62.6 percent. If I’d focused on the session I was talking to, I would’ve started with the smaller share of the bill.

The post image is a placeholder.

The lead still had something worth looking at. Cache reads accounted for 83.7 percent of its weighted spend, and 84.2 percent of the lead’s spend happened after turn 200. Those are two different cuts of the same spend. One tells me what I was paying for, and the other tells me when I was paying for it. I want to see what happens if I end lead sessions sooner, including what it costs to hand the work to a fresh session and get it back up to speed. The late-session number tells me where to run that experiment.

## I was sending the same instructions twice

A second copy of an instruction file was 97.8 percent identical to the first. Every implementer agent was getting about 5.4k tokens of that second copy on its first turn. In the controlled test, the first turn went from 34.6k to 39.9k with the extra copy. So I replaced the duplicate with a 508-byte pointer. I have the controlled comparison that showed what the duplicate added. The effect of the replacement on spend across the workflow is still unmeasured.

The type of agent I dispatched mattered enough to look at on its own. Over 14 days, 940 of 1,855 dispatches, or 50.7 percent, used the untyped or general-purpose agent. Its median first turn was 59.5k tokens. The implementer’s was 35.2k. Before I change routing based on that, I want to know which jobs are going to the general-purpose agent and which ones actually need it. Those medians give me a reason to look at the calls. To see what changing a call buys me, I’d have to give the same job to both and check the work.

## The local server had two separate problems

I noticed my agent tooling had stopped using the local model on calls where I expected it. In the report window, 256 of 7,007 dispatches used the local model server. That’s 3.6 percent. If I’m counting on a local server to save me money, I need to know how often my tooling actually sends work to it.

I also caught that the small local model was set to 8K context. In testing it silently kept only the last 4,098 tokens when the input ran longer. It can still answer you after it drops the front of the prompt. If that’s where you put the instructions you expect it to follow, reading the answer alone is a lousy way to find out whether the model ever saw them.

The larger local model should have been at 128K. In tests at that setting it recalled cleanly up to about 80k tokens, at about 0.75 ms per prompt token. I care about both numbers because I need to know how much input it can actually use and how long it takes to read it. I’d use the recall test to decide how much work to hand it, and then check whether my tooling is actually sending those jobs there.

My estimate for savings from the local model server alone is about 1 to 3 percent. My estimate for shorter-lived lead sessions is 8 to 17 percent, and for trimming fixed prompt prefixes it’s about 8 percent. I still need spend measurements after the changes. I’m leaving those estimates as estimates.

## What did the check actually check?

On the board cleanup, I had code compare before and after snapshots. It verified that 190 closed cards were corrected, 268 cards got a Kind, and zero changes fell outside the plan. That last part is something you have to check across the board. Looking at the cards I meant to change would only tell me whether those cards looked right.

A flaky test was comparing CPU time ratios, so the test was changed to count the work done. An automated security review of the new work also found a Medium hardening gap in an existing runner check. The fix was written test-first. The adversarial review is pending.

And yes, I pushed back when I was asked to run merge commands after I’d already approved the work. If I’m being asked to take over an operation, I want to know what still needs my involvement. I already made the approval decision.

This is the problem with vibe coding. I’ve spent years engineering and architecting IT and cybersecurity systems, and that’s why I knew to ask for a yardstick and to look at what happened before an agent ever got to the job. When the local model dropped out of the calls, I knew to ask where the calls were going. When I saw 8K, I wanted to know what the model could actually recall. A convincing answer from the model would have told me very little about either of those things.

AI is a tool, and it can help me do the work. It can write the comparison that checks the board, but I still have to know why I care about cards outside the plan. Same thing with token spend. I have to know what I’m counting, what changed and what evidence would let me say the change worked.

Could you answer questions about the things you talk about without a computer screen?
