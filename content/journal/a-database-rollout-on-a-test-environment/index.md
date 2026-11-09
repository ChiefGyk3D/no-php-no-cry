---
title: "A database rollout on a test environment"
date: 2026-11-09T22:00:00-05:00
draft: true
description: "I rolled several pending migrations onto a non-production Cloudflare D1 database, with exports, verification and a restore drill around the risky parts."
slug: "a-database-rollout-on-a-test-environment"
categories: ["Journal"]
tags: ["cloudflare", "d1", "database", "security"]
syndicate: false
---

Several pending migrations needed to land on a non-production Cloudflare D1 database, and some of them changed how analytics data was stored. I treated the rollout as an ordered operation instead of pasting commands until everything turned green.

<!--more-->

## Read before write

I started with read-only checks. Before changing the schema, I confirmed what was already applied and what the database currently contained. Then I saved an export and a point-in-time bookmark before the first risky write.

That order matters because a migration being correct in the repository does not mean the target is in the state I expect. The export gave me a concrete copy to inspect, while the bookmark gave me another recovery point before the schema moved.

I applied the pending migrations in sequence, then deployed the Worker that expected the new schema. After that, I verified the counters actually increased. A successful deployment only proves that the deployment command completed. It does not prove that requests reached the Worker or that the database accepted the writes.

The browser test added another wrinkle. Browsers that block the HTML `ping` attribute never send those click reports, so clicking a link was not a reliable test of the Worker path. I sent a direct request instead and confirmed the counter changed.

## The credential was stale

The credential already stored for deployment was stale. Its replacement was scoped to one account and one zone with an expiry.

This was also a good reminder not to paste a command while it still contains placeholders. A placeholder is useful in documentation because publishing real identifiers would be worse. In an operational shell, it is an unfinished command. Fill it in, inspect the complete command, then run it.

I also managed to start a destructive helper without its dry-run flag. The confirmation prompt stopped it before it changed anything. That prompt did exactly what it was there to do, but relying on the final prompt is not a process. I should have run the dry run first and read its output.

## The one-way cleanup

One migration enabled a one-way privacy cleanup of stored country values. I took a fresh export immediately before running it, then performed the cleanup and verified the result.

The fresh export was intentional. Earlier backups protected the rollout generally, but this operation changed stored data in a way that could not be reversed from the cleaned database. The recovery copy needed to represent the state immediately before that operation, not merely the state from the beginning of the session.

I left the alerting tables until last. They were useful operational additions, but they were not prerequisites for the Worker path or the privacy cleanup. Keeping them at the end reduced the number of moving parts while I verified the core data path.

## Backups that can be restored

The backup tooling has a few deliberately inconvenient rules. It refuses to write inside a git repository, never exports visitor tables, and checks every export instead of assuming the command succeeded because a file appeared.

Those rules keep database exports out of commits and visitor data inside the service. They also stop a partial or failed export from being treated as usable.

The runbook includes a restore drill, because a document describing a restore is not evidence that the restore works. The only useful proof is taking the backup through the restoration procedure and checking the result.

## The boundary stayed narrow

I allowed the coordinator to run these steps only because the projects were not yet live and every target was a test resource. That permission did not include DNS, production, tokens or reading secrets.

That gave the coordinator enough access for the job without giving it unlimited operational access. It could execute the reviewed database and deployment sequence, while credential handling and anything capable of changing live traffic stayed with me.

## Lessons

- Start with read-only inspection, then create recovery points before the first write.
- Verify the data path by watching counters change, not by trusting a successful deploy.
- Treat placeholders as unfinished commands.
- Put the dry run before the destructive command, even when a confirmation prompt exists.
- Take a fresh export immediately before a one-way privacy cleanup.
- Keep backups out of repositories and exclude visitor tables by design.
- Run the restore drill. A restore plan that has never been exercised is still a theory.
- Keep delegated operational access limited to test resources with explicit exclusions.
