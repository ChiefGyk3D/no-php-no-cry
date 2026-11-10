---
title: "Shipping Reach Around while moving machines"
date: 2026-11-10T20:00:00-05:00
description: "I shipped several parts of Reach Around while moving to a new work machine, with parallel AI agents implementing, verifying and reviewing the work."
slug: "shipping-reach-around-while-moving-machines"
categories: ["Journal"]
tags: ["ai", "analytics", "threat-modeling", "workflow"]
syndicate: false
---

Reach Around moved several pieces in one day while I was also moving to a new work machine. The project gained a better media kit, more honest analytics, a reviewed threat model, several small interface changes and a design direction that connects it to this blog. Running many AI agents in parallel made that possible, but only because each change still had an implementation, an independent verification and a controlled path into the repository.

<!--more-->

## Shipping the visible work

Reach Around is a self-hosted link page, media kit and analytics project. The engagement section of the media kit landed, along with a display policy that keeps private analytics figures out of the public kit.

The analytics report also gained gap detection. If a number was built across a collection gap, the report now labels that condition instead of quietly presenting the number as if collection had been continuous. Hiding the gap would produce a cleaner report, but it would also imply confidence the data does not support.

A cutover marker went into both the report and the Grafana export. That gives the data an explicit boundary instead of requiring somebody to remember when collection changed.

Several smaller changes shipped around the same work. StreamElements and Pixelfed gained icons on the link page, and the store moved to the top of the support page. None of those changes is large alone, but they remove small bits of friction from the pages people actually use.

## Choosing a direction before polishing it

The design study produced three layout directions for each page at phone, tablet and desktop widths. The selected direction aligns Reach Around with this blog's branding without changing the role of the project.

The link page remains the landing page from social profiles. It is not being pushed aside for a larger site front door just because the project now has more pages. The label that previously said WordPress now says Blog, which describes the destination instead of exposing an implementation detail.

The Contact page also gained the owner's public postal mailbox. That addition caused CI to fail because the page no longer fit inside a 1920x930 viewport. The rule for these short pages is that they fit without scrolling, so I fixed the layout instead of loosening the check.

That failure was useful. The check did not object to the content or tell me the page was generally bad. It caught one concrete regression at the viewport the project promises to support.

## Reviewing the model, not admiring it

A Threat Dragon model for Reach Around went up for review with four diagrams in STRIDE form. It uses the same renderer approach as this site's threat model.

The reviews found real gaps. Some flows were missing, some threats lacked source IDs, and one control was still marked open even though it had already shipped and been tested. I corrected the model rather than treating a rendered set of diagrams as evidence that the work was finished.

Security work is tracked. The useful part of the model review was that it compared the diagrams and records against the project as it exists. A clean render can still describe the wrong system.

## Giving agents separate jobs

Codex performed the specified implementation, then a second agent verified each result. Verification included reverting the change far enough to prove that the new tests failed without it. The verifying agent also opened the pull request.

That separation kept implementation and acceptance from becoming the same opinion repeated twice. A passing test is stronger when somebody has shown that it catches the missing behavior instead of merely passing alongside the change.

Merges still went through one at a time. A watcher pinned each commit so the result being observed was the result that had actually been reviewed. Parallel work was useful before the merge queue, but parallel merges would have made the evidence harder to trust.

An automated review flagged a database query that divided a bound number. The query was fragile rather than exploitable, and I fixed it by calculating the day window in code before passing the value to the query. The review was wrong about the severity and right that the construction should change.

The same standard applied to CI. A known egress flake was rerun, not waived. And when a board audit found cards missing required fields, agents repaired the drift that day. Automation did not remove judgment. It made more places available for judgment, provided each agent had a narrow job and a result another agent could challenge.

## Moving the parts outside git

At the same time, I was moving to a new work machine. The repository was the easy part. The setup outside git included merge scripts, board configuration and private notes.

I copied that material to a flash drive with checksums and a restore script. Nothing secret was committed to make the move more convenient.

That boundary matters because “put everything in git” is not a backup plan for material that does not belong in a repository. The checksums provide a way to verify the copy, and the restore script records how the pieces are supposed to return without turning private machine setup into published project history.

## What I would change

I would audit the board fields before starting the shipping run, not after several pull requests were already moving. The agents fixed the drift quickly, but catching it earlier would have removed avoidable bookkeeping from an already crowded day.
