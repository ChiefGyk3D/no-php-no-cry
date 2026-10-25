#!/usr/bin/env python3
"""Convert a WordPress WXR export into Hugo page bundles.

    python3 -I tools/wxr2hugo/convert.py --wxr PATH --out DIR \
        [--scrub-terms FILE] [--site-url URL] [--media DIR]

Stdlib only. The export, the terms file and the output all live outside the
repository; the tool refuses paths inside it. Same input, same bytes out.

Exit codes: 0 done, 1 unexpected error (class name only, never the input),
2 usage or refused path, 3 scrub findings (nothing written).
"""

import argparse
import importlib.util
import json
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
MARKER = ".wxr2hugo-out"
DEFAULT_SITE_URL = "https://test-blog.chiefgyk3d.com"
OWN_DOMAIN = "chiefgyk3d.com"

WP = "{http://wordpress.org/export/1.2/}"
CONTENT = "{http://purl.org/rss/1.0/modules/content/}encoded"
UPLOADS = re.compile(r"/wp-content/uploads/([^?#]+)")
SIZE_SUFFIX = re.compile(r"-\d+x\d+(?=\.[^./]+$)")


def _load_scrub():
    spec = importlib.util.spec_from_file_location("wxr2hugo_scrub", HERE / "scrub.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


scrub = _load_scrub()


class UsageError(Exception):
    pass


class ScrubFailure(Exception):
    pass


# --------------------------------------------------------------------------
# small helpers


def inside_repo(path):
    resolved = Path(path).expanduser().resolve()
    return resolved == REPO or REPO in resolved.parents


def q(value):
    return json.dumps(value, ensure_ascii=False)


def dump_json(obj):
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def safe_slug(text):
    text = re.sub(r"[^A-Za-z0-9._-]+", "-", text).strip("-.")
    return text


def parse_stamp(text):
    try:
        return datetime.strptime(text.strip(), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def iso_date(local, gmt):
    """RFC 3339 with the offset implied by WordPress's local and GMT stamps."""
    l_stamp, g_stamp = parse_stamp(local), parse_stamp(gmt)
    if l_stamp and g_stamp:
        offset = l_stamp - g_stamp
    elif l_stamp:
        try:
            from zoneinfo import ZoneInfo

            offset = ZoneInfo("America/New_York").utcoffset(l_stamp.replace(tzinfo=ZoneInfo("America/New_York")))
        except Exception:  # no tz database: fall back to UTC
            offset = timedelta(0)
    elif g_stamp:
        return g_stamp.strftime("%Y-%m-%dT%H:%M:%SZ")
    else:
        return None
    minutes = int(offset.total_seconds() // 60)
    if minutes == 0:
        return l_stamp.strftime("%Y-%m-%dT%H:%M:%SZ")
    sign = "+" if minutes > 0 else "-"
    hours, mins = divmod(abs(minutes), 60)
    return l_stamp.strftime("%Y-%m-%dT%H:%M:%S") + "%s%02d:%02d" % (sign, hours, mins)


def esc(text):
    """Escape Markdown specials in running text."""
    text = text.replace("\\", "\\\\").replace("*", "\\*").replace("`", "\\`")
    text = text.replace("[", "\\[").replace("]", "\\]").replace("<", "\\<")
    text = re.sub(r"(?<![A-Za-z0-9])_|_(?![A-Za-z0-9])", r"\\_", text)
    text = re.sub(r"&(?=#?\w+;)", r"\\&", text)
    return text


def esc_line_start(text):
    return re.sub(r"^(\s*)(#|>|\+|-(?= )|\d+(?=[.)] ))", r"\1\\\2", text)


def url_dest(url):
    return url.replace(" ", "%20").replace("(", "%28").replace(")", "%29")


# --------------------------------------------------------------------------
# context: link rewriting, media, affiliate log


class Site:
    """Everything shared across pages: hosts, media index, logs, counters."""

    def __init__(self, site_url, temp_hosts, own_hosts, media_root, attachments):
        self.site_url = site_url.rstrip("/")
        self.temp_hosts = sorted(temp_hosts)
        self.own_hosts = {h.lower() for h in own_hosts}
        self.media_root = media_root
        self.attachments = attachments  # stripped relative path -> {"alt","title"}
        self.temp_re = (
            re.compile(
                r"https?://(?:%s)(?![A-Za-z0-9-])" % "|".join(re.escape(h) for h in self.temp_hosts),
                re.I,
            )
            if self.temp_hosts
            else None
        )
        self.affiliate = []
        self.warnings = []
        self.counts = {
            "temp_host_links_rewritten": 0,
            "temp_host_images_localized": 0,
            "attachments_localized": 0,
        }
        self.image_files = set()

    def is_local_host(self, host):
        host = (host or "").lower().rstrip(".")
        if not host:
            return True
        return (
            host in self.own_hosts
            or host in {h.lower() for h in self.temp_hosts}
            or host == OWN_DOMAIN
            or host.endswith("." + OWN_DOMAIN)
        )

    def rewrite_text(self, text):
        if not self.temp_re:
            return text
        text, n = self.temp_re.subn(self.site_url, text)
        self.counts["temp_host_links_rewritten"] += n
        return text

    def find_media(self, url):
        """(path, relative) of a local uploads file for url, or (None, rel)."""
        parts = urlsplit(url)
        if parts.scheme not in ("", "http", "https") or not self.is_local_host(parts.hostname):
            return None, None
        found = UPLOADS.search(parts.path)
        if not found:
            return None, None
        rel = unquote(found.group(1))
        if self.media_root:
            for candidate in (rel, SIZE_SUFFIX.sub("", rel)):
                path = (self.media_root / candidate)
                if ".." not in Path(candidate).parts and path.is_file():
                    return path, rel
        return None, rel

    def attachment_info(self, rel):
        return self.attachments.get(SIZE_SUFFIX.sub("", rel), {})


class PageCtx:
    """Per-page state: the bundle's files and where this page lives."""

    def __init__(self, site, page_path):
        self.site = site
        self.page_path = page_path
        self.bundle = {}  # file name -> source path

    def _bundle_name(self, path):
        name = path.name
        stem, suffix = path.stem, path.suffix
        n = 1
        while name in self.bundle and self.bundle[name] != path:
            n += 1
            name = "%s-%d%s" % (stem, n, suffix)
        self.bundle[name] = path
        return name

    def rewrite_text(self, text):
        return self.site.rewrite_text(text)

    def link(self, href):
        href = href.strip()
        parts = urlsplit(href)
        host = (parts.hostname or "").lower()
        if host == "amzn.to" or host.endswith(".amzn.to"):
            self.site.affiliate.append(
                {
                    "file": self.page_path,
                    "url": href,
                    "decision": "kept",
                    "disclosure": "not added",
                }
            )
        path, rel = self.site.find_media(href)
        if path is not None:
            self.site.counts["attachments_localized"] += 1
            return self._bundle_name(path)
        if rel is not None:
            self.site.warnings.append({"file": self.page_path, "kind": "missing-media-link", "detail": rel})
        return self.rewrite_text(href)

    def image(self, src, alt):
        """(destination, alt text) for an image reference."""
        src = src.strip()
        path, rel = self.site.find_media(src)
        info = self.site.attachment_info(rel) if rel else {}
        alt = (alt or "").strip() or info.get("alt") or info.get("title") or ""
        if not alt:
            stem = Path(rel or urlsplit(src).path).stem
            alt = re.sub(r"[-_]+", " ", SIZE_SUFFIX.sub("", stem + ".x")[:-2]).strip() or "image"
        if path is not None:
            name = self._bundle_name(path)
            if path.suffix.lower() not in (".png", ".jpg", ".jpeg"):
                # layouts/_markup/render-image.html only accepts JPEG and PNG
                self.site.warnings.append({"file": self.page_path, "kind": "unsupported-image-format", "detail": name})
            self.site.image_files.add((self.page_path, name))
            if self.site.temp_re and self.site.temp_re.match(src):
                self.site.counts["temp_host_images_localized"] += 1
            return name, alt
        if rel is not None:
            self.site.warnings.append({"file": self.page_path, "kind": "missing-media-image", "detail": rel})
        else:
            self.site.warnings.append({"file": self.page_path, "kind": "external-image", "detail": urlsplit(src).netloc})
        return url_dest(self.rewrite_text(src)), alt


# --------------------------------------------------------------------------
# HTML to Markdown


class Md(HTMLParser):
    HEADINGS = {"h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6}
    BLOCKS = {"p", "div", "section", "article", "figure", "figcaption", "tr", "table", "header", "footer", "aside", "main", "dl", "dt", "dd"}

    def __init__(self, ctx):
        super().__init__(convert_charrefs=True)
        self.ctx = ctx
        self.entries = []  # (text, kind)
        self.cur = []
        self.lists = []
        self.prefix = None
        self.wraps = []  # (start index in cur, kind, extra)
        self.quote = 0
        self.pre = None
        self.skip = 0
        self.heading = 0

    # -- output
    def flush(self):
        text = "".join(self.cur)
        self.cur = []
        self.wraps = []
        text = re.sub(r"[ \t\r\f\v\xa0]+", " ", text)
        text = re.sub(r" ?\\\n ?", "\\\n", text).strip()
        if text.endswith("\\"):
            text = text[:-1].rstrip()
        if not text:
            self.prefix = None
            return
        if self.heading:
            text = "#" * self.heading + " " + text.replace("\\\n", " ").replace("\n", " ")
            kind = "h"
        elif self.prefix is not None:
            text = self.prefix + text.replace("\n", "\n" + " " * len(self.prefix))
            kind = "li"
        else:
            text = esc_line_start(text)
            kind = "p"
        self.prefix = None
        if self.quote:
            text = "\n".join("> " + line for line in text.split("\n"))
            kind = "q"
        self.entries.append((text, kind))

    def render(self):
        self.flush()
        out = []
        prev = None
        for text, kind in self.entries:
            if prev is not None:
                if kind == "li" and prev == "li":
                    out.append("\n")
                elif kind == "q" and prev == "q":
                    out.append("\n>\n")
                else:
                    out.append("\n\n")
            out.append(text)
            prev = kind
        return "".join(out)

    # -- inline wraps
    def open_wrap(self, kind, extra=None):
        self.wraps.append((len(self.cur), kind, extra))

    def close_wrap(self, kind):
        for i in range(len(self.wraps) - 1, -1, -1):
            if self.wraps[i][1] == kind:
                start, _, extra = self.wraps.pop(i)
                break
        else:
            return
        inner = "".join(self.cur[start:])
        del self.cur[start:]
        lead = inner[: len(inner) - len(inner.lstrip())]
        trail = inner[len(inner.rstrip()) :]
        core = inner.strip()
        if not core:
            self.cur.append(inner)
            return
        if kind == "a":
            self.cur.append("%s[%s](%s)%s" % (lead, core, url_dest(extra), trail))
        elif kind in ("strong", "em", "code"):
            mark = {"strong": "**", "em": "*", "code": "`"}[kind]
            if kind == "code":
                core = core.replace("\\*", "*").replace("\\_", "_").replace("\\`", "`").replace("\\[", "[").replace("\\]", "]")
                if "`" in core:
                    mark = "``"
            self.cur.append("%s%s%s%s%s" % (lead, mark, core, mark, trail))

    # -- parser events
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("script", "style"):
            self.skip += 1
        elif self.skip:
            return
        elif tag in self.HEADINGS:
            self.flush()
            self.heading = self.HEADINGS[tag]
        elif tag in self.BLOCKS:
            self.flush()
        elif tag in ("ul", "ol"):
            self.flush()
            self.lists.append({"ordered": tag == "ol", "n": 0})
        elif tag == "li":
            self.flush()
            if self.lists:
                state = self.lists[-1]
                state["n"] += 1
                marker = "%d. " % state["n"] if state["ordered"] else "- "
                self.prefix = "    " * (len(self.lists) - 1) + marker
        elif tag == "blockquote":
            self.flush()
            self.quote += 1
        elif tag == "pre":
            self.flush()
            self.pre = []
        elif tag == "hr":
            self.flush()
            self.entries.append(("---", "p"))
        elif tag == "br":
            self.cur.append("\\\n")
        elif tag == "a":
            href = a.get("href")
            self.open_wrap("a", self.ctx.link(href) if href else None)
        elif tag in ("strong", "b"):
            self.open_wrap("strong")
        elif tag in ("em", "i"):
            self.open_wrap("em")
        elif tag == "code" and self.pre is None:
            self.open_wrap("code")
        elif tag == "img":
            src = a.get("src")
            if src:
                dest, alt = self.ctx.image(src, a.get("alt"))
                alt = re.sub(r"[\[\]\n]+", " ", alt).strip()
                self.cur.append("![%s](%s)" % (alt, dest))
        elif tag in ("td", "th"):
            self.cur.append(" ")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.skip = max(0, self.skip - 1)
            return
        if self.skip:
            return
        if tag in self.HEADINGS:
            self.flush()
            self.heading = 0
        elif tag in self.BLOCKS:
            self.flush()
        elif tag in ("ul", "ol"):
            self.flush()
            if self.lists:
                self.lists.pop()
        elif tag == "li":
            self.flush()
        elif tag == "blockquote":
            self.flush()
            self.quote = max(0, self.quote - 1)
        elif tag == "pre":
            if self.pre is not None:
                code = "".join(self.pre).strip("\n")
                self.pre = None
                longest = max([len(m) for m in re.findall(r"`+", code)] or [0])
                fence = "`" * max(3, longest + 1)
                text = "%s\n%s\n%s" % (fence, code, fence)
                if self.quote:
                    text = "\n".join("> " + line for line in text.split("\n"))
                self.entries.append((text, "q" if self.quote else "p"))
        elif tag == "a":
            self.close_wrap("a")
        elif tag in ("strong", "b"):
            self.close_wrap("strong")
        elif tag in ("em", "i"):
            self.close_wrap("em")
        elif tag == "code" and self.pre is None:
            self.close_wrap("code")

    def handle_data(self, data):
        if self.skip:
            return
        data = self.ctx.rewrite_text(data)
        if self.pre is not None:
            self.pre.append(data)
            return
        data = re.sub(r"\s+", " ", data)
        self.cur.append(esc(data))


def html_to_md(html_text, ctx):
    parser = Md(ctx)
    parser.feed(html_text or "")
    parser.close()
    return parser.render()


def strip_tags(html_text):
    class Plain(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.parts = []

        def handle_data(self, data):
            self.parts.append(data)

        def handle_starttag(self, tag, attrs):
            if tag == "br":
                self.parts.append("\n")

    parser = Plain()
    parser.feed(html_text or "")
    parser.close()
    return "".join(parser.parts).strip()


# --------------------------------------------------------------------------
# block builder JSON


def _link_value(props):
    link = props.get("link")
    value = link.get("value") if isinstance(link, dict) else None
    return value.strip() if isinstance(value, str) and value.strip() else None


def builder_to_md(tree, ctx):
    blocks = []

    def inline(markup):
        return html_to_md(markup, ctx).replace("\\\n", " ").replace("\n", " ").strip()

    def visit(node, depth):
        if not isinstance(node, dict):
            return
        if depth > 200:
            raise ValueError("builder tree too deep")
        props = node.get("props") if isinstance(node.get("props"), dict) else {}
        name = node.get("name")
        if name == "hop-heading" and isinstance(props.get("content"), str):
            text = inline(props["content"])
            href = _link_value(props)
            if text:
                blocks.append("## " + ("[%s](%s)" % (text, url_dest(ctx.link(href))) if href else text))
        elif name == "hop-text" and isinstance(props.get("content"), str):
            text = html_to_md(props["content"], ctx)
            if text:
                blocks.append(text)
        elif name == "hop-button" and isinstance(props.get("text"), str):
            text, href = inline(props["text"]), _link_value(props)
            if text:
                blocks.append("[%s](%s)" % (text, url_dest(ctx.link(href))) if href else text)
        elif name == "hop-image" and isinstance(props.get("url"), str):
            dest, alt = ctx.image(props["url"], None)
            image = "![%s](%s)" % (re.sub(r"[\[\]\n]+", " ", alt).strip(), dest)
            href = _link_value(props)
            blocks.append("[%s](%s)" % (image, url_dest(ctx.link(href))) if href else image)
            caption = props.get("caption")
            if isinstance(caption, dict) and isinstance(caption.get("text"), str) and caption["text"].strip():
                blocks.append(inline(caption["text"]))
        elif name in ("hop-social-icons", "hop-icon-list"):
            items = []
            for entry in props.get("icons") or props.get("iconList") or []:
                if not isinstance(entry, dict):
                    continue
                href = _link_value(entry)
                if not href:
                    continue
                label = inline(entry["text"]) if isinstance(entry.get("text"), str) and entry["text"].strip() else ""
                href = ctx.link(href)
                items.append("- [%s](%s)" % (label or esc(href), url_dest(href)))
            if items:
                blocks.append("\n".join(items))
        for child in node.get("children") or []:
            visit(child, depth + 1)
        slots = node.get("slots")
        if isinstance(slots, dict):
            for key in sorted(slots):
                for child in slots[key] or []:
                    visit(child, depth + 1)

    visit(tree, 0)
    return "\n\n".join(blocks)


# --------------------------------------------------------------------------
# reading the export


def read_wxr(path):
    data = Path(path).read_bytes()
    if re.search(rb"<!(?:DOCTYPE|ENTITY)", data, re.I):
        raise UsageError("input declares a DOCTYPE or ENTITY; refusing to parse it")
    # With DOCTYPE and ENTITY refused above, the stdlib parser has no entity
    # expansion left to abuse.
    root = ET.fromstring(data)
    return root, data.decode("utf-8", "replace")


def detect_hosts(raw_text, base_urls):
    temp, own = set(), set()
    for host in re.findall(r"https?://([A-Za-z0-9.-]+)", raw_text):
        host = host.lower().rstrip(".")
        if host == OWN_DOMAIN or host.endswith("." + OWN_DOMAIN):
            continue
        if "bluehost" in host:
            temp.add(host)
    for url in base_urls:
        host = (urlsplit(url or "").hostname or "").lower()
        if host and host not in temp:
            own.add(host)
    return temp, own


def child_text(element, tag):
    found = element.find(tag)
    return (found.text or "") if found is not None else ""


def read_item(el):
    meta = {}
    for m in el.findall(WP + "postmeta"):
        meta[child_text(m, WP + "meta_key")] = child_text(m, WP + "meta_value")
    comments = []
    for c in el.findall(WP + "comment"):
        comments.append(
            {
                "id": int(child_text(c, WP + "comment_id") or 0),
                "author": child_text(c, WP + "comment_author"),
                "date": child_text(c, WP + "comment_date"),
                "date_gmt": child_text(c, WP + "comment_date_gmt"),
                "content": child_text(c, WP + "comment_content"),
                "approved": child_text(c, WP + "comment_approved").strip(),
                "type": child_text(c, WP + "comment_type").strip(),
                "parent": int(child_text(c, WP + "comment_parent") or 0),
            }
        )
    categories, tags = [], []
    for t in el.findall("category"):
        name = (t.text or "").strip()
        bucket = categories if t.attrib.get("domain") == "category" else tags if t.attrib.get("domain") == "post_tag" else None
        if bucket is not None and name and name not in bucket:
            bucket.append(name)
    return {
        "id": int(child_text(el, WP + "post_id") or 0),
        "type": child_text(el, WP + "post_type"),
        "status": child_text(el, WP + "status"),
        "title": child_text(el, "title"),
        "slug": child_text(el, WP + "post_name").strip(),
        "link": child_text(el, "link").strip(),
        "date": child_text(el, WP + "post_date"),
        "date_gmt": child_text(el, WP + "post_date_gmt"),
        "content": child_text(el, CONTENT),
        "attachment_url": child_text(el, WP + "attachment_url").strip(),
        "meta": meta,
        "comments": comments,
        "categories": categories,
        "tags": tags,
    }


def old_permalink(link):
    parts = urlsplit(link)
    if parts.query or parts.fragment:
        return None
    path = parts.path
    if path in ("", "/"):
        return None
    return path if path.startswith("/") else "/" + path


def find_media_root(wxr_path):
    raw = Path(wxr_path).resolve().parent / "raw"
    if not raw.is_dir():
        return None
    for base, dirs, _ in os.walk(raw):
        dirs.sort()
        if Path(base).name == "uploads" and Path(base).parent.name == "wp-content":
            return Path(base)
    return None


# --------------------------------------------------------------------------
# conversion


def front_matter(fields):
    lines = []
    for key, value in fields:
        if value is None:
            continue
        if isinstance(value, bool):
            lines.append("%s: %s" % (key, "true" if value else "false"))
        elif key == "date":
            lines.append("date: %s" % value)
        elif isinstance(value, list) and key == "aliases":
            if value:
                lines.append("aliases:")
                lines.extend("  - %s" % q(v) for v in value)
        elif isinstance(value, list):
            lines.append("%s: [%s]" % (key, ", ".join(q(v) for v in value)))
        else:
            lines.append("%s: %s" % (key, q(value)))
    return "---\n" + "\n".join(lines) + "\n---\n"


def convert(wxr_path, site_url, media_root):
    """Returns (files, media, summary_pieces). Pure with respect to the disk."""
    root, raw_text = read_wxr(wxr_path)
    channel = root.find("channel")
    base_urls = [child_text(channel, WP + "base_site_url"), child_text(channel, WP + "base_blog_url"), child_text(channel, "link")]
    temp_hosts, own_hosts = detect_hosts(raw_text, base_urls)

    items = [read_item(el) for el in channel.findall("item")]
    by_id = {i["id"]: i for i in items}

    attachments = {}
    for item in items:
        if item["type"] == "attachment" and item["attachment_url"]:
            found = UPLOADS.search(urlsplit(item["attachment_url"]).path)
            if found:
                attachments[SIZE_SUFFIX.sub("", unquote(found.group(1)))] = {
                    "alt": item["meta"].get("_wp_attachment_image_alt", "").strip(),
                    "title": item["title"].strip(),
                }

    site = Site(site_url, temp_hosts, own_hosts, media_root, attachments)
    dropped = {}
    wanted = []
    for item in items:
        if item["type"] in ("post", "page") and item["status"] in ("publish", "draft"):
            wanted.append(item)
        elif item["type"] not in ("attachment", "extb_post_json"):
            dropped[item["type"]] = dropped.get(item["type"], 0) + 1
    wanted.sort(key=lambda i: (parse_stamp(i["date_gmt"]) or parse_stamp(i["date"]) or datetime.min, i["id"]))

    files, media, pmap = {}, {}, []
    used = {"post": set(), "page": set()}
    counts = {"posts": 0, "pages": 0, "drafts": 0, "comments": 0, "comments_dropped": 0, "aliases": 0, "builder_pages": 0}

    for item in wanted:
        kind = item["type"]
        section = "posts" if kind == "post" else "pages"
        slug = safe_slug(item["slug"]) or slugify(html_text(item["title"])) or "%s-%d" % (kind, item["id"])
        base, n = slug, 1
        while slug in used[kind]:
            n += 1
            slug = "%s-%d" % (base, n)
        used[kind].add(slug)
        bundle = "%s/%s" % (section, slug)
        page_path = bundle + "/index.md"
        ctx = PageCtx(site, page_path)
        draft = item["status"] == "draft"

        body, builder_id = None, None
        found = re.search(r's:4:"json";i:(\d+);', item["meta"].get("extend_builder", ""))
        if found:
            builder_id = int(found.group(1))
            source = by_id.get(builder_id)
            if source and source["type"] == "extb_post_json":
                body = builder_to_md(json.loads(source["content"]), ctx)
                counts["builder_pages"] += 1
            else:
                site.warnings.append({"file": page_path, "kind": "builder-json-missing", "detail": str(builder_id)})
        if body is None:
            body = html_to_md(item["content"], ctx)

        old = None if draft else old_permalink(item["link"])
        aliases = [old] if old else []
        counts["aliases"] += len(aliases)
        fields = [
            ("title", html_text(item["title"])),
            ("date", iso_date(item["date"], item["date_gmt"])),
            ("draft", draft),
            ("slug", slug),
            ("categories", item["categories"]),
            ("tags", item["tags"]),
            ("syndicate", kind == "post" and item["meta"].get("_share_on_mastodon") == "1"),
            ("aliases", aliases),
        ]
        text = front_matter(fields) + ("\n" + body + "\n" if body else "")
        files[page_path] = text.encode("utf-8")

        for name, source_path in sorted(ctx.bundle.items()):
            media["%s/%s" % (bundle, name)] = source_path

        approved = [
            c
            for c in item["comments"]
            if c["approved"] == "1" and c["type"] in ("", "comment")
        ]
        counts["comments_dropped"] += len(item["comments"]) - len(approved)
        if approved:
            approved.sort(key=lambda c: (parse_stamp(c["date_gmt"]) or datetime.min, c["id"]))
            data = [
                {
                    "id": c["id"],
                    "parent": c["parent"],
                    "author": c["author"].strip(),
                    "date": iso_date(c["date"], c["date_gmt"]),
                    "content": site.rewrite_text(strip_tags(c["content"])),
                }
                for c in approved
            ]
            files[bundle + "/comments.json"] = dump_json(data).encode("utf-8")
            counts["comments"] += len(approved)

        counts[section] += 1
        counts["drafts"] += 1 if draft else 0
        pmap.append(
            {
                "id": item["id"],
                "type": kind,
                "draft": draft,
                "slug": slug,
                "old": old,
                "new": "/%s/%s/" % (section, slug),
                "file": page_path,
            }
        )

    pmap.sort(key=lambda e: e["id"])
    files["permalink-map.json"] = dump_json(pmap).encode("utf-8")

    counts["images"] = len(site.image_files)
    counts["affiliate_links"] = len(site.affiliate)
    counts["dropped_activitypub"] = sum(v for k, v in dropped.items() if k.startswith("ap_"))
    counts["dropped_other_types"] = sum(v for k, v in dropped.items() if not k.startswith("ap_"))
    counts.update(site.counts)
    counts["warnings"] = len(site.warnings)
    log = {
        "summary": counts,
        "affiliate_links": site.affiliate,
        "warnings": site.warnings,
        "dropped_item_types": dropped,
    }
    files["decision-log.json"] = dump_json(log).encode("utf-8")
    return files, media, counts


def html_text(markup):
    return re.sub(r"\s+", " ", strip_tags(markup)).strip()


# --------------------------------------------------------------------------
# output


def write_output(out, files, media):
    out = Path(out)
    stage = out.with_name(out.name + ".partial")
    if stage.exists():
        if not (stage / MARKER).exists():
            raise UsageError("%s exists and is not a wxr2hugo staging directory" % stage.name)
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    (stage / MARKER).write_text("wxr2hugo output; safe to replace\n", encoding="utf-8")
    for rel, data in sorted(files.items()):
        target = stage / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    for rel, source in sorted(media.items()):
        target = stage / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    if out.exists():
        shutil.rmtree(out)
    stage.rename(out)


def prepare_out(out):
    out = Path(out)
    if out.exists():
        if not out.is_dir():
            raise UsageError("--out exists and is not a directory")
        if any(out.iterdir()) and not (out / MARKER).exists():
            raise UsageError("--out is not empty and was not made by this tool; refusing to touch it")


def run(args):
    wxr = Path(args.wxr).expanduser()
    if not wxr.is_file():
        raise UsageError("--wxr is not a file")
    if inside_repo(wxr):
        raise UsageError("--wxr is inside the repository; keep the export outside it")
    out = Path(args.out).expanduser() if args.out else wxr.resolve().parent / "out"
    if inside_repo(out):
        raise UsageError("--out is inside the repository; write generated content elsewhere")
    if args.scrub_terms and inside_repo(args.scrub_terms):
        raise UsageError("--scrub-terms is inside the repository; keep the terms file outside it")

    try:
        rules = scrub.load_terms(args.scrub_terms) if args.scrub_terms else scrub.Rules()
    except scrub.TermsError as err:
        raise UsageError(str(err))
    prepare_out(out)

    media_root = Path(args.media).expanduser() if args.media else find_media_root(wxr)
    files, media, counts = convert(wxr, args.site_url, media_root)

    listing = dict(files)
    listing.update({rel: None for rel in media})
    findings = scrub.scan_files(listing, rules)
    if findings:
        for finding in findings:
            print(scrub.format_finding(finding), file=sys.stderr)
        print("scrub: %d finding(s); nothing written" % len(findings), file=sys.stderr)
        raise ScrubFailure()

    write_output(out, files, media)
    print(json.dumps(counts, indent=2, sort_keys=True))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Convert a WordPress WXR export to Hugo page bundles.")
    parser.add_argument("--wxr", required=True, help="WXR export (outside the repo)")
    parser.add_argument("--out", help="output directory (outside the repo; default: out/ beside the export)")
    parser.add_argument("--scrub-terms", help="file of category:term lines (outside the repo)")
    parser.add_argument("--site-url", default=DEFAULT_SITE_URL, help="current site URL for rewritten links")
    parser.add_argument("--media", help="wp-content/uploads directory (default: found under raw/ beside the export)")
    args = parser.parse_args(argv)
    try:
        run(args)
    except UsageError as err:
        print("error: %s" % err, file=sys.stderr)
        return 2
    except ScrubFailure:
        return 3
    except Exception as err:  # never echo the message: it may quote the input
        print("error: unexpected %s" % type(err).__name__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
