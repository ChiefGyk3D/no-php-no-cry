# Threat model

This directory contains the project's OWASP Threat Dragon model and a plain-language risk register.

- [`no-php-no-cry.threat-model.json`](no-php-no-cry.threat-model.json) is the source model.
- [`RISKS.md`](RISKS.md) is the readable register, grouped by diagram and trust boundary.

## Coverage

| Diagram | Coverage |
| --- | --- |
| 1 Publishing path | Authoring, pull requests, review, CI, deployment, and planned syndication. |
| 2 Reader path | Visitors, edge delivery, static assets, response policies, sharing, external links, planned analytics, and released reports. |
| 3 Data stores and secrets | Secret storage, workload identity, deployment credentials, repository policy, and planned analytics credentials. |

The model considers public visitors, contributors, compromised dependencies, and readers of released
reports. The owner is a trusted operator, but accidental owner actions are in scope. Dashed boxes labeled
TB1 through TB12 are trust boundaries.

## Status policy

The model uses four statuses:

- `Open`: more work or verification is needed.
- `Mitigated`: a visible repository control exists, and the mitigation cites its path.
- `Accepted`: the owner has chosen to carry the remaining risk.
- `NotApplicable`: the modeled feature is absent, and the mitigation explains why the threat does not apply.

A provider-side control stays `Open` until it receives a dated review. A planned control stays `Open` until
it is implemented and tested.

## Open and update the model

The file targets Threat Dragon 2.6.2. Open it with the Threat Dragon desktop application, or with a locally
configured Threat Dragon web application that supports local files. Threat Dragon validates the model when
it opens and may reformat the JSON when it saves.

When architecture, data flow, credentials, third parties, or trust boundaries change:

1. Update the diagram and affected threats in Threat Dragon.
2. Keep threat titles in verb plus object form, without a trailing period.
3. Use only the status vocabulary above. Move a threat to `Mitigated` only when its mitigation cites a
   repository control.
4. Regenerate the risk register:

   ```sh
   python3 -I scripts/render-threat-summary.py \
       docs/threat-model/no-php-no-cry.threat-model.json \
       docs/threat-model/RISKS.md
   ```

5. Run the checks:

   ```sh
   python3 -I scripts/check-threat-model.py
   scripts/test-check-threat-model.sh
   scripts/test-render-threat-summary.sh
   ```

The checker validates structure, identifiers, status and severity values, STRIDE categories, cited paths,
open-threat flags, trust boundaries, and published counts. It cannot prove that a control works. That proof
belongs in the control's own test or review.

Review the model when a new third-party script or embed appears, a planned feature is deployed, a credential
is created, or hosting changes.
