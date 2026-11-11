---
title: "A threat model for a static site"
date: 2026-11-07T20:00:00-05:00
description: "A static Hugo site still has a publishing pipeline, credentials, third parties, and readers to protect. I put those risks into an OWASP Threat Dragon model and made CI keep the model tied to controls that actually exist."
slug: "a-threat-model-for-a-static-site"
categories: ["Journal"]
tags: ["security", "threat-modeling", "hugo"]
syndicate: false
---

The site is static. The system that publishes it is not. It has an authoring path, pull requests, GitHub Actions, a credentialed deployment to Cloudflare Pages, third-party scripts, share targets, and planned analytics. Calling the output static does not make those trust boundaries disappear.

<!--more-->

## Drawing the actual system

I built the model in OWASP Threat Dragon using STRIDE. It has three diagrams covering the publishing path, the reader path, and the data stores and secrets behind both.

The publishing diagram follows content from the editor through review, CI, and deployment. The reader diagram covers the visitor, Cloudflare, static assets, response headers, links, sharing, and the planned analytics path. The third diagram collects the places where identities, credentials, and other sensitive values enter the design.

That division was useful because it stopped “static site” from becoming shorthand for “nothing to model.” There may not be an application server rendering each page, but there is still code running before publication, automation with deployment authority, browser-side behavior, external services, and a supply chain.

The adversary in this model is a public visitor or somebody reading a released report. I treat the owner as trusted, while still including accidents by the owner or a contributor. That boundary matters because a model that quietly treats every operator mistake as out of scope is mostly documenting optimism.

## Counts with rules behind them

The model currently contains 63 threats. Of those, 33 are mitigated, 24 remain open, 3 are accepted, and 3 are not applicable.

Those statuses have a deliberately strict meaning. I only mark a threat mitigated when the repository contains a visible control and the mitigation text names it. Provider-side settings stay open until somebody checks them and records the result. Planned features stay open because a design document is not an implemented control.

The plain-language risk summary once lagged the model by one mitigated and one open threat. That is exactly the sort of drift a living threat model has to expose instead of hiding behind a polished document.

The checker verifies the JSON structure, required fields, identifiers, STRIDE types, statuses, severities, trust boundaries, and flow references. It also requires every mitigated threat to cite at least one repository path and fails when a cited path does not exist. The current model passes that check with all three diagrams and the current 63-threat count.

That still does not prove a control works. It proves the model is well formed and points at something real. The control needs its own test or review.

## The finding that paid for the work

The model found a real policy violation in the deployment path. Credentials are supposed to come from Doppler only, but the workflow still contained fallbacks to repository secrets.

Those fallbacks were removed. The deployment documentation now states that there is no fallback, and the workflow fails if Doppler does not provide the required values. A separate scanner rejects stored repository-secret access in GitHub Actions workflows.

The scanner runs in CI with the other content validation. It currently finds none.

I threat model small systems because this work found an implementation that contradicted the stated credential policy. I removed that contradiction and added a check so the same class of mistake cannot quietly return. A diagram sitting untouched in a documentation folder would not have done that.

## Keeping it alive

The pull request template asks whether a change affects architecture, data flow, secrets, or a third party. If it does, the model is supposed to change with the code.

CI checks the model during content validation, and the checker is also included in the repository validation. New scripts, embeds, data stores, credentials, hosting changes, and analytics work all create reasons to review it again.

The model will still need human judgment. CI can confirm that a cited control exists. It cannot decide whether the control is effective, whether the diagram matches reality, or whether an open risk has become acceptable.

## Lessons

- Static output does not mean a static threat surface.
- A threat is not mitigated because the fix is planned.
- A model tied to repository controls is harder to hand-wave.
- Documentation counts can drift even when the model is correct.
- CI can keep the model structurally honest, but review still has to determine whether the controls work.
