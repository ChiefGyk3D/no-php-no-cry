---
title: "A Contact Form on Cloudflare Pages With No Server Behind It"
date: 2026-11-19T21:30:00-05:00
draft: true
description: "I put a contact form on a static Hugo site on Cloudflare Pages with no server: a Pages Function, Turnstile, and a Worker that can only email one address. The bugs were more useful than the build."
slug: "contact-form-on-cloudflare-pages"
categories: ["Journal"]
tags: ["cloudflare", "cloudflare-pages", "hugo", "turnstile", "email", "ci"]
syndicate: false
---

The contact form for my LLC site is working on staging, and the bug that taught me the most was not in my code. Cloudflare rewrote my own email link into a page called Email Protection, and my content security policy blocked the script that was supposed to decode it.

<!--more-->

The site is static Hugo on Cloudflare Pages, deployed with wrangler direct upload. I did not want a server just to receive a form, so the form posts to a Pages Function. The function checks the Turnstile token, then calls a separate Worker through a service binding with a shared secret in a header. The Worker is the only thing that holds the send_email binding, and that binding is pinned to one destination address. It has no route, workers.dev is off, and preview URLs are off. If the Pages side is ever popped, it still cannot send mail to anyone but me.

Wrangler wanted Node 22 and the machine had 20, so I installed the official Node tarball and checked the SHA-256 first. I also read through wrangler before running it and pinned the version, because I do not run a tool I have not looked at.

Cloudflare Email Sending is a public beta on the Workers Paid plan, and the onboarding is dashboard only. The thing to know before you click: do not turn on Email Routing for this. Routing takes over the root MX, and my mail already lives on Microsoft 365 at the root. Email Sending adds its own records on a cf-bounce subdomain, plus DKIM and a DMARC record, and leaves the root MX and SPF alone. I checked that against live DNS before and after instead of trusting the wizard. My first mistake was onboarding the domain to Office 365 when I meant Cloudflare, which is the kind of mistake you only make once.

The first test message never arrived. The function said success and the Worker said success, so Cloudflare had accepted it, and the problem was on my 365 side. After I fixed that, the second one landed.

Two things I found only because I tested the failure path. When the mail send failed, the function returned a 502 with a friendly message and the visitor got Cloudflare's generic Bad Gateway page instead. I think Cloudflare swaps its own page in for 5xx responses, though I have not confirmed that in their docs. The fix was to stop returning a 5xx: a small dark HTML page with a 424 and my fallback address on it.

The other one is the email obfuscation setting. Cloudflare rewrites visible email addresses into links like /cdn-cgi/l/email-protection and relies on a script to decode them. My CSP does not allow that script, so clicking my contact address landed on Cloudflare's Email Protection page. I turned it off in the dashboard, because my API token cannot touch zone settings, which is how I want it, and the contact page now serves a plain mailto link.

The part that kept it honest was CI. Every merge waits on one gate, and Copilot review caught a real regression where a redesign dropped the contact form CSS entirely.
