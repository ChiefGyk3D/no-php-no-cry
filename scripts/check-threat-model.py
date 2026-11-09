#!/usr/bin/env python3
"""Check the OWASP Threat Dragon model in docs/threat-model/ (Python standard library only).

Usage: python3 -I scripts/check-threat-model.py [--root DIR] [--model FILE]

Default model: docs/threat-model/no-php-no-cry.threat-model.json under the root.

The structure follows the published Threat Dragon v2 schema
(td.vue/src/assets/schema/threat-dragon-v2.schema.json in OWASP/threat-dragon,
read 2026-11-09, app release 2.6.2). The required keys are the schema's own.
The status, severity and per-element STRIDE tables are read from the app's
source (td.vue/src/service/threats/status.js, the severity list in the threat
dialog, td.vue/src/service/threats/models/stride.json). Findings print as
"[rule] location detail"; the exit status is 1 when there is any.

Rules:
  parse            the file is not valid JSON
  top-level        version, summary (title), detail are required
  detail           contributors, diagrams, diagramTop, reviewer, threatTop are required;
                   diagrams is a non-empty list
  diagram          each diagram has diagramType, id, thumbnail, title, version and cells;
                   ids are unique integers; the type is STRIDE; each has a trust boundary
  cell             each cell has id, shape and zIndex; ids are unique across the model;
                   data.type and data.hasOpenThreats are present; hasOpenThreats is true
                   exactly when a threat is Open
  flow             a flow's source and target name cells of the same diagram
  threat           every threat has non-empty description, mitigation, severity, status,
                   title and type; status and severity are values the app writes; the
                   type is allowed for the element kind (STRIDE table); ids and numbers
                   are unique; threatTop is at least the highest number
  (cell and top-level rules also cover the schema's size, position, stroke, id and version-length limits)
  mitigated-path   a Mitigated threat cites at least one path in this repository
  bad-path         a path-like word in a mitigation or description names a file or folder
                   that does not exist
  em-dash          an em dash anywhere in the file (house style)

A path-like word has a slash and starts with a top-level folder or file of the repository,
or is a bare file name with a known extension that exists nowhere in the tree.

Exit codes: 0 clean, 1 a finding, 2 usage.
"""

import json
import os
import re
import sys

DEFAULT_MODEL = os.path.join("docs", "threat-model", "no-php-no-cry.threat-model.json")

STATUSES = {"NotApplicable", "Open", "Mitigated", "Accepted", "Transferred", "Avoided", "Eliminated"}
SEVERITIES = {"TBD", "Low", "Medium", "High", "Critical"}
ELEMENT_KINDS = {"tm.Actor": "actor", "tm.Process": "process", "tm.Store": "store", "tm.Flow": "flow"}
STRIDE_BY_KIND = {
    "actor": {"Spoofing", "Repudiation"},
    "store": {"Tampering", "Repudiation", "Information disclosure", "Denial of service"},
    "process": {"Spoofing", "Tampering", "Repudiation", "Information disclosure", "Denial of service",
                "Elevation of privilege"},
    "flow": {"Tampering", "Information disclosure", "Denial of service"},
}
EXTENSIONS = (".md", ".yml", ".yaml", ".py", ".sh", ".mjs", ".js", ".json", ".toml", ".sql", ".xml",
              ".sha256", ".html", ".css", ".txt")
SKIP_DIRS = {".git", "tmp", "public", "node_modules", "resources"}
EM_DASH = "—"
EM_DASH_ESCAPED = "\\" + "u2014"  # how a JSON writer spells it with ASCII output
WORD = re.compile(r"[A-Za-z0-9_.][A-Za-z0-9_./-]*")


class Findings:
    def __init__(self):
        self.items = []

    def add(self, rule, where, detail):
        self.items.append("[%s] %s %s" % (rule, where, detail))


def repo_index(root):
    top = set(os.listdir(root))
    names = set()
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            names.add(f)
    return top, names


def cited_paths(text, root, top, names):
    """Return (existing, missing) path-like words found in text."""
    ok, missing = [], []
    real_root = os.path.realpath(root)
    text = re.sub(r"\S+://\S+", " ", text)
    for raw in WORD.findall(text):
        w = raw.rstrip(".-")
        if not w or w.startswith("/"):
            continue
        if "/" in w:
            norm = os.path.normpath(w)
            if norm == ".." or norm.startswith("../") or os.path.isabs(norm):
                missing.append(w)  # climbs out of the repository
                continue
            first = norm.split("/", 1)[0]
            if first not in top:
                continue
            real = os.path.realpath(os.path.join(root, norm))
            inside = real == real_root or real.startswith(real_root + os.sep)
            (ok if inside and os.path.exists(real) else missing).append(w)
        elif w.lower().endswith(EXTENSIONS) and len(w) > 4 and not w.startswith("."):
            (ok if w in names or w in top else missing).append(w)
        elif w.startswith(".") and w.lower().endswith(EXTENSIONS):
            (ok if w in names or w in top else missing).append(w)
    return ok, missing


