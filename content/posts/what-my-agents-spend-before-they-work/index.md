---
title: "My Agents Were Eating 40,225 Tokens Before They Did Any Work"
date: 2026-11-26T21:00:00-05:00
draft: true
description: "I measured where my assistant spent its tokens, found a local model silently dropping instructions, and set a baseline to check what my fixes actually change."
slug: "what-my-agents-spend-before-they-work"
categories: ["Open Source"]
tags: ["ai", "vibe-coding", "local-llm", "measurement"]
syndicate: false
image: "featured.jpg"
imageAlt: "Stacks of coins with a green seedling growing from each, rising in height toward a glass jar of coins with a larger plant"
---

I sent a 28,905-token prompt to qwen3.5:4b and the response reported processing 4,098 prompt tokens. It answered from the tail of the input. The instructions at the top were gone, and nothing printed a warning. The answer by itself looked like an answer.

I got there by asking where all my tokens were going. I wanted a yardstick before I changed anything, and the first numbers gave me one. I measured a median of 40,225 tokens on a subagent’s first turn, before it did any work. The agents I dispatched accounted for 62.6 percent of my weighted Claude spend. I would’ve started with the smaller share of the bill if I’d gone by what I could see in the main conversation. I knew to ask for those measurements and then check what the local model had actually received because I’ve spent years engineering and architecting IT and cybersecurity systems.

<!--more-->

## Where the tokens were going

A weekly token-spend report I wrote covered all tracked weeks through November 26, 2026. I weighted input at 1, output at 5, cache reads at 0.1, and cache writes at 1.25. Those are weights I chose for comparing my own runs. On that scale the report put the measured total at about 4.36 billion, with 37.4 percent in the lead session, the one I was talking to, and the rest in the agents it spawned. The main conversation is the part I can watch. A lot of the work it sets in motion is out of sight unless I count it.

The lead session still had something worth looking at. I measured that 70.3 percent of lead-session turns came after turn 200, and those turns carried 84.2 percent of lead-session spend. That gives me a place to try ending sessions sooner. If I move work to a fresh session, I also have to count what it costs to write the handoff and get the next session back up to speed. A shorter transcript is easy to produce. To see if I came out ahead, I need to count the work on both sides of the handoff.

The subagents had their own starting cost. My estimate is that about half of the 40,225-token median was instructions and the list of available skills, using 3.5 characters per token as the conversion. I measured the median first turn. The breakdown of what was in it came from that character-based estimate. An agent can come back with useful work and still have a pile of context it had to read before it got anywhere near the job. That pile is worth looking at when I pay to load it on every fresh start.

## The prompt was quietly cut from the top

I counted how often the brief sent to an agent included a local-model step. The hook log put it at 3.6 percent of dispatches across the report window. In the first tracked week it was 11.8 percent, or 8 of 68 dispatches. The next week it was 14.4 percent, or 13 of 90. By week 48 it was 2.4 percent, or 49 of 2,076. Dispatches grew from 68 to 2,076 while the local share fell. That count tells me what the briefs asked agents to do. To see what happened when they called the local model, I had to look at the call records.

The log counted 1,433 successful calls since October 7, 2026. It started recording failures and busy exits on November 25 at 19:18, so the 1,433 figure covers successful calls only. Across those calls there was one row with a recorded quality outcome. I could count the calls that completed. How often the answers were right was still an open question.

On November 26 I read the context settings on the local model server. I hadn’t checked either setting until the token measurement made me go looking. The small model, qwen3.5:4b, was configured for 8,192 tokens. The large model, gemma4:12b, was configured for 131,072. Then the 28,905-token prompt came back with a count of 4,098.

I followed up with tests at nominal sizes of 9k, 10k, and 12k tokens on the small model. I put an instruction at the top and a marker at the end so I could check which part of the prompt the answer used. All 9 calls reported exactly 4,098 prompt tokens. The instruction at the top showed up in 0 of 9 answers. The marker at the end showed up in 9 of 9. No warning was printed.

