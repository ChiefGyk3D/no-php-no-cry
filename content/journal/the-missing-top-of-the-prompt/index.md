---
title: "The Missing Top of the Prompt"
date: 2026-11-26T20:00:00-05:00
draft: false
description: "A local model silently dropped the top of a long prompt, showing why AI output needs a yardstick and measured results."
slug: "the-missing-top-of-the-prompt"
categories: ["Journal"]
tags: ["ai", "vibe-coding", "local-models", "measurement"]
syndicate: false
---

I sent a 28,905-token prompt to qwen3.5:4b. The response reported that it had evaluated 4,098 prompt tokens, and the answer came from the tail of the input only. The model did not warn me that the instructions at the top were gone.

That count should have stopped the entire workflow. An answer is not useful when the model never saw the question that defined the job, even if the resulting text looks structurally normal. Accepting it because it looks like an answer is vibe coding.

<!--more-->

## What the count exposed

I followed the first result with tests at nominal 9k, 10k, and 12k tokens. All 9 calls reported exactly 4,098 prompt tokens. An instruction placed at the top appeared in 0 of 9 answers. A marker placed at the end appeared in 9 of 9. No warning was printed.

Up to 8k nominal tokens, the reported prompt counts matched the real input on both models I tested, and I saw no truncation. That puts the apparent cutoff somewhere between 8k and 9k, but that location is an inference, not an exact measurement.

The small model was configured with an 8,192-token context window. The large model, gemma4:12b, was configured for 131,072 tokens. I had not checked either setting until this measurement gave me a reason to look.

The large model retained both markers in 14 of 14 tested size cells up to 8k. I did not test it above 8k in that round, so that result says nothing about larger inputs. It only says that the tested inputs survived.

I knew to inspect the prompt count because I have spent years engineering and architecting IT and cybersecurity systems. When a system returns a result that does not fit the input, I look for the missing boundary, dropped data, or unstated limit. AI does not remove that responsibility. It gives the system another place to fail.

The model produced text. The workflow failed because it had no check proving that the model received the whole input. Without the top and bottom markers, the prompt count, and a known expected result, the output could have gone straight into later work.

That is the problem with vibe coding. It is not the use of an assistant. It is accepting what the assistant produced without a yardstick for what went in, what came out, and what the answer should contain.

## The ledger still says zero

I also have a ledger containing seven planned changes intended to reduce token spend. One change was applied on 2026-11-26: an instruction file was reduced to a 508-byte pointer.

A controlled test predicted about 5,400 fewer tokens for one agent type. That is a prediction, not a measured result. The ledger currently has zero changes with a measured after-value.

That distinction is easy to erase once a change appears obviously better. The file is smaller, and the controlled test predicts a lower starting cost. But neither fact proves what happened in the real workflow after the change.

The ledger rule is simple: a row counts only when the after-value has been measured. Until then, I have an implementation and a prediction. I do not have measured savings.

And that is the same failure in a different place. A model answer that looks complete is not proof that the model saw the full prompt. A smaller instruction file is not proof that total spend fell. The expected result can be reasonable and still remain unmeasured.

So, how many tokens does your assistant session start with, how large does its context get, and how would you know if a local model had quietly cut off the top of its input without a computer screen?