---
title: "The Missing Top of the Prompt"
date: 2026-11-26T20:00:00-05:00
draft: false
description: "A local model silently dropped the top of my prompt, so I tested what it actually read and checked which workflow changes had measured results."
slug: "what-i-measured-before-i-cut-the-prompt"
categories: ["Journal"]
tags: ["ai", "vibe-coding", "local-models", "measurement"]
syndicate: false
image: "featured.jpg"
imageAlt: "Stacks of coins with a green seedling growing from each, rising in height toward a glass jar of coins with a larger plant"
---

I sent a 28,905-token prompt to `qwen3.5:4b` and it reported processing 4,098 prompt tokens. The answer came from the tail of the input. The instructions at the top were gone, and the model gave me an answer anyway.

That count should have stopped the workflow. The answer looked normal enough to pass along, which is exactly the problem. The top of the prompt defined the job. If all I checked was whether the model returned something that looked like an answer, I could have handed the next step a result from a model that only saw the end of the input.

<!--more-->

## What the count exposed

I followed up at nominal 9k, 10k, and 12k tokens. All 9 calls reported exactly 4,098 prompt tokens. The instruction at the top showed up in 0 of 9 answers, and the marker at the end showed up in 9 of 9. No warning was printed. I knew what a complete answer should contain because I'd planted the markers myself. I could check the answer against the input without asking another model if it looked right.

Up to 8k nominal tokens, the reported counts matched the input on both models, with no truncation observed. The larger model passed both marker checks in all 14 size cells in that round, which stopped at 8k. The small model's cutoff somewhere between 8k and 9k is an inference from the test sizes. I only checked the server settings after seeing the count. `qwen3.5:4b` was configured for 8,192 tokens and `gemma4:12b` for 131,072. In a later test, `gemma4:12b` recalled a planted marker cleanly up to about 80 thousand tokens and took roughly 0.75 milliseconds per prompt token.

The reason I knew to look at the count in the first place is that I've spent years engineering and architecting IT and cybersecurity systems. This is the problem with vibe coding. If I accept an answer without knowing what the system received or what a good answer should contain, it can quietly lose the part that defines the job and I can still call it done. AI is a tool. I still have to think through what I'm asking it to do and how I'd catch it getting that wrong.

I added a guard that stops a call when the server truncates its input, and character caps that refuse oversized prompts before sending. Every local call now records its project, agent, and dispatch. A separate outcome step records whether I accepted, rewrote, or discarded the answer, or found a factual error. The log had 1,433 successful calls since October 7 and one recorded quality outcome. Logging for failures and busy exits only started November 25 at 19:18. I have a count of successful calls and almost no evidence of how often the answers were right.

I switched the default for drafting issue, pull request, and comment text to the larger model. A busy server now puts the call back in the queue for retry. In my test, turning on JSON output took the larger model from 43 fenced answers out of 50 to 0 out of 50. Its answers were identical across five repeats on all 10 inputs with the option on. The pass count stayed at 45 out of 50 before and after. That's a small sample, and the wrong answers were still wrong.

## What I had a baseline for

Before making changes, I wanted to know where the tokens were going. I merged a weekly token-spend report with a stored baseline. Through November 26 it counted about 4.36 billion weighted Claude tokens. I used my own weights of 1 for input, 5 for output, 0.1 for cache reads, and 1.25 for cache writes. The lead session accounted for 37.4 percent and spawned agents for 62.6 percent. After turn 200 came 70.3 percent of lead-session turns and 84.2 percent of its spend. The median first turn for a spawned agent was already 40,225 tokens before it did any work. My estimate, using 3.5 characters per token, is that instructions and the available skills list account for about half of that.

The hook log measured how often a dispatch brief included a local-model step. It went from 8 of 68 in the first week tracked, or 11.8 percent, to 13 of 90 the next week, or 14.4 percent. By week 48 it was 49 of 2,076, or 2.4 percent. Dispatches grew while the local share fell. Across the report window the share was 3.6 percent. Digesting big inputs locally first is still planned. My untested judgment is that the spare 8 GB GPU can't hold the larger model with useful context, so a second machine would need a smaller model.

## The ledger still says zero

