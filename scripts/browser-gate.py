#!/usr/bin/env python3
"""Browser gate for the built site (issue 65, docs/performance-gates.md).

Usage: python3 -I scripts/browser-gate.py [site-dir] [--shots DIR] [--pages a,b] [--widths 1440,390]
       (site-dir defaults to public; CHROME names the browser binary)

Serves the built site on 127.0.0.1 with the response headers from its own
_headers file (so the real Content-Security-Policy is enforced), drives
headless Chrome over the DevTools protocol through a pipe (no WebSocket, no
Node, no pip packages), and loads one URL per template at 1440, 1024, 768 and
390 CSS px wide. The 404 template is loaded from a path that does not exist.

Fails (exit 1) on any of, printed as "[rule] page@width detail":
  overflow    the page scrolls sideways (also at 200 percent zoom and 320 px)
  console     a console error or warning, an uncaught exception, a CSP report
  network     a failed request, an HTTP status of 400 or more (except the 404
              page itself), or any request that leaves 127.0.0.1
  axe         an axe-core violation (WCAG 2.2 A/AA and best-practice rules)
  lcp, cls    Largest Contentful Paint above 2000 ms or Cumulative Layout
              Shift above 0.05, measured cold under an emulated mid-range
              phone on 4G (1.6 Mbps, 150 ms round trip, 4x CPU slowdown)
  target      a control under 44 x 44 CSS px (links inside running text are
              exempt, WCAG 2.5.8 inline exception)
  tab         keyboard: the skip link is not first, the Tab order differs from
              document order, a focused control is off screen or has no focus
              ring, or the Menu button does not open and close from the keyboard
  toggle      only if the build ships /theme.js: the theme button is missing,
              not a button, not reachable by Tab, or does not change state
  setup       axe-core does not match its pinned hash, no browser, no pages

axe-core is vendored in tools/axe (MPL-2.0, license beside it) and verified
against tools/axe/axe.min.js.sha256 before it is used; nothing is fetched.
"""
import argparse
import base64
import functools
import hashlib
import http.server
import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LCP_MAX_MS = 2000
CLS_MAX = 0.05
TARGET_PX = 44
# Lighthouse's mobile preset: Slow 4G, 4x CPU slowdown. Bytes per second.
NET = dict(offline=False, latency=150, downloadThroughput=int(1.6 * 1024 * 1024 / 8), uploadThroughput=int(0.75 * 1024 * 1024 / 8))
CPU_SLOWDOWN = 4
FULL_WIDTHS = [1440, 1024, 768, 390]
# Zoom: 1440 px at 200 percent is 720 CSS px at device pixel ratio 2; 320 px is
# 400 percent of 1280 and the WCAG 1.4.10 reflow width.
ZOOM_VIEWPORTS = [("zoom200", 720, 450, 2), ("reflow320", 320, 256, 1)]
PAGES = [
    ("home", "/"),
    ("posts", "/posts/"),
    ("post", None),  # first post found in the build
    ("social", "/social/"),
    ("products", "/products/"),
    ("support", "/support/"),
    ("about", "/about/"),
    ("resume", "/resume/"),
    ("privacy", "/privacy/"),
    ("404", "/no-such-page-gate/"),
]
AXE_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"]

OBSERVERS = """
window.__m = {lcp: 0, cls: 0, src: []};
new PerformanceObserver(l => { for (const e of l.getEntries()) window.__m.lcp = e.startTime; })
  .observe({type: 'largest-contentful-paint', buffered: true});
new PerformanceObserver(l => { for (const e of l.getEntries()) if (!e.hadRecentInput) {
    window.__m.cls += e.value;
    for (const s of e.sources || []) if (s.node && window.__m.src.length < 6)
      window.__m.src.push((s.node.nodeName || '?').toLowerCase() + (s.node.className ? '.' + String(s.node.className).split(' ')[0] : '') + ' ' + e.value.toFixed(3));
  } })
  .observe({type: 'layout-shift', buffered: true});
"""

JS_OVERFLOW = """(() => { const d = document.documentElement;
  return Math.max(d.scrollWidth - d.clientWidth, document.body.scrollWidth - d.clientWidth); })()"""

