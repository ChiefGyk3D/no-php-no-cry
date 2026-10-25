import json
import unittest
from pathlib import Path

from helpers import (
    FIXTURES,
    PNG,
    REPO,
    convert,
    make_media,
    only_items,
    run,
    scratch,
    tree_digest,
)


def basic():
    return convert((FIXTURES / "basic.xml").read_text(encoding="utf-8"))


class BasicConversionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.proc, cls.out, cls.work = basic()
        cls.post = (cls.out / "posts/first-post/index.md").read_text()

    def test_exit_zero(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stderr)

    def test_counts_on_stdout(self):
        counts = json.loads(self.proc.stdout)
        self.assertEqual(counts["posts"], 2)
        self.assertEqual(counts["pages"], 2)
        self.assertEqual(counts["drafts"], 1)
        self.assertEqual(counts["comments"], 1)
        self.assertEqual(counts["affiliate_links"], 3)
        self.assertEqual(counts["temp_host_links_rewritten"], 1)
        self.assertEqual(counts["images"], 1)

    def test_only_posts_and_pages_become_bundles(self):
        names = sorted(p.parent.relative_to(self.out).as_posix() for p in self.out.rglob("index.md"))
        self.assertEqual(
            names,
            ["pages/about", "pages/hidden-draft", "posts/first-post", "posts/second-post"],
        )

    def test_front_matter(self):
        head = self.post.split("---\n")[1]
        self.assertIn('title: "First Post"\n', head)
        self.assertIn("date: 2023-02-10T09:00:00-05:00\n", head)
        self.assertIn('slug: "first-post"\n', head)
        self.assertIn('categories: ["Reviews"]\n', head)
        self.assertIn('tags: ["alpha"]\n', head)
        self.assertIn("syndicate: true\n", head)
        self.assertIn("draft: false\n", head)
        self.assertIn('  - "/2023/02/10/first-post/"\n', head)

    def test_syndicate_false_without_the_old_flag(self):
        second = (self.out / "posts/second-post/index.md").read_text()
        self.assertIn("syndicate: false\n", second)

    def test_html_permalink_alias_kept_as_is(self):
        second = (self.out / "posts/second-post/index.md").read_text()
        self.assertIn('  - "/second-post.html"\n', second)
        self.assertNotIn('"/second-post.html/"', second)

    def test_draft_page(self):
        draft = (self.out / "pages/hidden-draft/index.md").read_text()
        self.assertIn("draft: true\n", draft)
        self.assertNotIn("aliases", draft)
        about = (self.out / "pages/about/index.md").read_text()
        self.assertIn("draft: false\n", about)
        self.assertIn('  - "/about/"\n', about)

    def test_body_markdown(self):
        self.assertIn("## A heading & more", self.post)
        self.assertIn("**bold**", self.post)
        self.assertIn("*italic*", self.post)
        self.assertIn("- one\n- two", self.post)
        self.assertIn('```\necho "hi"\nexit 0\n```', self.post)
        self.assertNotIn("<!--", self.post)
        self.assertNotIn("<p>", self.post)

    def test_image_beside_post_with_alt(self):
        self.assertIn("![A striped test pattern](pic.png)", self.post)
        self.assertEqual((self.out / "posts/first-post/pic.png").read_bytes(), PNG)

    def test_temp_host_links_rewritten_to_site_url(self):
        self.assertIn("(https://test-blog.chiefgyk3d.com/about/)", self.post)
        everything = "\n".join(p.read_text() for p in self.out.rglob("*.md"))
        self.assertNotIn("bluehost", everything)

    def test_affiliate_links_kept_and_logged(self):
        self.assertIn("(https://amzn.to/abc123)", self.post)
        log = json.loads((self.out / "decision-log.json").read_text())
        entries = log["affiliate_links"]
        self.assertEqual(len(entries), 3)
        for entry in entries:
            self.assertEqual(entry["decision"], "kept")
            self.assertEqual(entry["disclosure"], "not added")
        self.assertEqual(entries[0]["file"], "posts/first-post/index.md")
        self.assertNotIn("Disclosure", self.post)

    def test_only_approved_comments(self):
        comments = json.loads((self.out / "posts/first-post/comments.json").read_text())
        self.assertEqual(len(comments), 1)
        self.assertEqual(comments[0]["author"], "Reader One")
        self.assertEqual(comments[0]["content"], "Nice post.")
        blob = (self.out / "posts/first-post/comments.json").read_text()
        for private in ("reader@example.invalid", "192.0.2.7", "Pending", "Spam", "Pingback"):
            self.assertNotIn(private, blob)
        self.assertFalse((self.out / "posts/second-post/comments.json").exists())

    def test_activitypub_and_trash_dropped(self):
        everything = "\n".join(p.read_text() for p in self.out.rglob("*") if p.is_file() and p.suffix in {".md", ".json"})
        self.assertNotIn("Outbox entry", everything)
        self.assertNotIn("Note", everything)
        self.assertNotIn("Gone.", everything)

    def test_permalink_map(self):
        pmap = json.loads((self.out / "permalink-map.json").read_text())
        by_id = {e["id"]: e for e in pmap}
        self.assertEqual(len(pmap), 4)
        self.assertEqual(by_id[11]["old"], "/2023/02/10/first-post/")
        self.assertEqual(by_id[11]["new"], "/posts/first-post/")
        self.assertEqual(by_id[12]["old"], "/second-post.html")
        self.assertEqual(by_id[13]["new"], "/pages/about/")
        self.assertEqual(by_id[14]["old"], None)
        self.assertTrue(by_id[14]["draft"])


