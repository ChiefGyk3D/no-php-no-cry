#!/usr/bin/env python3
"""Landmark check for one built HTML page (docs/redesign-brief.md section 11).

Usage: python3 -I scripts/check-landmarks.py <page.html>

Prints one rule name per line and nothing else (page content is never
printed):
  skip-link  the first link in the body is not a link to #main
  landmark   not exactly one <header>, one <nav aria-label="Main">, one
             <main id="main">, one <footer>, or the landmarks are out of order
             (header, main, footer) or unbalanced
"""
import sys
from html.parser import HTMLParser


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_body = False
        self.first_link = None
        self.order = []
        self.main_ids = []
        self.nav_labels = []
        self.closed = {"header": 0, "main": 0, "footer": 0}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "body":
            self.in_body = True
        elif tag == "a" and self.in_body and self.first_link is None:
            self.first_link = a.get("href")
        elif tag in ("header", "main", "footer"):
            self.order.append(tag)
            if tag == "main":
                self.main_ids.append(a.get("id"))
        elif tag == "nav":
            self.nav_labels.append(a.get("aria-label"))

    def handle_endtag(self, tag):
        if tag in self.closed:
            self.closed[tag] += 1


def main(path):
    p = Page()
    with open(path, encoding="utf-8", errors="replace") as fh:
        p.feed(fh.read())
    p.close()
    if p.first_link != "#main":
        print("skip-link")
    ok = (
        p.order == ["header", "main", "footer"]
        and p.closed == {"header": 1, "main": 1, "footer": 1}
        and p.main_ids == ["main"]
        and p.nav_labels.count("Main") == 1
    )
    if not ok:
        print("landmark")


if __name__ == "__main__":
    main(sys.argv[1])
