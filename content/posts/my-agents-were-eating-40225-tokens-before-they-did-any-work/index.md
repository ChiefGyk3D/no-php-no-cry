---
title: "My Agents Were Eating 40,225 Tokens Before They Did Any Work"
date: 2026-11-26T21:00:00-05:00
draft: true
description: "I measured what my agents cost before they did any work and found a local model quietly dropping the instructions at the top of its prompt."
slug: "my-agents-were-eating-40225-tokens-before-they-did-any-work"
categories: ["Open Source"]
tags: ["ai", "vibe-coding", "local-llm", "measurement"]
syndicate: false
image: "featured.jpg"
imageAlt: "Stacks of coins with a green seedling growing from each, rising in height toward a glass jar of coins with a larger plant"
---

The median first turn for a subagent in my workflow was 40,225 tokens before it did any work. I started by asking where all my tokens were going, because I wanted a yardstick before I changed anything. A weekly token-spend report I wrote showed that the lead session, the one I was talking to, accounted for 37.4 percent of weighted Claude spend. The agents it spawned accounted for 62.6 percent. I would’ve started with the smaller share of the bill if I’d gone by what I could see in the main conversation.

That report sent me looking at the local model server, where I sent a 28,905-token prompt to qwen3.5:4b and got a response that reported processing 4,098 prompt tokens. It answered from the tail of the input. The instructions at the top were gone, and nothing printed a warning. The reason I knew to ask for the measurements and check what the model had actually received is that I’ve spent years engineering and architecting IT and cybersecurity systems. The answer by itself looked like an answer.

<!--more-->

## Where the tokens were going

The report covered all tracked weeks through November 26, 2026. I weighted input at 1, output at 5, cache reads at 0.1, and cache writes at 1.25, for a weighted total of about 4.36 billion. I chose those weights to compare where the work was going, so the percentages describe spend on that scale.

The lead sessions still had something worth looking at. Of their turns, 70.3 percent came after turn 200, and those turns carried 84.2 percent of lead-session spend. That gives me a place to try ending sessions sooner. If I move work to a fresh session, I also have to count what it costs to write the handoff and get the next session back up to speed. A shorter transcript is easy to produce. To see if I came out ahead, I need to count the work on both sides of the handoff.

The subagents had their own starting cost. I estimate that about half of the 40,225-token median was instructions and the list of available skills, using 3.5 characters per token. I measured the median first turn. The share I attributed to instructions and skills came from that character-based estimate. An agent can come back with useful work and still have a pile of context it had to read before it got anywhere near the job.

Some of that context was easy to account for. A second copy of an instruction file was 97.8 percent identical to the first, and only one of the tools in use ever read it. In 303 of 303 sessions, the other tool read only its own file. I tested an implementer agent with the second copy out and with it in. Its first turn went from 34.6 thousand tokens to 39.9 thousand. That controlled test put the cost of the extra copy at about 5.4 thousand tokens for that agent. It gave me something specific to change and a prediction I could check after changing it.

The type of agent I dispatched also mattered enough to look at. Over 14 days, 940 of 1,855 dispatches, or 50.7 percent, used the untyped general-purpose agent. Its median first turn was 59.5 thousand tokens. The specialized implementer’s was 35.2 thousand. Those agents were doing different jobs, so I’d have to give both the same job and check the work before I could tell what changing the dispatch buys me. The medians tell me which calls to look at first.

There was a similar question in the skill list. Of 183 available skills, 22 distinct ones were used in 60 days. I can leave a skill available and list it by name without putting its full description in front of every agent. I also found four connectors with write powers that showed zero calls since September. Disabling them is still pending. That’s a permissions question as much as a prompt-size question. If a connector can make changes, I want to know which work actually requires it.

## The prompt was quietly cut from the top

