import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from helpers import (
    CONVERT,
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


DISCLOSURE = "As an Amazon Associate I earn from qualifying purchases."


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
            ["about", "hidden-draft", "posts/first-post", "posts/second-post"],
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
        draft = (self.out / "hidden-draft/index.md").read_text()
        self.assertIn("draft: true\n", draft)
        self.assertNotIn("aliases", draft)
        about = (self.out / "about/index.md").read_text()
        self.assertIn("draft: false\n", about)
        self.assertIn('url: "/about/"\n', about)
        # The old permalink equals the new URL: an alias would overwrite the page.
        self.assertNotIn("aliases", about)

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
            self.assertEqual(entry["disclosure"], "added")
        self.assertEqual(entries[0]["file"], "posts/first-post/index.md")
        self.assertEqual(self.post.count(DISCLOSURE), 1)

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
        self.assertEqual(by_id[13]["new"], "/about/")
        self.assertEqual(by_id[14]["old"], None)
        self.assertTrue(by_id[14]["draft"])


class RootPageTests(unittest.TestCase):
    def page_text(self, **changes):
        text = only_items("basic.xml", {"13"})
        for old, new in changes.items():
            text = text.replace(old, new)
        return text

    def test_page_with_a_different_old_permalink_keeps_its_alias(self):
        text = only_items("basic.xml", {"13"}).replace("example.invalid/about/", "example.invalid/old/about-us/")
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        page = (out / "about/index.md").read_text()
        self.assertIn('url: "/about/"\n', page)
        self.assertIn('  - "/old/about-us/"\n', page)
        pmap = json.loads((out / "permalink-map.json").read_text())
        self.assertEqual(pmap[0]["old"], "/old/about-us/")
        self.assertEqual(pmap[0]["new"], "/about/")
        self.assertEqual(pmap[0]["file"], "about/index.md")

    def test_posts_stay_under_posts_without_a_url_key(self):
        proc, out, _ = basic()
        post = (out / "posts/first-post/index.md").read_text()
        self.assertNotIn("\nurl:", post)

    def test_page_slug_colliding_with_a_section_is_refused(self):
        for slug in ("posts", "journal"):
            text = only_items("basic.xml", {"13"}).replace("<![CDATA[about]]>", "<![CDATA[%s]]>" % slug)
            proc, out, _ = convert(text)
            self.assertEqual(proc.returncode, 2, slug)
            self.assertIn("collides", proc.stderr)
            self.assertFalse(out.exists())

    def test_page_slug_colliding_with_a_repo_top_level_directory_is_refused(self):
        # static/ and content/ both publish top-level paths.
        names = sorted(
            p.name for base in ("content", "static") for p in (REPO / base).iterdir() if p.is_dir()
        )
        self.assertTrue(names, "no top-level directories found to test against")
        text = only_items("basic.xml", {"13"}).replace("<![CDATA[about]]>", "<![CDATA[%s]]>" % names[0])
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 2)
        self.assertFalse(out.exists())

    def test_non_colliding_slug_still_converts(self):
        proc, out, _ = convert(only_items("basic.xml", {"13"}))
        self.assertEqual(proc.returncode, 0, proc.stderr)


class EmptyPageTests(unittest.TestCase):
    def test_empty_body_page_is_skipped_and_logged(self):
        text = only_items("basic.xml", {"13", "14"}).replace("<p>About this fixture site.</p>", "")
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse((out / "about").exists())
        self.assertTrue((out / "hidden-draft/index.md").exists())
        log = json.loads((out / "decision-log.json").read_text())
        self.assertEqual(len(log["skipped"]), 1)
        entry = log["skipped"][0]
        self.assertEqual(entry["id"], 13)
        self.assertEqual(entry["reason"], "empty body")
        self.assertEqual(log["summary"]["pages_skipped_empty"], 1)
        self.assertEqual(log["summary"]["pages"], 1)
        pmap = json.loads((out / "permalink-map.json").read_text())
        self.assertEqual([e["id"] for e in pmap], [14])

    def test_whitespace_only_conversion_counts_as_empty(self):
        text = only_items("basic.xml", {"13"}).replace("<p>About this fixture site.</p>", "<p> </p><div></div>")
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse((out / "about").exists())

    def test_empty_post_is_not_skipped(self):
        text = only_items("basic.xml", {"12"}).replace(
            '<p>Two links: <a href="https://amzn.to/xyz789">one</a> and <a href="https://amzn.to/xyz789">again</a>. Tom &amp; Jerry.</p>',
            "",
        )
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((out / "posts/second-post/index.md").exists())

    def test_no_skips_gives_empty_list(self):
        proc, out, _ = basic()
        self.assertEqual(json.loads((out / "decision-log.json").read_text())["skipped"], [])


class DisclosureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.proc, cls.out, _ = basic()
        cls.first = (cls.out / "posts/first-post/index.md").read_text()
        cls.second = (cls.out / "posts/second-post/index.md").read_text()
        cls.log = json.loads((cls.out / "decision-log.json").read_text())

    def test_once_per_post_even_with_several_links(self):
        self.assertEqual(self.first.count(DISCLOSURE), 1)
        self.assertEqual(self.second.count(DISCLOSURE), 1)
        self.assertTrue(self.second.rstrip().endswith(DISCLOSURE))

    def test_post_without_an_affiliate_link_gets_none(self):
        text = only_items("basic.xml", {"12"}).replace("https://amzn.to/xyz789", "https://example.invalid/x")
        proc, out, _ = convert(text)
        self.assertNotIn(DISCLOSURE, (out / "posts/second-post/index.md").read_text())
        log = json.loads((out / "decision-log.json").read_text())
        self.assertEqual(log["disclosures"], [])

    def test_pages_never_get_it(self):
        text = only_items("basic.xml", {"13"}).replace(
            "<p>About this fixture site.</p>", '<p><a href="https://amzn.to/pg">x</a></p>'
        )
        proc, out, _ = convert(text)
        self.assertNotIn(DISCLOSURE, (out / "about/index.md").read_text())

    def test_decision_log_records_each_post(self):
        files = [d["file"] for d in self.log["disclosures"]]
        self.assertEqual(files, ["posts/first-post/index.md", "posts/second-post/index.md"])
        self.assertTrue(all(d["added"] is True for d in self.log["disclosures"]))
        self.assertEqual(self.log["summary"]["disclosures_added"], 2)

    def test_already_disclosed_body_is_not_doubled(self):
        text = only_items("basic.xml", {"12"}).replace(
            "Tom &amp; Jerry.</p>", "Tom &amp; Jerry.</p><p>%s</p>" % DISCLOSURE
        )
        proc, out, _ = convert(text)
        self.assertEqual((out / "posts/second-post/index.md").read_text().count(DISCLOSURE), 1)

    def test_rerun_does_not_double(self):
        text = (FIXTURES / "basic.xml").read_text(encoding="utf-8")
        _, out1, _ = convert(text)
        _, out2, _ = convert(text)
        self.assertEqual(tree_digest(out1), tree_digest(out2))


class SyndicateTests(unittest.TestCase):
    def flags(self, out, rel):
        head = (out / rel).read_text().split("---\n")[1]
        return [l for l in head.splitlines() if l.startswith("syndicate:")]

    def test_post_mirrors_the_old_share_flag_and_pages_are_false(self):
        proc, out, _ = basic()
        self.assertEqual(self.flags(out, "posts/first-post/index.md"), ["syndicate: true"])
        self.assertEqual(self.flags(out, "posts/second-post/index.md"), ["syndicate: false"])
        self.assertEqual(self.flags(out, "about/index.md"), ["syndicate: false"])

    def test_page_with_the_share_flag_stays_false(self):
        text = only_items("basic.xml", {"13"}).replace(
            "</item>",
            "<wp:postmeta><wp:meta_key><![CDATA[_share_on_mastodon]]></wp:meta_key>"
            "<wp:meta_value><![CDATA[1]]></wp:meta_value></wp:postmeta></item>",
        )
        proc, out, _ = convert(text)
        self.assertEqual(self.flags(out, "about/index.md"), ["syndicate: false"])


class EscapingTests(unittest.TestCase):
    def test_markdown_specials_in_text_are_escaped(self):
        text = only_items("basic.xml", {"13"}).replace(
            "<p>About this fixture site.</p>",
            "<p>2 * 3 [not a link] _x_ &lt;b&gt;</p><p># not a heading</p>",
        )
        proc, out, _ = convert(text)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = (out / "about/index.md").read_text().split("---\n")[2]
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
        cls.page = (cls.out / "builder-page/index.md").read_text()

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
        self.assertFalse((self.out / "header-template").exists())
        self.assertFalse((self.out / "22").exists())

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
        self.assertTrue((work / "out" / "about/index.md").exists())


