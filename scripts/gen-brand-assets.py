#!/usr/bin/env python3
"""Generate the site's brand image derivatives from the approved sources.

Usage:
  python3 -I scripts/gen-brand-assets.py --master PATH --kit PATH [--out-root DIR]

  --master  the approved 900 px mascot JPEG (kit row mascot-master-001)
  --kit     a checkout of the brand kit (chiefgyk3d-brand), read only
  --out-root  repository root to write into (default: this repository)

Outputs (all under static/brand/, listed in brand/approved-assets.txt):
  mascot-128.webp, mascot-256.webp, mascot-512.webp   from the master
  favicon-32.png, favicon-192.png, favicon-512.png,
  apple-touch-icon-180.png                            from kit derivative-001
  og-card.png                                         1200x630, from tokens
  icons/<slug>.svg                                    kit Simple Icons, copied unmodified
and brand/assets-build.json, the record of source hashes, parameters and the
Pillow version. Every source is checked against a pinned sha256 BEFORE anything
is read as an image, so a wrong or tampered source stops the run with no output.
Nothing is ever upscaled past the 900 px master. Output bytes depend on the
Pillow/libwebp build, so CI does not regenerate; approved-assets.txt pins the
committed bytes instead.
"""

import argparse
import hashlib
import json
import pathlib
import sys

MASTER_SHA = "82edc2004ced79de845a04c466ac39604ffd3e9c961e89f205f4bee4be361189"
MASTER_MAX = 900
COLOR_SHA = "0f34d05fe06348bb158190269cb85f28693a2f37b789c3d6808e0259d72fc4d8"
COLOR_REL = "assets/derivatives/penguin-color.png"
# Kit assets/MANIFEST.md rows icon-*, Simple Icons 16.36.0, unmodified.
ICONS = {
    "twitch": "dbe27bc02a01b8d89b6259cacef328c9fa70bb13c29f38c36eb1421863f6f0b6",
    "youtube": "5038808acbbc4e6edda16cbeb1cc6dec80e4e4ee4e227e039c41229fa222aa8c",
    "kick": "ef6002e2eedaeb685a23ccabcafa970f04b53f109bf931d6c645fc1957a0d135",
    "mastodon": "b27197d1e47e19f31a80bf5d08b3dc9a8d073083436215f672e8e1016178cbe4",
    "bluesky": "49752973164fbbf4464fbb4776f011c1eff207e5d7ad9254e031af025814eb75",
    "tiktok": "6f54ac8d325faacea8935bdc44cbed60206a6b408641799e5fea1cba7c1a0af7",
    "instagram": "f53af2d1fc5292ba1433b5c1faf50005ce6a997fa302d1816989929f379a59dc",
    "threads": "3511f687f9a5713a3700130627f8d3611fb4cd54d3a9757071c93652c7fe16e8",
    "discord": "1d364b72c9eaf1fe37d17ca88cd8fb541308dc0f3b09e2ab3b824f380b3493d5",
    "github": "3bf8cceead820aec50d4ee825a3fd02c5a1cd6665cc9cf4cbf3d9c8861a204bb",
}
MASCOT_SIZES = (128, 256, 512)


def sha256(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def need(path, want, label):
    if not path.is_file():
        sys.exit(f"{label}: {path} is not a file")
    got = sha256(path)
    if got != want:
        sys.exit(f"{label}: sha256 mismatch (expected {want}, file {got}); nothing written")
    return got


def hex_rgb(value):
    return tuple(int(value[i : i + 2], 16) for i in (1, 3, 5))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--master", required=True, type=pathlib.Path)
    ap.add_argument("--kit", required=True, type=pathlib.Path)
    ap.add_argument(
        "--out-root",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent.parent,
    )
    args = ap.parse_args()

    # Verify every source first; Pillow is imported only afterwards.
    need(args.master, MASTER_SHA, "master")
    color_src = args.kit / COLOR_REL
    need(color_src, COLOR_SHA, "kit derivative-001")
    icon_src = {}
    for slug, want in ICONS.items():
        p = args.kit / "assets/icons/simple-icons" / f"{slug}.svg"
        need(p, want, f"icon {slug}")
        icon_src[slug] = p

    from PIL import Image, __version__ as pil_version

    root = args.out_root
    brand = root / "static/brand"
    (brand / "icons").mkdir(parents=True, exist_ok=True)
    tokens = json.loads((root / "brand/tokens.json").read_text())
    flat = {k: v for g in tokens["groups"] for k, v in g["tokens"].items()}
    ground, amber = hex_rgb(flat["bg"]), hex_rgb(flat["accent"])
    outputs = []

    master = Image.open(args.master).convert("RGB")
    if master.size[0] > MASTER_MAX or master.size[1] > MASTER_MAX:
        sys.exit("master is larger than the 900 px ceiling")
    for size in MASCOT_SIZES:
        if size > master.size[0]:
            sys.exit(f"refusing to upscale the master to {size}")
        out = brand / f"mascot-{size}.webp"
        master.resize((size, size), Image.LANCZOS).save(
            out, "WEBP", quality=82, method=6
        )
        outputs.append(out)

    color = Image.open(color_src).convert("RGBA")
    for size in (32, 192, 512):
        out = brand / f"favicon-{size}.png"
        img = color if size == color.size[0] else color.resize((size, size), Image.LANCZOS)
        img.save(out, optimize=True)
        outputs.append(out)
    # Apple touch icons are not transparent: mascot on the ground color, with margin.
    tile = Image.new("RGB", (180, 180), ground)
    inner = color.resize((148, 148), Image.LANCZOS)
    tile.paste(inner, (16, 16), inner)
    out = brand / "apple-touch-icon-180.png"
    tile.save(out, optimize=True)
    outputs.append(out)

    # OG card 1200x630: ground, the master centered at 630x630 (below 900),
    # an amber rule on each side of it.
    card = Image.new("RGB", (1200, 630), ground)
    card.paste(master.resize((630, 630), Image.LANCZOS), (285, 0))
    for x in list(range(275, 285)) + list(range(915, 925)):
        for y in range(630):
            card.putpixel((x, y), amber)
    out = brand / "og-card.png"
    card.save(out, optimize=True)
    outputs.append(out)

    for slug, p in icon_src.items():
        out = brand / "icons" / f"{slug}.svg"
        out.write_bytes(p.read_bytes())
        outputs.append(out)

    record = {
        "note": "Written by scripts/gen-brand-assets.py. Output bytes depend on the Pillow build.",
        "pillow": pil_version,
        "sources": {
            "master": {"kit_path": "assets/masters/mascot-rifle-penguin-900.jpg", "sha256": MASTER_SHA},
            "kit_derivative_001": {"kit_path": COLOR_REL, "sha256": COLOR_SHA},
            "simple_icons_16.36.0": ICONS,
        },
        "parameters": {
            "mascot_webp": {"sizes": list(MASCOT_SIZES), "quality": 82, "method": 6, "resample": "LANCZOS"},
            "og_card": {"size": [1200, 630], "ground": flat["bg"], "accent": flat["accent"]},
        },
        "outputs": {str(o.relative_to(root)): sha256(o) for o in sorted(outputs)},
    }
    (root / "brand/assets-build.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"wrote {len(outputs)} files and brand/assets-build.json")


if __name__ == "__main__":
    main()
