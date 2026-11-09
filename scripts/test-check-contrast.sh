#!/usr/bin/env bash
# Tests for scripts/check-contrast.py: the repository passes, and the tint check
# (text on --frame-fill composited over the ground) fails when the tint gets too
# strong, when the fill token is missing, and when the text token drops.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
ok() { echo "ok: $1"; }
bad() {
    echo "FAIL: $1"
    fail=1
}

run() { python3 -I "$root/scripts/check-contrast.py" "$1/tokens.css" >"$1/out.log" 2>&1; }

mk() { # mk <name>: a copy of the two CSS files
    mkdir -p "$work/$1"
    cp "$root/assets/css/tokens.css" "$root/assets/css/borders.css" "$work/$1/"
}

mk good
if run "$work/good" && grep -q "frame-fill tint" "$work/good/out.log"; then
    ok "the repository passes and the tint pairs are checked"
else
    bad "the repository fails or the tint is not checked: $(cat "$work/good/out.log")"
fi

mk strong
sed -i 's|--frame-fill: rgb([0-9 ]*/ *[0-9.]*)|--frame-fill: rgb(251 176 59 / 0.9)|' "$work/strong/borders.css"
if run "$work/strong"; then bad "a 0.9 alpha tint passed"; else ok "a tint that breaks 4.5:1 fails"; fi

mk missing
sed -i 's|--frame-fill:.*|--frame-fill: red;|' "$work/missing/borders.css"
if run "$work/missing"; then bad "a missing fill token passed"; else ok "a missing --frame-fill fails"; fi

mk dim
sed -i 's|--text: #F0F0F0|--text: #404040|' "$work/dim/tokens.css"
if run "$work/dim"; then bad "dim text passed"; else ok "dim text fails"; fi

mk hover
sed -i 's|--frame-fill-hover: rgb([0-9 ]*/ *[0-9.]*)|--frame-fill-hover: rgb(251 176 59 / 0.9)|' "$work/hover/borders.css"
if run "$work/hover"; then bad "a 0.9 alpha hover tint passed"; else ok "a hover tint that breaks 4.5:1 fails"; fi

mk nohover
sed -i 's|--frame-fill-hover:.*|--frame-fill-hover: red;|' "$work/nohover/borders.css"
if run "$work/nohover"; then bad "a missing hover tint token passed"; else ok "a missing --frame-fill-hover fails"; fi

mk gold
sed -i 's|--accent: #FBB03B|--accent: #6B4A12|' "$work/gold/tokens.css"
if run "$work/gold"; then bad "a dim gold title passed on the tint"; else ok "gold titles that break 4.5:1 on the tint fail"; fi

((fail == 0)) && echo "test-check-contrast: all passed"
exit "$fail"