The second copy of the instruction file was 97.8 percent identical to the first. Only one tool read the duplicate. The other read only its own file in 303 of 303 sessions. In a controlled test, an implementer's first turn was 34.6 thousand tokens with the duplicate out and 39.9 thousand with it in. I replaced the duplicate with a 508-byte pointer. The test predicts about 5,400 fewer tokens for that agent type. I still need the first-turn measurement with the pointer in place.

I merged a typed general-purpose agent and a warning when a dispatch uses the untyped one. Over 14 days, 940 of 1,855 dispatches used the untyped type, or 50.7 percent. Its median first turn was 59.5 thousand tokens. The specialized implementer's was 35.2 thousand. They get different jobs, so the gap tells me where to look. I also switched 117 rarely used skills to list by name only. A test predicted about 2.9 thousand fewer characters. The usage records showed 22 distinct skills used in 60 days out of 183 available. Four connectors with write powers showed zero calls since September. Disabling them is pending.

By the evening of November 26 Eastern time, the ledger had three applied changes and zero measured after-values. A row counts when I measure the after-value. I had that comparison for a cleanup on a board of 785 cards. A script corrected 190 closed cards and set a category on 268 open ones. The write looked right in the tool output first. I trusted the before-and-after snapshot comparison in code, which showed zero changes outside the plan.

Shorter lead sessions with a written handoff and a background merge and CI watcher are still unstarted. My estimates for weighted spend are 8 to 17 percent for shorter sessions, with an upper bound near 22 percent, and 1.5 to 3 percent for the watcher. I estimate about 8 percent after overlap for trimming what agents start with and 0.7 to 2.6 percent for digesting big inputs. I filed three more ideas. My guesses are 1 to 3 percent for reusing finished agents, 0.5 to 1.5 percent for capping reports, and 0.5 to 2 percent for keeping the prompt start stable so caching holds. These ranges overlap. My combined estimate is 10 to 15 percent without shorter sessions and 15 to 30 percent with them. Session length is the biggest and least certain piece. My estimate for the local server alone is about 1 to 3 percent of total spend because so much depends on how large contexts start and how long sessions run. All of those figures are estimates. The ledger still needs measurements.

## What else I checked

A test that compared CPU-time ratios kept failing in CI on busy machines. I replaced it with a count of the work done, and the fix passed and merged. Ten more tight wall-clock tests were converted to CPU-time or event checks and are in review. Deliberately breaking the behavior proved the new checks could catch it. Measured margins supported leaving 22 tests alone. I filed conditional web requests, a shared read-only build environment per project, running only tests a change touches, keeping both local models loaded, and auto-merging dependency updates after a 7-day hold. Those are still plans.

An automated security review flagged a gap in the wrapper that checks a repository before running a code assistant on it. I had the fix written test-first and sent it through six adversarial review rounds. Round 1 found two Highs, round 3 found one, and round 5 found two more. Round 6 found zero Highs and one Medium. The fixes were real, and the reviews kept finding things the previous fix had missed.

An installer an assistant wrote for me trusted whatever binary it found in a folder I could write to and approved its own hash pin. That defeats the point of a pin. Three automated reviews surfaced three different problems involving the pin, the writable folder, and terminal escape bytes and binary bytes that could hide what was about to be installed. Now I type part of the hash myself.

I merged a check that blocks pushes when generated rule files are stale, and set up a root-owned wrapper pair so a sandboxed shell can start the code assistant safely. Still filed are a lint rule against timing-ratio tests, a weekly rerun of the model quality tests, a branch protection audit across repositories, a generated-file pre-push check in every repository, and a secret scan on briefs and reports. I updated the local model wrapper, drafting and evaluation tool, and spend report docs. The tooling guide now covers the wrappers and install steps.

Every task starts with an issue and a board card. Delegated agents leave merging to the lead assistant. I kept getting merge commands handed back to me for work I'd already approved, so now the lead assistant merges green changes I asked for, pins each merge to the checked commit, does them one at a time, and tells me afterward. If it needs me to run something, every request includes the full command, even when it's asking again.

I'm also building a portable edition as a separate, private project for coworkers with different AI tools or none. The starter set, record schema, threat model, local-model tier design, and contracts for briefs and reports are done. Storage and the event log are merged, the commands that use them are in progress, and delegation that accounts for task dependencies is still unstarted.

Away from your computer screen, could you tell me how many tokens your assistant session starts with, how large its context gets, and how you'd know if a local model had quietly cut off the top of its input?