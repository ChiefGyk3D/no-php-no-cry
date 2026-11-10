#!/usr/bin/env bash
# The local full gate: the same steps as the `ci` job (the shared parallel-ci workflow: one
# build, then the checks side by side) in .github/workflows/ci.yml, plus the
# shell lint the `shell` job runs (shfmt, shellcheck), in one command.
#
#   scripts/gate.sh                  every step
#   scripts/gate.sh --fast           only what the changed files touch
#   scripts/gate.sh --plan           print the steps, run nothing (combines with --fast/--only)
#   scripts/gate.sh --only NAME      run just that step (repeatable); a build it needs runs first
#   scripts/gate.sh --keep           keep the temp directory with the per-step logs
#   scripts/gate.sh --with-drift     also run the live Reach Around token drift check (network)
#
# Every step prints its name and exit code; a failure does not stop the run. The
# exit code is 0 only when every step passed, and the last line names the failed
# steps. Exit 2 is a usage error or a missing tool. Never pipe the gate into grep
# for its exit code: capture it (`scripts/gate.sh > log 2>&1; echo $?`).
#
# Tools: hugo, shellcheck and shfmt are looked up on PATH after the directories in
# GATE_TOOLS (colon separated; default: the dev directory and its lint/ folder when
# they exist). CHROME names the browser (default: google-chrome, then chromium).
# GATE_TMP or TMPDIR picks where the build output and logs go. GATE_BASE is the
# ref that --fast diffs against (default origin/main).
#
# CI does not call this script: the `ci` job runs each step natively, the shell
# lint is a shared git-your-ship-together workflow, and swapping either for this
# script would change what runs where. See CONTRIBUTING.md.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base="${GATE_BASE:-origin/main}"

# --- the step registry -------------------------------------------------------
# step <name> <needs> <command>. Commands run under `bash -ec` in the repo root
# with $T (the temp directory) exported. Order here is the order of execution.
names=()
declare -A cmds needs

step() {
    names+=("$1")
    needs["$1"]="$2"
    cmds["$1"]="$3"
}