Up to 8k nominal tokens, the reported prompt counts matched the actual input on both models and I saw no truncation. From those tests I infer the small model’s cutoff is somewhere between 8k and 9k. The large model passed on both markers in all 14 of 14 size cells through 8k, the largest input it got in that round. In a later test, gemma4:12b recalled the planted marker cleanly up to about 80 thousand tokens and took roughly 0.75 milliseconds per prompt token to read the input. That measured how it handled a marker and how long it spent reading. I still need to check its answers on the work I want to send it.

Any context window has a limit. What bothered me was that the server accepted the request, dropped the top, and returned a plausible answer the same way it did when it had the whole prompt. If I put the task and its constraints at the top, the model can produce a clean answer to whatever text happened to survive. Reading the answer alone is a lousy way to find out whether the model ever saw the instructions.

## What I changed about local calls

I put character caps in front of the call so oversized prompts get refused before sending. I also added a guard that stops the call when the server reports truncation. I want the calling code to treat a response based on a partial prompt as a failed call. Otherwise that response can go straight into the next step, where the agent sees text and has every reason to assume the local model got the job it was given.

Every local call now records which project, agent, and dispatch it came from. I added an outcome step that records whether the answer was accepted, rewritten, discarded, or had a factual error. With that in place I can trace a draft back to the call that produced it and see what happened to it afterward. I need enough of those outcomes to tell how the local model does on actual work. The single historical outcome row gives me very little to go on.

The tool that drafts issue, pull request, and comment text now defaults to gemma4:12b. The queue also treats a busy server as a reason to retry. A busy model is already doing work and the queue can try again. I updated the documentation for the local model wrapper, the drafting tool, the evaluation tool, and the spend report. The tooling guide covers the wrappers and the install steps.

In the evaluation I also turned on the JSON output option for gemma4:12b. I measured the number of answers wrapped in Markdown code fences dropping from 43 of 50 to 0 of 50. On all 10 test inputs, the answers were identical across five repeats. The pass rate was 45 of 50 before the change and 45 of 50 after it. I had fixed something real for the code that reads the response, and I still had wrong answers.

A parser can tell me whether it got valid JSON and whether the fields it expects are there. I needed expected answers to check what was in those fields. And 10 inputs with five repeats is a small sample. The repeats let me see how consistently the model answered those inputs. The outcome records are for the other thing I need to know, which is how it does across the jobs I send it.

I still plan to use the local model to digest big inputs before they get passed along. That work hasn’t started. I’d want to check whether a digest keeps the details the next model needs, because dropping those details on purpose gets me back to a version of the same problem. I’ve also thought about putting a spare 8 GB GPU to work in a second machine. My untested hardware estimate is that it couldn’t hold the larger model with useful context, so I’d need a smaller model there.

## What an agent reads before it starts

The weekly report is merged and has a stored baseline. I used that baseline to find out which parts of the job deserved a closer look. Some of what was being sent to agents was easy to account for. A second copy of an instruction file was 97.8 percent identical to the first, and only one of the tools in use ever read it. In 303 of 303 observed sessions, the other tool read only its own file.

I tested an implementer agent with the second copy out and with it in. Its measured first turn went from 34.6 thousand tokens to 39.9 thousand. The controlled test put the cost of the extra copy at about 5.4 thousand tokens for that agent. I replaced the duplicate with a 508-byte pointer. The controlled result gives me a prediction of about 5,400 fewer tokens for that agent type when I run it with the pointer. I still need the after-value from the changed workflow.

The type of agent I dispatched mattered enough to look at too. Over 14 days I counted 940 of 1,855 dispatches, or 50.7 percent, going to the untyped general-purpose agent. Its measured median first turn was 59.5 thousand tokens. The specialized implementer’s was 35.2 thousand. Those agents were doing different jobs. I’d have to give both the same work and check the results before I could tell what changing the dispatch buys me. A typed general-purpose agent and a warning when a dispatch uses the untyped one are merged. I can now see where the untyped one is still being used and follow up on those calls.

