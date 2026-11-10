---
title: "Privacy engineering for analytics"
date: 2026-11-06T20:00:00-05:00
description: "I built analytics reporting around privacy floors, fixed release periods, and an append-only ledger. Security review kept finding ways that individually safe reports could reveal more when compared."
slug: "privacy-engineering-for-analytics"
categories: ["Journal"]
tags: ["privacy", "analytics", "security"]
syndicate: false
---

Reach Around’s analytics could suppress every small cell and still disclose one when two reports were compared. That was the problem I spent this stretch fixing. A privacy floor works inside one report, but it does not magically make a collection of overlapping reports safe.

<!--more-->

## Floors are only the start

The basic rule is straightforward: small cells do not appear in a report. If a source, destination, or country falls below the floor, the report suppresses or merges it instead of printing the exact count.

That protects against the obvious disclosure, but published totals can still reveal suppressed information indirectly. Reach Around handles that by folding small cells into an other bucket before anything is printed, and the report says plainly what that does and does not protect.

I am deliberately calling this suppression, not differential privacy or k-anonymity. The guarantee is narrower: the released report should not pin down a hidden cell from the values it prints. A reader with other information may still know more than the report can protect against.

## One release path

The harder problem appears across reports. Overlapping releases can each satisfy the floor and still disclose information when compared.

So the source and country funnel reports now have one release path. A release covers one complete weekly or monthly period. Free-form date windows do not release those cells.

Every release goes through an append-only, hash-chained ledger. The ledger records the period and binds the release to the complete public output. Releasing the same period again is allowed only when that output is identical. A changed total, a partial export, or a conflicting period is refused.

The ledger is not pretending to stop a malicious operator with control of the files. It is there to stop accidents, including stale exports, overlapping releases, and repeated periods with different results.

## Review found the composition bugs

I ran the privacy-touching changes through rounds of review by a cyber-tier model. The useful findings were not about one obviously unsafe query. They were about how safe-looking outputs composed over time.

The review found four important classes:

- Overlapping releases could expose suppressed information.
- Comparison features created another release surface.
- Period metadata created a side channel.
- Inconsistent repeat releases created another composition problem.

The fixes were structural. Released reports no longer carry a daily series or a previous-window comparison. Period boundaries are fixed. Metadata does not expose the distinction that created the side channel. And the ledger binds repeats to the complete released output, not just the requested dates.

That last part matters. Binding only the period would say, “Yes, this is the same week,” while ignoring that the numbers changed. The public output is the thing a reader can compare, so that is what the release record has to bind.

## Write down who the attacker is

I also wrote the threat model explicitly because “privacy preserving” is useless without saying against whom.

The adversary is a public visitor who can shape traffic, or a reader who can compare released reports. The operator is trusted. Operator mistakes are still in scope, which is why the ledger refuses dangerous release combinations instead of relying on me to remember every prior report.

The review process is bounded too. High and Medium findings get fixed. Low findings are accepted and documented when appropriate. Then I run a verification round and stop when the bounded review is complete. Otherwise security review becomes an infinite loop where every new opinion silently changes the finish line.

## Reusing the design on the blog

The blog analytics design reuses the same approach to aggregates and floors, but it keeps the existing Cloudflare Web Analytics script by decision. That means the privacy page needs to disclose both counters and explain that they operate under different rules.

Some analytics choices are less private than the safest available option. I am not hiding that behind a generic privacy claim. Each decision gets its own guardrail section covering what must be bounded, suppressed, disclosed, tested, or kept separate.

## Lessons

- A privacy floor protects a report, not an unlimited series of reports.
- Comparison features create another release surface.
- The ledger has to bind the complete public output.
- Threat models need named adversaries and explicit trust assumptions.
- Bounded review rounds keep security work rigorous without making “done” undefined.
