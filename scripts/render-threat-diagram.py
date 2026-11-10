#!/usr/bin/env python3
"""Render the OWASP Threat Dragon diagrams of the threat model as dark-mode SVG (issue 352).

Reads detail.diagrams[].cells from docs/threat-model/no-php-no-cry.threat-model.json
(actors, processes, stores, flows, trust-boundary boxes) and writes one
deterministic SVG per diagram next to the post that shows them. Every label comes
from the model. Standard library only; no scripts, links, fonts or external
references in the output.

Usage:
  python3 -I scripts/render-threat-diagram.py            write the SVG files
  python3 -I scripts/render-threat-diagram.py --check    fail if a committed SVG
                                                          differs from a fresh render
Options: --root DIR (repository root), --model FILE, --out DIR.
"""

import argparse
import json
import math
import sys
import textwrap
from pathlib import Path
from xml.sax.saxutils import escape

OUT_REL = "content/posts/new-site-no-php"
MODEL_REL = "docs/threat-model/no-php-no-cry.threat-model.json"
FILES = ["threat-model-publishing.svg", "threat-model-reader.svg", "threat-model-secrets.svg"]

WIDTH = 1200.0
PAD = 24.0
FONT = "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
FS = 18.0
LH = 21.0
CHAR_W = 0.52  # average glyph width in em

BG = "#12141a"
TEXT = "#eceff4"
NODE_FILL = "#1e232d"
LINE = "#a5b0c0"
BOUNDARY = "#fbbf24"
STROKE = {"actor": "#8fb4ff", "process": "#7fe0a8", "store": "#e0a8ff"}


def f(n):
    s = "%.1f" % n
    return s[:-2] if s.endswith(".0") else s


def wrap(text, avail, fs=FS):
    cols = max(8, int(avail / (fs * CHAR_W)))
    return textwrap.wrap(text, cols, break_long_words=False, break_on_hyphens=False) or [text]


def cell_label(c):
    return (c.get("data") or {}).get("name") or ""


def flow_label(c):
    labels = c.get("labels") or []
    if labels:
        t = labels[0].get("attrs", {}).get("label", {}).get("text")
        if t:
            return t
    return cell_label(c)


def clip(box, tx, ty):
    """Point where the ray from the box center toward (tx, ty) leaves the box."""
    x, y, w, h = box
    cx, cy = x + w / 2, y + h / 2
    dx, dy = tx - cx, ty - cy
    if dx == 0 and dy == 0:
        return cx, cy
    k = min((w / 2) / abs(dx) if dx else math.inf, (h / 2) / abs(dy) if dy else math.inf)
    return cx + dx * k, cy + dy * k


def quad(p0, p1, p2, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])


def inside(p, box, m):
    return box[0] - m <= p[0] <= box[0] + box[2] + m and box[1] - m <= p[1] <= box[1] + box[3] + m


def hit(a, b):
    return not (a[0] + a[2] < b[0] or b[0] + b[2] < a[0] or a[1] + a[3] < b[1] or b[1] + b[3] < a[1])


