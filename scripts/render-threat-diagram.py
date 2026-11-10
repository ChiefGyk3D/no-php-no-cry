#!/usr/bin/env python3
"""Render the OWASP Threat Dragon diagrams of the threat model as dark-mode SVG (issue 352).

Reads detail.diagrams[].cells from docs/threat-model/no-php-no-cry.threat-model.json
and writes one deterministic SVG per diagram next to the post that shows them.
The model supplies only labels, kinds, flows and which trust boundary holds which
element; the layout is this script's own: one band per trust boundary stacked
top to bottom, elements on a grid inside it, flows routed as orthogonal lines
that never cross an element, label chips on a segment of their own flow. Every
label comes from the model. Standard library only; no scripts, links, fonts or
external references in the output.

Usage:
  python3 -I scripts/render-threat-diagram.py            write the SVG files
  python3 -I scripts/render-threat-diagram.py --check    fail if a committed SVG
                                                          differs from a fresh render
Options: --root DIR (repository root), --model FILE, --out DIR.
After a change to the model or this script, rerun it and update the sha256 rows
of the three SVGs in brand/approved-assets.txt.
"""

import argparse
import heapq
import json
import sys
import textwrap
from pathlib import Path
from xml.sax.saxutils import escape

OUT_REL = "content/posts/new-site-no-php"
MODEL_REL = "docs/threat-model/no-php-no-cry.threat-model.json"
FILES = ["threat-model-publishing.svg", "threat-model-reader.svg", "threat-model-secrets.svg"]

W = 900
FONT = "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
FS = 17
LH = 21
CHAR_W = 0.55  # average glyph width in em, generous
MAX_LINES = 3
NW, NH = 250, 90
COLS_X = (100, 550)
GAPY = 120
BAND_X, BAND_W = 20, 860
BAND_TOP, BAND_BOT, BAND_GAP = 50, 30, 80
HEAD = 70
CELL = 10
CHIP_COLS = 220

BG = "#12141a"
TEXT = "#eceff4"
NODE_FILL = "#1e232d"
LINE = "#a5b0c0"
BOUNDARY = "#fbbf24"
STROKE = {"actor": "#8fb4ff", "process": "#7fe0a8", "store": "#e0a8ff"}

DIRS = ((0, -1), (1, 0), (0, 1), (-1, 0))  # up, right, down, left


class LayoutError(Exception):
    pass


def wrap(text, avail, fs=FS):
    cols = max(8, int(avail / (fs * CHAR_W)))
    lines = textwrap.wrap(text, cols, break_long_words=False, break_on_hyphens=False) or [text]
    if len(lines) > MAX_LINES:
        raise LayoutError("[label-too-long] %r needs %d lines, limit %d" % (text, len(lines), MAX_LINES))
    return lines


def text_w(lines, fs=FS):
    return max(len(t) for t in lines) * fs * CHAR_W


def cell_label(c):
    return (c.get("data") or {}).get("name") or ""


def flow_label(c):
    labels = c.get("labels") or []
    if labels:
        t = labels[0].get("attrs", {}).get("label", {}).get("text")
        if t:
            return t
    return cell_label(c)


def contains(box, x, y):
    return box[0] <= x <= box[0] + box[2] and box[1] <= y <= box[1] + box[3]


def rect_hit(a, b, m=0):
    return not (a[0] + a[2] + m <= b[0] or b[0] + b[2] + m <= a[0] or a[1] + a[3] + m <= b[1] or b[1] + b[3] + m <= a[1])


def seg_hits_rect(p, q, r):
    """True when the axis-aligned segment p-q touches the closed rectangle r."""
    x0, x1 = sorted((p[0], q[0]))
    y0, y1 = sorted((p[1], q[1]))
    return not (x1 < r[0] or x0 > r[0] + r[2] or y1 < r[1] or y0 > r[1] + r[3])