# Controls under 44 x 44. Skips what is not rendered or is clipped to a pixel
# (the skip link until focused), and links inside running text.
JS_TARGETS = """((px) => {
  const out = [];
  const sel = 'a[href],button,summary,input:not([type=hidden]),select,textarea,[role=button],[tabindex]';
  for (const e of document.querySelectorAll(sel)) {
    if (!e.checkVisibility()) continue;
    const r = e.getBoundingClientRect();
    if (r.width <= 1 || r.height <= 1) continue;
    if (r.right <= 0 || r.bottom <= 0 || r.left >= innerWidth) continue;  // parked off screen (skip link)
    if (e.tabIndex < 0 && !e.matches('a[href],button,summary,input,select,textarea')) continue;
    if (e.tagName === 'A') {
      const b = e.closest('p,li,blockquote,figcaption,dd,dt,td,th');
      // Inline: the block holds running text of its own (a direct text node, not
      // just the text of a date or a count in a child element).
      if (b && [...b.childNodes].some(n => n.nodeType === 3 && /[A-Za-z0-9]/.test(n.textContent))) continue;
    }
    if (r.width < px - 0.01 || r.height < px - 0.01) {
      out.push(e.tagName.toLowerCase() + (e.className ? '.' + String(e.className).split(' ')[0] : '') +
        ' "' + (e.getAttribute('aria-label') || e.textContent.trim()).slice(0, 24) + '" ' +
        Math.round(r.width) + 'x' + Math.round(r.height));
    }
  }
  return out;
})(%d)"""

# Tags the controls that can take Tab focus, in document order, and reports
# tabindex above zero (which would reorder the walk).
JS_TABBABLE = """(() => {
  const sel = 'a[href],button,summary,input:not([type=hidden]),select,textarea,[tabindex]';
  const list = [...document.querySelectorAll(sel)].filter(e =>
    e.tabIndex >= 0 && !e.disabled && e.checkVisibility() && !e.closest('[inert]'));
  list.forEach((e, i) => { e.__tab = i; });
  return {n: list.length, positive: list.filter(e => e.tabIndex > 0).length,
          first: list.length ? (list[0].getAttribute('href') || '') + '|' + list[0].textContent.trim().slice(0, 30) : ''};
})()"""

JS_FOCUS = """(() => {
  const e = document.activeElement;
  if (!e || e === document.body || e === document.documentElement) return null;
  const r = e.getBoundingClientRect(), cs = getComputedStyle(e);
  return {i: e.__tab === undefined ? -1 : e.__tab,
          name: e.tagName.toLowerCase() + ' "' + (e.getAttribute('aria-label') || e.textContent.trim()).slice(0, 24) + '"',
          onscreen: r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth,
          ring: (cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0) || cs.boxShadow !== 'none'};
})()"""


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def load_axe(js_path, hash_path):
    """Return the axe source after checking it against the pinned hash."""
    with open(hash_path, "r", encoding="ascii") as f:
        parts = f.read().split()
    if not parts or len(parts[0]) != 64:
        raise SystemExit("[setup] %s is not a sha256sum line" % hash_path)
    if sha256(js_path) != parts[0]:
        raise SystemExit("[setup] %s does not match the pinned hash in %s" % (js_path, hash_path))
    with open(js_path, "r", encoding="utf-8") as f:
        return f.read()


def find_chrome():
    for name in (os.environ.get("CHROME"), "google-chrome", "chromium", "chromium-browser"):
        if name and shutil.which(name):
            return shutil.which(name)
    raise SystemExit("[setup] no headless Chrome or Chromium found (set CHROME)")


class Handler(http.server.SimpleHTTPRequestHandler):
    headers_to_send = []
    site = ""

    def end_headers(self):
        for k, v in self.headers_to_send:
            self.send_header(k, v)
        super().end_headers()

    def send_error(self, code, message=None, explain=None):
        page = os.path.join(self.site, "404.html")
        if code == 404 and os.path.isfile(page):
            with open(page, "rb") as f:
                body = f.read()
            self.send_response(404)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
        else:
            super().send_error(code, message, explain)

    def log_message(self, *a):
        pass


def start_server(site):
    hdrs, in_block = [], False
    path = os.path.join(site, "_headers")
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                if not line[0].isspace():
                    in_block = line.strip() == "/*"
                elif in_block and ":" in line:
                    k, v = line.split(":", 1)
                    hdrs.append((k.strip(), v.strip()))
    cls = type("H", (Handler,), {"headers_to_send": hdrs, "site": site})
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(cls, directory=site))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


