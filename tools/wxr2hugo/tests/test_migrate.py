"""Migration tests (issue #63): draft-all, alt TODO flags, syndication fields,
annotations (archive banner, forward link), hostile permalinks and file names,
and the permalink map against the aliases. Stdlib only; fixtures are synthetic."""

import json
import re
import unittest

from helpers import FIXTURES, PNG, convert, make_media, only_items, run, scratch

BASIC = (FIXTURES / "basic.xml").read_text(encoding="utf-8")


def head(out, rel):
    return (out / rel).read_text().split("---\n")[1]


def meta(key, value):
    return (
        "<wp:postmeta><wp:meta_key><![CDATA[%s]]></wp:meta_key>"
        "<wp:meta_value><![CDATA[%s]]></wp:meta_value></wp:postmeta>" % (key, value)
    )


def first_post_with(extra):
    """Only the first post and its attachment, plus extra markup before </item>."""
    text = only_items("basic.xml", {"10", "11"})
    marker = "<wp:comment_status><![CDATA[open]]></wp:comment_status>"
    assert marker in text
    return text.replace(marker, marker + extra)


def log_of(out):
    return json.loads((out / "decision-log.json").read_text())


class DraftAllTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.proc, cls.out, _ = convert(BASIC, extra=["--draft-all"])

    def test_exit_zero(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stderr)

    def test_every_post_and_page_is_a_draft_but_keeps_its_alias(self):
        for rel in ("posts/first-post", "posts/second-post", "team"):
            text = (self.out / rel / "index.md").read_text()
            self.assertIn("draft: true\n", text, rel)
            self.assertNotIn("draft: false", text, rel)
        first = head(self.out, "posts/first-post/index.md")
        self.assertIn('  - "/2023/02/10/first-post/"\n', first)
        second = head(self.out, "posts/second-post/index.md")
        self.assertIn('  - "/second-post.html"\n', second)

    def test_default_run_keeps_the_wordpress_status(self):
        _, out, _ = convert(BASIC)
        self.assertIn("draft: false\n", (out / "posts/first-post/index.md").read_text())

    def test_review_list_names_every_page_and_the_reasons(self):
        review = {e["file"]: e["reasons"] for e in log_of(self.out)["review"]}
        self.assertEqual(
            sorted(review),
            ["hidden-draft/index.md", "posts/first-post/index.md", "posts/second-post/index.md", "team/index.md"],
        )
        self.assertIn("migrated-draft", review["posts/first-post/index.md"])
        self.assertIn("affiliate-links", review["posts/first-post/index.md"])
        self.assertIn("approved-comments", review["posts/first-post/index.md"])
        self.assertIn("affiliate-links", review["posts/second-post/index.md"])
        self.assertNotIn("affiliate-links", review["team/index.md"])


