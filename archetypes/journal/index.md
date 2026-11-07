---
title: "{{ replace .File.ContentBaseName "-" " " | title }}"
date: {{ .Date }}
# Stays true until the entry is ready. Drafts are never built or published.
draft: true
description: ""
slug: "{{ .File.ContentBaseName }}"
categories: []
tags: []
# Journal entries are not announced unless you say so.
syndicate: false
---

Write the entry here. Journal entries are short work notes.

<!--more-->

<!--
  Images go next to this index.md and need real alt text:
  ![Describe what the image shows](photo.webp)
  Keep private data out: no real callsign, grid square, employer, hostname or
  serial number.
-->