def build(diagram):
    """Lay out one diagram. Returns a dict of plain geometry (see geometry_problems)."""
    cells = diagram["cells"]
    bounds = [c for c in cells if c.get("shape") == "trust-boundary-box"]
    nodes = [c for c in cells if c.get("shape") in STROKE]
    flows = [c for c in cells if c.get("shape") == "flow"]
    brect = {c["id"]: (c["position"]["x"], c["position"]["y"], c["size"]["width"], c["size"]["height"]) for c in bounds}
    owner = {}
    for n in nodes:
        cx = n["position"]["x"] + n["size"]["width"] / 2
        cy = n["position"]["y"] + n["size"]["height"] / 2
        best = None
        for b in bounds:
            r = brect[b["id"]]
            if contains(r, cx, cy) and (best is None or r[2] * r[3] < brect[best][2] * brect[best][3]):
                best = b["id"]
        owner[n["id"]] = best

    # Order bands and members by first appearance in the flows, then model order.
    order, member_order = [], []
    for fl in flows:
        for end in (fl["source"]["cell"], fl["target"]["cell"]):
            if end not in member_order:
                member_order.append(end)
            if owner.get(end, "x") not in order and end in owner:
                order.append(owner[end])
    for n in nodes:
        if n["id"] not in member_order:
            member_order.append(n["id"])
        if owner[n["id"]] not in order:
            order.append(owner[n["id"]])
    for b in bounds:
        if b["id"] not in order:
            order.append(b["id"])
    by_id = {c["id"]: c for c in cells}

    title = diagram.get("title") or "Threat model diagram"
    y = HEAD
    out_nodes, out_bands, titles = {}, [], []
    for gid in order:
        members = [m for m in member_order if m in owner and owner[m] == gid]
        rows = (len(members) + 1) // 2
        boxed = gid is not None
        top = BAND_TOP if boxed else 10
        bot = BAND_BOT if boxed else 10
        h = top + (rows * NH + (rows - 1) * GAPY if rows else 0) + bot
        if boxed:
            label = cell_label(by_id[gid])
            lines = wrap(label, BAND_W - 24)
            tw = text_w(lines) + 16
            titles.append((BAND_X + 4, y + 2, tw, 8 + LH * len(lines)))
            out_bands.append({"id": gid, "label": label, "lines": lines, "rect": (BAND_X, y, BAND_W, h)})
        for i, m in enumerate(members):
            r, k = divmod(i, 2)
            ncols = min(2, len(members) - r * 2)
            shift = (2 - ncols) * (COLS_X[1] - COLS_X[0]) // 2 // 10 * 10
            nd = by_id[m]
            lines = wrap(cell_label(nd), NW - 8)
            out_nodes[m] = {
                "id": m,
                "kind": nd["shape"],
                "label": cell_label(nd),
                "lines": lines,
                "rect": (COLS_X[k] + shift, y + top + r * (NH + GAPY), NW, NH),
                "group": gid,
            }
        y += h + BAND_GAP
    height = y - BAND_GAP + 30
    titles.append((BAND_X, 4, BAND_W, 50))
    return route_all(
        {
            "title": title,
            "height": height,
            "nodes": out_nodes,
            "bands": out_bands,
            "titles": titles,
            "flows": [(fl["source"]["cell"], fl["target"]["cell"], flow_label(fl)) for fl in flows],
            "routes": [],
            "chips": [],
        }
    )


def slots(rect):
    """(side, slot cell-center point, outward direction index) for each free port of a node."""
    x, y, w, h = rect
    res = []
    for off in (55, 125, 195):
        res.append(("top", (x + off, y - 5), 0))
        res.append(("bottom", (x + off, y + h + 5), 2))
    for off in (25, 45, 65):
        res.append(("left", (x - 5, y + off), 3))
        res.append(("right", (x + w + 5, y + off), 1))
    return res


def edge_point(side, p):
    return {"top": (p[0], p[1] + 5), "bottom": (p[0], p[1] - 5), "left": (p[0] + 5, p[1]), "right": (p[0] - 5, p[1])}[side]


