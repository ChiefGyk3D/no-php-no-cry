---
title: "Work journal: November 27, 2026"
date: 2026-11-28T09:30:00-05:00
draft: true
description: "What my agents and I merged on November 27, 2026, with the pull request and commit counts, and what those numbers do and do not cover."
slug: "work-journal-2026-11-27"
categories: ["Journal"]
tags: ["journal", "agents", "pull-requests", "workflow"]
syndicate: false
---

My agents and I merged 183 pull requests and recorded 1,068 unique commits across the projects I was working on November 27, 2026. Those numbers include branch work, review fixes, merges, tooling, documentation, and private tooling. The pull request dates come from GitHub in UTC, so a few changes close to midnight Eastern could land on either side of the date.

<!--more-->

## What the numbers actually cover

The public project breakdown was 46 merged pull requests in scrum-around-and-find-out, 34 in FAFO, 20 in Strategic-Herding-of-IT-Tasks, 18 in Reach-Around, 11 in siem-docker-stack, eight in department-of-internal-arguments, seven in FrankenLLM, and three in no-php-no-cry. git-your-ship-together and Patch-Gremlin each had active commits but no pull requests merged during the UTC window.

Private tooling accounted for another 17, 14, three, one, and one merged pull requests across five repositories. I am deliberately leaving those repository names and their contents private.

The commit side was even more lopsided. SAFO had 301 unique commits and FAFO had 267. Reach-Around had 120, siem-docker-stack had 55, department-of-internal-arguments had 46, FrankenLLM had 35, Strategic-Herding-of-IT-Tasks had 26 on its default branch, Patch-Gremlin had nine, no-php-no-cry had six, and git-your-ship-together had five. Private tooling supplied the remaining 198 commits.

That is how the day reaches 183 pull requests and 1,068 commits. It was not 1,068 finished features. Merge commits, review rounds, test-first commits, conflict repairs, documentation, release work, and side branches all count. But it is still a useful picture of how much was moving at once.

## Review rounds were most of the work

A lot of the commit volume came from repeatedly reviewing work, fixing what the review found, and running another round. This was especially visible in the runner tooling, installers, queue machinery, review-export tools, and infrastructure helpers.

The runner-pool work went through multiple Daybreak rounds covering launch approval, the kill switch, state directories, lock handling, resource sizing, health checks, cleanup, and the operator sink used by the GitHub App manifest tool. The fixes generally tightened ownership, file modes, state validation, read-back, and the binding between an approved job and the exact queued revision. I am keeping the security details at that level because this is a public journal, not a finding dump.

That same pattern ran through other projects. The private infrastructure work had repeated rounds on image handling, discovery and claim state, hardware profiles, rebuild planning, cluster verification, first-boot behavior, and artifact handling. siem-docker-stack had review rounds on collectors, backup synchronization, alerts, mount verification, bounded parsing, and the weekly digest. FrankenLLM had hardening rounds around the installer, remote setup path, watchdog, service configuration, and recovery from an interrupted swap.

The important part is that the reviews found things the original tests did not. Several new tools received serious findings from Daybreak or automated review even though their existing tests had passed. Passing the first test suite was not the same as being finished.

One SAFO change, the shared read-only hash-locked virtual environment, reached Daybreak round eight. A Medium finding was fixed, but the review still was not clean when it merged. I recorded that plainly. “Merged” and “clean review” are different facts, and pretending otherwise would erase the useful part of the record.

The new queue in Strategic-Herding-of-IT-Tasks also went through eight review rounds before the relevant work merged. The project gained a dependency graph, durable queue, per-task leases, storage and transition handling, import contracts, optional tool adapters, privacy checks, configuration validation, and hardened readers. Later in the day I chose to replace the file-based queue design with a SQLite store, so the queue work moved into transaction-backed storage, audit export, offline verification, backend selection, and concurrency and crash testing.

That project is now public after a clean audit. The trigger was painfully practical: private repository GitHub Actions jobs were failing because the billing limit had been reached. I raised the budget to $30 that day, but public repositories run Actions without consuming the same private-repository minutes. Before making the repository public, I removed one private repository reference from an issue, redacted two private-process phrases, enabled secret scanning and push protection, required approval for pull requests from external contributors, and left branch protection in place.

I also established that SAFO and Strategic-Herding-of-IT-Tasks are sister projects. SAFO remains the custom system. Strategic-Herding-of-IT-Tasks is the flexible edition. Base features should remain at parity, and every change now needs an explicit port decision instead of depending on somebody remembering later.

