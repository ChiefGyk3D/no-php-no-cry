---
title: "Running a fleet of AI agents"
date: 2026-11-09T19:00:00-05:00
draft: true
description: "What worked, what failed, and what I changed while coordinating AI agents across two projects."
slug: "running-a-fleet-of-ai-agents"
categories: ["Journal"]
tags: ["ai", "agents", "workflow", "ci"]
syndicate: false
---

I had agents repeatedly tell me work was merged when the merge queue said otherwise. That sums up running a fleet of AI agents across No PHP No Cry and Reach Around: the agents can move a lot of work, but their status reports are evidence to check, not state to trust. I was coordinating the work and reviewing it, while short-lived agents handled implementation and review.

<!--more-->

## Give every task a home

The part that worked was boring, which is usually a good sign. Before work started, every task got one issue and one project card. Each brief included the issue line and a cleanup duty, so the agent knew both what to change and what it had to leave tidy.

Agents never merge. The merge queue pins the exact head commit and requires the named CI gate to be green before anything moves. CI is the merge authority, and the gate is a required check named `CI green`.

Status reports needed their own rule. I now audit the project boards fresh before reporting anything. One board status drifted to 245 lines before I cleared it back to zero. A cached summary is not project state, even when it is written with great confidence.

## Trust the queue, not the narration

I made the mistake of claiming merges from agent statements instead of checking the queue. Agents also misreported merge state more than once, and a merge watcher sat silently because unresolved review threads were still blocking it. None of that was mysterious after I looked at the actual state. The mistake was treating narration as verification.

Several agents also committed conflict markers in changelogs. That is the kind of failure a human can dismiss as too obvious to happen, right until multiple agents do it. The fix is not another reminder in a prompt. It is a check that examines the artifact and fails clearly.

Reviewers kept finding real defects in work already described as finished. Reviews came from CI, GitHub Copilot, a local model on my own hardware, and a cyber-tier model when privacy or credentials were involved. So one verification round after every fix round is now standard. A fix report tells me where to look. It does not close the loop.

## Guards can become noise

Some command guards produced hundreds of false positives. Agents ended up working around them, so the guard was still present without reliably controlling the behavior it was meant to control.

The proposed fix is to replace loose matching with structured command parsing and tests. That is a direction, not a shipped fix. Until it exists and has tests, I am treating it as an idea.

## I still have to look

Visual work made the verification gap painfully obvious. Agents reported that renders matched the reference several times when they did not. CI can validate structure, budgets, and browser rules, but it cannot decide that a visual treatment actually matches the source material. I have to open the render and the reference side by side before I call it done.

The same cleanup rule applies below the interface. Short-lived work still leaves long-lived processes and worktrees behind. I confirm the process first, kill it by process ID, and clean worktrees as the work progresses. Broad cleanup commands are not a substitute for knowing what I am removing.

Public copy has a separate lane too. I route it to ChatGPT through Codex instead of asking coding agents to write it. The first announcement draft was built from a fact sheet rather than an analysis of the whole project, which was not the assignment. Tool separation only helps when the tool receives the full job.

## Lessons

- Create one issue and one project card before work begins.
- Put the issue line and cleanup duty in every brief.
- Let agents implement and review, never merge.
- Believe the head-pinned queue and the named CI gate, not a status sentence.
- Audit project boards before reporting their state.
- Run a verification round after every fix round.
- Inspect renders against their references myself.
- Treat noisy guards as broken controls, and do not call the structured-parsing idea shipped.
- Confirm stale processes, then kill by process ID and clean worktrees as I go.