Of 183 available skills, I counted 22 distinct ones used in 60 days. I switched 117 rarely used skills to be listed by name only. They’re still available, and the test predicted about 2.9 thousand fewer characters in the list. I also counted four connectors with write powers that had zero calls since September. Disabling them is pending. That’s a permissions question as much as a prompt-size question. If a connector can make changes, I want to know which work actually requires it.

The other changes deal with how often I load that material and how much an agent has to read as work goes on. Shorter lead sessions with a written handoff, a background watcher for merges and CI, and digesting big inputs are still waiting to be built. I filed ideas to reuse finished agents, cap how much they report back, and keep the start of the prompt stable so more of it can come from cache. Each needs a check that covers the work it changes. For a shorter report, for example, I’d want to know whether the lead session had to go back and retrieve the details the agent left out.

## Speed and tests

I had a test that compared CPU-time ratios and kept failing in CI on busy machines. I replaced it with a count of the work done. The fix passed and is merged. The test was supposed to tell me how much work the code was doing. The timing on a busy machine was getting in the way of measuring that. Counting the work gave me a check I could tie directly to what I expected the code to do.

A separate change in review converts ten more tight wall-clock tests to CPU-time or event checks. I used deliberate changes to the code to show that the revised checks still catch the regressions they’re supposed to catch. I left 22 tests alone after measuring their timing margins. A test can stop failing in CI because I fixed the way it measures the work. It can also stop failing because it no longer catches the thing I wrote it for. I want to see it fail when the behavior is wrong.

I filed conditional web requests to avoid fetching a full response when it hasn’t changed, a shared read-only build environment per project to avoid repeating setup, and running only the tests a change touches. Keeping both local models loaded is filed too, so they’d be ready when a call comes in. So is auto-merging dependency updates after a proposed seven-day hold. Those ideas are still on the board. The work-count test is the one I can point to here and say what I changed and what passed.

## Reliability, reviews, and merges

I used the same thinking on a project board with 785 cards. A script corrected 190 closed cards and set a category on 268 open ones. The write looked right in the tool output. What I trusted was code comparing snapshots from before and after, which showed zero changes outside the plan. Looking at the cards I meant to change would only tell me whether those cards looked right. I wanted to know what happened to the rest of the board too, and I had to ask for a check that would actually catch it.

An automated security review flagged a gap in a small wrapper that checks a repository before it runs a code assistant on it. I had a test written to catch the problem before the fix went in, then sent the work through six rounds of adversarial review. Round 1 found two Highs. Round 3 found one, and round 5 found two more. Round 6 found no Highs and one Medium. The fixes were real, and review kept finding things the previous fix had missed. A test that catches the gap I know about is worth keeping. I still want someone looking for what I missed when I decided what that test should cover.

Then there was an installer an assistant wrote for me. It trusted a binary it found in a folder I could write to, calculated the hash, and approved that hash as the pin. The point of a hash pin is to have an expected value to check against. The installer was taking the value from the very thing it was supposed to check. Three separate automated security reviews turned up three different problems. One flagged the pin, another flagged installing from a writable folder, and another flagged that terminal escape bytes and binary bytes could hide what would be installed. In the hardened version I have to type part of the hash myself. That’s a place where I want the extra work, because my input is part of the check.

I also added a pair of root-owned wrappers so a sandboxed shell can start the code assistant safely. A check that blocks a push when generated rule files are stale is merged. I filed a pre-push check for generated files across all repositories, a secret scan on briefs and reports, and an audit of branch protection across repositories. The lint rule against timing-ratio tests and a weekly canary to rerun the local model quality tests are filed too. The canary would give me a recurring check on known cases like losing the start of a prompt. Those filed checks are still waiting to be built.