## FAFO went from scaffold to an actual fleet view

FAFO started the day with an initial commit and then moved through 34 merged pull requests and 267 commits.

The first slice was the foundation: package scaffolding, GYST CI callers, Dependabot, security policy, documentation, configuration loading, snapshot storage, and command-line redaction. The snapshot store used atomic writes and restrictive modes. The configuration loader rejected secret material and tightened key handling. The redactor went through several rounds to cover secret-named flags, environment-style values, cookies, ANSI text, and bounded matching.

From there, FAFO grew the collector engine and the sources needed to see the agent fleet. It gained per-source workers, timeouts, backoff, stale-row handling, host information, Claude sessions, Codex and Gemini process trees, Ollama state, runner state, GitHub REST data, Copilot cloud work, and an adapter boundary that can include SAFO.

Project attribution received its own guarded Git runner and cache. Process runners learned to kill the process group before reaping. Tests stopped assuming a process disappeared immediately and started polling through a shared helper. Under load, the process-runner tests moved to explicit readiness files and more stable child-process behavior.

Then the data became something I could actually use. FAFO gained a shared view model, table output, JSON output, session output, a Textual terminal interface with six views, a systemd user unit, and a quickstart. It writes a bounded `views.json` beside the main snapshot so the Claude pane can read the data without launching a subprocess. CI type-checks that pane integration against vendored API types, and the type-check job had egress blocked.

Session display got more useful as the day went on. FAFO added redacted task labels from transcript tails, kept the last attributed repository for idle sessions with a visible marker, collapsed boring helper processes into summary rows, and allowed the helper rows to be expanded. It also gained an opt-in safe command display mode. That mode is conservative about values after flags and does not assume a command line is harmless just because it looks familiar.

The storage path kept getting tighter too. Snapshot writing became strict JSON with iterative capped walks instead of relying on recursion behavior. Reads gained bounds, validation, and per-row repair for bad typed numbers. Oversized snapshots are shrunk while preserving session and health rows, or the previous readable file is kept. External display text is masked for credential-shaped material, and row identity comes from the raw identifier instead of whatever redacted text happens to be visible.

Performance was not left as a guess. FAFO gained load and overhead tests, a per-instance scrub memo, performance documentation, and load-invariant timing checks. The typical active performance phase used seven sources with 20 rows by default, while the full variant exercised seven sources against the 256-row display cap.

By the end of the day, it was no longer just a process list. It could render the fleet, show session context, account for multiple Ollama servers, expose a one-line status summary, register Codex session state, and report Claude and Codex usage windows from their local data sources. Some of that work continued beyond the pull request list captured for November 27, but the 34 merges are the UTC-window count.

## SAFO kept turning recurring pain into commands

SAFO’s 46 merged pull requests covered a lot of the problems that show up when many agents and repositories are active at once.

Several changes were about cost and local routing. `safo-draft` made the local model the default path for drafts and recorded each call’s project and outcome. The default draft model moved to `gemma4:12b`. `safo spend` added a weekly spend report with a stored baseline, and `safo spend-post` could place that summary in a private issue. `safo lead-curve` measured how the lead session’s cost changed over time and what handoffs cost.

The measurements explained why this mattered. The local server alone saved about 1 to 3 percent of weighted Claude spend. The lead session accounted for 37 percent of the spend, and 84 percent of that lead-session spend happened after turn 200. Agent reports handed 3,157 messages back into the lead context, with a median length of 438 words. Those reports represented 5.69 percent of the lead session’s weighted spend.

The result is not “local models save everything.” They did not. The larger problem was the long-running lead context and the amount of material repeatedly handed back into it. That is also why the token-savings writing took the angle it did: vibe coding was the problem, and engineering judgment was what told me where to look.

SAFO added an evaluation canary that compares local-model scores against a stored baseline and detects silent truncation behavior. It also gained a shared read-only virtual environment per lockfile, a capped digest runner for approved Git and GitHub commands, and a script that selects impacted tests with a full-suite fallback when it cannot decide safely.

The workflow controls changed too. `safo-threads` can list, reply to, and resolve review threads from a dispositions file, including unresolved outdated threads. That matters because unresolved Copilot threads were blocking merges even after the named CI gate was green. Green checks alone did not make the pull request mergeable.

`safo-remerge` addressed the other repeated failure: main moved quickly enough that `pyproject.toml`, the changelog, and README files kept conflicting. The command can merge main and preserve both sides of specific list-style conflicts. It later learned how to handle additions in the `pyproject.toml` scripts table.

