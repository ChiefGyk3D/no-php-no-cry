---
title: "The 4,098 Token Warning Vibe Coding Misses"
date: 2026-11-26T21:00:00-05:00
draft: false
description: "A silent context cutoff shows why AI-assisted work still needs baselines, measurements, and an engineer who knows what to question."
slug: "the-4098-token-warning-vibe-coding-misses"
categories: ["Open Source"]
tags: ["ai", "vibe-coding", "local-llm", "measurement"]
syndicate: false
---

A 28,905-token prompt went into qwen3.5:4b. The response said the model had processed 4,098 prompt tokens. It answered using the tail of the input, while the instructions at the top were gone. Nothing printed a warning.

That did not look right, but I only knew to look because I have spent years engineering and architecting IT and cybersecurity systems. I have a yardstick for systems that accept input, transform it, and produce an answer. I expect to know what entered the system, what survived, what changed, and how the result was checked. Without that background, the answer looked like an answer.

<!--more-->

## The first numbers were somewhere else

I did not start by testing local model truncation. I started with a simpler question: where were all my tokens going?

A weekly token-spend report I wrote counted all weeks through 2026-11-26. I assigned weights of input 1, output 5, cache read 0.1, and cache write 1.25. Those are weights I chose for comparing the work. They are not vendor prices.

The weighted total was about 4.36 billion. Lead sessions accounted for 37.4 percent, while subagents accounted for 62.6 percent. That immediately challenged my assumption that the main conversation was the obvious place to optimize.

The lead sessions still had a clear problem. Of their turns, 70.3 percent happened after turn 200, and those later turns carried 84.2 percent of lead-session spend. Long-running sessions were not just lengthy transcripts. They were where most of that part of the spend accumulated.

Subagents had their own starting cost. The median first turn contained 40,225 tokens before the agent did any work. About half of that was instructions and the available-skills list, based on my estimate using 3.5 characters per token. That estimate is not a measured token breakdown, but the 40,225-token median is measured.

This is where vibe coding becomes a workflow problem rather than a criticism of a particular model. If an assistant creates a subagent and the subagent returns useful-looking work, it is easy to treat the dispatch as successful. The result may even be correct. But without measuring the starting context, there is no way to know what it cost before the actual task began.

The local-model routing numbers made that gap harder to ignore. In the first tracked week, 11.8 percent of dispatches included a local-model step, or 8 of 68. The next week was 14.4 percent, or 13 of 90. By week 48, it was 2.4 percent, or 49 of 2,076.

Dispatches had grown from 68 to 2,076 while the local share fell. That was not proof that local routing was failing. It was proof that merely having a local model available did not mean the workflow was consistently using it.

I had 1,433 successful local-model calls logged since 2026-10-07. Failures and busy exits were not logged before 2026-11-25 19:18, so that count covers successful calls only. More importantly, quality outcomes had been recorded for one row across those 1,433 calls.

That means nobody had measured how often the local answers were right. The call count looked substantial, but it answered an operational question, not a quality question.

## The prompt was quietly cut from the top

On 2026-11-26, I finally checked the context windows configured on the local model server. The small model, qwen3.5:4b, was configured for 8,192 tokens. The large model, gemma4:12b, was configured for 131,072. I had not checked either setting until the token measurement made me go looking.

Then the 28,905-token prompt produced the 4,098 prompt-token count.

I followed that with controlled tests at nominal 9k, 10k, and 12k input sizes. All 9 calls reported exactly 4,098 prompt tokens. The instruction placed at the top appeared in 0 of 9 answers. The marker placed at the end appeared in 9 of 9.

Up to 8k nominal tokens, the reported prompt counts matched the real input on both models and no truncation appeared. The cutoff occurring somewhere between 8k and 9k is an inference, not an exact measurement of the boundary.

The large model showed no input loss at any size tested through 8k. Both markers passed in 14 of 14 size cells. I did not test it above 8k in that round, so the result does not establish what happens beyond the tested range.

The dangerous part was not that a finite context existed. Every bounded system has a limit somewhere. The problem was that the workflow accepted an overlong request, removed the top, and returned a plausible answer without a warning.

If the top contains the task, constraints, source definitions, or the distinction between measured and estimated facts, the response can be formatted cleanly and still answer the wrong request. Reading the answer alone cannot reveal what disappeared.

That is what accepting assistant output without a yardstick misses. The assistant completed a response, but completion was never the same thing as correctness.

## Clean JSON did not fix the answers

I also tested a formatting change on gemma4:12b. With its JSON output option enabled, fenced output dropped from 43 of 50 answers to 0 of 50. Across 10 test inputs, the answers were identical through five repeats.

That sounds like a clean fix until the correctness result is included. The pass rate was 45 of 50 before the formatting change and 45 of 50 after it.

The option fixed the format. It did not fix the wrong answers. And 10 inputs with five repeats is a small sample, so I am not turning that result into a broad claim about the model.

This distinction matters because structured output is easy to validate mechanically. A parser can confirm that a response is valid JSON, contains the expected fields, and repeats consistently. None of those checks prove that the content is correct.

Vibe coding tends to reward visible progress. The fence is gone, the parser stops complaining, and repeated runs produce the same answer. The workflow looks stable. But if the pass rate did not move, the underlying problem did not move either.

AI is a tool, but it cannot do all the thinking for me. It cannot decide that the prompt count should be compared with the input size unless I build that comparison. It cannot establish the expected answer unless I provide a test. And it cannot turn consistent output into correct output by repeating itself.

## The ledger still says zero

I now have a change ledger with seven planned changes intended to reduce spend. One was applied on 2026-11-26: the instruction file was reduced to a 508-byte pointer.

A controlled test predicted about 5,400 fewer tokens for one agent type. That is a prediction, not a measured result from the changed workflow.

The ledger currently has zero changes with a measured after-value. Its rule is simple: a row counts only after the after-value has been measured. Applied is not verified. Predicted is not measured. Cleaner output is not more correct.

My estimate, not a measurement, is that the local model server alone is worth about 1 to 3 percent of total spend. Most of the spend appears to come from how large contexts start and how long sessions run. Until I collect after-values, that remains an estimate and not a savings claim.

That ledger is the part vibe coding usually leaves out. Producing a change feels like finishing the task, especially when an assistant supplies a convincing explanation of why the change should work. But the explanation is not the before-and-after measurement.

The uncomfortable test is whether I understand the system without relying on its own output to explain itself: could you answer these things without a computer screen, including how many tokens your assistant session starts with, how large its context gets, and how you would know if a local model had quietly cut off the top of its input?