class Cdp:
    """DevTools protocol over --remote-debugging-pipe: JSON messages, NUL separated."""

    def __init__(self, binary, profile):
        r1, w1 = os.pipe()  # we write, Chrome reads (its fd 3)
        r2, w2 = os.pipe()  # Chrome writes (its fd 4), we read
        hi = [os.dup(fd) for fd in (r1, w2)]
        for fd in hi:
            os.set_inheritable(fd, True)

        def pre():
            os.dup2(hi[0], 3)
            os.dup2(hi[1], 4)

        args = [binary, "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-extensions",
                "--disable-background-networking", "--disable-component-update", "--no-first-run",
                "--no-default-browser-check", "--mute-audio", "--user-data-dir=" + profile,
                "--remote-debugging-pipe", "about:blank"]
        self.proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, preexec_fn=pre, pass_fds=(3, 4))
        for fd in (r1, w2, *hi):
            os.close(fd)
        self.out = os.fdopen(w1, "wb", buffering=0)
        self.q = queue.Queue()
        self.events = []
        self.mid = 0
        threading.Thread(target=self._read, args=(r2,), daemon=True).start()

    def _read(self, fd):
        buf = b""
        with os.fdopen(fd, "rb", buffering=0) as f:
            while True:
                try:
                    chunk = f.read(65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
                while b"\0" in buf:
                    msg, buf = buf.split(b"\0", 1)
                    self.q.put(json.loads(msg))
        self.q.put(None)

    def call(self, method, params=None, session=None, timeout=30):
        self.mid += 1
        msg = {"id": self.mid, "method": method, "params": params or {}}
        if session:
            msg["sessionId"] = session
        self.out.write(json.dumps(msg).encode() + b"\0")
        end = time.time() + timeout
        while True:
            m = self._next(end, method)
            if m.get("id") == self.mid:
                if "error" in m:
                    raise RuntimeError("%s: %s" % (method, m["error"].get("message")))
                return m.get("result", {})
            self.events.append(m)

    def _next(self, end, what):
        left = end - time.time()
        if left <= 0:
            raise TimeoutError("timed out waiting for " + what)
        try:
            m = self.q.get(timeout=left)
        except queue.Empty:
            raise TimeoutError("timed out waiting for " + what)
        if m is None:
            raise RuntimeError("Chrome closed the pipe")
        return m

    def pump(self, seconds):
        """Collect events for a fixed time."""
        end = time.time() + seconds
        while time.time() < end:
            try:
                m = self.q.get(timeout=max(0.01, end - time.time()))
            except queue.Empty:
                break
            if m is None:
                raise RuntimeError("Chrome closed the pipe")
            self.events.append(m)

    def wait_event(self, method, session, timeout=30):
        end = time.time() + timeout
        while True:
            for m in self.events:
                if m.get("method") == method and m.get("sessionId") == session:
                    return m
            self.events.append(self._next(end, method))

    def close(self):
        try:
            self.call("Browser.close", timeout=5)
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()
            self.proc.wait()


class Page:
    def __init__(self, cdp):
        self.c = cdp
        tid = cdp.call("Target.createTarget", {"url": "about:blank"})["targetId"]
        self.tid = tid
        self.s = cdp.call("Target.attachToTarget", {"targetId": tid, "flatten": True})["sessionId"]

    def call(self, method, params=None, timeout=30):
        return self.c.call(method, params, self.s, timeout)

    def js(self, expr, timeout=60):
        r = self.call("Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": True}, timeout)
        if "exceptionDetails" in r:
            raise RuntimeError("page script failed: " + json.dumps(r["exceptionDetails"].get("exception", {}).get("description", ""))[:300])
        return r.get("result", {}).get("value")

    def key(self, key, code, vk, text=None):
        for typ in ("keyDown", "keyUp"):
            p = {"type": typ, "key": key, "code": code, "windowsVirtualKeyCode": vk}
            if text and typ == "keyDown":
                p["text"] = text
            self.call("Input.dispatchKeyEvent", p)

    def events(self):
        return [m for m in self.c.events if m.get("sessionId") == self.s]

    def close(self):
        try:
            self.c.call("Target.closeTarget", {"targetId": self.tid}, timeout=5)
        except Exception:
            pass
        self.c.events[:] = [m for m in self.c.events if m.get("sessionId") != self.s]


