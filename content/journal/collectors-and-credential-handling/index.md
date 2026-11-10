---
title: "Collectors and credential handling"
date: 2026-11-07T23:00:00-05:00
description: "A collector audit exposed why credential names cannot be treated as configuration. I standardized the boundary across sources and simplified the CI wrapper that feeds them."
slug: "collectors-and-credential-handling"
categories: ["Journal"]
tags: ["security", "credentials", "collectors"]
syndicate: false
---

The collector configuration could name the environment variable holding a credential. That looked flexible, and it was wrong. A review found a credential-confusion risk at that boundary, so I stopped treating credential names as user-configurable data and audited every existing source against one fixed pattern.

<!--more-->

## One boring pattern

Reach Around started with follower counts and was being extended toward views and engagement across Twitch, Instagram, Threads, TikTok, and YouTube. Those platforms do not share one authentication model, but they can still share one security boundary.

Each collector now reads only its canonical environment variables. The configuration cannot name a different one. The check happens while loading configuration and again immediately before reading the environment, which keeps the boundary in place even when configuration reaches the collector through another path.

The network side follows the same deliberately boring shape: fixed HTTPS destinations, no redirects, bounded requests, and fixed-word failures. An unexpected fetch exception becomes a closed error class instead of carrying a URL, response body, header, or library message across the collector boundary. The useful result is still there: the source failed, the credential expired, the response was too large, or the platform rejected the request. The dangerous detail is not.

Refresh is off by default. Some platforms rotate credentials, and asking for a replacement is not useful unless the new pair can be stored successfully. The collector only adopts a replacement after a storage sink confirms it kept the value. Without that sink, the owner gets a content-free health signal and handles rotation outside the collector.

The platforms are not identical (Instagram and Threads use long-lived user tokens, for one), but the boundary stays consistent even when the vendor mechanics do not.

## The audit changed the rule

Adding another validation branch was the wrong fix. The choice itself had to go.

Allowing configuration to select an environment variable created a credential-confusion class. The response was to audit every source, refuse noncanonical names, and keep the runtime check independent of the configuration loader.

I also kept error output intentionally dull. Fixed words are not pleasant diagnostics, but collector failures can travel through status files, CI logs, and alerts. A closed vocabulary gives those systems enough information to react without turning an exception chain into an accidental disclosure path.

## The wrapper was not a second engine

The CI wrapper had its own YAML parsing logic so it could decide which credentials to forward. That parser kept drifting from the engine's loader, which meant the wrapper and the application could disagree about the same configuration.

The fix was to stop making the wrapper understand the configuration format. It now forwards only a fixed allowlist of canonical credential names for the source kinds in use. The engine remains responsible for parsing and validation. The wrapper has one smaller job, and a config-provided name never decides what crosses the process boundary.

There is a broader rule in there for CI glue: if a wrapper needs to reimplement the application's loader, the wrapper is becoming a second application with worse tests.

## A short note on alerts

The same boundary applies to health alerts. They carry the source and a closed status, not a credential, response body, destination, or exception message. Other owner alerts use content-free failure classes too, with redirects disabled and channel failures isolated from the visitor path.

## Lessons

- Credential names are part of the security boundary, not customization.
- Validate the fixed name at load time and again before touching the environment.
- Keep destinations fixed, refuse redirects, and collapse unexpected failures into closed words.
- Never rotate a credential unless the replacement has somewhere trustworthy to go.
- CI wrappers should forward a fixed allowlist, not grow a second parser for application configuration.
