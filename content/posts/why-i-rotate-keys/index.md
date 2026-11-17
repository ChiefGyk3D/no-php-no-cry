---
title: "Why I Rotate Keys Before Something Goes Wrong"
date: 2026-11-16T19:08:00-05:00
draft: true
description: "Keys leak through ordinary mistakes, not dramatic breaches. Rotation limits how long a leaked credential stays useful and makes recovery routine."
slug: "why-i-rotate-keys"
categories: ["Open Source"]
tags: ["security", "credentials", "key-rotation", "least-privilege"]
syndicate: true
image: "featured.webp"
imageAlt: "AI-generated illustration of a cartoon penguin in a hard hat and hi-vis vest fitting a new key into a padlock on a pipe while the old key sits in a bin."
---

Most keys do not leak because somebody performed some elite hacker magic. They leak because a command printed too much, a screenshot included the wrong window, somebody pasted one into chat, or an old CI run kept output nobody remembered was there.

<!--more-->

That is the annoying part about credential security. The failures are usually boring.

A key ends up in a log because debug output was enabled. Somebody shares a screenshot while troubleshooting and does not notice the value in the corner. A laptop disappears. A person leaves, but something they used still works. An old automation run keeps its output much longer than anyone expected. None of this requires an attacker to break cryptography. It only requires one ordinary mistake and enough time for somebody else to find it.

Rotation changes what that mistake means.

If a leaked key remains valid indefinitely, the useful lifetime of the leak is also indefinite. You can remove it after discovering the problem, but that assumes you discover it. Plenty of exposed credentials are found late, and some are probably never found by the owner at all.

A regularly rotated key gives the leak a bounded window. The exposed value stops working when it is replaced, even if nobody noticed where it escaped. Rotation does not make the leak harmless, but it turns an open-ended problem into a temporary one.

That is why short-lived credentials beat long-lived credentials wherever the vendor supports them. A credential that expires quickly gives an attacker less time to use it, and it gives me less stale access to remember later. Long-lived credentials are convenient right up until everyone forgets where they were copied.

## Rotation should not mean downtime

The obvious objection is that replacing a key can break whatever depends on it. If the old value stops working before the new one reaches the application, requests fail and somebody gets to spend their evening discovering which tiny piece of automation was apparently holding civilization together.

The safer pattern uses a pair.

Both members of the pair are valid during the handoff. One is active while the other is ready to replace it. The new value becomes available before the old one is disabled, and the application starts using the replacement while the previous value remains valid for a grace period.

Then their roles swap on the next rotation.

That overlap matters because a credential change is not one instant event. A new value has to be created, stored, delivered, loaded, and used successfully. Treating that entire path as atomic is wishful thinking. The overlap gives every part of the system time to catch up without leaving a gap where neither value works.

It also makes rotation boring, which is exactly what I want from security infrastructure. If rotating a credential is a dramatic maintenance event, people will avoid doing it. If it happens routinely and the application keeps working, it becomes part of operating the service.

## One key should do one job

Rotation limits how long a leaked credential works. Least privilege limits what it can do during that time.

A deployment job does not need every permission a vendor offers. It needs the permissions required to deploy. A read-only task does not need write access just because granting broad access is faster. And a credential used by one application should not quietly become the shared master credential for five unrelated jobs.

This is where I challenge defaults and recommendations. If a tool asks for broad access, I want to know why. If the answer is convenience, that is not good enough.

A useful test is simple: reduce the permissions, then run the real path. Do not stop after a settings page accepts the change. Run the actual deployment or operation the credential exists to perform. If it succeeds, the smaller permission set is evidence. If it fails, the failure shows which ability was really missing.

An opinion about least privilege is nice. A passing run with reduced permissions is better.

## Keep credentials in one place

I use Doppler as my secret manager. This is not an advertisement. It is simply the tool I use to keep credentials in one controlled place instead of scattering them across loose files, shell history, CI settings, and whatever temporary note seemed convenient at the time.

Loose copies are how forgotten access survives.

When applications read credentials from one source at run time, there are fewer places to update during rotation and fewer stale values waiting to surprise me later. It also becomes much easier to answer the question that matters during an incident: where could this credential have gone?

The answer should never include chat, a ticket, or a command that echoed it into a terminal.

Do not paste a secret into a conversation so somebody can “help troubleshoot.” Do not put one in an issue and delete it afterward. Do not pass one through a command that prints its arguments or enables verbose tracing. Deletion is not a time machine, and logs have an impressive ability to outlive the reason they were created.

If a key does appear somewhere it should not, rotate it. Do not argue with yourself about whether anyone saw it. Do not spend hours trying to prove a negative while the exposed value remains valid. Replace it, verify the real path still works, and then investigate how it escaped.

Rotation is not a substitute for preventing leaks. It is the control that keeps one boring mistake from becoming permanent access.