Every task now gets an issue and a board card first. I was repeatedly asked to run merge commands by hand across several projects, for work I’d already approved. The standing rule now is that subagents never merge. The assistant I’m working with merges green changes for work I asked for, pins each merge to the exact commit that passed, handles them one at a time, and tells me afterward. Every time I’m asked to run a command, the request includes the full command. I want to spend my time deciding whether the change is ready and checking the parts that need my judgment. Pasting an approved merge command was just making me the person the job had to wait for.

## A portable version

I’m also building a portable edition as a separate, private project for coworkers who have different mixes of AI tools or use none. The initial starter set, record schema, threat model, local-model tier design, and contracts for briefs and reports are done, with storage and the event log merged, the commands that use them in progress, and delegation that accounts for task dependencies still to come.

## The ledger still says zero

By the evening of November 26, 2026, Eastern time, the spend ledger had three applied changes. The duplicate instruction file had become the pointer, the warning for untyped dispatches was in place, and the rarely used skills had moved to names only. The ledger still had zero changes with a measured after-value. A row counts only when I have that measurement. A merged change tells me I can start collecting that evidence.

For the instruction file, I can check the prompt count on another implementer run and then use the spend report to see how much that change affects the workflow. The warning’s effect depends on which dispatches change. Shortening the skill list depends on where the list shows up and how often it gets read. For all of those, I need to look at how the next set of dispatches actually runs. The report gives me something to compare it to.

Local quality has a similar gap. I have a way to record outcomes now, and I have the measured results from the marker and JSON tests. To decide whether to put more jobs through the local model, I need to see what happens to the drafts and digests on the jobs they’re meant for, including how often somebody has to rewrite one or correct a fact. The call count can grow just fine while that answer stays unknown.

## What I expect to get back

My estimate for the local model server alone is about 1 to 3 percent of total spend. That’s an estimate. I expect the bigger items to be how large contexts start and how long sessions run. My estimate for shorter-lived lead sessions is about 8 to 17 percent of weighted spend, with an upper bound near 22 percent. The handoff is a big part of the uncertainty. For trimming the fixed material agents start with, my estimate is about 8 percent after accounting for overlap among the instruction file, the agent type, and the lists of skills and connectors.

My estimate for a background merge and CI watcher is 1.5 to 3 percent of weighted spend. I’m estimating the work a lead session could avoid spending on checking status while it waits. My estimate for digesting big inputs before they reach the model is 0.7 to 2.6 percent. The digest has to preserve enough of the input for the work to get done, and producing and checking it is part of the cost.

The smaller estimates are guesses too. I put reusing finished agents at 1 to 3 percent, capping how much they report back at 0.5 to 1.5 percent, and keeping the start of the prompt stable for caching at 0.5 to 2 percent. Those estimates overlap. If I reuse an agent, for example, there’s one fewer fresh start where I can save tokens by trimming the instructions and skill list. Adding the individual estimates would count some of the same work twice. My combined estimate is about 10 to 15 percent without the lead-session change and about 15 to 30 percent with it. The second range is wide because the biggest change is the one I’m least sure about.

## The answer looked fine

This is the problem with vibe coding. If I take a response that looks right as proof that the work is right, each of these jobs can look finished. The local model answered. The JSON parsed. The board tool reported the write. I could’ve taken the cleaned-up JSON as evidence the model was doing a better job, or counted the pointer as savings as soon as it went in. I got those distinctions by deciding what I expected to see and checking the numbers that would tell me whether I got it.

AI is a tool and it can help me do the work, but it can’t do all the thinking for me. It can write the comparison for the board. I still have to know why I care about cards outside the plan and make sure the comparison covers them. It can write a test for the local model too. I have to put something at the top of the prompt that I expect to see reflected in the answer, otherwise I can watch the model produce clean output all day and miss the fact that it never got the instructions.

Without a computer screen, could you tell me how many tokens your assistant session starts with, how large its context gets, and how you’d know if a local model had quietly cut off the top of its input?