From the dispatch log I could see how often the brief sent to an agent included a local-model step. In the first tracked week it was 11.8 percent, or 8 of 68 dispatches. The next week it was 14.4 percent, or 13 of 90. By week 48 it was 2.4 percent, or 49 of 2,076. Dispatches grew from 68 to 2,076 while the local share fell. That count tells me what the briefs asked agents to do. To see what happened when they called the local model, I had to look at the call records.

There were 1,433 successful local-model calls logged since October 7. The log only started recording failures and busy exits on November 25 at 19:18, so the 1,433 figure counts successes only. And across those successful calls there was one row with a recorded quality outcome. I could count the calls that completed. How often the answers were right was still an open question.

On November 26 I checked how much context the local server was set up to give each model. I hadn’t checked either setting until the token measurement made me go looking. The small model, qwen3.5:4b, was configured for 8,192 tokens. The large model, gemma4:12b, was configured for 131,072. Then the 28,905-token prompt came back with a count of 4,098.

I followed up with controlled tests at nominal sizes of 9k, 10k, and 12k tokens on the small model. I put an instruction at the top and a marker at the end, so I could check which part of the prompt the answer used. All 9 calls reported exactly 4,098 prompt tokens. The instruction at the top showed up in 0 of 9 answers. The marker at the end showed up in 9 of 9. No warning was printed.

Up to 8k nominal tokens, the reported prompt counts matched the actual input on both models and I saw no truncation. The small model’s cutoff appears to be somewhere between 8k and 9k based on those tests. The large model passed on both markers in all 14 of 14 size cells through 8k, the largest input it got in that round. In a later test, gemma4:12b at 131,072 tokens recalled the planted marker cleanly up to about 80 thousand tokens and took roughly 0.75 milliseconds per prompt token to read the input. I’d still check its answers on the work I wanted to send it.

Any context window has a limit. What bothered me was that the server accepted the request, dropped the top, and returned a plausible answer in the same way it did when it had the whole prompt. If I put the task and its constraints at the top, the model can produce a clean answer to whatever text happened to survive. Reading the answer alone is a lousy way to find out whether the model ever saw the instructions.

## Clean JSON and wrong answers

I also turned on the JSON output option for gemma4:12b. The number of answers wrapped in Markdown code fences dropped from 43 of 50 to 0 of 50. On all 10 test inputs, the answers were identical across five repeats. The pass rate was 45 of 50 before the change and 45 of 50 after it. I had fixed something real for the code that reads the response, and I still had wrong answers.

A parser can tell me whether it got valid JSON and whether the fields it expects are there. I needed expected answers to check what was in those fields. And 10 inputs with five repeats is a small sample. Those repeats let me see how consistently the model answered those inputs. I’d need to test more cases to say how it does across the jobs I actually send it.

I used the same thinking on a project board with 785 cards. A script corrected 190 closed cards and set a category on 268 open ones. The write looked right in the tool output. What I trusted was code comparing snapshots from before and after, which showed zero changes outside the plan. Looking at the cards I meant to change would only tell me whether those cards looked right. I wanted to know what happened to the rest of the board too, and I had to ask for a check that would actually catch it.

Sometimes the check itself is wrong. I had a test that compared CPU-time ratios and kept failing in CI on busy machines. I replaced it with a count of the work done, and the fix passed. The test was supposed to tell me how much work the code was doing. The timing on a busy machine was getting in the way of measuring that.

An automated security review flagged a gap in a small wrapper that checks a repository before it runs a code assistant on it. I had a test written to catch the problem before the fix went in, then sent the work through six rounds of adversarial review. Round 1 found two Highs. Round 3 found one, and round 5 found two more. Round 6 found no Highs and one Medium. The fixes were real, and review kept finding things the previous fix had missed. A test that catches the gap I know about is worth keeping. I still want someone looking for what I missed when I decided what that test should cover.

