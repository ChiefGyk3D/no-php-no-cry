"""Doc test for the counter reconciliation note and report footer (issue 301).

Usage: python3 -I scripts/test-analytics-reconciliation.py

Collects loosely (any file under docs/ named analytics-reconciliation.md) and
asserts strictly. check_note() is run on the real note and on broken copies so
the guard is shown to bite.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTE = ROOT / "docs" / "analytics-reconciliation.md"

CAUSES = {
    "script blockers": r"script blockers?",
    "crawlers": r"crawlers",
    "prefetches": r"prefetch",
    "link previews": r"link previews",
    "global privacy control": r"global privacy control",
    "do not track": r"do not track",
    "utc days": r"utc days?",
    "5 view floor": r"5 view floor",
    "fail-open": r"fail-open",
}
RULES = [
    r"blog counter is the source for pages, sources and clicks",
    r"cloudflare is the source for page timing",
    r"neither is a billing figure",
]
FOOTER = re.compile(r"<!-- report-footer:start -->\n(.*?)\n<!-- report-footer:end -->", re.S)


def check_note(text):
    """Return a list of problems; empty means the note is complete."""
    problems = []
    low = " ".join(text.lower().split())
    for name, pat in CAUSES.items():
        if not re.search(pat, low):
            problems.append("cause missing: " + name)
    for pat in RULES:
        if not re.search(pat, low):
            problems.append("rule missing: " + pat)
    if re.search(r"\b(is|are) exact\b", re.sub(r"neither (number )?is exact", "", low)):
        problems.append("claims a counter is exact")
    m = FOOTER.search(text)
    if not m:
        problems.append("footer block missing")
    else:
        foot = " ".join(m.group(1).lower().split())
        for name, pat in CAUSES.items():
            if not re.search(pat, foot):
                problems.append("footer lacks cause: " + name)
        for pat in RULES[:3]:
            core = pat.replace("blog counter is the source for pages, sources and clicks", "blog counter for pages, sources and clicks")
            core = core.replace("cloudflare is the source for page timing", "cloudflare for page timing")
            if not re.search(core, foot):
                problems.append("footer lacks: " + core)
        if "neither is exact" not in foot:
            problems.append("footer lacks the not-exact statement")
    for ch in (chr(0x2014), chr(0x2013)):
        if ch in text:
            problems.append("em or en dash present")
    return problems


class ReconciliationNote(unittest.TestCase):
    def test_note_present_and_complete(self):
        self.assertTrue(NOTE.is_file(), "missing " + str(NOTE))
        self.assertEqual(check_note(NOTE.read_text(encoding="utf-8")), [])

    def test_guard_bites(self):
        text = NOTE.read_text(encoding="utf-8")
        for broken in (
            re.sub("(?i)fail-open", "dropped", text),
            text.replace("billing figure", "money"),
            text.replace("<!-- report-footer:start -->", ""),
            re.sub(r"(?i)global\s+privacy\s+control", "a header", text),
            text + "\nBoth counters are exact.\n",
            # a cause removed from the footer only (the body still names it)
            FOOTER.sub(lambda m: re.sub(r"UTC\s+days,\s+", "", m.group(0)), text),
        ):
            self.assertNotEqual(check_note(broken), [])


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0], "-v"])
