"""Exit 0 when a built file shows the project name where the site name belongs.

Usage: python3 -I scripts/old-name-scan.py <decode|raw> <file>

The site's public name is ChiefGyk3D; "no-php-no-cry" is the project name and
must not be shown. In decode mode (html, xml, svg) character references are
decoded first, because a browser shows the decoded text: no&#45;php&#45;no-cry
is the project name. The match is case-insensitive. The one allowed form is a
link to the repository, https://github.com/ChiefGyk3D/no-php-no-cry followed by
end of text, a slash, a quote, whitespace or an angle bracket.

Exit 0: the name is present (finding). Exit 1: clean. Nothing is printed.
"""
import html
import re
import sys

ALLOW = re.compile(
    r"https?://github\.com/ChiefGyk3D/no-php-no-cry(?=[/\"'<>\s]|$)", re.I)
NAME = re.compile(r"no-php-no-cry", re.I)


def main(argv):
    if len(argv) != 3 or argv[1] not in ("decode", "raw"):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    with open(argv[2], encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    if argv[1] == "decode":
        text = html.unescape(text)
    return 0 if NAME.search(ALLOW.sub("X", text)) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
