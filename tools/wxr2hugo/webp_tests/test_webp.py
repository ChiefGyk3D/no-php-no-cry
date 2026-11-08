"""Tests for tools/wxr2hugo/webp.py. Needs Pillow: run through
scripts/test-wxr2hugo-webp.sh, which installs the pinned release into a
throwaway venv. Every image here is generated; nothing is a real photo."""

import io
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

TOOL = Path(__file__).resolve().parent.parent / "webp.py"


def scratch():
    return Path(tempfile.mkdtemp(prefix="webp-test-")).resolve()


def photo_like(size, mode="RGB"):
    """A smooth gradient with mild noise: the kind of image WebP shrinks."""
    rng = random.Random(7)
    w, h = size
    img = Image.new(mode, size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            n = rng.randint(-6, 6)
            r, g, b = (x * 255 // w + n) % 256, (y * 255 // h + n) % 256, ((x + y) * 255 // (w + h) + n) % 256
            px[x, y] = (r, g, b) if mode == "RGB" else (r, g, b, 40 + (x * 200 // w))
    return img


def png_bytes(size=(200, 120), mode="RGB"):
    buf = io.BytesIO()
    photo_like(size, mode).save(buf, "PNG")
    return buf.getvalue()


def jpeg_with_exif(size=(120, 200), orientation=6):
    img = photo_like(size)
    exif = Image.Exif()
    exif[0x0112] = orientation
    exif[0x010F] = "SecretCameraMaker"
    gps = exif.get_ifd(0x8825)
    gps[1] = "N"
    gps[2] = (40.0, 41.0, 42.0)
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)
    return buf.getvalue()


def bundle(root, name="posts/p", index="# P\n\n![alt text](a.png)\n\n[full size](a.png)\n"):
    d = Path(root) / name
    d.mkdir(parents=True)
    (d / "index.md").write_text(index, encoding="utf-8")
    return d


def run(directory, *extra):
    return subprocess.run(
        [sys.executable, "-I", str(TOOL), str(directory), *extra], capture_output=True, text=True, check=False
    )


class HostilePartialTests(unittest.TestCase):
    def test_symlinked_partial_is_not_followed(self):
        root = scratch()
        outside = scratch() / "victim.txt"
        outside.write_text("keep me")
        d = bundle(root)
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        (d / "a.webp.partial").symlink_to(outside)
        proc = run(root)
        self.assertEqual(outside.read_text(), "keep me")
        self.assertEqual(proc.returncode, 1, proc.stderr)  # refused, not converted
        self.assertEqual([r["file"] for r in json.loads(proc.stdout)["refused"]], ["posts/p/a.png"])
        self.assertTrue((d / "a.webp.partial").is_symlink())
        self.assertFalse((d / "a.webp").exists())
        self.assertTrue((d / "a.png").is_file())

    def test_directory_named_partial_is_refused_not_crashed(self):
        root = scratch()
        d = bundle(root)
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        (d / "a.webp.partial").mkdir()
        proc = run(root)
        self.assertEqual(proc.returncode, 1, proc.stderr)
        report = json.loads(proc.stdout)
        self.assertEqual(report["converted"], [])
        self.assertEqual([r["file"] for r in report["refused"]], ["posts/p/a.png"])
        self.assertTrue((d / "a.png").is_file())
        self.assertTrue((d / "a.webp.partial").is_dir())
        self.assertIn("a.png", (d / "index.md").read_text())

    def test_stale_regular_partial_is_replaced(self):
        root = scratch()
        d = bundle(root)
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        (d / "a.webp.partial").write_bytes(b"stale")
        self.assertEqual(run(root).returncode, 0)
        self.assertFalse(os.path.lexists(d / "a.webp.partial"))
        with Image.open(d / "a.webp") as img:
            self.assertEqual(img.format, "WEBP")


class ConvertTests(unittest.TestCase):
    def test_png_and_jpeg_become_webp_and_references_follow(self):
        root = scratch()
        d = bundle(root, index="![one](a.png)\n\n![two](b.jpg)\n\nprose a.png is untouched\n")
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        (d / "b.jpg").write_bytes(jpeg_with_exif((600, 400), 1))
        proc = run(root)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(proc.stdout)
        self.assertEqual(sorted(c["to"] for c in report["converted"]), ["a.webp", "b.webp"])
        self.assertEqual(sorted(os.listdir(d)), ["a.webp", "b.webp", "index.md"])
        text = (d / "index.md").read_text()
        self.assertIn("![one](a.webp)", text)
        self.assertIn("![two](b.webp)", text)
        self.assertIn("prose a.png is untouched", text)
        with Image.open(d / "a.webp") as img:
            self.assertEqual((img.format, img.size), ("WEBP", (600, 400)))
        for c in report["converted"]:
            self.assertLess(c["after"], c["before"])

    def test_legacy_upload_map_follows_the_new_file_names(self):
        # convert.py writes legacy-uploads.json (old address -> bundle file); the
        # redirect target must be the .webp that now exists, and an image that
        # was kept or refused keeps its target.
        root = scratch()
        d = bundle(root, index="![one](a.png)\n\n![two](b.png)\n")
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        (d / "b.png").write_bytes(b"not a png")
        before = [
            {"from": "/wp-content/uploads/2023/05/a-300x200.png", "to": "/posts/p/a.png"},
            {"from": "/wp-content/uploads/2023/05/a.png", "to": "/posts/p/a.png"},
            {"from": "/wp-content/uploads/2023/05/b.png", "to": "/posts/p/b.png"},
        ]
        (root / "legacy-uploads.json").write_text(json.dumps(before), encoding="utf-8")
        proc = run(root)
        self.assertEqual(proc.returncode, 1, proc.stderr)  # b.png is refused
        after = json.loads((root / "legacy-uploads.json").read_text())
        self.assertEqual([e["to"] for e in after], ["/posts/p/a.webp", "/posts/p/a.webp", "/posts/p/b.png"])
        self.assertEqual([e["from"] for e in after], [e["from"] for e in before])
        for entry in after:
            self.assertTrue((root / entry["to"].lstrip("/")).is_file(), entry)

    def test_link_and_image_to_the_same_file_both_follow(self):
        root = scratch()
        d = bundle(root)
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        self.assertEqual(run(root).returncode, 0)
        text = (d / "index.md").read_text()
        self.assertIn("![alt text](a.webp)", text)
        self.assertIn("[full size](a.webp)", text)
        self.assertNotIn("a.png", text)

    def test_exif_and_gps_are_dropped_and_orientation_applied(self):
        root = scratch()
        d = bundle(root, index="![x](c.jpg)\n")
        (d / "c.jpg").write_bytes(jpeg_with_exif((120, 200), 6))
        self.assertEqual(run(root).returncode, 0)
        data = (d / "c.webp").read_bytes()
        self.assertNotIn(b"SecretCameraMaker", data)
        self.assertNotIn(b"EXIF", data)
        with Image.open(d / "c.webp") as img:
            self.assertEqual(img.size, (200, 120))  # rotated by the orientation tag
            self.assertFalse(img.getexif())

    def test_alpha_is_kept(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n")
        (d / "a.png").write_bytes(png_bytes((600, 400), "RGBA"))
        self.assertEqual(run(root).returncode, 0)
        with Image.open(d / "a.webp") as img:
            self.assertEqual(img.mode, "RGBA")

    def test_name_collision_gets_a_new_name(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n\n![y](a.jpg)\n")
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        (d / "a.jpg").write_bytes(jpeg_with_exif((600, 400), 1))
        self.assertEqual(run(root).returncode, 0)
        self.assertEqual(sorted(os.listdir(d)), ["a-2.webp", "a.webp", "index.md"])
        text = (d / "index.md").read_text()
        self.assertIn("(a.webp)", text)
        self.assertIn("(a-2.webp)", text)

    def test_second_run_changes_nothing(self):
        root = scratch()
        d = bundle(root)
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        run(root)
        before = {n: (d / n).read_bytes() for n in os.listdir(d)}
        proc = run(root)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(json.loads(proc.stdout)["converted"], [])
        self.assertEqual(before, {n: (d / n).read_bytes() for n in os.listdir(d)})

    def test_an_image_that_would_grow_is_kept(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n")
        # Sharp one-pixel dots on a flat field: tiny as PNG, large as lossy WebP.
        img = Image.new("RGB", (600, 400), (200, 40, 40))
        for x in range(0, 600, 7):
            for y in range(0, 400, 5):
                img.putpixel((x, y), (10, 200, 30))
        buf = io.BytesIO()
        img.save(buf, "PNG")
        (d / "a.png").write_bytes(buf.getvalue())
        proc = run(root)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(proc.stdout)
        self.assertEqual(report["converted"], [])
        self.assertEqual(report["kept_original"], ["posts/p/a.png"])
        self.assertEqual((d / "a.png").read_bytes(), buf.getvalue())
        self.assertIn("(a.png)", (d / "index.md").read_text())


class HostileInputTests(unittest.TestCase):
    def assert_untouched(self, d, name, data, proc, reason):
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertEqual((d / name).read_bytes(), data)
        self.assertEqual(sorted(os.listdir(d)), sorted([name, "index.md"]))
        self.assertIn("(%s)" % name, (d / "index.md").read_text())
        self.assertIn(reason, json.loads(proc.stdout)["refused"][0]["reason"])

    def test_text_pretending_to_be_a_png_is_refused(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n")
        data = b"<?php system($_GET['c']); ?>"
        (d / "a.png").write_bytes(data)
        self.assert_untouched(d, "a.png", data, run(root), "unreadable image")

    def test_jpeg_named_png_is_refused(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n")
        data = jpeg_with_exif((50, 50), 1)
        (d / "a.png").write_bytes(data)
        self.assert_untouched(d, "a.png", data, run(root), "content is JPEG")

    def test_decompression_bomb_is_refused(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n")
        buf = io.BytesIO()
        Image.new("1", (30000, 30000)).save(buf, "PNG", optimize=True)  # 900 Mpixel, a few KB
        data = buf.getvalue()
        self.assertLess(len(data), 5_000_000)
        (d / "a.png").write_bytes(data)
        self.assert_untouched(d, "a.png", data, run(root), "pixel cap")

    def test_truncated_image_is_refused(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n")
        data = png_bytes((600, 400))[:200]
        (d / "a.png").write_bytes(data)
        self.assert_untouched(d, "a.png", data, run(root), "unreadable image")

    def test_animated_png_is_refused(self):
        root = scratch()
        d = bundle(root, index="![x](a.png)\n")
        buf = io.BytesIO()
        frames = [Image.new("RGB", (40, 40), c) for c in ((255, 0, 0), (0, 255, 0))]
        frames[0].save(buf, "PNG", save_all=True, append_images=frames[1:], duration=100)
        data = buf.getvalue()
        (d / "a.png").write_bytes(data)
        self.assert_untouched(d, "a.png", data, run(root), "animated")

    def test_symlink_is_never_followed(self):
        root = scratch()
        outside = scratch() / "secret.png"
        outside.write_bytes(png_bytes((600, 400)))
        d = bundle(root, index="![x](a.png)\n")
        os.symlink(outside, d / "a.png")
        proc = run(root)
        self.assertEqual(proc.returncode, 1)
        self.assertTrue((d / "a.png").is_symlink())
        self.assertEqual(os.listdir(outside.parent), ["secret.png"])
        self.assertIn("not a regular file", json.loads(proc.stdout)["refused"][0]["reason"])

    def test_symlinked_directory_is_not_entered(self):
        root = scratch()
        elsewhere = scratch()
        d = bundle(elsewhere, "p")
        (d / "a.png").write_bytes(png_bytes((600, 400)))
        os.symlink(d, root / "link")
        proc = run(root)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(sorted(os.listdir(d)), ["a.png", "index.md"])

    def test_hostile_file_name_cannot_rewrite_other_text(self):
        root = scratch()
        d = bundle(root, index="![x](a.b.png)\n\n[y](aXb.png)\n")
        (d / "a.b.png").write_bytes(png_bytes((600, 400)))
        self.assertEqual(run(root).returncode, 0)
        text = (d / "index.md").read_text()
        self.assertIn("![x](a.b.webp)", text)
        self.assertIn("[y](aXb.png)", text)  # the dot is literal, not a wildcard

    def test_one_bad_file_does_not_stop_the_good_ones(self):
        root = scratch()
        d = bundle(root, index="![x](bad.png)\n\n![y](good.png)\n")
        (d / "bad.png").write_bytes(b"not an image")
        (d / "good.png").write_bytes(png_bytes((600, 400)))
        proc = run(root)
        self.assertEqual(proc.returncode, 1)
        report = json.loads(proc.stdout)
        self.assertEqual([c["to"] for c in report["converted"]], ["good.webp"])
        self.assertEqual(len(report["refused"]), 1)

    def test_usage_errors(self):
        self.assertEqual(run(scratch() / "missing").returncode, 2)
        self.assertEqual(run(scratch(), "--quality", "0").returncode, 2)
        self.assertEqual(run(scratch(), "--quality", "101").returncode, 2)


class FeaturedImageSurvivesTests(unittest.TestCase):
    """The importer writes front matter image: "featured.png"; the WebP pass must
    not delete that file (layouts and the card read it by name)."""

    def test_importer_then_webp_keeps_the_featured_file_front_matter_names(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tests"))
        try:
            import helpers
            from test_convert import thumb_export
        finally:
            sys.path.pop(0)
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(thumb_export(), encoding="utf-8")
        media = helpers.make_media(work / "media")
        (media / "2023" / "02" / "pic.png").write_bytes(png_bytes((600, 400)))
        out = work / "out"
        self.assertEqual(helpers.run(["--wxr", wxr, "--out", out, "--media", media]).returncode, 0)
        post = out / "posts" / "first-post"
        self.assertTrue((post / "featured.png").is_file())
        self.assertEqual(run(out).returncode, 0)
        head = (post / "index.md").read_text(encoding="utf-8").split("---\n")[1]
        match = re.search(r'^image: "([^"]+)"$', head, re.M)
        self.assertIsNotNone(match, head)
        self.assertTrue((post / match.group(1)).is_file(), "front matter image %s is gone" % match.group(1))
        # Inline images are still converted: the exclusion is only for featured.*
        self.assertTrue(any(p.suffix == ".webp" for p in post.iterdir()))


if __name__ == "__main__":
    unittest.main()