`safo-cards` gained a REST-only path to set Kind, Epic, and Effort from a table. `safo protection --all` can audit every tracked repository’s default branch against the standard. The branch-protection work expanded to cover strict checks, conversation resolution, the named gate, secret scanning, and generation of an application plan.

The brief scanner now checks briefs and reports for secrets and private data. The idle check can block the end of a turn when the active worker count is below the configured floor and ready work exists, but only trusted authors count toward that ready work. Third-party text and queue text stay out of the block reason.

`safo-ship` received a queue mode with head-lag retry, update-branch handling, deadlines, per-pull-request checks, and named stop conditions. Review rounds tightened the relationship among the pull request, the exact check run, the base revision, branch protection, workflow files, and anything the workflow executes. A local workflow or local action became a human stop.

The guarded wrapper work also had an honest failure and recovery sequence. One change was merged, later reverted, then reconciled with the other implementation. The final result used one implementation of the wrapper form. That is less tidy than a straight line, but it is what happened.

## CI cost became product work

The GitHub Actions billing failure was not just an account setting problem. It exposed how much private-repository CI time was being spent on changes that did not need the full matrix.

git-your-ship-together added `skip-docs-only` support to its Python, Bash, and OpenTofu reusable workflows. The work started with failing tests, then added the implementation and documentation. Private repositories adopted the docs-only skip and pull request matrix changes the same day.

The GYST repository had five commits and no merged pull requests in the UTC window, because the branch work had not merged inside that slice. The callers still started landing in private tooling immediately, which is why some of the private pull request subjects reference GYST issue 460.

SAFO also worked on making load-sensitive tests less dependent on wall-clock luck. Several tests moved from ratios of measured time to CPU time, operation counts, bounded polling, or deterministic fake timers. A lint rule was added to reject timing-ratio assertions. Three heavy-load flakes were made deterministic, and another guard test counted lines of work instead of seconds.

The failures did not disappear. Two flaky tests were still tracked at the end of the period. The correct statement is that several known load-sensitive tests were repaired and two more remained open.

## The runner pool and local model path got real safeguards

The runner work covered both job execution and local model capacity.

The pool gained per-job CPU and memory sizing from the host, health reporting, alerts, and a fallback switch. The launch path bound approval to the queued revision, serialized kill-switch activation with launch, checked private state directories and their ancestors, and verified lock identity. The kill command was changed to report in-flight launches honestly instead of implying they were already gone.

The GitHub App manifest tool was also hardened through repeated review rounds. It moved toward a purpose-built operator sink with strict ownership and allowlisting, restrictive launch-file creation, broader token-prefix redaction, runner-group read-back, and cleanup verification. The public point is simple: credentials were directed to an operator-controlled sink, not handed back through agent output.

The local model routing gained an optional overflow tier that is used only when the primary tier is busy. I explicitly approved the runner model server to receive overflow work from any repository, including private repositories. That exception applies to that service, not to arbitrary external models.

A benchmark harness was added for the runner tier, followed by fence-tolerant scoring, preamble and reasoning checks, an ATLAS-mapped resilience suite, poisoning and injection-detection tasks, safe context-window drivers, context sweeps for 8 GB and 16 GB cards, and a GPU-fit warm-up before benchmarking. The model evaluation write-up was deliberately deferred until that work was graded. The plan is an evidence document, a journal entry, and a blog post, staged before production.

Claude quota pressure also affected routing late in the day. I approved leaning on Codex for implementation until the Claude quota reset at 8:00 PM Eastern on November 28, including overage. That was a cost decision made with an explicit reset time, not a silent change in model policy.

## Installers and watchdogs got less trusting

FrankenLLM merged seven pull requests and recorded 35 commits.

The installer gained optional bind-address configuration, a dedicated service user, resource caps, an optional pinned Ollama version, and an opt-in fail-closed GPU guard. The model scripts were fixed to honor the configured bind address.

The remote installation path received the heavier review. It moved toward verified release assets, private staging, validated ports and installation directories, staged service replacement with rollback, and recovery from interrupted swaps. Configuration files were read as data instead of sourced as shell code. Model names and ports became validated arguments.

The watchdog learned to alert when the GPU, driver, or Ollama failed during uptime. Follow-up fixes covered fast installer failure, real-setting use in status and tests, per-channel retries, settings-path checks, safer command lookup, and recurrence handling while recovery was already pending.