step check-hugo-version "" 'scripts/check-hugo-version.sh "$(tr -d "[:space:]" < .hugo-version)"'
step build-production "" 'hugo --minify --gc --destination "$T/public"'
step check-output-production build-production 'EXPECT_ENV=production scripts/check-output.sh "$T/public"'
step check-site-artifact-production build-production 'scripts/check-site-artifact.sh "$T/public"'
step build-staging "" 'HUGO_PARAMS_ENVIRONMENT=staging hugo --minify --gc --destination "$T/public-staging"'
step check-output-staging build-staging 'EXPECT_ENV=staging scripts/check-output.sh "$T/public-staging"'
step check-site-artifact-staging build-staging 'scripts/check-site-artifact.sh "$T/public-staging"'
step test-check-output "" 'scripts/test-check-output.sh'
step test-head "" 'scripts/test-head.sh'
step test-featured-image "" 'scripts/test-featured-image.sh'
step test-social-products "" 'scripts/test-social-products.sh'
step test-share "" 'scripts/test-share.sh'
step test-borders "" 'scripts/test-borders.sh'
step test-resume "" 'scripts/test-resume.sh'
step test-layout "" 'scripts/test-layout.sh'
step test-check-site-artifact "" 'scripts/test-check-site-artifact.sh'
step test-deploy-sparse "" 'scripts/test-deploy-sparse.sh'
step test-deploy-doppler-vars "" 'scripts/test-deploy-doppler-vars.sh'
step test-pages "" 'scripts/test-pages.sh'
step test-titles "" 'scripts/test-titles.sh'
step test-social-identity "" 'scripts/test-social-identity.sh'
step test-about-email "" 'scripts/test-about-email.sh'
step test-contact-page "" 'scripts/test-contact-page.sh'
step test-comments "" 'scripts/test-comments.sh'
step test-redirects "" 'scripts/test-redirects.sh'
step test-crosscheck-redirects "" 'scripts/test-crosscheck-redirects.sh'
step check-email-image "" 'scripts/check-email-image.sh'
step test-check-email-image "" 'scripts/test-check-email-image.sh'
step check-script-count "" 'scripts/check-script-count.sh'
step test-check-script-count "" 'scripts/test-check-script-count.sh'
step gen-support-qr "" 'scripts/gen-support-qr.sh --check --decode'
step check-wording "" 'scripts/check-wording.sh'
step test-check-wording "" 'scripts/test-check-wording.sh'
step check-threat-model "" 'python3 -I scripts/check-threat-model.py'
step test-check-threat-model "" 'scripts/test-check-threat-model.sh'
step test-render-threat-summary "" 'scripts/test-render-threat-summary.sh'
step check-license "" 'scripts/check-license.sh'
step test-check-license "" 'scripts/test-check-license.sh'
step check-wiki "" 'python3 -I scripts/check-wiki.py'
step test-check-wiki "" 'scripts/test-check-wiki.sh'
step test-publish-wiki "" 'scripts/test-publish-wiki.sh'
step test-check-launch-seo "" 'scripts/test-check-launch-seo.sh'
step check-content "" 'python3 -I scripts/check-content.py'
step test-check-content "" 'scripts/test-check-content.sh'
step test-author "" 'scripts/test-author.sh'
step test-pin-script "" 'scripts/test-pin-script.sh'
step test-check-hugo-version "" 'scripts/test-check-hugo-version.sh'
step test-smoke-site "" 'scripts/test-smoke-site.sh'
step test-verify-live "" 'scripts/test-verify-live.sh'
step test-robots-wildcard "" 'scripts/test-robots-wildcard.sh'
step test-llms "" 'scripts/test-llms.sh'
step test-wait-for-ci-green "" 'scripts/test-wait-for-ci-green.sh'
step test-ensure-pages-project "" 'scripts/test-ensure-pages-project.sh'
step test-wxr2hugo "" 'scripts/test-wxr2hugo.sh'
step test-wxr2hugo-webp "" 'scripts/test-wxr2hugo-webp.sh'
step test-migration "" 'scripts/test-migration.sh'
step test-archetype "" 'scripts/test-archetype.sh'
step test-analytics "" 'scripts/test-analytics.sh'
step gen-tokens "" 'python3 -I scripts/gen-tokens.py --check'
step check-contrast "" 'python3 -I scripts/check-contrast.py assets/css/tokens.css'
step test-check-contrast "" 'scripts/test-check-contrast.sh'
step check-brand-assets "" 'scripts/check-brand-assets.sh'
step test-brand "" 'scripts/test-brand.sh'
step test-check-reach-around-drift "" 'scripts/test-check-reach-around-drift.sh'
step test-gitleaks-config "" 'scripts/test-gitleaks-config.sh'
step test-scrub-config "" 'scripts/test-scrub-config.sh'
step check-budget build-production 'python3 -I scripts/check-budget.py "$T/public"'
step test-check-budget "" 'scripts/test-check-budget.sh'
step browser-gate build-production '"$CHROME" --version && python3 -I scripts/browser-gate.py "$T/public"'
step test-browser-gate "" 'scripts/test-browser-gate.sh'
step shfmt "" 'shfmt -d -i 4 -ci scripts/*.sh'
step shellcheck "" 'shellcheck -S warning scripts/*.sh'
# Live and optional: reads another repo's state over the network (docs/token-drift.md),
# so it runs only with --with-drift or --only check-reach-around-drift, never by default.
step check-reach-around-drift "" 'scripts/check-reach-around-drift.sh'
# Not in CI: this script's own test (CI lists tests one by one and is unchanged).
step test-gate "" 'scripts/test-gate.sh'

declare -A optional
optional["check-reach-around-drift"]="live check: needs the network and Reach Around's state"

