# Contributing

The project is open source and a teaching project: the site, the build, the
checks and the tooling are here to read and reuse. A post, a bug fix or a
clearer doc are all welcome. The authoritative text is
[CONTRIBUTING.md](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/CONTRIBUTING.md)
and the
[Code of Conduct](https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/CODE_OF_CONDUCT.md);
this page is the short path.

## Before you start

- Every change starts from an issue. Open one, or comment on an existing one.
  The pull request links it with `Refs #N` or `Closes #N`.
- Proposing a post? Use the "Post proposal" issue template and wait for a reply
  before you write a long one. See [Writing a post](Writing-a-post.md).

## Make a change

1. Fork the repository and branch from `main`.
2. Make the smallest change that does the job. Add or update a test when you
   change behavior.
3. Run the checks. `scripts/gate.sh --fast` runs only what your changed files
   touch; `scripts/gate.sh` runs everything CI runs. See
   [Getting started](Getting-started.md).
4. Open a pull request with the template filled in. CI runs the build, the checks
   and the security scans; the single required check is `CI green`.

## Rules that never bend

- No secrets, tokens or credentials. No `.env` files.
- No private data: a real callsign, grid square, employer, hostname, serial
  number or asset tag. Use placeholders.
- No third-party scripts, styles, fonts, embeds or analytics in the pages. The
  Content Security Policy blocks them and CI checks for them.
- The house wording rule: never the short form of cryptocurrency.
- American English, and no em dashes.
- Raw WordPress exports and unscrubbed drafts are never committed.
- Never weaken, skip or narrow a check to get green. If a check is wrong, say so
  in the issue and fix the check in its own change.

## Adding or changing a check

A check ships with its test, including a case that must fail. Wire both into
`.github/workflows/ci.yml` and into `scripts/gate.sh` in the same pull request.
Read [Build checks and budgets](Build-checks-and-budgets.md) first.

## Editing this wiki

The wiki is Markdown under `docs/wiki/` and changes in pull requests like any
other file. `python3 -I scripts/check-wiki.py` fails when a page links to a file
that does not exist, names a repository path that does not exist, uses an em dash
or a home-folder path, or when a required page is missing; its test is
`scripts/test-check-wiki.sh`. `scripts/publish-wiki.sh <wiki-clone>` mirrors
the pages into a clone of the GitHub wiki and rewrites `Page.md` links to full
wiki addresses (tested by `scripts/test-publish-wiki.sh`). Conventions:

- Link to another wiki page with its file name, for example
  `[Getting started](Getting-started.md)`.
- Link to a repository file with a full address of the form
  `https://github.com/ChiefGyk3D/no-php-no-cry/blob/main/<path>`. The check
  resolves it against the working tree, and the link works the same once the
  pages are copied to the GitHub wiki.
- Put commands and repository paths in backticks or a fenced block, so the check
  reads them. Only paths that start with a known top-level folder are judged.
- Describe what is on `main`. For a feature in an open pull request, write a
  clearly marked "lands with PR #N" note and remove it when the pull request
  merges.

## Reporting a security problem

Do not open a public issue for a vulnerability. Use the repository's private
vulnerability reporting (the Security tab, "Report a vulnerability") if it is
enabled. If it is not, open an issue that says only that you have a security
report and ask for a private way to send it, with no details.
