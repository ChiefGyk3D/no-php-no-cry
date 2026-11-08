# Getting started

From a fresh machine to a running preview and a passing set of checks.

## What you need

| Tool | Needed for |
| --- | --- |
| The Hugo release named in `.hugo-version` (standard edition, not extended) | Everything. `scripts/check-hugo-version.sh` refuses any other release or edition. |
| `git` and a POSIX shell | Cloning and the scripts. |
| Python 3 | The Python checks (`scripts/check-budget.py`, `scripts/check-wiki.py` and others, run as `python3 -I`). |
| Chrome or Chromium | Only `scripts/browser-gate.py` and its test. Set `CHROME` to pick a browser. |
| `shellcheck` and `shfmt` | Only the shell lint steps of `scripts/gate.sh`. |
| Node 20 or newer | Only `scripts/test-analytics.sh`. |

## 1. Install the pinned Hugo

CI installs the same release and verifies its sha256 before using it. Do the
same. This installs under your home folder and needs no root:

```sh
git clone https://github.com/ChiefGyk3D/no-php-no-cry.git
cd no-php-no-cry
V="$(tr -d '[:space:]' < .hugo-version)"
T="hugo_${V}_linux-amd64.tar.gz"
mkdir -p "$HOME/hugo-$V"
(
  cd "$HOME/hugo-$V"
  curl -fsSLO "https://github.com/gohugoio/hugo/releases/download/v${V}/${T}"
  curl -fsSLO "https://github.com/gohugoio/hugo/releases/download/v${V}/hugo_${V}_checksums.txt"
  grep " ${T}\$" "hugo_${V}_checksums.txt" | sha256sum -c -
  tar -xzf "$T" hugo
)
export PATH="$HOME/hugo-$V:$PATH"
scripts/check-hugo-version.sh "$V"
```

The last line prints the Hugo version and exits 0 when the release is the
pinned standard edition. Use the matching archive for another platform from the
same release page.

## 2. Preview

```sh
hugo server --buildDrafts
```

The address is printed in the terminal. Drafts are shown in the preview only;
without `--buildDrafts` the server shows what the real site will show.

## 3. Build

```sh
hugo --minify --gc
```

The site is written to `public/` (ignored by git). A second build with the
staging switch shows the other environment: every page gets a noindex tag and
`robots.txt` disallows everything.

```sh
HUGO_PARAMS_ENVIRONMENT=staging hugo --minify --gc --destination "$HOME/public-staging"
EXPECT_ENV=staging scripts/check-output.sh "$HOME/public-staging"
```

## 4. Run the checks

Run these against the build in `public/`:

```sh
EXPECT_ENV=production scripts/check-output.sh public
scripts/check-site-artifact.sh public
python3 -I scripts/check-budget.py public
scripts/check-wording.sh
scripts/check-license.sh
python3 -I scripts/check-wiki.py
```

Each prints `ok` and exits 0, or prints one `[rule] page detail` line per
finding and exits 1. [Build checks and budgets](Build-checks-and-budgets.md)
says what each one fails on.

## 5. The local gate

```sh
scripts/gate.sh --plan      # list the steps, run nothing
scripts/gate.sh --fast      # only the steps your changed files touch
scripts/gate.sh             # everything CI runs, plus the shell lint
```

Every step prints its name and exit code and a failure does not stop the run;
the exit code is non-zero if any step failed. A missing tool is reported by step
(exit 2). `GATE_TOOLS` adds directories to `PATH` and `CHROME` names the browser.
Capture the exit code instead of piping the gate into another command:

```sh
scripts/gate.sh > "$HOME/gate.log" 2>&1; echo "gate exit=$?"
```

CI does not call this script. It runs each step itself, and the shell lint comes
from a shared workflow, so a new CI check must also be added to
`scripts/gate.sh`. See [Contributing](Contributing.md).

## 6. Make your first change

```sh
hugo new content posts/my-first-post
```

Then follow [Writing a post](Writing-a-post.md).

## Troubleshooting

- `scripts/check-hugo-version.sh` fails: you have the extended edition or another
  release. Install the one in `.hugo-version`.
- The build fails with "has no alt text": every image needs real alt text, see
  [Images and alt text](Images-and-alt-text.md).
- The browser gate fails on a loaded machine: rerun that one step with
  `scripts/gate.sh --only browser-gate`; the thresholds keep headroom but are
  measured in a real browser.