def keyboard(pg, label, fails, menu):
    """Tab through the page; every control gets focus in document order."""
    pg.js("document.activeElement && document.activeElement.blur(); window.scrollTo(0, 0)")
    info = pg.js(JS_TABBABLE)
    if info["n"] == 0:
        fails.append("[tab] %s no focusable control at all" % label)
        return
    if info["positive"]:
        fails.append("[tab] %s %d control(s) with tabindex above 0 reorder the walk" % (label, info["positive"]))
    if not info["first"].startswith("#"):
        fails.append("[tab] %s the first control is not the skip link (%s)" % (label, info["first"]))
    seen = []
    for _ in range(info["n"]):
        pg.key("Tab", "Tab", 9)
        f = pg.js(JS_FOCUS)
        if f is None:
            break
        seen.append(f)
        if not f["onscreen"]:
            fails.append("[tab] %s %s took focus but is off screen" % (label, f["name"]))
        if not f["ring"]:
            fails.append("[tab] %s %s has no visible focus ring" % (label, f["name"]))
    order = [f["i"] for f in seen]
    if order != list(range(info["n"])):
        fails.append("[tab] %s Tab order differs from document order: reached %d of %d controls, sequence %s" % (
            label, len(order), info["n"], order[:12]))
    if menu:
        has = pg.js("(() => { const s = document.querySelector('.nav-menu summary'); return !!s && s.checkVisibility(); })()")
        if has:
            pg.js("document.querySelector('.nav-menu summary').focus()")
            pg.key("Enter", "Enter", 13, "\r")
            if not pg.js("document.querySelector('.nav-menu').open"):
                fails.append("[tab] %s the Menu button does not open from the keyboard (Enter)" % label)
            else:
                pg.key("Tab", "Tab", 9)
                if not pg.js("!!document.activeElement.closest('.nav-menu ul')"):
                    fails.append("[tab] %s after opening the menu, Tab does not enter the menu list" % label)
                pg.js("document.querySelector('.nav-menu summary').focus()")
                pg.key("Enter", "Enter", 13, "\r")
                if pg.js("document.querySelector('.nav-menu').open"):
                    fails.append("[tab] %s the Menu button does not close from the keyboard (Enter)" % label)


def toggle(pg, label, fails):
    """Only when the build ships /theme.js: the toggle is a real, reachable button that changes state."""
    btn = "(document.querySelector('header button[aria-pressed],header [data-theme-toggle]'))"
    if not pg.js("!!" + btn):
        fails.append("[toggle] %s /theme.js ships but there is no theme button in the header" % label)
        return
    if pg.js(btn + ".tagName") != "BUTTON":
        fails.append("[toggle] %s the theme control is not a <button>" % label)
        return
    pg.js(btn + ".__tabprobe = 1")
    reached = False
    pg.js("document.activeElement && document.activeElement.blur(); window.scrollTo(0, 0)")
    for _ in range(80):
        pg.key("Tab", "Tab", 9)
        if pg.js("!!document.activeElement && document.activeElement.__tabprobe === 1"):
            reached = True
            break
    if not reached:
        fails.append("[toggle] %s the theme button is not reachable by Tab" % label)
        return
    before = pg.js("document.documentElement.getAttribute('data-theme') + '|' + " + btn + ".getAttribute('aria-pressed')")
    pg.key("Enter", "Enter", 13, "\r")
    after = pg.js("document.documentElement.getAttribute('data-theme') + '|' + " + btn + ".getAttribute('aria-pressed')")
    if before == after:
        fails.append("[toggle] %s Enter on the theme button changed nothing (%s)" % (label, before))


