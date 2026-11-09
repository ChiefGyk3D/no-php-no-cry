---
title: "I Rebuilt My Site Without PHP"
date: 2026-11-09
draft: true
slug: "new-site-no-php"
description: "A static Hugo site with no PHP, built to be fast, locked down and open to read, now on a staging address."
categories: ["Open Source"]
tags: ["hugo", "security", "accessibility", "performance", "open-source"]
syndicate: false
affiliate: false
---

No PHP No Cry is my static site and work journal, built with Hugo, with no PHP and no database. It is running at [test-blog.chiefgyk3d.com](https://test-blog.chiefgyk3d.com) right now, but that is staging. My main domain still serves the WordPress site, and it will stay that way until both this project and Reach Around are done.

<!--more-->

## Why I built it

I built this because of PHP2Shell and my frustration with Matt Mullenweg and his toxicity. I covered the WordPress situation in [Who can't drive an Automattic? The fall of Wordpress and Matt Mullenweg](https://www.youtube.com/watch?v=FnoazrD6-Rg), [The Internet at Risk: WordPress Drama and Matt Mullenweg's Petty Fight Against WP Engine](https://www.youtube.com/watch?v=RqRZoQqKPgs), and [Automattic and Matt Mullenweg "Are Doing Open Source Dirty"](https://www.youtube.com/watch?v=QLEzJ3cXiWI).

I wanted something fast, light, capable, better designed and more secure, with the code open so other creators could use it and learn from it. The templates are written from scratch. This is not a Hugo theme wrapped around somebody else's decisions.

The site deploys to Cloudflare Pages. When I eventually cut over, the old WordPress addresses will remain as 301 redirects. I also built a converter that turns a WordPress export into Hugo page bundles and scrubs private data. There is no cutover date.

## What is here

The site has posts and a work journal, with each entry stored as a page bundle containing `index.md` and its images. It supports tags, categories, optional headline images, archive notices on older posts and links to newer material.

Search starts as a complete A to Z index, so it still works without JavaScript. A small pinned script adds filtering when JavaScript is available. The site also publishes RSS at `/feed/index.xml`, redirects the old WordPress feed addresses there, provides feeds for the home, posts and journal sections, and includes a sitemap, environment-aware `robots.txt` and `/llms.txt`.

Each post and journal entry has a share row made from plain links, with no embedded widgets or tracking parameters. It covers Threads, Bluesky, Twitter, Reddit, LinkedIn, Facebook, Hacker News, Email and Pinterest when the post has a headline image. There is also a Copy link button. Mastodon and Lemmy ask for the visitor's instance in a small box, check it in the browser and send it nowhere through the site. It stays in that browser only if the visitor selects Remember. This replaces the old Discuss on Mastodon links, which did not work.

## Three scripts

The site ships exactly three scripts: `/copy.js` on Support, `/search.js` on Search and `/share.js` on posts and journal entries. Each is pinned with a sha256 hash file, limited to the pages where it belongs and held under a 1 KB gzip budget.

The build fails on a fourth script, a script on the wrong page, inline scripts or styles, event handlers, third-party assets and plain HTTP references. The site's own code sets no cookies and embeds nothing from other sites.

Cloudflare Web Analytics is enabled at the host, and that is the one third-party script I chose to allow. The Privacy page says so. Cloudflare currently injects it in a form that the staging Content Security Policy blocks, which is also why one of the Lighthouse scores below is not 100.

## Headers, CI and design

The Content Security Policy begins with `default-src 'none'`. Images, styles, fonts, the manifest and scripts are restricted to the site itself. Connections are limited to the site, while base URIs, form actions and framing are disabled. Trusted Types are required for scripts.

Staging also sends Strict Transport Security for one year with subdomains, `nosniff`, a strict-origin-when-cross-origin referrer policy, same-origin opener isolation and a Permissions Policy that disables the accelerometer, camera, geolocation, gyroscope, microphone, payment and USB features.

CI uses reusable workflows pinned by commit. A local job named CI green is the single required check, and deployment runs from `main` only after that check passes on the same commit. The checks come paired with tests that prove they fail when they should.

The design is dark only, using amber on near-black, with Jost and Orbitron stored in the repository instead of requested from a third party. The target is WCAG 2.2 AA. There is a skip link, proper landmarks, native controls, visible focus, reduced-motion and forced-colors rules, and controls are at least 44 by 44 CSS pixels.

Images cannot ship without alt text. Remote images, unsupported formats, EXIF data and GPS data also fail the build. A real-browser gate uses headless Chrome and a vendored, hash-pinned copy of axe-core to check axe violations, horizontal overflow at several widths including 200 percent zoom and 320 CSS pixels, small targets, bad focus order, console errors and CSP violations.

That still is not human testing. Axe cannot decide every contrast case, and no script replaces somebody using a screen reader.

## Measured performance

I measured the site on 2026-11-09 with Lighthouse 13.6.0, Chromium 156.0.8078.47 headless and Hugo 0.168.0. Each result is the median of three runs per page and strategy. These are lab numbers, not field data, and they move a few points between runs.

The local production build scored 100/100/100/100 for Performance, Accessibility, Best Practices and SEO on Home, Search and About for mobile and desktop. The migrated Mastodon relays guide, which has a hero image, scored 99/100/100/100 on mobile with a 2.0 s Largest Contentful Paint, and 100/100/100/100 on desktop. Cumulative Layout Shift was 0 and Total Blocking Time was 0 ms on every page.

Over the real network and real Cloudflare headers, public staging scored 99/100/92/69 on mobile and 100/100/92/69 on desktop across Home, Post, Search and About. One About desktop run scored 99. Mobile Largest Contentful Paint was 1.6 s on Home and 1.8 s on the post. Desktop was 0.5 s on all four. Cumulative Layout Shift was 0 and Total Blocking Time was 0 ms.

Best Practices is 92 because Cloudflare adds a version suffix to its Web Analytics beacon path, while the CSP names the path without that suffix. The browser blocks it and logs a console error. This is a host setting, and the CSP has not been changed for it.

SEO is 69 because staging is deliberately `noindex`, and its `robots.txt` disallows everything. The local production build scores SEO 100. The size budget also passed on November 9: `budget: ok (39 pages, 132 files)`.

## Threat model

The repository carries an OWASP Threat Dragon model with diagrams for the publishing path, reader path, and data stores and secrets, plus a plain-language risk summary. As of 2026-11-09, it contains 57 threats: 33 Mitigated, 21 Open, 2 Accepted and 1 N/A.

A threat counts as Mitigated only when its control exists in the repository and the model names that control by path. The build fails if a named path does not exist. Controls in a provider account, including sign-in strength, token permissions and DNS, stay Open until somebody reads them and records the date. The check proves the model is well formed and its named controls exist. It cannot prove those controls work.

The largest open items are owner account or machine takeover, Cloudflare token scopes, domain or account takeover at the provider, and the planned analytics and syndication pieces that are not built. Build-step network egress policy runs in audit mode, not block.

The pull request template asks whether a change affects the architecture, a data flow, a secret or a third party. If it does, the model is updated in the same pull request. A review is also due when a third-party script or embed, the analytics function, syndication job, a new token or secret, or a hosting change lands.

## Reach Around

[Reach Around](https://github.com/ChiefGyk3D/Reach-Around) is my Apache-2.0 project for putting a creator's link page, media kit and numbers across platforms in one self-hosted place using their own API keys. It is meant to replace Beacons.ai for creators, close to 1:1 and then go further, but that is the goal, not the finished state. It is alpha software. Expect breaking changes, no stable configuration format and no upgrade path between 0.x releases. The latest published release on GitHub is v0.2.2, published 2026-11-06 and checked 2026-11-09; the 0.3.0 release candidates in the changelog are not releases yet.

The alpha code includes a configuration loader, static link page builder, a non-root container image for Docker or Podman, click tracking through a small write-only Cloudflare Worker, a media kit with an email gate, follower counts pulled from a few platforms into a numbers file and an owner-run report command. Platform API research covers 16 platforms. Link-page clicks use the `ping` attribute on anchors, so the page needs no script for them.

The blog's page-view counter is built and tested locally, but it is not deployed, and its drafted privacy text is not live. Posts carry a `syndicate` flag in their front matter for the syndication job to read, and the job itself is planned.

## What is next

The cutover to the main domain waits for this site and Reach Around to be done, and it has no date. The page-view counter, a Cloudflare Pages Function with a D1 database, is built and tested but not deployed, and its privacy text will go live with it. The syndication job is planned. The authoring helper is phase 1 of a local editor, with a full check command, editor settings and a publish step planned. The threat model's open items around token scopes and domain checks still need to be read from the provider side and recorded with a date.

## Read the project

The [public repository](https://github.com/ChiefGyk3D/no-php-no-cry) contains the site, checks, migration tooling, threat model and documentation. Code is Apache-2.0, written content and documentation are CC BY 4.0, and the mascot, wordmark and logos are not licensed for reuse. The [wiki](https://github.com/ChiefGyk3D/no-php-no-cry/wiki) has 15 pages, including a Learn from this site reading order through the repository.