class AltTextTests(unittest.TestCase):
    def test_source_alt_is_used(self):
        _, out, _ = convert(BASIC)
        self.assertIn("![A striped test pattern](pic.png)", (out / "posts/first-post/index.md").read_text())
        self.assertFalse([w for w in log_of(out)["warnings"] if w["kind"] == "alt-todo"])

    def test_missing_alt_becomes_a_visible_todo_and_is_logged(self):
        text = BASIC.replace("A striped test pattern", "")
        proc, out, _ = convert(text, extra=["--draft-all"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        post = (out / "posts/first-post/index.md").read_text()
        self.assertIn("![TODO alt text](pic.png)", post)
        log = log_of(out)
        todo = [w for w in log["warnings"] if w["kind"] == "alt-todo"]
        self.assertEqual(todo, [{"file": "posts/first-post/index.md", "kind": "alt-todo", "detail": "pic.png"}])
        review = {e["file"]: e["reasons"] for e in log["review"]}
        self.assertIn("alt-todo", review["posts/first-post/index.md"])

    def test_attachment_title_is_not_alt_text(self):
        text = BASIC.replace("A striped test pattern", "").replace("<title>pic</title>", "<title>IMG_4821</title>", 1)
        _, out, _ = convert(text)
        post = (out / "posts/first-post/index.md").read_text()
        self.assertNotIn("IMG_4821", post)
        self.assertIn("![TODO alt text](pic.png)", post)

    def test_hostile_alt_cannot_break_out_of_the_image_syntax(self):
        text = BASIC.replace("A striped test pattern", "x](https://evil.invalid) <script>alert(1)</script> [y")
        _, out, _ = convert(text)
        post = (out / "posts/first-post/index.md").read_text()
        self.assertNotIn("](https://evil.invalid)", post)
        self.assertNotIn("<script", post)
        self.assertEqual(len(re.findall(r"!\[[^\]\n]*\]\(pic\.png\)", post)), 1)


class SyndicationTests(unittest.TestCase):
    URL = "https://social.example.invalid/@someone/109819136558223108"

    def test_recorded_announcement_becomes_the_syndicated_map(self):
        _, out, _ = convert(first_post_with(meta("_share_on_mastodon", "1") + meta("_share_on_mastodon_url", self.URL)))
        fm = head(out, "posts/first-post/index.md")
        self.assertIn("syndicate: false\n", fm)
        self.assertIn('syndicated:\n  mastodon: "%s"\n' % self.URL, fm)

    def test_no_recorded_announcement_means_no_map(self):
        _, out, _ = convert(first_post_with(meta("_share_on_mastodon", "1")))
        self.assertNotIn("syndicated", head(out, "posts/first-post/index.md"))

    def test_only_plain_https_urls_are_kept(self):
        bad = [
            "http://social.example.invalid/@a/1",
            "javascript:alert(1)",
            "https://social.example.invalid/@a/1\nsyndicate: true",
            'https://social.example.invalid/"><x',
            "https://user:pw@social.example.invalid/@a/1",
            "https://social.example.invalid/ a",
            "https://",
        ]
        for value in bad:
            with self.subTest(value=value):
                proc, out, _ = convert(first_post_with(meta("_share_on_mastodon_url", value)))
                self.assertEqual(proc.returncode, 0, proc.stderr)
                fm = head(out, "posts/first-post/index.md")
                self.assertNotIn("syndicated", fm)
                self.assertIn("syndicate: false\n", fm)
                kinds = [w["kind"] for w in log_of(out)["warnings"]]
                self.assertIn("bad-syndicated-url", kinds)

    def test_pages_never_get_a_map(self):
        text = only_items("basic.xml", {"13"}).replace("</item>", meta("_share_on_mastodon_url", self.URL) + "</item>")
        _, out, _ = convert(text)
        self.assertNotIn("syndicated", head(out, "team/index.md"))


class AnnotationTests(unittest.TestCase):
    def annotated(self, data, raw=None):
        work = scratch()
        path = work / "annotations.json"
        path.write_text(raw if raw is not None else json.dumps(data), encoding="utf-8")
        return convert(BASIC, extra=["--annotations", path])

    def test_archive_and_forward_link_land_in_front_matter(self):
        data = {
            "first-post": {"archive": "Written about a proposed ban.", "supersededBy": "/posts/second-post/"},
        }
        proc, out, _ = self.annotated(data)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        fm = head(out, "posts/first-post/index.md")
        self.assertIn('archive: "Written about a proposed ban."\n', fm)
        self.assertIn('supersededBy: "/posts/second-post/"\n', fm)
        self.assertNotIn("archive", head(out, "posts/second-post/index.md"))
        review = {e["file"]: e["reasons"] for e in log_of(out)["review"]}
        self.assertIn("annotation", review["posts/first-post/index.md"])

    def test_archive_true_is_allowed(self):
        proc, out, _ = self.annotated({"first-post": {"archive": True}})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("archive: true\n", head(out, "posts/first-post/index.md"))

    def test_an_annotation_for_a_slug_that_does_not_exist_is_a_warning(self):
        proc, out, _ = self.annotated({"no-such-post": {"archive": True}})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        kinds = [(w["kind"], w["detail"]) for w in log_of(out)["warnings"]]
        self.assertIn(("annotation-unmatched", "no-such-post"), kinds)

    def test_hostile_annotations_are_refused_and_nothing_is_written(self):
        hostile = [
            {"first-post": {"supersededBy": "javascript:alert(1)"}},
            {"first-post": {"supersededBy": "//evil.invalid/x"}},
            {"first-post": {"supersededBy": "http://evil.invalid/x"}},
            {"first-post": {"supersededBy": "/posts/a b/"}},
            {"first-post": {"supersededBy": "/posts/../../x/"}},
            {"first-post": {"archive": "line one\nsyndicate: true"}},
            {"first-post": {"archive": "x" * 400}},
            {"first-post": {"archive": ["not", "text"]}},
            {"first-post": {"title": "Overwrite the title"}},
            {"first-post": {"draft": False}},
            {"first-post": "not an object"},
            ["not", "an", "object"],
        ]
        for data in hostile:
            with self.subTest(data=data):
                proc, out, _ = self.annotated(data)
                self.assertEqual(proc.returncode, 2, proc.stderr)
                self.assertFalse(out.exists())
                self.assertNotIn("evil.invalid", proc.stderr)

    def test_duplicate_keys_and_bad_json_are_refused(self):
        for raw in ('{"a": {"archive": true}, "a": {"archive": true}}', "{not json", "", "﻿[]"):
            with self.subTest(raw=raw):
                proc, out, _ = self.annotated(None, raw=raw)
                self.assertEqual(proc.returncode, 2, proc.stderr)
                self.assertFalse(out.exists())

    def test_missing_file_is_a_usage_error(self):
        work = scratch()
        proc, out, _ = convert(BASIC, extra=["--annotations", work / "nope.json"])
        self.assertEqual(proc.returncode, 2)

    def test_the_committed_annotations_file_is_valid_and_matches_real_slugs(self):
        from helpers import TOOL_DIR

        path = TOOL_DIR / "annotations.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(data), 2)
        proc, out, _ = convert(BASIC, extra=["--annotations", path])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for slug in data:
            self.assertRegex(slug, r"^[a-z0-9-]+$")
        self.assertTrue(any("tiktok" in s for s in data))
        self.assertTrue(any("twitch-and-toot" in s for s in data))


class HostilePermalinkTests(unittest.TestCase):
    def alias_lines(self, link):
        text = only_items("basic.xml", {"12"}).replace(
            "<link>https://example.invalid/second-post.html</link>", "<link>%s</link>" % link
        )
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        fm = head(out, "posts/second-post/index.md")
        return fm, log_of(out)

    def test_whitespace_and_control_characters_are_not_aliased(self):
        for link in (
            "https://example.invalid/a\n/b/",
            "https://example.invalid/a b/",
            "https://example.invalid/a\t/",
            "https://example.invalid/a&quot;b/",
            "https://example.invalid/a&#13;&#10;/x/",
            "https://example.invalid/x\\y/",
        ):
            with self.subTest(link=link):
                fm, log = self.alias_lines(link)
                self.assertNotIn("aliases", fm)
                self.assertIn("bad-old-permalink", [w["kind"] for w in log["warnings"]])

    def test_traversal_and_double_slash_are_not_aliased(self):
        for link in ("https://example.invalid//evil.invalid/x/", "https://example.invalid/a/../b/", "https://example.invalid/./b/"):
            with self.subTest(link=link):
                fm, log = self.alias_lines(link)
                self.assertNotIn("aliases", fm)
                self.assertIn("bad-old-permalink", [w["kind"] for w in log["warnings"]])

    def test_non_ascii_permalink_is_percent_encoded(self):
        fm, log = self.alias_lines("https://example.invalid/café-notes/")
        self.assertIn('  - "/caf%C3%A9-notes/"\n', fm)
        self.assertFalse([w for w in log["warnings"] if w["kind"] == "bad-old-permalink"])

    def test_alias_of_the_pages_own_new_url_is_dropped(self):
        fm, _ = self.alias_lines("https://example.invalid/posts/second-post/")
        self.assertNotIn("aliases", fm)

    def test_query_style_permalink_has_no_alias_and_no_warning(self):
        fm, log = self.alias_lines("https://example.invalid/?p=12")
        self.assertNotIn("aliases", fm)


class BundleNameTests(unittest.TestCase):
    def test_hostile_media_file_names_are_made_safe(self):
        work = scratch()
        wxr = work / "export.xml"
        names = ["my pic (1).png", "a](b)c.png"]
        media = work / "media" / "uploads" / "2023" / "02"
        media.mkdir(parents=True)
        for n in names:
            (media / n).write_bytes(PNG)
        html = "".join(
            '<p><img src="https://example.invalid/wp-content/uploads/2023/02/%s" alt="ok"/></p>'
            % n.replace(" ", "%20").replace(" ", "%20")
            for n in names
        )
        text = only_items("basic.xml", {"12"}).replace(
            "<p>Two links:", html + "<p>Two links:"
        )
        wxr.write_text(text, encoding="utf-8")
        out = work / "out"
        proc = run(["--wxr", wxr, "--out", out, "--media", work / "media" / "uploads"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        post = (out / "posts/second-post/index.md").read_text()
        files = sorted(p.name for p in (out / "posts/second-post").iterdir() if p.suffix == ".png")
        self.assertEqual(len(files), 2)
        for name in files:
            self.assertRegex(name, r"^[A-Za-z0-9._-]+$")
            self.assertIn("](%s)" % name, post)


class PostsOnlyTests(unittest.TestCase):
    def test_pages_are_listed_not_written(self):
        proc, out, _ = convert(BASIC, extra=["--draft-all", "--posts-only"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse((out / "team").exists())
        self.assertFalse((out / "hidden-draft").exists())
        self.assertTrue((out / "posts/first-post/index.md").exists())
        log = log_of(out)
        self.assertEqual(log["summary"]["pages"], 0)
        self.assertEqual(log["summary"]["posts"], 2)
        self.assertEqual(
            sorted((p["slug"], p["old"]) for p in log["pages_not_migrated"]),
            [("hidden-draft", None), ("team", "/team/")],
        )
        pmap = json.loads((out / "permalink-map.json").read_text())
        self.assertEqual(sorted(e["type"] for e in pmap), ["post", "post"])

    def test_default_run_still_writes_pages(self):
        _, out, _ = convert(BASIC)
        self.assertTrue((out / "team/index.md").exists())
        self.assertEqual(log_of(out)["pages_not_migrated"], [])


class RedirectMapTests(unittest.TestCase):
    def test_every_old_permalink_is_an_alias_of_exactly_its_page(self):
        proc, out, _ = convert(BASIC, extra=["--draft-all"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        pmap = json.loads((out / "permalink-map.json").read_text())
        seen = {}
        for entry in pmap:
            if not entry["old"]:
                continue
            fm = head(out, entry["file"])
            if entry["old"].rstrip("/") == entry["new"].rstrip("/"):
                self.assertNotIn("aliases", fm)
                continue
            self.assertIn('  - "%s"\n' % entry["old"], fm)
            self.assertNotIn(entry["old"], seen, "two pages claim %s" % entry["old"])
            seen[entry["old"]] = entry["new"]
        self.assertEqual(
            seen,
            {"/2023/02/10/first-post/": "/posts/first-post/", "/second-post.html": "/posts/second-post/"},
        )
        self.assertEqual(json.loads(proc.stdout)["aliases"], len(seen))
        # No alias may shadow a real page.
        self.assertFalse(set(a.rstrip("/") for a in seen) & set(e["new"].rstrip("/") for e in pmap))


if __name__ == "__main__":
    unittest.main()
