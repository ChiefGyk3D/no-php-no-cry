import unittest

from helpers import load_module, scratch

scrub = load_module("scrub")


def rules(*terms, allow=()):
    return scrub.Rules(list(terms), allow)


class ShapeTests(unittest.TestCase):
    def cats(self, text, r=None):
        return [f.category for f in scrub.scan_text(text, "f", r or rules())]

    def test_callsign_placeholders_match(self):
        self.assertEqual(self.cats("de N0CALL"), ["callsign"])
        self.assertEqual(self.cats("de N0TST"), ["callsign"])

    def test_callsign_shapes(self):
        for text in ("W1AW", "KD2ABC", "AA1A", "VE3XYZ", "(N0CALL)", "N0CALL/P"):
            self.assertEqual(self.cats(text), ["callsign"], text)

    def test_callsign_near_misses_do_not_match(self):
        for text in (
            "ChiefGyk3D",
            "CVE-2023-1234",
            "AES256",
            "MP3",
            "X86_64",
            "PS5",
            "IPv6",
            "n0call",
            "ABCD1EF",
            "2023-02-10T09:00:00-05:00",
        ):
            self.assertEqual(self.cats(text), [], text)

    def test_grid_shapes(self):
        for text in ("FN31pr", "FN31PR", "FN31", "IO91wm"):
            self.assertEqual(self.cats(text), ["grid"], text)

    def test_grid_near_misses_do_not_match(self):
        for text in ("ZZ99", "FN3", "FN31p", "FN31prx", "fn31pr", "XFN31pr"):
            self.assertEqual(self.cats(text), [], text)

    def test_allow_exempts_a_token(self):
        self.assertEqual(self.cats("H2O"), ["callsign"])
        self.assertEqual(self.cats("H2O", rules(allow=["H2O"])), [])

    def test_terms_are_case_insensitive_and_per_category(self):
        r = rules(
            ("employer", "Acme Fixture"),
            ("hostname", "box01.lab.invalid"),
            ("serial", "SN-0000-TEST"),
        )
        self.assertEqual(self.cats("at ACME fixture corp", r), ["employer"])
        self.assertEqual(self.cats("ssh box01.lab.invalid", r), ["hostname"])
        self.assertEqual(self.cats("sn-0000-test", r), ["serial"])
        self.assertEqual(self.cats("nothing to see", r), [])

    def test_line_numbers(self):
        text = "clean\nclean\nde N0CALL\nclean\nFN31pr\n"
        got = [(f.category, f.line) for f in scrub.scan_text(text, "a.md", rules())]
        self.assertEqual(got, [("callsign", 3), ("grid", 5)])


class NoLeakTests(unittest.TestCase):
    def test_finding_has_no_matched_text(self):
        found = scrub.scan_text("de N0CALL in FN31pr", "a.md", rules())
        for finding in found:
            self.assertNotIn("N0CALL", repr(finding))
            self.assertNotIn("FN31pr", scrub.format_finding(finding))

    def test_path_match_is_reported_without_the_path(self):
        r = rules(("employer", "acmefixture"))
        files = {"posts/acmefixture-news/index.md": b"clean\n", "posts/ok/index.md": b"x"}
        found = scrub.scan_files(files, r)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].category, "employer")
        self.assertNotIn("acmefixture", scrub.format_finding(found[0]))

    def test_binary_entries_are_path_scanned_only(self):
        found = scrub.scan_files({"posts/a/pic.png": None}, rules())
        self.assertEqual(found, [])


class TermsFileTests(unittest.TestCase):
    def write(self, text):
        path = scratch() / "terms.txt"
        path.write_text(text, encoding="utf-8")
        return path

    def test_loads_categories_comments_and_allow(self):
        path = self.write(
            "# comment\n\nemployer: Acme Fixture\nhostname:box01.lab.invalid\n"
            "serial:SN-0000-TEST\nallow:H2O\n"
        )
        r = scrub.load_terms(path)
        self.assertEqual(r.terms["employer"], ["acme fixture"])
        self.assertEqual(r.allow, {"H2O"})

    def test_bad_lines_name_the_line_not_the_content(self):
        for text in ("no colon here SECRETTERM\n", "bogus:SECRETTERM\n", "employer:\n"):
            with self.assertRaises(scrub.TermsError) as ctx:
                scrub.load_terms(self.write(text))
            self.assertIn("line 1", str(ctx.exception))
            self.assertNotIn("SECRETTERM", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