def run_one(cdp, base, name, url, width, height, dpr, mobile, full, axe_src, has_theme, shots, fails, rows):
    label = "%s@%d%s" % (name, width, "" if full else "(zoom)")
    pg = Page(cdp)
    try:
        pg.call("Page.enable")
        pg.call("Network.enable")
        pg.call("Network.setCacheDisabled", {"cacheDisabled": True})
        pg.call("Runtime.enable")
        pg.call("Log.enable")
        pg.call("Emulation.setDeviceMetricsOverride", {"width": width, "height": height, "deviceScaleFactor": dpr, "mobile": mobile})
        pg.call("Emulation.setFocusEmulationEnabled", {"enabled": True})
        pg.call("Page.addScriptToEvaluateOnNewDocument", {"source": OBSERVERS})
        if full:
            pg.call("Network.emulateNetworkConditions", NET)
            pg.call("Emulation.setCPUThrottlingRate", {"rate": CPU_SLOWDOWN})
        pg.call("Page.navigate", {"url": base + url})
        cdp.wait_event("Page.loadEventFired", pg.s, 60)
        pg.js("document.fonts.ready.then(() => new Promise(r => setTimeout(r, 700)))")
        m = pg.js("window.__m")
        if full:
            pg.call("Network.emulateNetworkConditions", dict(NET, latency=0, downloadThroughput=-1, uploadThroughput=-1))
            pg.call("Emulation.setCPUThrottlingRate", {"rate": 1})
        cdp.pump(0.2)

        # Console and network.
        reqs, n_req = {}, 0
        for e in pg.events():
            meth, p = e["method"], e.get("params", {})
            if meth == "Network.requestWillBeSent":
                u = p["request"]["url"]
                reqs[p["requestId"]] = u
                n_req += 1
                if u.startswith(("http:", "https:", "ws:", "wss:")) and not u.startswith(base):
                    fails.append("[network] %s request leaves the site: %s" % (label, u.split("?")[0][:120]))
            elif meth == "Network.responseReceived":
                st, u = p["response"]["status"], p["response"]["url"]
                if st >= 400 and not (name == "404" and u == base + url and st == 404):
                    fails.append("[network] %s HTTP %d for %s" % (label, st, u[len(base):][:120]))
            elif meth == "Network.loadingFailed" and not p.get("canceled"):
                fails.append("[network] %s request failed (%s): %s" % (label, p.get("errorText"), reqs.get(p["requestId"], "?")[len(base):][:120]))
            elif meth == "Runtime.consoleAPICalled" and p["type"] in ("error", "warning", "assert"):
                fails.append("[console] %s console.%s: %s" % (label, p["type"], " ".join(str(a.get("value", a.get("description", ""))) for a in p["args"])[:160]))
            elif meth == "Runtime.exceptionThrown":
                fails.append("[console] %s uncaught exception: %s" % (label, p["exceptionDetails"].get("text", "")[:160]))
            elif meth == "Log.entryAdded" and p["entry"]["level"] in ("error", "warning"):
                en = p["entry"]
                # The 404 page's own 404 response is logged as a network error.
                if name == "404" and en.get("source") == "network" and en.get("url") == base + url:
                    continue
                fails.append("[console] %s %s %s: %s" % (label, en.get("source"), en["level"], en["text"][:160]))

        ov = pg.js(JS_OVERFLOW)
        if ov > 0:
            fails.append("[overflow] %s the page is %d px wider than the viewport" % (label, ov))

        row = {"label": label, "lcp": None, "cls": None, "req": n_req}
        if full:
            row["lcp"], row["cls"] = m["lcp"], m["cls"]
            if m["lcp"] > LCP_MAX_MS:
                fails.append("[lcp] %s %.0f ms, limit %d" % (label, m["lcp"], LCP_MAX_MS))
            if m["lcp"] <= 0:
                fails.append("[lcp] %s no Largest Contentful Paint was reported" % label)
            if m["cls"] > CLS_MAX:
                fails.append("[cls] %s %.4f, limit %s (shifted: %s)" % (label, m["cls"], CLS_MAX, ", ".join(m["src"])))
            pg.js(axe_src)
            viol = pg.js("axe.run(document, {runOnly: {type: 'tag', values: %s}, resultTypes: ['violations']})"
                         ".then(r => r.violations.map(v => ({id: v.id, impact: v.impact, n: v.nodes.length, "
                         "t: v.nodes.slice(0, 3).map(n => n.target.join(' '))})))" % json.dumps(AXE_TAGS))
            for v in viol:
                fails.append("[axe] %s %s (%s) %d node(s): %s" % (label, v["id"], v["impact"], v["n"], "; ".join(v["t"])[:200]))
            for t in pg.js(JS_TARGETS % TARGET_PX):
                fails.append("[target] %s under %dx%d: %s" % (label, TARGET_PX, TARGET_PX, t))
        keyboard(pg, label, fails, menu=full and width <= 768)
        if has_theme and name == "home" and width in (1440, 390):
            toggle(pg, label, fails)
        if shots:
            h = pg.call("Page.getLayoutMetrics")["cssContentSize"]["height"]
            data = pg.call("Page.captureScreenshot", {"format": "png", "captureBeyondViewport": True,
                                                       "clip": {"x": 0, "y": 0, "width": width, "height": min(h, 6000), "scale": 1}})["data"]
            with open(os.path.join(shots, "%s-%d%s.png" % (name, width, "" if full else "-zoom")), "wb") as f:
                f.write(base64.b64decode(data))
        rows.append(row)
    except (TimeoutError, RuntimeError) as err:
        fails.append("[setup] %s browser run failed: %s" % (label, err))
    finally:
        pg.close()