class EscapingTests(unittest.TestCase):
    def test_markdown_specials_in_text_are_escaped(self):
        text = only_items("basic.xml", {"13"}).replace(
            "<p>About this fixture site.</p>",
            "<p>2 * 3 [not a link] _x_ &lt;b&gt;</p><p># not a heading</p>",
        )
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = (out / "pages/about/index.md").read_text().split("---\n")[2]
        self.assertIn("2 \\* 3 \\[not a link\\] \\_x\\_ \\<b>", body)
        self.assertIn("\\# not a heading", body)


class MediaWarningTests(unittest.TestCase):
    def test_unsupported_and_missing_images_are_logged(self):
        text = only_items("basic.xml", {"10", "11"}).replace("pic.png", "pic.gif")
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(text, encoding="utf-8")
        media = make_media(work / "media")
        (media / "2023" / "02" / "pic.gif").write_bytes(PNG)
        out = work / "out"
        proc = run(["--wxr", wxr, "--out", out, "--media", media])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        kinds = [w["kind"] for w in json.loads((out / "decision-log.json").read_text())["warnings"]]
        self.assertEqual(kinds, ["unsupported-image-format"])
        # No media directory at all: the reference is logged as missing.
        proc = run(["--wxr", wxr, "--out", work / "out2", "--media", work / "nowhere"])
        kinds = [w["kind"] for w in json.loads((work / "out2" / "decision-log.json").read_text())["warnings"]]
        self.assertEqual(kinds, ["missing-media-image"])