def need(obj, key, kind, where, f, rule):
    if not isinstance(obj, dict) or key not in obj:
        f.add(rule, where, "missing key %r" % key)
        return None
    v = obj[key]
    if kind is not None and (not isinstance(v, kind) or isinstance(v, bool) and kind is int):
        f.add(rule, where, "key %r has the wrong type" % key)
        return None
    return v


def nonempty(obj, key, where, f):
    v = obj.get(key) if isinstance(obj, dict) else None
    if not isinstance(v, str) or not v.strip():
        f.add("threat", where, "%s is missing or empty" % key)
        return None
    return v


def check_cell_geometry(c, cwhere, f):
    """Constraints the v2 schema puts on a cell's position, size and stroke attributes."""
    cid = c.get("id")
    if isinstance(cid, str) and len(cid) < 2:
        f.add("cell", cwhere, "id is shorter than the schema's 2 characters")
    pos = c.get("position")
    if pos is not None:
        for k in ("x", "y"):
            if not isinstance(pos, dict) or not isinstance(pos.get(k), (int, float)) or isinstance(pos.get(k), bool):
                f.add("cell", cwhere, "position needs a numeric %s" % k)
    size = c.get("size")
    if size is not None:
        for k in ("width", "height"):
            v = size.get(k) if isinstance(size, dict) else None
            if not isinstance(v, (int, float)) or isinstance(v, bool) or v < 10:
                f.add("cell", cwhere, "size needs a numeric %s of at least 10" % k)
    attrs = c.get("attrs")
    if isinstance(attrs, dict):
        body = attrs.get("body")
        if isinstance(body, dict):
            for k in ("stroke", "strokeWidth", "strokeDasharray"):
                if k not in body:
                    f.add("cell", cwhere, "attrs.body is missing %s" % k)
        line = attrs.get("line")
        if isinstance(line, dict) and "targetMarker" not in line:
            f.add("cell", cwhere, "attrs.line is missing targetMarker")


