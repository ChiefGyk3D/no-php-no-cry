#!/usr/bin/env python3
"""Convert the PNG and JPEG images in converted page bundles to WebP.

    python3 -I tools/wxr2hugo/webp.py DIR [--quality N]

DIR holds page bundles (a directory with an index.md and its images), such as
the output of convert.py or a copy of it under content/. Needs Pillow; run it
through scripts/test-wxr2hugo-webp.sh's pinned requirements
(tools/wxr2hugo/requirements-webp.txt). Each PNG or JPEG becomes a .webp beside
it, the original is removed and the bundle's index.md is updated, but only when
the WebP is smaller. featured.* (the headline image front matter names) is left alone. EXIF (including any GPS position) and other metadata are
dropped, and the camera orientation is applied first.

Hostile files are refused one by one and left exactly as they were: a file
whose content is not the image format its name claims, an image over the pixel
cap (decompression bomb), an animated PNG, and a symlink (never followed).
Exit codes: 0 done, 1 at least one file refused, 2 usage error.
"""

import argparse
import io
import json
import os
import re
import sys
import warnings
from pathlib import Path

MAX_PIXELS = 40_000_000
FEATURED_STEM = "featured"
SUFFIXES = {".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG"}


def convert_one(src, quality):
    """Returns (webp_bytes, None) or (None, reason). Never touches src."""
    from PIL import Image, ImageOps

    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(src) as img:
                if img.format != SUFFIXES[src.suffix.lower()]:
                    return None, "content is %s, not %s" % (img.format, SUFFIXES[src.suffix.lower()])
                if getattr(img, "n_frames", 1) > 1:
                    return None, "animated image"
                if img.width * img.height > MAX_PIXELS:
                    return None, "over the pixel cap"
                img.load()
                img = ImageOps.exif_transpose(img)
                has_alpha = img.mode in ("RGBA", "LA") or "transparency" in img.info
                img = img.convert("RGBA" if has_alpha else "RGB")
                buf = io.BytesIO()
                img.save(buf, "WEBP", quality=quality, method=6)
                return buf.getvalue(), None
    except (Image.DecompressionBombError, Image.DecompressionBombWarning):
        return None, "over the pixel cap"
    except Exception as err:  # unreadable or truncated: class name only
        return None, "unreadable image (%s)" % type(err).__name__


def free_name(directory, stem):
    name, n = stem + ".webp", 1
    while (directory / name).exists():
        n += 1
        name = "%s-%d.webp" % (stem, n)
    return name


def write_new(path, data):
    """Create path exclusively (never following a symlink) and write data.
    A leftover regular file is removed first; anything else (symlink,
    directory, device) is refused and left alone. Returns False when refused."""
    if os.path.lexists(path):
        if path.is_symlink() or not path.is_file():
            return False
        path.unlink()
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags, 0o600)
    except FileExistsError:
        return False
    with os.fdopen(fd, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    return True


def process_bundle(directory, root, quality, report):
    index = directory / "index.md"
    if index.is_symlink() or not index.is_file():
        return
    text = index.read_text(encoding="utf-8")
    changed = False
    for src in sorted(directory.iterdir()):
        if src.suffix.lower() not in SUFFIXES:
            continue
        if src.stem == FEATURED_STEM:
            # The headline image is named by front matter (image: "featured.png"),
            # which this tool does not rewrite, and it is only a source for the
            # site's resize pipeline (build.publishResources is false), never served.
            continue
        rel = str(src.relative_to(root))
        if src.is_symlink() or not src.is_file():
            report["refused"].append({"file": rel, "reason": "not a regular file"})
            continue
        data, reason = convert_one(src, quality)
        if reason:
            report["refused"].append({"file": rel, "reason": reason})
            continue
        before = src.stat().st_size
        if len(data) >= before:
            report["kept_original"].append(rel)
            continue
        name = free_name(directory, src.stem)
        target = directory / name
        tmp = directory / (name + ".partial")
        if not write_new(tmp, data):
            report["refused"].append({"file": rel, "reason": "leftover temporary file is not a regular file"})
            continue
        os.replace(tmp, target)
        pattern = re.compile(r"\]\(" + re.escape(src.name) + r"\)")
        text = pattern.sub("](%s)" % name, text)
        changed = True
        src.unlink()
        report["converted"].append({"file": rel, "to": name, "before": before, "after": len(data)})
    if changed:
        index.write_text(text, encoding="utf-8")


def follow_legacy_uploads(root, report):
    """Point legacy-uploads.json (written by convert.py beside the bundles) at the
    new .webp names, so the site's redirect for an old /wp-content/uploads/
    address lands on a file that exists. Entries for files that were kept or
    refused are left alone."""
    path = root / "legacy-uploads.json"
    if path.is_symlink() or not path.is_file():
        return
    renamed = {}
    for item in report["converted"]:
        old = Path(item["file"])
        renamed["/" + old.as_posix()] = "/" + (old.parent / item["to"]).as_posix()
    entries = json.loads(path.read_text(encoding="utf-8"))
    for entry in entries:
        entry["to"] = renamed.get(entry["to"], entry["to"])
    path.write_text(json.dumps(entries, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Convert PNG and JPEG images in page bundles to WebP.")
    parser.add_argument("directory")
    parser.add_argument("--quality", type=int, default=82)
    args = parser.parse_args(argv)
    root = Path(args.directory).expanduser()
    if not root.is_dir() or root.is_symlink():
        print("error: DIR is not a directory", file=sys.stderr)
        return 2
    if not 1 <= args.quality <= 100:
        print("error: --quality must be 1 to 100", file=sys.stderr)
        return 2
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("error: Pillow is not installed (see tools/wxr2hugo/requirements-webp.txt)", file=sys.stderr)
        return 2
    report = {"converted": [], "kept_original": [], "refused": []}
    for base, dirs, _ in os.walk(root, followlinks=False):
        dirs.sort()
        process_bundle(Path(base), root, args.quality, report)
    follow_legacy_uploads(root, report)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 1 if report["refused"] else 0


if __name__ == "__main__":
    sys.exit(main())
