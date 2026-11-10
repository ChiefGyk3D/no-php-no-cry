"""Fake deployed site for scripts/test-verify-live.sh. Local only (127.0.0.1).

Serves a built site directory the way Cloudflare Pages would: files from
ROOT, the rules of _redirects with their declared status (301 or 302), the headers of _headers on every
response, 404.html with status 404 for anything else. MODE injects one fault
(see FAULTS). REWRITE_FROM, when set, is replaced by the server's own base URL
in text bodies so a real build (whose baseURL is the staging host) can be served
from 127.0.0.1. The port is chosen by the OS and written to PORTFILE.
"""
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

root = os.environ["ROOT"]
mode = os.environ.get("MODE", "good")
rewrite_from = os.environ.get("REWRITE_FROM", "")
portfile = os.environ["PORTFILE"]

# _headers blocks: a path pattern on its own line, then indented headers. "/*"
# applies to every response, "/prefix/*" to paths under the prefix, a plain
# path to that path only (what this repo's _headers uses).
blocks = []
with open(os.path.join(root, "_headers")) as f:
    for line in f:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^\s+([A-Za-z][A-Za-z0-9-]*):\s*(.*?)\s*$", line)
        if m:
            blocks[-1][1].append((m.group(1), m.group(2)))
        elif not line[0].isspace():
            blocks.append((line.strip(), []))


def applies(pat, path):
    if pat == "/*":
        return True
    if pat.endswith("/*"):
        return path.startswith(pat[:-1])
    return path == pat


def headers_for(path):
    return [h for pat, hs in blocks if applies(pat, path) for h in hs]


redirects = {}
with open(os.path.join(root, "_redirects")) as f:
    for line in f:
        parts = line.split()
        if len(parts) == 3 and parts[0].startswith("/"):
            redirects[parts[0]] = (parts[1], int(parts[2]) if parts[2].isdigit() else 301)

TEXT = (".html", ".xml", ".txt", ".css", ".js", ".webmanifest")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body=b"", ctype="text/html", extra=(), path="/"):
        hs = headers_for(path)
        is_css = path.startswith("/css/")
        if mode == "immutable-on-html" and not is_css:
            hs = hs + [("Cache-Control", "public, max-age=31536000, immutable")]
        if mode == "css-immutable-missing" and is_css:
            hs = [(k, v) for k, v in hs if k != "Cache-Control"]
        if mode == "csp-wrong":
            hs = [(k, v + "; img-src https://cdn.example.net" if k == "Content-Security-Policy" else v) for k, v in hs]
        if mode == "csp-missing":
            hs = [(k, v) for k, v in hs if k != "Content-Security-Policy"]
        if mode == "hsts-missing":
            hs = [(k, v) for k, v in hs if k != "Strict-Transport-Security"]
        if mode == "nosniff-wrong":
            hs = [(k, "sniff" if k == "X-Content-Type-Options" else v) for k, v in hs]
        if mode == "csp-dup":
            hs = hs + [h for h in hs if h[0] == "Content-Security-Policy"]
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in hs + list(extra):
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        base = "http://%s" % self.headers.get("Host")
        for pre in [k[:-1] for k in redirects if k.endswith("/*")]:
            if path.startswith(pre) and path not in redirects:
                redirects[path] = (redirects[pre + "*"][0].replace(":splat", path[len(pre):]), redirects[pre + "*"][1])
        if path in redirects and mode != "redirect-missing":
            target, status = redirects[path]
            if mode == "redirect-wrong-status":
                return self.send(307, extra=[("Location", target)], path=path)
            if mode == "redirect-302-as-301" and status == 302:
                return self.send(301, extra=[("Location", target)], path=path)
            if mode == "redirect-wrong-location":
                return self.send(status, extra=[("Location", "/wrong/")], path=path)
            if mode == "redirect-other-host":
                return self.send(status, extra=[("Location", "https://evil.example" + target)], path=path)
            loc = base + target if mode == "redirect-absolute" else target
            return self.send(status, extra=[("Location", loc)], path=path)
        rel = path.lstrip("/")
        if path.endswith("/"):
            rel += "index.html"
        full = os.path.normpath(os.path.join(root, rel))
        code = 200
        if mode == "page-500" and path == "/about/":
            code = 500
        gone = (mode == "robots-missing" and path == "/robots.txt") or (mode == "feed-missing" and path.endswith("/index.xml") and path != "/posts/index.xml")
        if gone or not full.startswith(root + os.sep) or not os.path.isfile(full) or rel.startswith("_"):
            full = os.path.join(root, "404.html")
            code = 200 if mode == "no-404" else 404
        data = open(full, "rb").read()
        name = full
        if name.endswith(TEXT):
            text = data.decode("utf-8")
            if rewrite_from:
                text = text.replace(rewrite_from, base)
            if code == 404 and mode == "404-indexable":
                text = text.replace("noindex", "index")
            if mode == "third-party" and path == "/":
                text = text.replace("</body>", '<img src="https://cdn.example.net/x.png"></body>')
            if mode == "css-external" and name.endswith(".css"):
                text += "\n@import url(https://fonts.example.net/a.css);\n"
            if mode == "sitemap-bad" and path == "/sitemap.xml":
                text = text[: len(text) // 2]
            if mode == "sitemap-host" and path == "/sitemap.xml":
                text = text.replace(base, "https://other.example")
            is_feed = path.endswith("/index.xml")
            if mode == "feed-bad" and is_feed:
                text = text[: len(text) // 2]
            if mode == "feed-doctype" and is_feed:
                text = '<!DOCTYPE x [<!ENTITY a "b">]>' + text
            if mode == "feed-self-other" and is_feed:
                text = text.replace('<atom:link href="' + base, '<atom:link href="https://other.example')
            if mode == "feed-self-missing" and is_feed:
                text = re.sub(r"<atom:link [^>]*/>", "", text)
            if mode == "feed-self-twice" and is_feed:
                text = text.replace("</channel>", '<atom:link href="' + base + '/index.xml" rel="self" type="application/rss+xml"/></channel>')
            if mode == "robots-flip" and path == "/robots.txt":
                text = "User-agent: *\nDisallow: /\n"
            if mode == "copy-js-wrong" and path == "/copy.js":
                text += "//x\n"
            data = text.encode("utf-8")
        ctype = "text/html"
        if name.endswith(".xml"):
            ctype = "application/xml"
        elif name.endswith(".css"):
            ctype = "text/css"
        elif name.endswith(".js"):
            ctype = "text/javascript"
        elif name.endswith(".txt"):
            ctype = "text/plain"
        self.send(code, data, ctype, path=path)


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(portfile + ".tmp", "w") as f:
    f.write(str(srv.server_address[1]))
os.replace(portfile + ".tmp", portfile)
sys.stdout.flush()
srv.serve_forever()