Patch-Gremlin had nine commits and no merged pull requests during the UTC window. Its secret-manager mode was repaired for both hardened service execution and manual runs, followed by several Daybreak rounds around confinement, migration, file modes, environment handling, and exact cleanup behavior. Version 2.0.2 was released.

A private installer also had a usability failure: it asked me to approve installation by typing a hash. That was changed to a plain yes prompt. The reviewed digest still mattered, but requiring a human to retype it was not useful approval.

## Monitoring, backups, and collectors moved together

siem-docker-stack merged 11 pull requests and recorded 55 commits.

The weekly digest gained real collectors for UniFi, pfSense, and Twingate data. A read-only UniFi OS Server version collector shipped with bounded parsing and stricter handling of the returned structure. A separate read-only fleet inventory followed later in the commit stream.

The UniFi backup work added synchronization from the Pi to network storage, health metrics, and paused alert rules. A real-system problem showed up in the mount procedure, so the implementation changed to mount first, bind-remount with the requested option, and verify the resulting mode. The backup age calculation was later tied to the epoch in the filename and kept from going negative.

The pfSense backup design went through three review rounds. It settled on a network-storage pull followed by object storage, with the secrets planned for the development environment first. The design also covered encryption, receipts, retention behavior, and negative testing, but I am not publishing security findings or unshipped attack details here.

The project also gained host update collection, paused alerts for stale package lists and failed update checks, a Synology update alert design using SNMPv3, and a read-only Wazuh alert-count export. Several of those changes landed after the 11 merged pull requests in the UTC list, so they contribute to the commit count without changing the merge count for the day.

Reach-Around’s 18 merged pull requests covered the fediverse collector, backup verification, CI stability, history guards, the media-kit leads database, and related hardening. The Bluesky and Mastodon provider slices landed, followed by configuration, refresh, history, instance-template wiring, rate-limit handling, and overflow recovery documentation.

Backup work checked export completeness, required tables, listing races, exact smoke headers, bounded reads, and database-specific identities. CI added bounded retries for the container image build and allowed the required image host. A flaky Wrangler test cleanup race was fixed. The media-kit leads work kept personal values off command lines and moved returned data into private files before later steps could fail.

department-of-internal-arguments merged eight pull requests and recorded 46 commits. It added cybersecurity-blue, GRC analyst, and Linux system administrator roles, bringing the recorded total to 13 roles and 31 packs. It added a DigitalOcean pack, updated its Python matrix handling, and made the threat-model pack ship an OWASP Threat Dragon JSON file with every model.

Its cyber-tier review tools also learned to parse findings, hold a review result that could not safely show its answer, create a clean export, and build the next-round prompt. Those tools received extensive checks around bounded input, path handling, export shape, rollback, atomic publication, and verdict parsing. Again, the public fact is that review rounds ran and the handling was hardened. The finding details stay out of this journal.

## The site shipped, and one credential lesson hurt

no-php-no-cry merged three pull requests and recorded six commits. The token-savings blog post and journal entry moved from draft to the fuller merged version with a CC0 image. The development build’s business link was corrected to the root domain, and the corresponding crosslink test was updated. The public site promotion happened through a separate private repository with one merged pull request.

There was also a credential-handling failure. A Doppler delete command printed the remaining secrets table into chat, which exposed two credentials. I rotated both.

The lesson was specific: a delete command can still print surviving secret values. From that point forward, every Doppler command handed to me that can produce that output needs its output redirected to `/dev/null`, and the full command help needs to be read before the command is used. No credential values belong in the journal, logs, or follow-up explanation.

Other workflow failures were less dramatic but still expensive. Long commands wrapped and broke in my terminal, so owner commands now need to be either a script path or one short line. Agents started from stale base commits, so implementation briefs need to tell them to branch from a fresh `origin/main`. Fast movement on main repeatedly produced conflicts in common files. Unresolved review threads blocked otherwise green merges. None of those problems required a motivational lesson. They required better tooling and more precise briefs.

By the end of the day, the board state was not clean either. The next audit found 1,336 items with 354 drift. Earlier work had written Phase 1 closed-card state for 190 cards and Kind values for 268 cards, but the later audit still showed how quickly board metadata could fall behind the code.

That is the November 27 record: 183 merged pull requests, 1,068 commits, a new fleet monitor taking shape, repeated security review rounds, cheaper CI paths, more measurable token spend, hardened installers and runner controls, and several failures that were fixed instead of edited out of the story.