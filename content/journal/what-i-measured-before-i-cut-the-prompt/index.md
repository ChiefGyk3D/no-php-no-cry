---
title: "The Missing Top of the Prompt"
date: 2026-11-26T20:00:00-05:00
draft: true
description: "A local model silently dropped the top of my prompt, and checking what actually happened left me with three changes and zero measured after-values."
slug: "what-i-measured-before-i-cut-the-prompt"
categories: ["Journal"]
tags: ["ai", "vibe-coding", "local-models", "measurement"]
syndicate: false
image: "featured.jpg"
imageAlt: "Stacks of coins with a green seedling growing from each, rising in height toward a glass jar of coins with a larger plant"
---

I sent a 28,905-token prompt to qwen3.5:4b and it reported processing 4,098 prompt tokens. The answer came from the tail of the input. The instructions at the top were gone, and the model gave me an answer anyway.

That count should have stopped the workflow. The answer looked normal enough to pass along, which is exactly the problem. The top of the prompt defined the job. If all I checked was whether the model returned something that looked like an answer, I could have handed the next step a result from a model that only saw the end of the input.

<!--more-->

## What the count exposed

I followed up with tests at nominal 9k, 10k, and 12k tokens. All 9 calls reported exactly 4,098 prompt tokens. The instruction I put at the top showed up in 0 of 9 answers, and the marker at the end showed up in 9 of 9. No warning was printed. I knew what a complete answer should contain because I'd planted the markers myself. I could check the answer against the input without asking another model if it looked right.

Up to 8k nominal tokens, the reported prompt counts matched the input on both models and I saw no truncation. That puts the apparent cutoff for the small model somewhere between 8k and 9k, which I inferred from the test sizes. I checked the server settings after seeing the count and found qwen3.5:4b configured for 8,192 tokens and gemma4:12b configured for 131,072. I'd been using the server without checking either setting.

The reason I knew to look at the count in the first place is that I've spent years engineering and architecting IT and cybersecurity systems. When the result looks plausible and the count is that far off, I want to know what made it through. This is the problem with vibe coding. If I accept an answer without knowing what the system received or what a good answer should contain, it can quietly lose the part that defines the job and I can still call it done. AI is a tool. I still have to think through what I'm asking it to do and how I'd catch it getting that wrong.

## What I had a baseline for

I'd asked for a yardstick before making changes. A weekly token-spend report I wrote, covering the weeks through November 26, put 37.4 percent of weighted Claude spend on the lead session and 62.6 percent on spawned agents. The weights were my own. The median first turn for a spawned agent was 40,225 tokens before it did any work. In the lead session, 84.2 percent of weighted spend came after turn 200. I want both cuts of that report when I rerun it because a shorter session could also change what I spend getting the next session caught up.

I'd also noticed the local model dropping out of work I expected it to handle. The hook log showed that a local-model step was included in 8 of 68 dispatch briefs in the first week tracked, or 11.8 percent. By week 48 it was 49 of 2,076, or 2.4 percent. A recall test can tell me whether the model can handle the prompt I give it. I still need the dispatch count to know whether the workflow sends it that prompt in the first place.

## The ledger still says zero

The second copy of the instruction file was 97.8 percent identical to the first. In a controlled test, an implementer agent's first turn went from 34.6 thousand tokens with the duplicate out to 39.9 thousand with it in. I replaced the duplicate with a 508-byte pointer. The test gave me a prediction of about 5,400 fewer tokens for that agent type. I still need the first-turn measurement with the pointer in place.

By the evening of November 26 Eastern time, I'd also added a warning when dispatching the untyped general-purpose agent and switched 117 rarely used skills to list by name only. A test predicted the shorter skill list would trim about 2.9 thousand characters. The warning gives me a reason to look at the dispatch because the general-purpose agent and the implementer get different kinds of jobs.

The ledger has three applied changes and zero measured after-values. A row counts when I measure the after-value. I checked a board cleanup the same way, by comparing before and after snapshots in code. The write looked right in the tool output, and the comparison showed that 190 closed cards were corrected, 268 open cards got a category, and zero changes fell outside the plan. For the pointer, I want that same kind of check on the first turn, followed by a spend comparison across sessions.

## What I kept finding

An automated security review flagged a gap in the wrapper that checks a repository before running a code assistant on it. I had the fix written test-first and sent it through six rounds of adversarial review. Round 1 found two Highs, round 3 found one, and round 5 found two more. Round 6 found no Highs and one Medium. The fixes were real, and the reviews kept finding things the previous fix had missed.

Then I looked at an installer an assistant had written for me. It took whatever binary it found in a folder I could write to and approved its own hash pin. That defeats the point of a pin. Three automated reviews surfaced three different problems involving the pin, the writable folder, and terminal escape bytes and binary bytes that could hide what was about to be installed. Now I type part of the hash myself.

In a later test, gemma4:12b recalled the planted marker cleanly up to about 80 thousand tokens and took roughly 0.75 milliseconds per prompt token. I had something specific to look for in the answer, the same way I did with the small model.

I was also the bottleneck. Across several projects, the assistant kept handing merge commands back to me for work I'd already approved, and I kept having to ask for commands again. I made two standing rules. If I asked for the change and the checks are green, the assistant merges it. If it needs me to run something, every request includes the full command, even when it's asking again.

These are my estimates for weighted spend, not measurements. Shorter lead sessions could account for about 8 to 17 percent, with an upper bound near 22 percent. Trimming what every agent starts with could account for about 8 percent after overlap. I put a background merge and CI watcher at 1.5 to 3 percent, and condensing big inputs before they reach the model at 0.7 to 2.6 percent. My guesses are 1 to 3 percent for reusing finished agents, 0.5 to 1.5 percent for capping their reports, and 0.5 to 2 percent for keeping the start of the prompt stable so caching holds. The ranges overlap and don't add up. My combined estimate is about 10 to 15 percent without shorter lead sessions and 15 to 30 percent with them. The range is wide because session length is the biggest and least certain piece.

I also filed ideas for conditional web requests, a shared read-only environment per project, running only the tests a change touches, a weekly rerun of the model quality tests, an audit of branch protection across repositories, and a lint rule against timing-ratio tests. I haven't measured any of those.

Away from your computer screen, could you tell me how many tokens your assistant session starts with, how large its context gets, and how you'd know if a local model had quietly cut off the top of its input?