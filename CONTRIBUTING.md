# Contributing

This is an open source project and a teaching project: the site, the build, the
checks and the tooling are all here to read and reuse. Contributions are
welcome: a post, a bug fix, a clearer doc.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- Every change starts from an issue. Open one first, or comment on an existing
  one. A pull request links its issue (`Refs #N` or `Closes #N`).
- Read the [README](README.md) for how to build and check the site.
- To propose or write a post, follow [docs/writing-a-post.md](docs/writing-a-post.md).

## Making a change

1. Fork the repository and branch from `main`.
2. Make the smallest change that does the job. Add or update a test when you
   change behavior.
3. Run the checks with `scripts/gate.sh` (the whole gate) or `scripts/gate.sh --fast`
   (only what your changed files touch); the README lists the individual checks. `shellcheck -S warning` and
   `shfmt -d -i 4 -ci` must pass on `scripts/*.sh`.
4. Open a pull request with the template filled in.

CI runs the build, the output checks and the security scans. The single required
check is `CI green`. Do not weaken, skip or narrow a check to get it green. If a
check is wrong, say so in the issue and fix the check in its own change.

CI uses the shared workflows from
[git-your-ship-together](https://github.com/ChiefGyk3D/git-your-ship-together)
for shell checks and security scans. The Hugo build and the site checks are local
to this repository.

### The local gate

`scripts/gate.sh` runs the steps of the CI `build` job plus `shfmt -d -i 4 -ci`
and `shellcheck -S warning` on `scripts/*.sh`. Every step prints its name and exit
code, a failure does not stop the run, and the exit code is non-zero if any step
failed. Needs hugo, shellcheck, shfmt, python3 and Chrome or Chromium (`CHROME`);
`GATE_TOOLS` adds directories to `PATH`.

- `scripts/gate.sh --fast` runs only what the changed files touch (diff against
  `origin/main` plus untracked files): content and data, scripts, or CSS and layout.
- `scripts/gate.sh --plan` prints the steps without running them.
- `scripts/gate.sh --only browser-gate` reruns one step (the browser gate can flake
  on a loaded machine); a build it needs runs first.
- `--keep` keeps the temp directory with the per-step logs.

CI does not call the script. The `build` job runs each step natively, and the shell
lint comes from a shared workflow, so a swap would not cover the same steps. Keep
the two lists in step: a new CI check goes into `scripts/gate.sh` too.

## Rules that never bend

- No secrets, tokens or credentials. No `.env` files.
- No private data: a real callsign, grid square, employer, hostname, serial
  number or asset tag. Use placeholders. See the private data section of the
  writing guide.
- No third-party scripts, styles, fonts, embeds or analytics. The Content
  Security Policy blocks them and CI checks for them.
- The house wording rule: never the short form of cryptocurrency. Say
  "cryptocurrency" or name the coin. `scripts/check-wording.sh` enforces it.
- Raw WordPress exports and unscrubbed drafts are never committed.

## Reporting a security problem

Do not open a public issue for a vulnerability. Use the repository's private
vulnerability reporting (the Security tab, "Report a vulnerability") if it is
enabled. If it is not, open an issue that says only that you have a security
report and ask for a private way to send it, with no details.

## Commit messages

Short subject line in the imperative. Say why in the body when it is not obvious.