# --- fast-mode groups --------------------------------------------------------
content_steps=(check-hugo-version build-production check-output-production check-site-artifact-production
    build-staging check-output-staging check-site-artifact-staging test-head test-featured-image test-social-products test-share test-borders test-resume test-layout
    test-pages test-titles test-about-email check-email-image test-check-email-image test-social-identity test-contact-page test-comments test-redirects test-llms test-migration test-archetype check-wording test-check-wording check-script-count test-check-script-count check-threat-model test-check-threat-model test-render-threat-summary check-wiki test-check-wiki test-publish-wiki test-check-launch-seo
    check-content test-check-content test-author)
layout_steps=("${content_steps[@]}" gen-tokens check-contrast test-check-contrast check-brand-assets test-brand check-budget
    test-check-budget browser-gate test-browser-gate)
docs_steps=(check-wording test-check-wording check-script-count test-check-script-count check-threat-model test-check-threat-model test-render-threat-summary check-license test-check-license check-wiki test-check-wiki test-publish-wiki test-check-launch-seo check-content test-check-content test-author test-scrub-config)

# Tools a step needs that its command line does not show (wrapper scripts call them).
# "chrome" means the browser named by CHROME.
declare -A requires
requires["test-analytics"]="node"
requires["test-share"]="node"
requires["test-browser-gate"]="chrome"
# The drift wrapper and its fixture test (which serves a local fake API) call curl and python3.
requires["check-reach-around-drift"]="curl python3"
requires["test-check-reach-around-drift"]="curl python3"

