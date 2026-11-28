---
title: "How I Run Key Rotation Through Doppler"
date: 2026-11-16T19:08:00-05:00
draft: false
description: "I use Doppler as the source for application credentials and rotate supported vendor access without interrupting deployments. The useful lessons came from permissions, references, and testing the real path."
slug: "running-key-rotation-through-doppler"
categories: ["Journal"]
tags: ["security", "doppler", "key-rotation", "ci", "least-privilege"]
syndicate: false
image: "featured.webp"
imageAlt: "AI-generated illustration of a cartoon penguin at a workbench hanging a second matching key on a pegboard beside the first."
---

I wanted credential rotation across my projects without turning every swap into a maintenance window, so I built the process around Doppler, short-lived CI identity, and overlapping credential pairs. The interesting part was not creating a replacement value. It was proving that applications kept reading the right thing after the replacement happened.

<!--more-->

Doppler is the single source I use for application credentials. I do not want one value in CI, another in a local file, and a third copy sitting somewhere with a name like “temporary” long after temporary stopped meaning anything.

The rule I hold myself to is that development and production never share a key. That boundary is important because convenience has a habit of becoming architecture when nobody stops it early. When I find a place where the rule is not true yet, I treat it as a bug and fix it.

An application reads what it needs at run time. CI does the same, but the CI system does not store a static Doppler credential. The job proves its identity with a short-lived identity, receives access for that run, and then the identity expires. There is no long-lived value sitting in the CI settings waiting for somebody to copy it or forget why it exists.

That removes one static credential, but it does not magically solve the credentials used with other vendors. Those still need their own lifecycle.

## The pair does the handoff

Wherever the vendor supports it, I use Doppler rotated secrets with a pair of credentials.

The documented behavior uses two instances. One is active while the other waits for its turn. Their roles swap halfway through the configured interval, and the previous instance remains enabled for a grace period before it is retired. The interval is expressed in days.

Rotated secrets also require a paid Doppler plan. That matters because this is an operational feature with a cost, not a free checkbox everyone can assume is available.

The overlap is the part that makes the design useful. The application does not have to stop at the exact moment a credential changes. The replacement can exist, become active, and reach the application while the previous value still works. If a process reloads a little later than another one, it does not immediately fall over.

Without overlap, rotation becomes a race between disabling the old value and getting the new value everywhere it needs to go. I have enough races in software already. I do not need to manufacture another one around the credentials required to fix the others.

## Point at the rotating value

The application-facing configuration should not be rewritten by hand every time the pair changes roles. I use a reference pattern instead.

The application configuration points at the current value managed by the rotated secret. The application keeps reading the stable reference while Doppler handles which member of the pair is active behind it.

That distinction sounds small, but it is the difference between managing a rotation system and repeatedly copying values around while calling it automation.

And this is where I hit one of the less obvious problems: creating a rotated secret can replace the plain entries that were already there. If the application configuration previously read one of those entries directly, the pointer may disappear during the change.

The fix was not complicated. Re-add the reference to the rotated value and test it. The lesson was more important than the fix: never assume the old application-facing entry survived just because the new rotated pair exists.

A secret manager can contain the correct credential while the application still points at nothing useful. Both statements can be true at the same time, which is a fun little way to learn that storage and wiring are separate problems.

## Both sides need the same permissions

The two credentials in a rotating pair must carry identical permissions.

If one side can perform the job and the other cannot, the system works until the roles swap. Then a perfectly scheduled rotation becomes a perfectly scheduled failure.

That kind of failure can be confusing because nothing appears wrong when the pair is created. The active side works. The test passes. Everyone goes home. Later, the other side becomes active and discovers it was given a different job description.

So I define everything the job will need up front and apply the same permissions to both members of the pair. That does not mean granting broad access just in case. It means understanding the actual operation before building the pair.

Rotation cannot compensate for sloppy permission design. It just gives sloppy permission design a schedule.

## I challenged an over-broad credential

One job had read access that was broader than the task required. Broad read access sounds less alarming than broad write access, but “read-only” is not the same thing as “safe.”

If a job needs one type of information, giving it permission to read unrelated information expands what a leak can expose. The credential may be temporary, but there is no reason to make its temporary access larger than the job.

I trimmed it down to the single permission the job needed, then ran a real deployment.

That last part matters. A permission description can sound correct while the actual path calls something unexpected. A synthetic check can confirm that authentication works without proving that deployment works. And a dashboard can happily show that everything is configured while the application is busy failing somewhere else.

The deployment passed with the narrower permission. That was the proof.

I do not consider least privilege finished when the settings look reasonable. I consider it finished when the real operation succeeds with the smaller permission set. A passing test of the real path beats my opinion, the vendor documentation, and whatever an assistant confidently guessed the job might need.

## Commands are part of the disclosure surface

The rotation work also reinforced a rule I already follow: never let a command echo a credential.

Shell tracing, verbose output, command arguments, copied terminal sessions, and CI logs can all turn a value that was handled correctly at rest into a value that is exposed during use. The secret manager cannot pull it back out of a screenshot after somebody posts it.

So the command should receive the value without printing it. Logs should confirm that an operation succeeded or failed without including the credential itself. Error output should remain useful without dumping the entire request or process state.

If I see a credential printed, I treat it as leaked and rotate it. I do not try to decide whether the terminal was private enough or whether the log was visible long enough to matter.

This is where rotation earns its keep. A leaked long-lived credential is a problem that lasts until somebody notices and removes it. A leaked credential under rotation is still a problem, but it is a short-lived one, and I can shorten that window further by rotating it immediately.

## Separation has to stay boring

Development and production never share a key. That is a rule, not a boast, and rules like it drift when nobody is looking.

A value used while testing should not become a path into production, and a production credential should not be copied into development because it makes one test easier.

So I audit for it. A simple check that lists which credential each context uses, by name and never by value, is cheap and catches the drift before an incident does.

Fallbacks feel resilient until they cross a security boundary. Then they are just an undocumented alternate path. Missing access should fail clearly instead of quietly reaching into a broader bucket.

Keeping the boundary boring also makes failures easier to understand. If development fails, I inspect the development path. If production fails, I inspect the production path.

## Done means the real thing worked

There were several points where I could have called the work complete.

The rotated pair existed. The reference appeared correct. CI authenticated with its short-lived identity. The narrower permission passed an isolated check. Every one of those was useful evidence, but none was the finish line.

Done meant the deployment passed and the public site answered afterward.

That checks the complete path: CI proved who it was, Doppler supplied what the run needed, the application-facing reference resolved to the active value, the vendor accepted the credential, the permissions were sufficient, deployment completed, and the result was actually reachable.

A green settings page cannot prove that chain. Neither can a successful login or a test that exercises only the first request.

The final check is deliberately boring. Run the real deployment, then ask the public site for a normal response. If both succeed, the rotation did not merely look correct. It carried the actual workload.

That is how I want key rotation to behave across my projects: routine, overlapping, narrowly scoped, and proven by the path it exists to support.