Then there was an installer an assistant wrote for me. It trusted a binary it found in a folder I could write to, calculated the hash, and approved that hash as the pin. The point of a hash pin is to have an expected value to check against. The installer was taking the value from the very thing it was supposed to check. Three separate automated security reviews turned up three different problems. One flagged the pin, another flagged installing from a writable folder, and another flagged that terminal escape bytes and binary bytes could hide what would be installed. In the hardened version I have to type part of the hash myself. That’s a place where I want the extra work, because my input is part of the check.

This is the problem with vibe coding. If I take a response that looks right as proof that the work is right, each of these jobs can look finished. The local model answered. The JSON parsed. The board tool reported the write. AI is a tool and it can help me do the work, but it can’t do all the thinking for me. It can write the comparison for the board. I still have to know why I care about cards outside the plan, and I have to make sure the comparison covers them.

I was also the bottleneck in places where I’d already made the decision. Across several projects I kept getting asked to run merge commands by hand for work I’d already approved. And when I did need to do something, I wanted the whole command in the message where I was being asked. Otherwise I had to go back through the conversation and find it again. I made two standing rules. When a change I asked for is green, the assistant merges it. Every time I’m asked to run a command, the request includes the full command. I want to spend my time deciding whether the change is ready and checking the parts that need my judgment. Pasting an approved merge command was just making me the person the job had to wait for.

## The ledger still says zero

By the evening of November 26, 2026, Eastern time, I’d applied three changes. I replaced the duplicate instruction file with a 508-byte pointer. I added a warning when a dispatch uses the untyped general agent. And I switched 117 rarely used skills to be listed by name only. A test predicted that the skill change would take about 2.9 thousand characters out of the list. The controlled test of the duplicate file predicted about 5,400 fewer tokens for one agent type. Both are predictions for the changes I made.

The ledger still has zero changes with a measured after-value. A row counts only when I have that measurement. I know I changed what an agent gets at startup, and for the general agent I know I added a warning. I still have to see how the next set of dispatches actually runs. The warning’s effect depends on which dispatches change, and the effect of shortening the skill list depends on where that list shows up and how often it gets read. The baseline is what lets me go back and check those things.

My estimate, not a measurement, is that the local model server alone is worth about 1 to 3 percent of total spend. I expect most of the spend to come from how large contexts start and how long sessions run. For shorter-lived lead sessions, my estimate is about 8 to 17 percent of weighted spend, with an upper bound near 22 percent. The handoff is a big part of the uncertainty there. For trimming the fixed material agents start with, my estimate is about 8 percent after accounting for overlap between changes to the instruction file, the agent type, and the lists of skills and connectors.

I estimate a background watcher for CI and merges at 1.5 to 3 percent of weighted spend, and condensing big inputs before they reach the model at 0.7 to 2.6 percent. My guesses for the smaller changes are 1 to 3 percent for reusing agents that have finished their work, 0.5 to 1.5 percent for capping how much they report back, and 0.5 to 2 percent for keeping the start of the prompt stable so more of it can come from cache.

Those are all my estimates. They overlap, so adding them up would count some of the same work twice. If I reuse an agent, for example, there’s one fewer fresh start where I can save tokens by trimming the instructions and skill list. My combined estimate is about 10 to 15 percent without the lead-session change and about 15 to 30 percent with it. The second range is wide because the biggest change is the one I’m least sure about.

I also filed a few ideas outside the token work. Use conditional web requests, share a read-only environment per project, run only the tests a change touches, rerun the model quality tests as a weekly canary, audit branch protection across repositories, and add a lint rule against timing-ratio tests. They’re filed ideas with no measured results yet.

I can check the prompt count on another implementer run after replacing the duplicate, then use the spend report to see how much that change matters across the workflow. For the lead sessions, I need to include the handoff and the time the next session spends getting its bearings. And if I route more jobs to the local model, I need a record of whether it got those jobs right. The existing call count gives me almost nothing to work with on that last part. It’s the same reason I care about the five wrong answers in the JSON test even after the parser stopped complaining.

Without a computer screen, could you tell me how many tokens your assistant session starts with, how large its context gets, and how you’d know if a local model had quietly cut off the top of its input?