class ScrubStdinTests(unittest.TestCase):
    """--scrub-terms - reads the terms from stdin (placeholder terms only)."""

    TERMS = "employer:ACME-PLACEHOLDER\nhostname:box01.lab.invalid\nserial:SN-0000-TEST\n"

    def run_stdin(self, wxr_text, stdin, extra=()):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(wxr_text, encoding="utf-8")
        out = work / "out"
        proc = subprocess.run(
            [sys.executable, "-I", str(CONVERT), "--wxr", str(wxr), "--out", str(out), "--scrub-terms", "-"]
            + [str(a) for a in extra],
            input=stdin,
            capture_output=True,
            text=True,
            cwd=tempfile.gettempdir(),
            check=False,
        )
        return proc, out

    def test_finding_from_stdin_terms_exits_3_and_writes_nothing(self):
        text = only_items("scrub_edge.xml", {"31"}).replace("near-misses", "acme-placeholder-news")
        proc, out = self.run_stdin(text, self.TERMS)
        self.assertEqual(proc.returncode, 3, proc.stderr)
        self.assertFalse(out.exists())
        self.assertIn("category=employer", proc.stderr)

    def test_terms_never_appear_in_any_output(self):
        text = only_items("scrub_edge.xml", {"31"}).replace("near-misses", "acme-placeholder-news")
        proc, out = self.run_stdin(text, self.TERMS)
        self.assertEqual(proc.returncode, 3, proc.stderr)
        combined = proc.stdout + proc.stderr
        for value in ("ACME-PLACEHOLDER", "acme-placeholder", "box01", "SN-0000"):
            self.assertNotIn(value, combined)
        self.assertFalse(out.exists())

    def test_unmatched_stdin_terms_exit_0_mark_ran_and_leak_nowhere(self):
        proc, out = self.run_stdin(only_items("scrub_edge.xml", {"31"}), self.TERMS, ["--require-terms"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for category in ("employer", "hostname", "serial"):
            self.assertIn("scrub %s: ran" % category, proc.stderr)
        self.assertNotIn("NOT RUN", proc.stderr)
        self.assertTrue(out.is_dir())
        for base, _, names in os.walk(out):
            for name in names:
                data = (Path(base) / name).read_bytes().lower()
                for value in (b"acme-placeholder", b"box01", b"sn-0000"):
                    self.assertNotIn(value, data, name)
        self.assertNotIn("ACME-PLACEHOLDER", proc.stdout + proc.stderr)

    def test_only_supplied_categories_are_marked_ran(self):
        proc, _ = self.run_stdin(only_items("scrub_edge.xml", {"31"}), "employer:ACME-PLACEHOLDER\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("scrub employer: ran", proc.stderr)
        self.assertIn("scrub hostname: NOT RUN", proc.stderr)
        self.assertIn("scrub serial: NOT RUN", proc.stderr)

    def test_allow_lines_work_from_stdin(self):
        proc, _ = self.run_stdin(only_items("scrub_edge.xml", {"33"}), "allow:H2O\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_require_terms_with_empty_stdin_exits_2(self):
        for stdin in ("", "  \n\t\n\n", "# only a comment\n"):
            proc, out = self.run_stdin(only_items("scrub_edge.xml", {"31"}), stdin, ["--require-terms"])
            self.assertEqual(proc.returncode, 2, repr(stdin))
            self.assertFalse(out.exists())

    def test_empty_stdin_without_require_terms_runs_with_not_run(self):
        proc, _ = self.run_stdin(only_items("scrub_edge.xml", {"31"}), "")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("scrub employer: NOT RUN", proc.stderr)

    def test_bad_stdin_line_exits_2_without_echoing_it(self):
        proc, out = self.run_stdin(only_items("scrub_edge.xml", {"31"}), "bogus:SECRETTERM\n")
        self.assertEqual(proc.returncode, 2)
        self.assertNotIn("SECRETTERM", proc.stdout + proc.stderr)
        self.assertFalse(out.exists())

    def test_allow_only_stdin_counts_as_empty_with_require_terms(self):
        for stdin in ("allow:H2O\n", "# c\nallow:H2O\n"):
            proc, out = self.run_stdin(only_items("scrub_edge.xml", {"31"}), stdin, ["--require-terms"])
            self.assertEqual(proc.returncode, 2, repr(stdin))
            self.assertFalse(out.exists())

    def test_unicode_line_separators_stay_inside_a_stdin_term(self):
        for sep in ("\u2028", "\u0085", "\x0c"):
            terms = "employer:ACME%sPLACEHOLDER\n" % sep
            proc, _ = self.run_stdin(only_items("scrub_edge.xml", {"31"}), terms, ["--require-terms"])
            self.assertEqual(proc.returncode, 0, (repr(sep), proc.stderr))
            self.assertIn("scrub employer: ran", proc.stderr)

    def test_cr_and_crlf_still_split_stdin_lines(self):
        proc, _ = self.run_stdin(
            only_items("scrub_edge.xml", {"31"}), "employer:ACME-PLACEHOLDER\rhostname:box01.lab.invalid\r\n"
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("scrub hostname: ran", proc.stderr)

    def test_repo_guard_still_applies_to_real_paths(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text((FIXTURES / "basic.xml").read_text(encoding="utf-8"))
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", REPO / "README.md"])
        self.assertEqual(proc.returncode, 2)
        self.assertIn("inside the repository", proc.stderr)


class ScrubTermsFileTests(unittest.TestCase):
    def run_file(self, content, extra=()):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"31"}), encoding="utf-8")
        terms = work / "terms.txt"
        terms.write_text(content, encoding="utf-8")
        return run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", terms] + list(extra)), work

    def test_empty_comment_or_allow_only_file_fails_require_terms(self):
        for content in ("", "\n  \n", "# c\n", "allow:H2O\n"):
            proc, work = self.run_file(content, ["--require-terms"])
            self.assertEqual(proc.returncode, 2, repr(content))
            self.assertFalse((work / "out").exists())

    def test_allow_only_file_still_runs_without_require_terms(self):
        proc, _ = self.run_file("allow:H2O\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_unicode_line_separators_stay_inside_a_file_term(self):
        proc, _ = self.run_file("employer:ACME\u2028PLACEHOLDER\n", ["--require-terms"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("scrub employer: ran", proc.stderr)

    def test_missing_terms_file_exits_2_without_echoing_the_path(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"31"}), encoding="utf-8")
        missing = work / "ACME-PLACEHOLDER-terms.txt"
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", missing])
        self.assertEqual(proc.returncode, 2, proc.stderr)
        self.assertNotIn("ACME-PLACEHOLDER", proc.stdout + proc.stderr)
        self.assertNotIn("unexpected", proc.stderr)
        self.assertFalse((work / "out").exists())

    def test_unreadable_terms_path_exits_2(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"31"}), encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", work])
        self.assertEqual(proc.returncode, 2, proc.stderr)


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

    def test_summary_says_which_categories_ran_without_terms(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("basic.xml", {"13"}), encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for c in ("callsign", "grid", "hostname-generic"):
            self.assertIn("scrub %s: ran" % c, proc.stderr)
        for c in ("employer", "hostname", "serial"):
            self.assertIn("scrub %s: NOT RUN" % c, proc.stderr)
        status = json.loads(proc.stdout)["scrub"]
        self.assertEqual(status["employer"], "NOT RUN")
        log = json.loads((work / "out" / "decision-log.json").read_text())
        self.assertEqual(log["summary"]["scrub"]["serial"], "NOT RUN")

    def test_summary_with_a_terms_file_marks_only_given_categories(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("basic.xml", {"13"}), encoding="utf-8")
        terms = work / "terms.txt"
        terms.write_text("employer:Acme Fixture\n", encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out", "--scrub-terms", terms])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("scrub employer: ran", proc.stderr)
        self.assertIn("scrub hostname: NOT RUN", proc.stderr)
        self.assertIn("scrub serial: NOT RUN", proc.stderr)
        self.assertNotIn("Acme", proc.stdout + proc.stderr)

    def test_summary_printed_when_findings_fail_the_run(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("scrub_edge.xml", {"32"}), encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out"])
        self.assertEqual(proc.returncode, 3)
        self.assertIn("scrub employer: NOT RUN", proc.stderr)

    def test_require_terms_exits_2_without_a_terms_file(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("basic.xml", {"13"}), encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out", "--require-terms"])
        self.assertEqual(proc.returncode, 2)
        self.assertIn("--require-terms", proc.stderr)
        self.assertFalse((work / "out").exists())

    def test_require_terms_passes_with_a_terms_file(self):
        work = scratch()
        wxr = work / "export.xml"
        wxr.write_text(only_items("basic.xml", {"13"}), encoding="utf-8")
        terms = work / "terms.txt"
        terms.write_text("employer:Acme Fixture\n", encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out", "--require-terms", "--scrub-terms", terms])
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_generic_private_host_is_caught_without_terms(self):
        work = scratch()
        text = only_items("basic.xml", {"13"}).replace("About this fixture site.", "Reach it at 192.168.7.7 or box.lan.")
        wxr = work / "export.xml"
        wxr.write_text(text, encoding="utf-8")
        proc = run(["--wxr", wxr, "--out", work / "out"])
        self.assertEqual(proc.returncode, 3)
        self.assertIn("category=hostname", proc.stderr)
        self.assertNotIn("192.168", proc.stdout + proc.stderr)
        self.assertNotIn("box.lan", proc.stdout + proc.stderr)
        terms = work / "terms.txt"
        terms.write_text("allow:192.168.7.7\nallow:box.lan\n", encoding="utf-8")
        ok = run(["--wxr", wxr, "--out", work / "out2", "--scrub-terms", terms])
        self.assertEqual(ok.returncode, 0, ok.stderr)

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
