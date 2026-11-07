---
title: "{{ replace .File.ContentBaseName "-" " " | title }}"
date: {{ .Date }}
# Stays true until the post is ready. Drafts are never built or published.
draft: true
# One or two plain sentences. Used for the page description, the social card
# and the announcement text, so write it as the pitch for the post.
description: ""
slug: "{{ .File.ContentBaseName }}"
categories: []
tags: []
# Announce on social networks after publish. Defaults to false here so a new
# post never announces by accident. Set it to true when the post is ready.
syndicate: false
# Written back by the syndication step. Leave it out when writing a post.
# syndicated:
#   mastodon: "https://..."
# Reminder for the author and the reviewer; the build does not read it. Set it
# to true when the post has affiliate links, and keep the disclosure line (see
# the comment below) in the body.
affiliate: false
---

Write the opening paragraph here. Keep it short: it can become the summary.

<!--more-->

<!--
  Images: put each file next to this index.md (WebP preferred, JPEG or PNG
  accepted) and reference it like this. The alt text is required, must describe
  what the image shows, and must not start with "TODO alt text" on a published
  post. A build fails on both.

  ![Describe what the image shows and why it matters here](diagram.webp)

  Alt text prompts: What would a listener need to know if they could not see it?
  Is it a screenshot (say which window and what it proves)? Is it decoration
  (then leave it out)?
-->

<!--
  Affiliate links: if you add one, set "affiliate: true" above and keep this
  line once in the body, near the first link or at the end:

  As an Amazon Associate I earn from qualifying purchases.

  Mark the link text plainly. Do not hide that it is an affiliate link.
-->

<!--
  House wording: write "cryptocurrency" for coins and "cryptography" for the
  math. Never put a real callsign, grid square, employer, hostname or serial
  number in a post.
-->
