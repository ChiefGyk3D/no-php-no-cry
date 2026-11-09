#!/usr/bin/env bash
# CSS-level layout guards (issue 308): the Home hero buttons sit on one row and text inside a
# bordered box uses the box width. A browser is not available in CI, so this asserts the rules
# in the stylesheets; the measured evidence (bounding boxes at the viewport matrix) is in
# docs/viewport-matrix.md. A guard self-test feeds the checker a stylesheet that breaks each
# rule and requires a failure.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "$root/tmp/layout.XXXXXX" 2>/dev/null || { mkdir -p "$root/tmp" && mktemp -d "$root/tmp/layout.XXXXXX"; })"
trap 'rm -rf "$work"' EXIT

checker="$work/check_layout.py"
cat >"$checker" <<'PY'
import re
import sys

strip = lambda t: re.sub(r"/\*.*?\*/", "", t, flags=re.S)
home, main = strip(open(sys.argv[1]).read()), strip(open(sys.argv[2]).read())
about = strip(open(sys.argv[3]).read())
errors = []


def block(css, selector):
    """Declaration text of every rule whose selector list is exactly this selector."""
    out = []
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
        sels = [s.strip() for s in m.group(1).split(",")]
        if selector in sels:
            out.append(m.group(2))
    return "\n".join(out)


def has(text, decl):
    return re.search(r"(^|[;\s])" + re.escape(decl) + r"\s*(;|$)", text) is not None


actions = block(home, ".hero-actions")
for d in ("display: flex", "flex-wrap: wrap", "gap: var(--space-3)"):
    if not has(actions, d):
        errors.append(f".hero-actions lacks {d}")
if not has(block(home, ".hero-actions .btn"), "padding-inline: var(--space-4)"):
    errors.append(".hero-actions .btn lacks padding-inline: var(--space-4)")
if not re.search(r"grid-template-columns:\s*minmax\(0,\s*6fr\)\s*minmax\(0,\s*5fr\)", home):
    errors.append("the desktop home grid is not 6fr 5fr")
if not has(main, "--box-prose-max: 100ch"):
    errors.append("--box-prose-max is not 100ch")
if not has(main, "--prose-max: 75ch"):
    errors.append("--prose-max is not 75ch")
boxed = block(main, ".panel p")
if not has(boxed, "max-width: var(--box-prose-max)"):
    errors.append(".panel p does not use --box-prose-max")
for sel in (".skill-group p", ".about-contact p", ".fact-card dd"):
    if block(main, sel) != boxed:
        errors.append(f"{sel} is not in the --box-prose-max rule")
if not has(block(about, ".skill-group:last-child p"), "max-width: none"):
    errors.append("the closing About block does not use the full box width")
if errors:
    print("\n".join(errors))
    sys.exit(1)
PY

failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

home="$root/assets/css/pages/home.css"
main="$root/assets/css/main.css"
about="$root/assets/css/pages/about.css"
if python3 -I "$checker" "$home" "$main" "$about" >"$work/real.out" 2>&1; then
    pass "the hero button row and the box text measure rules are in place"
else
    cat "$work/real.out"
    fail "a layout rule changed (see above)"
fi

# Self-test: each mutation must be caught.
mutate() { # mutate <file> <sed expression> <name>
    local f="$work/mut-$3.css"
    sed -E "$2" "$1" >"$f"
    if cmp -s "$1" "$f"; then
        fail "self-test $3: the mutation changed nothing"
        return
    fi
    if [[ "$1" == "$about" ]]; then
        python3 -I "$checker" "$home" "$main" "$f" >/dev/null 2>&1 && fail "self-test $3: not caught" || pass "self-test $3: caught"
    elif [[ "$1" == "$home" ]]; then
        python3 -I "$checker" "$f" "$main" "$about" >/dev/null 2>&1 && fail "self-test $3: not caught" || pass "self-test $3: caught"
    else
        python3 -I "$checker" "$home" "$f" "$about" >/dev/null 2>&1 && fail "self-test $3: not caught" || pass "self-test $3: caught"
    fi
}
mutate "$home" 's/padding-inline: var\(--space-4\)/padding-inline: var(--space-5)/' hero-padding
mutate "$home" 's/minmax\(0, 6fr\)/minmax(0, 5fr)/' hero-ratio
mutate "$main" 's/--box-prose-max: 100ch/--box-prose-max: 60ch/' box-token
mutate "$about" 's/max-width: none/max-width: 75ch/' about-closing
mutate "$main" 's/max-width: var\(--box-prose-max\)/max-width: var(--prose-max)/' box-rule

if ((failures > 0)); then
    echo "$failures failure(s)"
    exit 1
fi
echo "all layout checks passed"
