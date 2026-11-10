#!/usr/bin/env python3
"""Render the threat counts in RISKS.md from a Threat Dragon model."""

import json
import sys

START = "<!-- threat-summary:start -->"
END = "<!-- threat-summary:end -->"
REGISTER_START = "<!-- threat-register:start -->"
REGISTER_END = "<!-- threat-register:end -->"
STATUSES = ("Mitigated", "Open", "Accepted", "NotApplicable")


def diagram_counts(diagram):
    counts = {status: 0 for status in STATUSES}
    for cell in diagram["cells"]:
        for threat in cell.get("data", {}).get("threats", []):
            counts[threat["status"]] += 1
    return counts


def row(name, counts):
    total = sum(counts.values())
    values = [total] + [counts[status] for status in STATUSES]
    return "| %s | %s |" % (name, " | ".join(str(value) for value in values))


def render(model):
    diagrams = model["detail"]["diagrams"]
    per_diagram = [(diagram["title"], diagram_counts(diagram)) for diagram in diagrams]
    totals = {status: sum(counts[status] for _, counts in per_diagram) for status in STATUSES}
    lines = [
        START,
        "| Diagram | Total | Mitigated | Open | Accepted | NotApplicable |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
        row("All diagrams", totals),
    ]
    lines.extend(row(name, counts) for name, counts in per_diagram)
    lines.append(END)
    return "\n".join(lines)


def boundary_name(cell):
    data = cell.get("data", {})
    if data.get("isTrustBoundary") or data.get("type") in ("tm.Boundary", "tm.BoundaryBox"):
        return data.get("name", "Unnamed trust boundary")
    return None


def containing_boundary(cell, boundaries):
    position, size = cell.get("position"), cell.get("size")
    if not position or not size:
        return "Boundary crossings"
    center_x = position["x"] + size["width"] / 2
    center_y = position["y"] + size["height"] / 2
    matches = []
    for boundary in boundaries:
        pos, dimensions = boundary["position"], boundary["size"]
        if (pos["x"] <= center_x <= pos["x"] + dimensions["width"] and
                pos["y"] <= center_y <= pos["y"] + dimensions["height"]):
            matches.append((dimensions["width"] * dimensions["height"], boundary_name(boundary)))
    return min(matches)[1] if matches else "Outside named boundaries"


def render_register(model):
    lines = [REGISTER_START]
    for diagram in model["detail"]["diagrams"]:
        lines.extend(("## " + diagram["title"], ""))
        boundaries = [cell for cell in diagram["cells"] if boundary_name(cell)]
        groups = {}
        for cell in diagram["cells"]:
            threats = cell.get("data", {}).get("threats", [])
            if not threats:
                continue
            group = containing_boundary(cell, boundaries)
            groups.setdefault(group, []).extend(threats)
        order = [boundary_name(boundary) for boundary in boundaries]
        order.extend(name for name in ("Boundary crossings", "Outside named boundaries") if name in groups)
        for name in order:
            if name not in groups:
                continue
            lines.extend(("### " + name, ""))
            for threat in sorted(groups[name], key=lambda item: item.get("number", 0)):
                title = threat.get("title", "Untitled threat")
                lines.append("- %s: %s" % (threat["status"], title))
            lines.append("")
    lines.append(REGISTER_END)
    return "\n".join(lines)


def replace_block(text, start, end, replacement):
    before, marker, rest = text.partition(start)
    if not marker:
        raise ValueError("missing %s marker" % start)
    _, marker, after = rest.partition(end)
    if not marker:
        raise ValueError("missing %s marker" % end)
    return before + replacement + after


def main(argv):
    check = bool(argv and argv[0] == "--check")
    if check:
        argv = argv[1:]
    if len(argv) != 2:
        print("usage: render-threat-summary.py [--check] MODEL RISKS", file=sys.stderr)
        return 2
    model_path, risks_path = argv
    with open(model_path, encoding="utf-8") as handle:
        model = json.load(handle)
    with open(risks_path, encoding="utf-8") as handle:
        text = handle.read()
    try:
        wanted = replace_block(text, START, END, render(model))
        wanted = replace_block(wanted, REGISTER_START, REGISTER_END, render_register(model))
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    if check:
        if wanted != text:
            print("threat summary is stale", file=sys.stderr)
            return 1
        return 0
    with open(risks_path, "w", encoding="utf-8") as handle:
        handle.write(wanted)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