def first_post(site):
    d = os.path.join(site, "posts")
    if os.path.isdir(d):
        for n in sorted(os.listdir(d)):
            if os.path.isfile(os.path.join(d, n, "index.html")):
                return "/posts/%s/" % n
    for dp, _, files in os.walk(site):
        if "index.html" in files and "/20" in dp[len(site):]:
            return dp[len(site):] + "/"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("site", nargs="?", default="public")
    ap.add_argument("--shots")
    ap.add_argument("--pages", help="comma list of template names (default: all)")
    ap.add_argument("--widths", help="comma list of widths (default: 1440,1024,768,390)")
    ap.add_argument("--no-zoom", action="store_true")
    ap.add_argument("--axe", default=os.path.join(ROOT, "tools", "axe", "axe.min.js"))
    ap.add_argument("--axe-sha256", default=os.path.join(ROOT, "tools", "axe", "axe.min.js.sha256"))
    a = ap.parse_args()

    site = os.path.abspath(a.site)
    if not os.path.isfile(os.path.join(site, "index.html")):
        print("[setup] %s has no index.html" % site)
        return 1
    axe_src = load_axe(a.axe, a.axe_sha256)
    chrome = find_chrome()
    widths = [int(w) for w in a.widths.split(",")] if a.widths else FULL_WIDTHS
    want = set(a.pages.split(",")) if a.pages else None
    pages = []
    for name, url in PAGES:
        if want and name not in want:
            continue
        if name == "post":
            url = first_post(site)
            if not url:
                print("[setup] no post found in the build")
                return 1
        pages.append((name, url))
    if not pages:
        print("[setup] no pages selected")
        return 1
    if a.shots:
        os.makedirs(a.shots, exist_ok=True)
    has_theme = os.path.isfile(os.path.join(site, "theme.js"))

    srv = start_server(site)
    base = "http://127.0.0.1:%d" % srv.server_address[1]
    profile = tempfile.mkdtemp(prefix="browser-gate.")
    cdp = Cdp(chrome, profile)
    fails, rows = [], []
    try:
        for name, url in pages:
            for w in widths:
                run_one(cdp, base, name, url, w, 900 if w > 500 else 844, 1, w <= 500, True, axe_src, has_theme, a.shots, fails, rows)
            if not a.no_zoom:
                for zname, zw, zh, dpr in ZOOM_VIEWPORTS:
                    run_one(cdp, base, name, url, zw, zh, dpr, False, False, axe_src, has_theme, a.shots, fails, rows)
    finally:
        cdp.close()
        srv.shutdown()
        shutil.rmtree(profile, ignore_errors=True)

    print("%-16s %9s %7s %5s" % ("page@width", "LCP ms", "CLS", "reqs"))
    for r in rows:
        print("%-16s %9s %7s %5d" % (r["label"], "-" if r["lcp"] is None else "%.0f" % r["lcp"],
                                      "-" if r["cls"] is None else "%.4f" % r["cls"], r["req"]))
    if not rows:
        fails.append("[setup] no page was measured")
    if fails:
        print("\n".join(sorted(set(fails))))
        print("browser gate: %d finding(s)" % len(set(fails)))
        return 1
    print("browser gate: ok (%d runs, LCP <= %d ms, CLS <= %s)" % (len(rows), LCP_MAX_MS, CLS_MAX))
    return 0


if __name__ == "__main__":
    sys.exit(main())