# --- arguments -----------------------------------------------------------------
fast=0
with_drift=0
plan=0
keep=0
only=()
usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast) fast=1 ;;
        --plan) plan=1 ;;
        --keep) keep=1 ;;
        --with-drift) with_drift=1 ;;
        --only)
            if [[ $# -lt 2 ]]; then
                echo "gate: --only needs a step name" >&2
                exit 2
            fi
            only+=("$2")
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "gate: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

is_step() {
    local n
    for n in "${names[@]}"; do [[ "$n" == "$1" ]] && return 0; done
    return 1
}

declare -A sel

# --- selection -----------------------------------------------------------------
if [[ ${#only[@]} -gt 0 ]]; then
    for o in "${only[@]}"; do
        if ! is_step "$o"; then
            echo "gate: no such step: $o (see scripts/gate.sh --plan)" >&2
            exit 2
        fi
        sel["$o"]=1
    done
elif [[ $fast -eq 1 ]]; then
    changed="$(
        git -C "$root" diff --name-only "$base" -- 2>/dev/null
        git -C "$root" ls-files --others --exclude-standard 2>/dev/null
    )"
    if ! git -C "$root" rev-parse --verify -q "$base" >/dev/null; then
        echo "gate: cannot find $base to diff against (git fetch origin, or set GATE_BASE)" >&2
        exit 2
    fi
    changed="$(sort -u <<<"$changed" | sed '/^$/d')"
    if [[ -z "$changed" ]]; then
        echo "gate: no changed files against $base; nothing to run"
        exit 0
    fi
    pick() {
        local s
        for s in "$@"; do sel["$s"]=1; done
    }
    # select_script <basename>: pick the steps a changed script affects. A script that
    # other scripts source (artifact-rules.sh, robots-wildcard.sh) counts as changed for
    # every consumer, transitively, so their checks and tests run too.
    select_script() {
        local eff=("$1") i=0 c b stem n tf
        while [[ $i -lt ${#eff[@]} ]]; do
            b="${eff[$i]}"
            i=$((i + 1))
            for c in "$root"/scripts/*.sh; do
                c="$(basename "$c")"
                [[ " ${eff[*]} " == *" $c "* ]] && continue
                if grep -qE "^[[:space:]]*(source|\\.)[[:space:]].*${b//./\\.}" "$root/scripts/$c"; then
                    eff+=("$c")
                fi
            done
        done
        for b in "${eff[@]}"; do
            stem="${b%.*}"
            for n in "${names[@]}"; do
                # A step runs a changed script directly, or is a test that names it.
                if [[ "${cmds[$n]}" == *"scripts/$b"* ]]; then
                    sel["$n"]=1
                elif [[ -f "$root/scripts/test-$stem.sh" && "${cmds[$n]}" == *"scripts/test-$stem.sh"* ]]; then
                    sel["$n"]=1
                elif [[ "${cmds[$n]}" == scripts/test-* ]]; then
                    tf="${cmds[$n]#scripts/}"
                    tf="${tf%% *}"
                    if [[ -f "$root/scripts/$tf" ]] && grep -qF -- "$b" "$root/scripts/$tf"; then
                        sel["$n"]=1
                    fi
                fi
            done
        done
    }
    while IFS= read -r f; do
        case "$f" in
            brand/tokens.json | scripts/gen-tokens.py)
                # Brand-affecting: the layout, contrast, brand and budget group runs too.
                pick "${layout_steps[@]}"
                ;;&
            brand/tokens.json | scripts/gen-tokens.py | scripts/*reach-around-drift* | docs/token-drift.md)
                # The offline fixture test; the live check follows the flag (below).
                pick test-check-reach-around-drift check-reach-around-drift
                ;;&
            scripts/*)
                pick shfmt shellcheck
                select_script "$(basename "$f")"
                ;;
            tools/wxr2hugo/*)
                pick test-wxr2hugo test-wxr2hugo-webp test-migration
                ;;
            data/support.yaml)
                pick gen-support-qr "${content_steps[@]}"
                ;;
            assets/* | layouts/* | static/* | brand/* | tools/* | hugo.toml | copy.js.sha256 | search.js.sha256 | share.js.sha256)
                pick "${layout_steps[@]}"
                ;;
            content/* | data/* | archetypes/*)
                pick "${content_steps[@]}"
                ;;
            analytics/* | functions/*)
                pick test-analytics
                ;;
            *.md | docs/* | .github/* | LICENSE* | NOTICE | .gitignore | board.yaml)
                pick "${docs_steps[@]}"
                ;;
            *)
                # Unrecognised: assume it can change the built site.
                pick "${content_steps[@]}"
                ;;
        esac
    done <<<"$changed"
else
    for n in "${names[@]}"; do sel["$n"]=1; done
fi

# Optional steps run only when asked for: --with-drift or an explicit --only.
skipped_optional=()
for n in "${names[@]}"; do
    [[ -n "${optional[$n]:-}" ]] || continue
    if [[ ${#only[@]} -gt 0 ]]; then continue; fi
    if [[ $with_drift -eq 1 ]]; then
        if [[ $fast -eq 0 ]]; then sel["$n"]=1; fi
    elif [[ $fast -eq 0 || -n "${sel[$n]:-}" ]]; then
        skipped_optional+=("$n")
        unset 'sel[$n]'
    fi
done
for n in "${skipped_optional[@]}"; do
    echo "gate: skipped $n (${optional[$n]}); run with --with-drift or --only $n"
done

# A selected step pulls in the build it reads.
for n in "${names[@]}"; do
    if [[ -n "${sel[$n]:-}" && -n "${needs[$n]}" ]]; then sel["${needs[$n]}"]=1; fi
done

selected=()
for n in "${names[@]}"; do
    if [[ -n "${sel[$n]:-}" ]]; then selected+=("$n"); fi
done

if [[ ${#selected[@]} -eq 0 ]]; then
    echo "gate: nothing to run"
    exit 0
fi

if [[ $plan -eq 1 ]]; then
    echo "gate plan: ${#selected[@]} step(s)"
    for n in "${selected[@]}"; do
        printf '%s: %s\n' "$n" "${cmds[$n]}"
    done
    exit 0
fi

# --- tools ---------------------------------------------------------------------
if [[ -v GATE_TOOLS ]]; then
    tools="$GATE_TOOLS"
else
    dev="$HOME/.local/share/no-php-no-cry-dev"
    tools=""
    for d in "$dev" "$dev/lint"; do
        if [[ -d "$d" ]]; then tools="${tools:+$tools:}$d"; fi
    done
fi
if [[ -n "$tools" ]]; then PATH="$tools:$PATH"; fi
export PATH

if [[ -z "${CHROME:-}" ]]; then
    for c in google-chrome chromium chromium-browser; do
        if command -v "$c" >/dev/null 2>&1; then
            CHROME="$c"
            break
        fi
    done
fi
export CHROME="${CHROME:-}"

missing=()
need_tool() { # <tool> <step>
    local t="$1" what
    if [[ "$t" == chrome ]]; then
        if [[ -z "$CHROME" ]] || ! command -v "$CHROME" >/dev/null 2>&1; then
            what="chrome (google-chrome or chromium; set CHROME) for $2"
        fi
    elif ! command -v "$t" >/dev/null 2>&1; then
        what="$t for $2"
    fi
    if [[ -n "${what:-}" && " ${missing[*]} " != *" $what "* ]]; then missing+=("$what"); fi
}
for n in "${selected[@]}"; do
    for t in hugo shellcheck shfmt python3; do
        if [[ " ${cmds[$n]} " == *" $t "* ]]; then need_tool "$t" "$n"; fi
    done
    if [[ "${cmds[$n]}" == *'$CHROME'* || "${cmds[$n]}" == *"--decode"* ]]; then need_tool chrome "$n"; fi
    read -r -a reqs <<<"${requires[$n]:-}"
    for t in "${reqs[@]}"; do need_tool "$t" "$n"; done
done
if [[ ${#missing[@]} -gt 0 ]]; then
    printf "gate: missing tool: %s\n" "${missing[@]}" >&2
    echo "gate: put them on PATH or in a directory listed in GATE_TOOLS" >&2
    exit 2
fi

# --- run -----------------------------------------------------------------------
T="$(mktemp -d "${GATE_TMP:-${TMPDIR:-/tmp}}/gate.XXXXXX")" || exit 2
export T
cleanup() {
    if [[ $keep -eq 1 ]]; then
        echo "gate: kept $T (per-step logs: $T/logs)"
    else
        rm -rf "$T"
    fi
}
trap cleanup EXIT
mkdir -p "$T/logs"

declare -A status
failed=()
total=${#selected[@]}
i=0
for n in "${selected[@]}"; do
    i=$((i + 1))
    dep="${needs[$n]}"
    if [[ -n "$dep" && "${status[$dep]:-0}" != 0 ]]; then
        status["$n"]="skipped"
        failed+=("$n")
        echo "[$i/$total] $n: SKIPPED ($dep failed)"
        continue
    fi
    log="$T/logs/$n.log"
    start=$SECONDS
    rc=0
    (cd "$root" && bash -o pipefail -ec "${cmds[$n]}") >"$log" 2>&1 || rc=$?
    status["$n"]="$rc"
    took=$((SECONDS - start))
    if [[ $rc -eq 0 ]]; then
        echo "[$i/$total] $n: ok (exit 0, ${took}s)"
    else
        failed+=("$n")
        echo "[$i/$total] $n: FAIL (exit $rc, ${took}s)"
        tail -n 15 "$log" | sed 's/^/    | /'
    fi
done

if [[ ${#failed[@]} -eq 0 ]]; then
    echo "gate: $total step(s), 0 failed"
    exit 0
fi
echo "gate: $total step(s), ${#failed[@]} failed: ${failed[*]}"
for n in "${failed[@]}"; do
    if [[ "$n" == browser-gate ]]; then
        echo "gate: browser-gate can flake under load (LCP); rerun just it: scripts/gate.sh --only browser-gate"
    fi
done
exit 1