class IdempotenceTests(unittest.TestCase):
    def test_same_input_byte_identical_output(self):
        text = (FIXTURES / "basic.xml").read_text(encoding="utf-8")
        first, out1, _ = convert(text)
        second, out2, _ = convert(text)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        d1, d2 = tree_digest(out1), tree_digest(out2)
        self.assertGreater(len(d1), 5)
        self.assertEqual(d1, d2)

    def test_rerun_into_same_out_replaces_without_leftovers(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text((FIXTURES / "basic.xml").read_text(encoding="utf-8"))
        media = make_media(work / "media")
        out = work / "out"
        args = ["--wxr", wxr, "--out", out, "--media", media]
        self.assertEqual(run(args).returncode, 0)
        before = tree_digest(out)
        (out / "stale.txt").write_text("stale")
        self.assertEqual(run(args).returncode, 0)
        self.assertEqual(tree_digest(out), before)

    def test_refuses_a_foreign_nonempty_out(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text((FIXTURES / "basic.xml").read_text(encoding="utf-8"))
        out = work / "out"
        out.mkdir()
        (out / "precious.txt").write_text("keep me")
        proc = run(["--wxr", wxr, "--out", out])
        self.assertEqual(proc.returncode, 2)
        self.assertTrue((out / "precious.txt").exists())


class ColibriTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.proc, cls.out, _ = convert((FIXTURES / "colibri.xml").read_text(), media=False)
        cls.page = (cls.out / "pages/builder-page/index.md").read_text()

    def test_text_comes_from_the_builder_json(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stderr)
        self.assertIn("## Welcome & hello", self.page)
        self.assertIn("Some **builder** text with [a link](https://example.invalid/x).", self.page)
        self.assertIn("## [Linked heading](https://example.invalid/target)", self.page)
        self.assertIn("[Press me](https://example.invalid/button)", self.page)
        self.assertIn("[Elsewhere](https://example.invalid/elsewhere)", self.page)

    def test_template_and_style_data_ignored(self):
        everything = "\n".join(p.read_text() for p in self.out.rglob("*.md"))
        self.assertNotIn("TEMPLATE_MARKUP_SENTINEL", everything)
        self.assertNotIn("STYLE_SENTINEL", everything)
        self.assertFalse((self.out / "pages/header-template").exists())
        self.assertFalse((self.out / "pages/22").exists())

    def test_counted_as_builder_page(self):
        self.assertEqual(json.loads(self.proc.stdout)["builder_pages"], 1)


class SafetyTests(unittest.TestCase):
    def test_refuses_wxr_inside_the_repo(self):
        out = scratch() / "out"
        proc = run(["--wxr", FIXTURES / "basic.xml", "--out", out])
        self.assertEqual(proc.returncode, 2)
        self.assertFalse(out.exists())

    def test_refuses_out_inside_the_repo(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text((FIXTURES / "basic.xml").read_text(encoding="utf-8"))
        for out in (REPO / "tmp" / "wxr-out", REPO / "content"):
            proc = run(["--wxr", wxr, "--out", out])
            self.assertEqual(proc.returncode, 2, out)
            self.assertFalse((REPO / "tmp" / "wxr-out").exists())

    def test_refuses_terms_file_inside_the_repo(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text((FIXTURES / "basic.xml").read_text(encoding="utf-8"))
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", REPO / "README.md"])
        self.assertEqual(proc.returncode, 2)

    def test_refuses_entity_declarations(self):
        text = (FIXTURES / "basic.xml").read_text(encoding="utf-8")
        text = text.replace("<rss", '<!DOCTYPE rss [<!ENTITY x "y">]>\n<rss', 1)
        proc, out, _ = convert(text)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(out.exists())

    def test_default_out_is_beside_the_input_not_in_the_repo(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("basic.xml", {"13"}))
        proc = run(["--wxr", wxr])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((work / "out" / "pages/about/index.md").exists())


class ScrubIntegrationTests(unittest.TestCase):
    def terms(self, work):
        path = work / "terms.txt"
        path.write_text(
            "employer:Acme Fixture\nhostname:box01.lab.invalid\nserial:SN-0000-TEST\n",
            encoding="utf-8",
        )
        return path

    def run_tripwire(self, extra=()):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"32"}), encoding="utf-8")
        out = work / "out"
        proc = run(["--wxr", wxr, "--out", out, "--scrub-terms", self.terms(work)] + list(extra))
        return proc, out

    def test_findings_fail_the_run_and_write_nothing(self):
        proc, out = self.run_tripwire()
        self.assertEqual(proc.returncode, 3)
        self.assertFalse(out.exists())

    def test_findings_name_category_file_and_line_only(self):
        proc, _ = self.run_tripwire()
        lines = [l for l in proc.stderr.splitlines() if l.startswith("scrub finding:")]
        got = {(l.split("category=")[1].split()[0]) for l in lines}
        self.assertEqual(got, {"callsign", "grid", "employer", "hostname", "serial"})
        self.assertTrue(all("file=posts/tripwire/index.md" in l or "file=posts/tripwire/comments.json" in l for l in lines))
        self.assertTrue(all("line=" in l for l in lines))
        callsign_lines = {l for l in lines if "category=callsign" in l}
        self.assertEqual(len(callsign_lines), 1)

    def test_matched_values_never_reach_stdout_or_stderr(self):
        proc, _ = self.run_tripwire()
        combined = proc.stdout + proc.stderr
        for value in ("N0CALL", "N0TST", "FN31pr", "FN31", "Acme", "Fixture Corp", "box01", "SN-0000"):
            self.assertNotIn(value, combined)

    def test_clean_near_misses_pass(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"31"}), encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", self.terms(work)])
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_shape_checks_run_without_a_terms_file(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"32"}), encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out"])
        self.assertEqual(proc.returncode, 3)
        self.assertFalse((work / "out").exists())

    def test_allow_line_clears_a_false_positive(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"33"}), encoding="utf-8")
        blocked = run(["--wxr", wxr, "--out", work / "blocked"])
        self.assertEqual(blocked.returncode, 3)
        terms = work / "terms.txt"
        terms.write_text("allow:H2O\n", encoding="utf-8")
        allowed = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", terms])
        self.assertEqual(allowed.returncode, 0, allowed.stderr)

    def test_a_matching_slug_is_not_echoed(self):
        work = scratch()
        text = only_items("scrub_edge.xml", {"31"}).replace("near-misses", "acmefixture-news")
        wxr = work / "export.xml"
        wxr.write_text(text, encoding="utf-8")
        terms = work / "terms.txt"
        terms.write_text("employer:acmefixture\n", encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", terms])
        self.assertEqual(proc.returncode, 3)
        self.assertIn("category=employer", proc.stderr)
        self.assertNotIn("acmefixture", (proc.stdout + proc.stderr).lower())

    def test_bad_terms_file_does_not_echo_its_content(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("basic.xml", {"13"}), encoding="utf-8")
        terms = work / "terms.txt"
        terms.write_text("bogus:SECRETTERM\n", encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", terms])
        self.assertEqual(proc.returncode, 2)
        self.assertNotIn("SECRETTERM", proc.stdout + proc.stderr)


class UnexpectedErrorTests(unittest.TestCase):
    def test_parse_failure_does_not_echo_the_input(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text("<rss><channel>SECRETCONTENT</rss>", encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out"])
        self.assertEqual(proc.returncode, 1)
        self.assertNotIn("SECRETCONTENT", proc.stdout + proc.stderr)
        self.assertFalse((work / "out").exists())


class MediaConfinementTests(unittest.TestCase):
    def _run_with_target(self, make_target):
        work = scratch()
        media = make_media(work / "media")
        secret = work / "secret.png"
        secret.write_bytes(PNG)
        make_target(media, secret)
        text = only_items("basic.xml", {"10", "11"}).replace(
            "uploads/2023/02/pic.png", "uploads/" + make_target.ref(media, secret)
        )
        wxr = work / "export.xml"
        wxr.write_text(text, encoding="utf-8")
        out = work / "out"
        proc = run(["--wxr", wxr, "--out", out, "--media", media])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return [p.name for p in out.rglob("*.png")]

    def test_absolute_path_after_uploads_is_not_followed(self):
        def make(media, secret):
            pass

        make.ref = lambda media, secret: "/" + str(secret).lstrip("/")
        self.assertEqual(self._run_with_target(make), [])

    def test_symlink_leaving_the_media_root_is_not_followed(self):
        def make(media, secret):
            (media / "2023" / "02" / "link.png").symlink_to(secret)

        make.ref = lambda media, secret: "2023/02/link.png"
        self.assertEqual(self._run_with_target(make), [])


if __name__ == "__main__":
    unittest.main()