def route_all(lay):
    gw, gh = W // CELL, lay["height"] // CELL + 1
    blocked = set()

    def block(rect, m):
        for i in range(gw):
            for j in range(gh):
                cx, cy = i * CELL + 5, j * CELL + 5
                if rect[0] - m <= cx <= rect[0] + rect[2] + m and rect[1] - m <= cy <= rect[1] + rect[3] + m:
                    blocked.add((i, j))

    for n in lay["nodes"].values():
        block(n["rect"], 4)
    for t in lay["titles"]:
        block(t, 0)
    for i in range(gw):
        for j in range(gh):
            if i < 6 or i >= gw - 6 or j == 0 or j == gh - 1:
                blocked.add((i, j))
    near = {}
    for n in lay["nodes"].values():
        for i in range(gw):
            for j in range(gh):
                cx, cy = i * CELL + 5, j * CELL + 5
                if n["rect"][0] - 16 <= cx <= n["rect"][0] + n["rect"][2] + 16 and n["rect"][1] - 16 <= cy <= n["rect"][1] + n["rect"][3] + 16:
                    near[(i, j)] = 3
    used_cells = {}
    used_slots = set()

    def cellof(p):
        return (int(p[0]) // CELL, int(p[1]) // CELL)

    for src, dst, label in lay["flows"]:
        sn, dn = lay["nodes"][src], lay["nodes"][dst]
        starts, goals = [], {}
        for side, p, d in slots(sn["rect"]):
            if (src, side, p) in used_slots:
                continue
            o = (cellof(p)[0] + DIRS[d][0], cellof(p)[1] + DIRS[d][1])
            if cellof(p) not in blocked and o not in blocked:
                starts.append((o, d, side, p))
        for side, p, d in slots(dn["rect"]):
            if (dst, side, p) in used_slots:
                continue
            o = (cellof(p)[0] + DIRS[d][0], cellof(p)[1] + DIRS[d][1])
            if cellof(p) not in blocked and o not in blocked:
                goals[(o, (d + 2) % 4)] = (side, p)
        if not starts or not goals:
            raise LayoutError("[no-port] no free port for a flow %s -> %s" % (sn["label"], dn["label"]))
        gcells = [g[0] for g in goals]

        def h(c):
            return min(abs(c[0] - g[0]) + abs(c[1] - g[1]) for g in gcells)

        heap, best, ctr = [], {}, 0
        for o, d, side, p in starts:
            st = (o, d)
            g0 = 1
            if st not in best or g0 < best[st][0]:
                best[st] = (g0, None, (side, p))
                ctr += 1
                heapq.heappush(heap, (g0 + h(o), ctr, g0, st))
        end = None
        while heap:
            _, _, g, st = heapq.heappop(heap)
            if best[st][0] < g:
                continue
            if st in goals:
                end = st
                break
            c, d = st
            for nd in range(4):
                if nd == (d + 2) % 4:
                    continue
                nc = (c[0] + DIRS[nd][0], c[1] + DIRS[nd][1])
                if nc in blocked:
                    continue
                cost = 1 + (10 if nd != d else 0) + near.get(nc, 0) + (25 if nc in used_cells else 0)
                ns = (nc, nd)
                ng = g + cost
                if ns not in best or ng < best[ns][0]:
                    best[ns] = (ng, st, None)
                    ctr += 1
                    heapq.heappush(heap, (ng + h(nc), ctr, ng, ns))
        if end is None:
            raise LayoutError("[no-route] no route for a flow %s -> %s" % (sn["label"], dn["label"]))
        path, st = [], end
        while st is not None:
            path.append(st[0])
            prev = best[st][1]
            if prev is None:
                start_slot = best[st][2]
            st = prev
        path.reverse()
        gside, gp = goals[end]
        s_side, s_p = start_slot
        used_slots.add((src, s_side, s_p))
        used_slots.add((dst, gside, gp))
        for c in path:
            used_cells[c] = True
        pts = [edge_point(s_side, s_p), s_p] + [(c[0] * CELL + 5, c[1] * CELL + 5) for c in path] + [gp, edge_point(gside, gp)]
        pts = simplify(pts)
        lay["routes"].append({"src": src, "dst": dst, "label": label, "points": pts})
    place_chips(lay)
    return lay


def simplify(pts):
    res = []
    for p in pts:
        if res and res[-1] == p:
            continue
        res.append(p)
    changed = True
    while changed:
        changed = False
        for i in range(1, len(res) - 1):
            a, b, c = res[i - 1], res[i], res[i + 1]
            if (a[0] == b[0] == c[0]) or (a[1] == b[1] == c[1]):
                del res[i]
                changed = True
                break
    return res


def place_chips(lay):
    obstacles = [n["rect"] for n in lay["nodes"].values()] + list(lay["titles"])
    placed = []
    for rt in lay["routes"]:
        pts = rt["points"]
        segs = [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
        foreign = [(q["points"][i], q["points"][i + 1]) for q in lay["routes"] if q is not rt for i in range(len(q["points"]) - 1)]
        ends = [(q["points"][k][0] - 18, q["points"][k][1] - 18, 36, 36) for q in lay["routes"] for k in (0, -1)]
        # inner segments first, longest first; each one's midpoint, then points along it
        cand_segs = sorted(range(len(segs)), key=lambda i: (-abs(segs[i][0][0] - segs[i][1][0]) - abs(segs[i][0][1] - segs[i][1][1]), i))
        chosen = None
        for strict, cols in [(a, b) for a in (True, False) for b in (CHIP_COLS, 170, 130)]:
            try:
                lines = wrap(rt["label"], cols)
            except LayoutError:
                continue
            cw = text_w(lines) + 14
            ch = LH * len(lines) + 6
            for si in cand_segs:
                a, b = segs[si]
                length = abs(a[0] - b[0]) + abs(a[1] - b[1])
                offs = [0.5] + [0.5 + s * k / 20.0 for k in range(1, 10) for s in (-1, 1)]
                for t in offs:
                    px = a[0] + (b[0] - a[0]) * t
                    py = a[1] + (b[1] - a[1]) * t
                    if min(abs(px - pts[0][0]) + abs(py - pts[0][1]), abs(px - pts[-1][0]) + abs(py - pts[-1][1])) < 16:
                        continue
                    chip = (px - cw / 2, py - ch / 2, cw, ch)
                    if chip[0] < 4 or chip[0] + cw > W - 4 or chip[1] < 4 or chip[1] + ch > lay["height"] - 4:
                        continue
                    if any(rect_hit(chip, o, 2) for o in obstacles + [q["rect"] for q in placed] + ends):
                        continue
                    if strict and any(seg_hits_rect(sa, sb, chip) for sa, sb in foreign):
                        continue
                    chosen = {"rect": chip, "center": (px, py), "lines": lines, "route": rt}
                    break
                if chosen:
                    break
            if chosen:
                break
        if chosen is None:
            raise LayoutError("[no-chip-spot] no free spot for the label %r" % rt["label"])
        placed.append(chosen)
    lay["chips"] = placed


def geometry_problems(lay):
    """Findings for a layout: [rule] detail lines. Empty when the layout is sound."""
    bad = []
    nodes = lay["nodes"]
    bands = {b["id"]: b for b in lay["bands"]}
    for n in nodes.values():
        if n["group"] is not None:
            br = bands[n["group"]]["rect"]
            r = n["rect"]
            if not (br[0] <= r[0] and br[1] <= r[1] and r[0] + r[2] <= br[0] + br[2] and r[1] + r[3] <= br[1] + br[3]):
                bad.append("[node-outside-boundary] %s" % n["label"])
        if len(n["lines"]) > MAX_LINES:
            bad.append("[too-many-lines] %s" % n["label"])
    for rt in lay["routes"]:
        pts = rt["points"]
        for i in range(len(pts) - 1):
            p, q = pts[i], pts[i + 1]
            if p[0] != q[0] and p[1] != q[1]:
                bad.append("[diagonal-segment] %s" % rt["label"])
            for n in nodes.values():
                if n["id"] in (rt["src"], rt["dst"]):
                    continue
                if seg_hits_rect(p, q, n["rect"]):
                    bad.append("[segment-crosses-node] %s crosses %s" % (rt["label"], n["label"]))
    others = [n["rect"] for n in nodes.values()] + list(lay["titles"])
    for i, c in enumerate(lay["chips"]):
        for o in others:
            if rect_hit(c["rect"], o):
                bad.append("[chip-overlap] %s overlaps a node or title" % c["route"]["label"])
        for d in lay["chips"][i + 1 :]:
            if rect_hit(c["rect"], d["rect"]):
                bad.append("[chip-overlap] %s overlaps %s" % (c["route"]["label"], d["route"]["label"]))
        pts = c["route"]["points"]
        cx, cy = c["center"]
        if not any(seg_hits_rect(pts[k], pts[k + 1], (cx, cy, 0, 0)) for k in range(len(pts) - 1)):
            bad.append("[chip-off-route] %s" % c["route"]["label"])
    return bad


def f(n):
    s = "%.1f" % n
    return s[:-2] if s.endswith(".0") else s


def render(diagram):
    lay = build(diagram)
    probs = geometry_problems(lay)
    if probs:
        raise LayoutError("\n".join(probs))
    height = lay["height"]
    names = {n["id"]: n["label"] for n in lay["nodes"].values()}
    desc = [
        "Data flow diagram with %d trust boundaries (dashed boxes): %s." % (len(lay["bands"]), "; ".join(b["label"] for b in lay["bands"])),
        "Elements: %s." % "; ".join(n["label"] for n in lay["nodes"].values()),
        "Flows: %s." % "; ".join("%s to %s, %s" % (names[r["src"]], names[r["dst"]], r["label"]) for r in lay["routes"]),
    ]
    o = []
    o.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-labelledby="t d">' % (W, height, W, height))
    o.append('<title id="t">%s</title>' % escape(lay["title"]))
    o.append('<desc id="d">%s</desc>' % escape(" ".join(desc)))
    o.append("<defs>")
    o.append(
        '<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">'
        '<path d="M0,0 L10,5 L0,10 z" fill="%s"/></marker>' % LINE
    )
    o.append("</defs>")
    o.append('<rect width="%d" height="%d" fill="%s"/>' % (W, height, BG))
    o.append('<g font-family="%s" font-size="%d">' % (FONT, FS))
    o.append('<text x="%d" y="34" fill="%s" font-size="22" font-weight="bold">%s</text>' % (BAND_X, TEXT, escape(lay["title"])))
    for b in lay["bands"]:
        x, y, w, h = b["rect"]
        o.append('<rect x="%d" y="%d" width="%d" height="%d" rx="10" fill="none" stroke="%s" stroke-width="3" stroke-dasharray="10 6"/>' % (x, y, w, h, BOUNDARY))
        for i, line in enumerate(b["lines"]):
            o.append('<text x="%d" y="%d" fill="%s" font-weight="bold">%s</text>' % (x + 12, y + 22 + i * LH, BOUNDARY, escape(line)))
    for r in lay["routes"]:
        d = "M" + " L".join("%s %s" % (f(px), f(py)) for px, py in r["points"])
        o.append('<path d="%s" fill="none" stroke="%s" stroke-width="2" marker-end="url(#arrow)"/>' % (d, LINE))
    for n in lay["nodes"].values():
        x, y, w, h = n["rect"]
        col = STROKE[n["kind"]]
        if n["kind"] == "actor":
            o.append('<rect x="%d" y="%d" width="%d" height="%d" fill="%s" stroke="%s" stroke-width="2"/>' % (x, y, w, h, NODE_FILL, col))
        elif n["kind"] == "process":
            o.append('<rect x="%d" y="%d" width="%d" height="%d" rx="22" fill="%s" stroke="%s" stroke-width="2"/>' % (x, y, w, h, NODE_FILL, col))
        else:
            o.append('<rect x="%d" y="%d" width="%d" height="%d" fill="%s" stroke="none"/>' % (x, y, w, h, NODE_FILL))
            o.append('<path d="M%d %dH%d M%d %dH%d" stroke="%s" stroke-width="2" fill="none"/>' % (x, y, x + w, x, y + h, x + w, col))
        top = y + h / 2 - (len(n["lines"]) - 1) * LH / 2 + 6
        for i, line in enumerate(n["lines"]):
            o.append('<text x="%d" y="%s" fill="%s" text-anchor="middle">%s</text>' % (x + w // 2, f(top + i * LH), TEXT, escape(line)))
    for c in lay["chips"]:
        x, y, w, h = c["rect"]
        o.append('<rect x="%s" y="%s" width="%s" height="%s" rx="4" fill="%s"/>' % (f(x), f(y), f(w), f(h), BG))
        for i, line in enumerate(c["lines"]):
            o.append('<text x="%s" y="%s" fill="%s" text-anchor="middle">%s</text>' % (f(c["center"][0]), f(y + 3 + 15 + i * LH), TEXT, escape(line)))
    o.append("</g>")
    o.append("</svg>")
    return "\n".join(o) + "\n"


def render_all(model_path):
    model = json.loads(Path(model_path).read_text(encoding="utf-8"))
    diagrams = model["detail"]["diagrams"]
    if len(diagrams) != len(FILES):
        raise SystemExit("[diagram-count] model has %d diagrams, renderer names %d files" % (len(diagrams), len(FILES)))
    try:
        return {name: render(d) for name, d in zip(FILES, diagrams)}
    except LayoutError as e:
        raise SystemExit(str(e))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--model")
    ap.add_argument("--out")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    root = Path(a.root)
    out = Path(a.out) if a.out else root / OUT_REL
    svgs = render_all(a.model or root / MODEL_REL)
    if a.check:
        bad = 0
        for name, text in svgs.items():
            p = out / name
            if not p.is_file() or p.read_text(encoding="utf-8") != text:
                print("[svg-drift] %s differs from a fresh render; run scripts/render-threat-diagram.py" % p)
                bad = 1
        return bad
    out.mkdir(parents=True, exist_ok=True)
    for name, text in svgs.items():
        (out / name).write_text(text, encoding="utf-8", newline="\n")
        print("wrote %s" % (out / name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
