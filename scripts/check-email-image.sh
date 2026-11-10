#!/usr/bin/env bash
# Drift guard for the committed email image (issue 331).
#
# assets/contact/email-address.png is drawn from the business address in
# data/about.yaml by scripts/gen-email-image.py, which also writes the stamp
# assets/contact/email-address.stamp: the sha256 of the address, of the font and of
# the PNG it drew. This check needs no Pillow, so it runs everywhere, and fails when
#   email-image-stale     the address (or the font) changed but the image was not redrawn
#   email-image-modified  the PNG differs from the one the stamp records
#   email-image-missing   the PNG or the stamp is absent while an address is published
# While the contact config is incomplete (scripts/about-email.sh prints nothing) no
# address is published and there is nothing to check.
#
# Usage: scripts/check-email-image.sh [repo-root]   (default: this repository)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${1:-$here/..}"
mail="$("$here/about-email.sh" "$root/data/about.yaml")"
if [[ -z "$mail" ]]; then
    echo "ok: no address is published, no image to check"
    exit 0
fi
png="$root/assets/contact/email-address.png"
stamp="$root/assets/contact/email-address.stamp"
font="$root/static/fonts/orbitron-wght.ttf"
if [[ ! -f "$png" || ! -f "$stamp" || ! -f "$font" ]]; then
    echo "[email-image-missing] assets/contact/email-address.png or .stamp is absent; run scripts/gen-email-image.py"
    exit 1
fi
sum() { sha256sum | cut -d' ' -f1; }
want_email="$(printf '%s' "$mail" | sum)"
want_font="$(sum <"$font")"
want_png="$(sum <"$png")"
rc=0
field() { sed -n "s/^$1 //p" "$stamp" | head -n 1; }
if [[ "$(field email)" != "$want_email" || "$(field font)" != "$want_font" ]]; then
    echo "[email-image-stale] the address or font changed; run scripts/gen-email-image.py and commit the image and stamp"
    rc=1
fi
if [[ "$(field png)" != "$want_png" ]]; then
    echo "[email-image-modified] email-address.png differs from the image the stamp records; run scripts/gen-email-image.py"
    rc=1
fi
[[ $rc -ne 0 ]] || echo "ok: the email image matches the address, font and stamp"
exit $rc
