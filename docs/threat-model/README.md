# Threat model

`no-php-no-cry.threat-model.json` is an OWASP Threat Dragon model of this project. It opens in the
Threat Dragon desktop app and the web app. The plain-language summary is in [RISKS.md](RISKS.md).
Issue 290 tracks this work.

## What it covers

| Diagram | Shows |
| --- | --- |
| 1 Publishing path | Owner authoring (local editor and the GitHub web editor), pull request and review, CI build, the credentialed deploy to Cloudflare Pages, and the planned syndication job. |
| 2 Reader path | A visitor, the Cloudflare edge and static assets, the response headers and CSP, links and share targets, the share panel and instance picker, the optional analytics Function and its database (planned, see [../analytics-from-reach-around.md](../analytics-from-reach-around.md)), and the readers of released reports. |
| 3 Data stores and secrets | Doppler, the OIDC identity, the GitHub secrets policy (secrets live in Doppler only), the Cloudflare token and the planned analytics hash secret. |

Actors: public visitor, reader of released reports, owner (trusted operator), contributor by pull
request, and the supply chain (actions, dependencies, Hugo, fonts). Dashed boxes are trust boundaries
(TB1 to TB12). The adversary is a public visitor or a reader of released reports. The owner is a trusted
operator; accidents are in scope.

Rule used for status: a threat is Mitigated only when a control is visible in this repository, and its
mitigation text names that control by path. Anything that lives in a provider account (sign-in strength,
token permissions, DNS settings) stays Open until someone reads it and records the date in RISKS.md.
Planned parts are marked "planned" and their threats are Open. Statuses in use: Open, Mitigated, Accepted
(the owner decided to carry the risk) and N/A (stored by the app as `NotApplicable`, with the reason in
the mitigation text).

## Open it

The file targets Threat Dragon 2.6.2 (the release read on 2026-11-09). The model's `version` field is
`2.6.2`, which is what that release writes into a new model (source: `td.vue/src/views/NewThreatModel.vue`
in OWASP/threat-dragon).

Desktop app (works on local files only):

1. Install from the releases page: https://github.com/OWASP/threat-dragon/releases/latest (Linux AppImage,
   snap, `.deb` and `.rpm`, macOS `.dmg`, Windows installer). Docs: `docs/install/desktop.md` in that
   repository.
2. On the Welcome page choose open, then pick this file.
3. Edit, then Save. A save writes the same file.

Web app:

1. Run it with local file access, as described in `docs/configure/local.md` of the Threat Dragon repository
   (a container or a local build; the page needs a configured server for the "Login to Local Session"
   button). The hosted demo does not read repository files.
2. Choose open on the Welcome page and pick this file, or use a GitHub session if you configured one.
3. Save to the same file or download the model.

Threat Dragon checks a model against its schema on load and warns, but still loads it. If it warns, run the
`ajv` command below.

## Keep it current

The pull request template asks whether a change alters the architecture, a data flow, a secret or a
third party. If yes:

1. Open the model and change the diagram, the threat or its status. Add a threat when a new data flow,
   store, secret, script, embed or outside service appears. Move a threat to Mitigated only when the
   control exists, and name it in the mitigation text by its path.
2. Save, then run `python3 -I scripts/check-threat-model.py`. It fails on a cited path that does not exist, a
   Mitigated threat that cites none, a missing field, a duplicate id and the other rules listed at the top
   of that script.
3. Update the counts and lists in [RISKS.md](RISKS.md).
4. Do not hand-edit positions. Threat Dragon may reformat the file when it saves; commit the diff it
   produces.

Review the model at least when any of these happen: a new third-party script or embed, the analytics
Function is deployed, the syndication job lands, a new token or secret is created, or the hosting changes.

## Validate and check

Structure (the schema Threat Dragon publishes, v2 models):

```sh
# fetch the schema from the 2.6.2 release (the version this file targets)
curl -fsSL -o threat-dragon-v2.schema.json \
    https://raw.githubusercontent.com/OWASP/threat-dragon/v2.6.2/td.vue/src/assets/schema/threat-dragon-v2.schema.json
npm install -g ajv-cli
npx ajv validate --allow-union-types -s threat-dragon-v2.schema.json --all-errors --verbose \
    -d docs/threat-model/no-php-no-cry.threat-model.json
```

The repository check (standard library only, runs in CI in the content checks job and in `scripts/gate.sh`):

```sh
python3 -I scripts/check-threat-model.py
scripts/test-check-threat-model.sh
```

The check cannot tell whether a named control works. It proves the model is well formed and that every
control it names exists. The control's own test or review is what shows it works.

## Export a report

Open the model, go to the model's details view and choose Report (lower right). Pick what to show. In the
desktop app use Print or the PDF Report button. In the web app use Print and save as PDF from the browser's
print dialog. (Docs: `docs/usage/getting-started.md`, section "Threat model report".)

## Which facts were verified

Read on 2026-11-09 from the OWASP/threat-dragon repository (main, latest release 2.6.2, published
2026-05-10):

| Fact | Source | State |
| --- | --- | --- |
| Model layout: `version`, `summary`, `detail` with `contributors`, `diagrams`, `diagramTop`, `reviewer`, `threatTop`; diagram and cell fields; threat required fields | `td.vue/src/assets/schema/threat-dragon-v2.schema.json`; sample `ThreatDragonModels/v2-threat-model.json` | Verified |
| A JSON Schema is published and `ajv` validates against it | `docs/development/schema.md` | Verified |
| Status values the app writes: `NotApplicable`, `Open`, `Mitigated`, `Accepted`, `Transferred`, `Avoided`, `Eliminated` | `td.vue/src/service/threats/status.js` | Verified |
| Severity values: TBD, Low, Medium, High, Critical | `docs/usage/threats.md`; the threat dialog source | Verified |
| STRIDE types and which element kinds accept them | `docs/usage/threat-categories.md`; `td.vue/src/service/threats/models/stride.json` | Verified |
| Trust boundary box shape `trust-boundary-box` and `tm.BoundaryBox` | `td.vue/src/service/x6/shapes/trust-boundary-box.js` | Verified |
| Opening a local file, saving, report and PDF export | `docs/usage/getting-started.md`, `docs/install/desktop.md` | Verified (documentation only) |
| This exact file opens in the 2.6.2 desktop and web apps without a warning | Not run | Unverified. The file passes the published schema (except that the app's own `null` for `strokeDasharray`, which the schema marks `nullable`, needs `ajv`'s union-type option) and follows the sample model's shapes. |
| Exact menu wording in the apps | Documentation text only | Unverified; follow what the app shows |