def check_model(model, root, f):
    top, names = repo_index(root)
    ver = need(model, "version", str, "model", f, "top-level")
    if isinstance(ver, str) and len(ver) > 10:
        f.add("top-level", "model", "version is longer than the schema's 10 characters")
    summary = need(model, "summary", dict, "model", f, "top-level")
    if summary is not None:
        need(summary, "title", str, "summary", f, "top-level")
    detail = need(model, "detail", dict, "model", f, "top-level")
    if detail is None:
        return
    contributors = need(detail, "contributors", list, "detail", f, "detail")
    for ct in contributors or []:
        if not isinstance(ct, dict) or ("name" in ct and not isinstance(ct["name"], str)):
            f.add("detail", "detail", "each contributor must be an object with a string name")
    need(detail, "reviewer", str, "detail", f, "detail")
    diagram_top = need(detail, "diagramTop", int, "detail", f, "detail")
    threat_top = need(detail, "threatTop", int, "detail", f, "detail")
    diagrams = need(detail, "diagrams", list, "detail", f, "detail")
    if not diagrams:
        if diagrams is not None:
            f.add("detail", "detail", "diagrams is empty")
        return

    cell_ids, diagram_ids, threat_ids, threat_numbers = set(), set(), set(), set()
    for di, dg in enumerate(diagrams):
        dwhere = "diagram[%d]" % di
        if not isinstance(dg, dict):
            f.add("diagram", dwhere, "is not an object")
            continue
        for key, kind in (("diagramType", str), ("id", int), ("thumbnail", str), ("title", str),
                          ("version", str), ("cells", list)):
            need(dg, key, kind, dwhere, f, "diagram")
        if dg.get("diagramType") != "STRIDE":
            f.add("diagram", dwhere, "diagramType must be STRIDE (the threat types below are STRIDE)")
        if isinstance(dg.get("version"), str) and len(dg["version"]) > 10:
            f.add("diagram", dwhere, "version is longer than the schema's 10 characters")
        did = dg.get("id")
        if isinstance(did, int):
            if did in diagram_ids:
                f.add("diagram", dwhere, "duplicate diagram id %r" % did)
            diagram_ids.add(did)
            if diagram_top is not None and did >= diagram_top:
                f.add("diagram", dwhere, "id %d is not below diagramTop %d" % (did, diagram_top))
        cells = dg.get("cells") if isinstance(dg.get("cells"), list) else []
        local_ids = {c.get("id") for c in cells if isinstance(c, dict)}
        boundaries = 0
        for ci, c in enumerate(cells):
            cwhere = "%s.cell[%d]" % (dwhere, ci)
            if not isinstance(c, dict):
                f.add("cell", cwhere, "is not an object")
                continue
            cid = c.get("id")
            for key, kind in (("id", str), ("shape", str), ("zIndex", int)):
                need(c, key, kind, cwhere, f, "cell")
            if isinstance(cid, str):
                cwhere = "%s(%s)" % (cwhere, cid[:8])
                if cid in cell_ids:
                    f.add("cell", cwhere, "duplicate cell id")
                cell_ids.add(cid)
            check_cell_geometry(c, cwhere, f)
            data = need(c, "data", dict, cwhere, f, "cell")
            if data is None:
                continue
            dtype = need(data, "type", str, cwhere + ".data", f, "cell")
            hot = need(data, "hasOpenThreats", bool, cwhere + ".data", f, "cell")
            if dtype in ("tm.Boundary", "tm.BoundaryBox") or data.get("isTrustBoundary") is True:
                boundaries += 1
                continue
            if c.get("shape") == "flow":
                for end in ("source", "target"):
                    e = c.get(end)
                    ref = e.get("cell") if isinstance(e, dict) else None
                    if ref not in local_ids:
                        f.add("flow", cwhere, "%s does not name a cell of this diagram" % end)
            kind = ELEMENT_KINDS.get(dtype)
            if kind is None:
                f.add("cell", cwhere, "unknown data.type %r" % dtype)
                continue
            threats = data.get("threats", [])
            if not isinstance(threats, list):
                f.add("threat", cwhere, "threats is not a list")
                continue
            open_seen = False
            for ti, t in enumerate(threats):
                twhere = "%s.threat[%d]" % (cwhere, ti)
                if not isinstance(t, dict):
                    f.add("threat", twhere, "is not an object")
                    continue
                title = nonempty(t, "title", twhere, f)
                desc = nonempty(t, "description", twhere, f)
                mit = nonempty(t, "mitigation", twhere, f)
                sev = nonempty(t, "severity", twhere, f)
                status = nonempty(t, "status", twhere, f)
                ttype = nonempty(t, "type", twhere, f)
                if title:
                    twhere = "%s %r" % (twhere, title[:40])
                if sev and sev not in SEVERITIES:
                    f.add("threat", twhere, "severity %r is not one of %s" % (sev, sorted(SEVERITIES)))
                if status and status not in STATUSES:
                    f.add("threat", twhere, "status %r is not one the app writes" % status)
                if status == "Open":
                    open_seen = True
                if ttype and t.get("modelType") == "STRIDE" and ttype not in STRIDE_BY_KIND[kind]:
                    f.add("threat", twhere, "type %r is not allowed on a %s in STRIDE" % (ttype, kind))
                if t.get("modelType") != "STRIDE":
                    f.add("threat", twhere, "modelType must be STRIDE")
                tid = t.get("id")
                if not isinstance(tid, str) or not tid:
                    f.add("threat", twhere, "missing id")
                elif tid in threat_ids:
                    f.add("threat", twhere, "duplicate threat id")
                else:
                    threat_ids.add(tid)
                num = t.get("number")
                if not isinstance(num, int) or isinstance(num, bool) or num < 0:
                    f.add("threat", twhere, "number must be a non-negative integer")
                elif num in threat_numbers:
                    f.add("threat", twhere, "duplicate threat number %d" % num)
                else:
                    threat_numbers.add(num)
                ok, missing = cited_paths("%s\n%s" % (mit or "", desc or ""), root, top, names)
                for m in sorted(set(missing)):
                    f.add("bad-path", twhere, "cites %s, which does not exist" % m)
                if status == "Mitigated":
                    mit_ok, _ = cited_paths(mit or "", root, top, names)
                    if not mit_ok:
                        f.add("mitigated-path", twhere, "Mitigated but the mitigation cites no existing repository path")
            if hot is not None and hot != open_seen:
                f.add("cell", cwhere, "hasOpenThreats is %s but the threats say %s" % (hot, open_seen))
        if boundaries == 0:
            f.add("diagram", dwhere, "has no trust boundary")
    if threat_top is not None and threat_numbers and threat_top < max(threat_numbers):
        f.add("detail", "detail", "threatTop %d is below the highest threat number %d" % (threat_top, max(threat_numbers)))


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    model_path = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--root", "--model") and i + 1 < len(argv):
            if a == "--root":
                root = os.path.abspath(argv[i + 1])
            else:
                model_path = argv[i + 1]
            i += 2
        else:
            sys.stderr.write(__doc__.split("\n\n")[0] + "\n")
            return 2
    if model_path is None:
        model_path = os.path.join(root, DEFAULT_MODEL)
    try:
        with open(model_path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as e:
        sys.stderr.write("check-threat-model: cannot read %s: %s\n" % (model_path, e.strerror))
        return 1
    f = Findings()
    if EM_DASH in text or EM_DASH_ESCAPED in text.lower():
        f.add("em-dash", os.path.basename(model_path), "contains an em dash")
    try:
        model = json.loads(text)
    except ValueError as e:
        f.add("parse", os.path.basename(model_path), "not valid JSON: %s" % e)
        model = None
    if model is not None:
        if not isinstance(model, dict):
            f.add("top-level", "model", "is not an object")
        else:
            check_model(model, root, f)
    if f.items:
        for line in f.items:
            print(line)
        print("check-threat-model: %d finding(s)" % len(f.items))
        return 1
    counts = {}
    for dg in model["detail"]["diagrams"]:
        for c in dg["cells"]:
            for t in c.get("data", {}).get("threats", []):
                counts[t["status"]] = counts.get(t["status"], 0) + 1
    print("check-threat-model: ok, %d diagrams, %s" % (
        len(model["detail"]["diagrams"]), ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items()))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