def render(diagram):
    cells = diagram["cells"]
    boxes = {}
    for c in cells:
        if "position" in c and "size" in c:
            boxes[c["id"]] = (c["position"]["x"], c["position"]["y"], c["size"]["width"], c["size"]["height"])
    minx = min(b[0] for b in boxes.values())
    miny = min(b[1] for b in boxes.values())
    maxx = max(b[0] + b[2] for b in boxes.values())
    maxy = max(b[1] + b[3] for b in boxes.values())
    s = WIDTH / (maxx - minx + 2 * PAD)
    height = (maxy - miny + 2 * PAD) * s
    title = diagram.get("title") or "Threat model diagram"

    bounds = [c for c in cells if c.get("shape") == "trust-boundary-box"]
    nodes = [c for c in cells if c.get("shape") in STROKE]
    flows = [c for c in cells if c.get("shape") == "flow"]
    names = {c["id"]: cell_label(c) for c in bounds + nodes}

    desc_parts = ["Data flow diagram with %d trust boundaries (dashed boxes): %s." % (len(bounds), "; ".join(cell_label(c) for c in bounds))]
    desc_parts.append("Elements: %s." % "; ".join(cell_label(c) for c in nodes))
    desc_parts.append(
        "Flows: %s."
        % "; ".join("%s to %s, %s" % (names.get(c["source"]["cell"], ""), names.get(c["target"]["cell"], ""), flow_label(c)) for c in flows)
    )

    o = []
    o.append(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%s" height="%s" role="img" aria-labelledby="t d">'
        % (f(WIDTH), f(round(height)), f(WIDTH), f(round(height)))
    )
    o.append("<title id=\"t\">%s</title>" % escape(title))
    o.append("<desc id=\"d\">%s</desc>" % escape(" ".join(desc_parts)))
    o.append("<defs>")
    o.append(
        '<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">'
        '<path d="M0,0 L10,5 L0,10 z" fill="%s"/></marker>' % LINE
    )
    o.append("</defs>")
    o.append('<rect width="%s" height="%s" fill="%s"/>' % (f(WIDTH), f(round(height)), BG))
    o.append('<g transform="scale(%.6f) translate(%s %s)" font-family="%s" font-size="%s">' % (s, f(PAD - minx), f(PAD - miny), FONT, f(FS)))

    blabels = []
    # Trust boundaries, biggest first so nested ones stay visible.
    for c in sorted(bounds, key=lambda c: -(c["size"]["width"] * c["size"]["height"])):
        x, y, w, h = boxes[c["id"]]
        o.append('<rect x="%s" y="%s" width="%s" height="%s" rx="10" fill="none" stroke="%s" stroke-width="3" stroke-dasharray="10 6"/>' % (f(x), f(y), f(w), f(h), BOUNDARY))
        for i, line in enumerate(wrap(cell_label(c), w - 20, 16.0)):
            blabels.append('<text x="%s" y="%s" fill="%s" font-size="16" font-weight="bold" stroke="%s" stroke-width="4" paint-order="stroke">%s</text>' % (f(x + 10), f(y + 16 + i * 17), BOUNDARY, BG, escape(line)))

    # Flows: arrows between box edges. A straight line that would cross a third
    # element, or that has a reverse twin, bends into a quadratic curve instead.
    pairs = {(c["source"]["cell"], c["target"]["cell"]) for c in flows}
    node_boxes = {c["id"]: boxes[c["id"]] for c in nodes}
    zones = []
    for c in bounds:
        bx, by, bw, _ = boxes[c["id"]]
        zones.append((bx, by, bw, 8 + 17 * len(wrap(cell_label(c), bw - 20, 16.0))))
    lo = (minx - PAD / 2, miny - PAD / 2, maxx + PAD / 2, maxy + PAD / 2)
    curves = []
    for c in flows:
        a, b = c["source"]["cell"], c["target"]["cell"]
        ba, bb = boxes[a], boxes[b]
        acx, acy = ba[0] + ba[2] / 2, ba[1] + ba[3] / 2
        bcx, bcy = bb[0] + bb[2] / 2, bb[1] + bb[3] / 2
        dx, dy = bcx - acx, bcy - acy
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        base = 30.0 if (b, a) in pairs else 0.0
        choice = None
        for off in (base, base + 40, base - 40, base + 80, base - 80, base + 130, base - 130, base + 190, base - 190, base + 260, base - 260):
            cpx, cpy = (acx + bcx) / 2 + nx * off * 2, (acy + bcy) / 2 + ny * off * 2
            x1, y1 = clip(ba, cpx, cpy)
            x2, y2 = clip(bb, cpx, cpy)
            pts = [quad((x1, y1), (cpx, cpy), (x2, y2), i / 24) for i in range(1, 24)]
            others = [bx for k, bx in node_boxes.items() if k not in (a, b)]
            ok = all(lo[0] <= p[0] <= lo[2] and lo[1] <= p[1] <= lo[3] for p in pts)
            if ok and not any(inside(p, bx, 6) for p in pts for bx in others + zones):
                choice = ((x1, y1), (cpx, cpy), (x2, y2))
                break
        if choice is None:
            choice = ((acx, acy), ((acx + bcx) / 2, (acy + bcy) / 2), (bcx, bcy))
        (x1, y1), (cpx, cpy), (x2, y2) = choice
        o.append(
            '<path d="M%s %sQ%s %s %s %s" fill="none" stroke="%s" stroke-width="2" marker-end="url(#arrow)"/>'
            % (f(x1), f(y1), f(cpx), f(cpy), f(x2), f(y2), LINE)
        )
        curves.append(((x1, y1), (cpx, cpy), (x2, y2), flow_label(c)))

    # Flow label chips: first spot along the curve that touches no element, boundary
    # label or other chip; narrower wraps are tried when the gap is short.
    labels = []
    placed = []
    obstacles = list(node_boxes.values()) + zones
    for p0, p1, p2, text in curves:
        pick = None
        for cols in (170, 120, 84):
            lines = wrap(text, cols, 16.0)
            w = max(len(t) for t in lines) * 16.0 * CHAR_W + 10
            h = len(lines) * 19.0 + 6
            for i in range(0, 15):
                t = 0.5 + (i + 1) // 2 * 0.05 * (1 if i % 2 else -1)
                mx, my = quad(p0, p1, p2, t)
                chip = (mx - w / 2, my - h / 2, w, h)
                if not any(hit(chip, bx) for bx in obstacles + placed):
                    pick = (mx, my, chip, lines)
                    break
            if pick:
                break
        if pick is None:
            lines = wrap(text, 84, 16.0)
            w = max(len(t) for t in lines) * 16.0 * CHAR_W + 10
            h = len(lines) * 19.0 + 6
            mx, my = quad(p0, p1, p2, 0.5)
            pick = (mx, my, (mx - w / 2, my - h / 2, w, h), lines)
        placed.append(pick[2])
        labels.append((pick[0], pick[1], pick[3]))

    # Elements.
    for c in nodes:
        x, y, w, h = boxes[c["id"]]
        kind = c["shape"]
        col = STROKE[kind]
        if kind == "actor":
            o.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s" stroke="%s" stroke-width="2"/>' % (f(x), f(y), f(w), f(h), NODE_FILL, col))
        elif kind == "process":
            o.append('<rect x="%s" y="%s" width="%s" height="%s" rx="22" fill="%s" stroke="%s" stroke-width="2"/>' % (f(x), f(y), f(w), f(h), NODE_FILL, col))
        else:
            o.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s" stroke="none"/>' % (f(x), f(y), f(w), f(h), NODE_FILL))
            o.append('<path d="M%s %sH%s M%s %sH%s" stroke="%s" stroke-width="2" fill="none"/>' % (f(x), f(y), f(x + w), f(x), f(y + h), f(x + w), col))
        lines = wrap(cell_label(c), w - 8)
        top = y + h / 2 - (len(lines) - 1) * LH / 2 + 5
        for i, line in enumerate(lines):
            o.append('<text x="%s" y="%s" fill="%s" text-anchor="middle">%s</text>' % (f(x + w / 2), f(top + i * LH), TEXT, escape(line)))

    # Flow labels last, on a dark chip, so lines never cross the text.
    for mx, my, lines in labels:
        w = max(len(t) for t in lines) * 16.0 * CHAR_W + 10
        h = len(lines) * 19.0 + 6
        o.append('<rect x="%s" y="%s" width="%s" height="%s" rx="4" fill="%s" fill-opacity="0.92"/>' % (f(mx - w / 2), f(my - h / 2), f(w), f(h), BG))
        for i, line in enumerate(lines):
            o.append('<text x="%s" y="%s" fill="%s" font-size="16" text-anchor="middle">%s</text>' % (f(mx), f(my - h / 2 + 19.0 + i * 19.0 - 3), TEXT, escape(line)))

    o.extend(blabels)
    o.append("</g>")
    o.append("</svg>")
    return "\n".join(o) + "\n"


def render_all(model_path):
    model = json.loads(Path(model_path).read_text(encoding="utf-8"))
    diagrams = model["detail"]["diagrams"]
    if len(diagrams) != len(FILES):
        raise SystemExit("[diagram-count] model has %d diagrams, renderer names %d files" % (len(diagrams), len(FILES)))
    return {name: render(d) for name, d in zip(FILES, diagrams)}


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
