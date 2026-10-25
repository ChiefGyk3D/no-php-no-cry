"""Scrub pass for wxr2hugo: find private identifiers without ever repeating them.

Categories:
  callsign   amateur radio callsign shape (uppercase prefix, digit, suffix)
  grid       Maidenhead grid square shape (4 or 6 characters)
  employer   terms from the --scrub-terms file only
  hostname   terms from the --scrub-terms file, plus generic private-network
             patterns that need no terms file: private IPv4 addresses (10/8,
             172.16/12, 192.168/16) and names ending .local, .lan, .internal
             or .home.arpa
  serial     terms from the --scrub-terms file only

The terms file (kept outside the repository) holds one `category:term` per
line. Blank lines and lines starting with `#` are ignored. A line
`allow:TOKEN` exempts that exact token from the callsign and grid shape
checks (for a false positive such as a chemical formula) and from the generic
hostname patterns.

Findings carry the category, the file and the line. They never carry the
matched text, and nothing here puts matched text in an exception message.
"""

import re
from typing import NamedTuple

CATEGORIES = ("callsign", "grid", "employer", "hostname", "serial")
TERM_CATEGORIES = ("employer", "hostname", "serial")

# 1-2 letter prefix, one digit, 1-4 letter suffix (4 so N0CALL matches), not part of a longer word.
_CALLSIGN = re.compile(r"(?<![A-Za-z0-9])[A-Z]{1,2}[0-9][A-Z]{1,4}(?![A-Za-z0-9])")
# Field A-R twice, two digits, optional subsquare a-x (either case).
_GRID = re.compile(r"(?<![A-Za-z0-9])[A-R]{2}[0-9]{2}(?:[A-Xa-x]{2})?(?![A-Za-z0-9])")
# Private IPv4: 10/8, 172.16/12, 192.168/16, each octet 0-255, not part of a longer dotted number.
_OCTET = r"(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
_PRIVATE_IP = re.compile(
    r"(?<![0-9.])(?:10\.%(o)s\.%(o)s\.%(o)s|172\.(?:1[6-9]|2[0-9]|3[01])\.%(o)s\.%(o)s|192\.168\.%(o)s\.%(o)s)(?!\.?[0-9])"
    % {"o": _OCTET}
)
# A dotted name ending in a private-network suffix (the last label must be the whole label).
_PRIVATE_NAME = re.compile(
    r"(?<![A-Za-z0-9.-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+(?:local|lan|internal|home\.arpa)"
    r"(?![A-Za-z0-9-]|\.[A-Za-z0-9])",
    re.I,
)


class Finding(NamedTuple):
    category: str
    file: str
    line: int


class TermsError(Exception):
    """Bad terms file. The message names a line number only."""


class Rules:
    def __init__(self, terms=None, allow=None):
        self.terms = {c: [] for c in TERM_CATEGORIES}
        for category, term in terms or ():
            self.terms[category].append(term.casefold())
        self.allow = set(allow or ())


def load_terms(path):
    """Read a terms file into Rules. Errors name the line, never its content."""
    terms, allow = [], []
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            category, sep, term = line.partition(":")
            category = category.strip().casefold()
            term = term.strip()
            if not sep or not term:
                raise TermsError("terms file line %d: expected category:term" % number)
            if category == "allow":
                allow.append(term)
            elif category in TERM_CATEGORIES:
                terms.append((category, term))
            else:
                raise TermsError("terms file line %d: unknown category" % number)
    return Rules(terms, allow)


def _line_categories(line, rules):
    found = []
    if any(m.group(0) not in rules.allow for m in _CALLSIGN.finditer(line)):
        found.append("callsign")
    if any(m.group(0) not in rules.allow for m in _GRID.finditer(line)):
        found.append("grid")
    generic = list(_PRIVATE_IP.finditer(line)) + list(_PRIVATE_NAME.finditer(line))
    hostname_hit = any(m.group(0) not in rules.allow for m in generic)
    lowered = line.casefold()
    for category in TERM_CATEGORIES:
        if any(term in lowered for term in rules.terms[category]):
            found.append(category)
        elif category == "hostname" and hostname_hit:
            found.append(category)
    return found


def status(rules):
    """Which scrub categories ran. Term categories without terms are NOT RUN."""
    result = {"callsign": "ran", "grid": "ran", "hostname-generic": "ran"}
    for category in TERM_CATEGORIES:
        result[category] = "ran" if rules.terms[category] else "NOT RUN"
    return result


def scan_text(text, name, rules):
    """Findings for one text, one per category per line. `name` is reported as is."""
    findings = []
    for number, line in enumerate(text.splitlines(), 1):
        for category in _line_categories(line, rules):
            findings.append(Finding(category, name, number))
    return findings


def scan_files(files, rules):
    """Scan a mapping of relative path -> bytes (text) or None (binary, path only).

    The path is scanned too. A path that itself matches is reported as
    `<path-N>` (N is its sorted position) so the finding never repeats it.
    """
    findings = []
    for index, path in enumerate(sorted(files), 1):
        shown = path
        path_hits = scan_text(path, "", rules)
        if path_hits:
            shown = "<path-%d>" % index
            findings.extend(Finding(h.category, shown, 0) for h in path_hits)
        data = files[path]
        if data is not None:
            findings.extend(scan_text(data.decode("utf-8", "replace"), shown, rules))
    return findings


def format_finding(finding):
    return "scrub finding: category=%s file=%s line=%d" % (
        finding.category,
        finding.file,
        finding.line,
    )
