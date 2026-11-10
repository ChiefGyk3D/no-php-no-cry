# Risk register

This register summarizes the Threat Dragon model in
[`no-php-no-cry.threat-model.json`](no-php-no-cry.threat-model.json). It covers the publishing path,
the reader path, and credential storage. The model contains the full descriptions, mitigations, severity,
and STRIDE categories.

<!-- threat-summary:start -->
| Diagram | Total | Mitigated | Open | Accepted | NotApplicable |
| --- | ---: | ---: | ---: | ---: | ---: |
| All diagrams | 63 | 33 | 26 | 3 | 1 |
| 1 Publishing path | 25 | 15 | 10 | 0 | 0 |
| 2 Reader path | 25 | 11 | 10 | 3 | 1 |
| 3 Data stores and secrets | 13 | 7 | 6 | 0 | 0 |
<!-- threat-summary:end -->

The summary is generated from the JSON model by `scripts/render-threat-summary.py`. The status vocabulary
is:

- `Open`: more work or verification is needed.
- `Mitigated`: a repository control exists and the model cites it.
- `Accepted`: the owner has chosen to carry the remaining risk.
- `NotApplicable`: the modeled feature is not present, and the model explains why the threat does not apply.

## Scope and assumptions

The model considers attacks by public visitors, contributors, compromised dependencies, and readers of
released reports. The owner is a trusted operator. Accidental owner actions remain in scope.

Controls that can be verified only in a provider account remain `Open` until a dated review is recorded.
Planned features also remain `Open` until their controls are implemented and tested.

## Main controls

- Content security policy and build checks restrict scripts and detect unsafe output.
- CI separates untrusted changes from deployment credentials and verifies the exact revision being deployed.
- Dependencies, actions, shared workflows, the site generator, and fonts are pinned or committed.
- Share links validate visitor input and use a fixed secure URL shape.
- Redirect generation rejects external destinations.
- Secret scanning and content checks reduce accidental publication of private data.
- Planned analytics code has privacy checks, request limits, and reporting safeguards under development.

## Remaining decisions

- Confirm provider-side sign-in, domain, credential, and workload identity settings during a dated review.
- Decide whether the single-owner branch policy should require an approving review.
- Decide whether to require signed commits.
- Complete and verify the controls for planned syndication and analytics features before deployment.

## Threats by diagram and trust boundary

Entries below are generated from the model. Positioned elements are assigned to the smallest trust boundary
that contains their center. Data flows without a position appear under `Boundary crossings`.

<!-- threat-register:start -->
## 1 Publishing path

### TB1 Owner machine and accounts (trusted operator)

- Open: Protect the owner account and session
- Open: Prevent the editor from altering content
- Mitigated: Prevent accidental publication of private details

### TB2 GitHub (public repository, untrusted input)

- Mitigated: Run checks on web edits
- Mitigated: Keep pull requests away from deployment credentials
- Mitigated: Preserve change attribution
- Mitigated: Protect reviewed history
- Mitigated: Preserve repository access and content
- Open: Stop build steps from leaking source or credentials
- Mitigated: Limit pull request use of CI
- Open: Prevent syndication of attacker-chosen text
- Open: Prevent duplicate or runaway announcements
- Open: Protect syndication credentials
- Open: Separate production build and deployment jobs

### TB3 Deploy job (the only credential holder)

- Mitigated: Deploy only commits that passed CI
- Open: Limit deployment credential permissions
- Open: Require review of production commits

### TB4 Cloudflare (third-party operated)

- Mitigated: Publish only the reviewed build

### Boundary crossings

- Mitigated: Protect content in transit to the repository
- Mitigated: Reject hostile pull request content
- Mitigated: Limit pull request review floods
- Mitigated: Prevent upstream components from altering the site
- Mitigated: Protect artifacts between build and deployment
- Open: Reject active content from production artifacts

### Outside named boundaries

- Mitigated: Verify the contributor's identity

## 2 Reader path

### TB6 Visitor browser (untrusted input)

- Open: Help visitors recognize look-alike sites
- Mitigated: Keep instance input from redirecting share links
- Mitigated: Limit details shared with external targets

### TB7 Cloudflare edge and Pages (third-party operated)

- Mitigated: Block script injection and policy bypass
- Open: Protect the site domain
- Mitigated: Keep redirects on this site
- Mitigated: Keep the site available during traffic spikes
- Open: Limit request floods against analytics
- Mitigated: Keep visitor details out of logs and storage
- Accepted: Limit third-party scripts on every page
- Open: Prevent re-identification from location counts
- Open: Prevent linking visitor codes across days
- Accepted: Treat client-provided counts as estimates
- Accepted: Limit scripts allowed by the beacon path
- Open: Refresh stale security headers at the edge

### TB8 Other people's sites

- Mitigated: Warn readers about external link tracking
- NotApplicable: Keep third-party embeds off the site

### TB9 Release of reports (owner to readers)

- Open: Prevent reports from revealing suppressed values
- Open: Limit destination growth in click reports
- Open: Label report periods and sources

### Boundary crossings

- Mitigated: Protect page requests in transit
- Mitigated: Prevent altered pages from entering the cache
- Open: Keep feed identifiers stable
- Mitigated: Make external link destinations clear
- Mitigated: Keep static routes away from the function

## 3 Data stores and secrets

### TB10 Doppler (secret store)

- Open: Protect the secret store account
- Mitigated: Limit credentials available to later steps
- Mitigated: Restrict the workload identity
- Open: Protect the analytics hashing secret
- Open: Restrict the production workload identity

### TB11 GitHub Actions (build and deploy)

- Mitigated: Keep deployment credentials out of repository settings
- Mitigated: Keep credentials out of logs and process arguments
- Mitigated: Keep secrets and personal data out of commits
- Open: Remove maintenance access after use

### TB12 Cloudflare account

- Open: Limit deployment credential permissions
- Open: Protect the hosting account

### Boundary crossings

- Mitigated: Protect credentials between the secret store and runner

### Outside named boundaries

- Mitigated: Keep secrets out of forked pull requests

<!-- threat-register:end -->

## Review log

| Date | Change |
| --- | --- |
| 2026-11-09 | Created the first model and recorded that provider-side settings had not been reviewed. |
| 2026-11-09 | Updated the model after repository credential fallbacks were removed. |
| 2026-11-09 | Added the accepted residual risk for the analytics beacon path. |
| 2026-11-10 | Added five open risks for the production publishing path. |
| 2026-11-10 | Standardized titles, status labels, descriptions, grouping, and generated counts for issue 353. |
