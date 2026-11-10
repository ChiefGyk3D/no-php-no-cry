#!/usr/bin/env bash
# Tests for scripts/render-threat-diagram.py (issue 352): the SVGs are well formed,
# deterministic, free of scripts, links and external URLs, carry every cell label of
# their diagram, and match the committed files; and each check bites on a bad input
# (a script element, an href, an external URL, a missing label, a drifted committed
# file, a stale model).
#
# Fixtures live under the repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/render-threat-diagram.XXXXXX")"
trap 'rm -rf "$work"' EXIT

render="$root/scripts/render-threat-diagram.py"
model="$root/docs/threat-model/no-php-no-cry.threat-model.json"
failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

mkdir -p "$work/a" "$work/b"
python3 -I "$render" --root "$root" --out "$work/a" >/dev/null
python3 -I "$render" --root "$root" --out "$work/b" >/dev/null

# verify <dir> <model>: prints one "[rule] detail" line per problem.
verify() {
    python3 -I - "$1" "$2" <<'PY'
import json, re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

d, model = Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text())
files = sorted(d.glob("threat-model-*.svg"))
diagrams = model["detail"]["diagrams"]
if not files or len(files) != len(diagrams):
    print("[collect] %d svg files for %d diagrams" % (len(files), len(diagrams)))
for p, dia in zip(files, diagrams):
    text = p.read_text()
    try:
        root = ET.fromstring(text)
    except ET.ParseError as e:
        print("[well-formed] %s: %s" % (p.name, e))
        continue
    tags = {el.tag.split("}")[-1].lower() for el in root.iter()}
    if "script" in tags or "foreignobject" in tags:
        print("[script] %s" % p.name)
    for el in root.iter():
        for k in el.attrib:
            if k.split("}")[-1].lower() == "href" or k.lower().startswith("on"):
                print("[href-or-handler] %s: %s" % (p.name, k))
    if re.search(r"https?://|//[a-z]", text.replace('xmlns="http://www.w3.org/2000/svg"', "")):
        print("[external-url] %s" % p.name)
    if "@import" in text or "@font-face" in text:
        print("[font-or-import] %s" % p.name)
    if not (root.find("{*}title") is not None and root.find("{*}desc") is not None):
        print("[title-desc] %s" % p.name)
    vb = [float(v) for v in root.attrib.get("viewBox", "0 0 0 0").split()]
    if vb[2] > 900 or vb[3] <= vb[2]:
        print("[legibility-viewbox] %s: viewBox %s must be at most 900 wide and taller than wide" % (p.name, root.attrib.get("viewBox")))
    sizes = [float(x) for x in re.findall(r'font-size="([0-9.]+)"', text)]
    if not sizes or min(sizes) < 16:
        print("[legibility-font] %s: font sizes %s, need 16 or more in viewBox units" % (p.name, sorted(set(sizes))))
    if "stroke-dasharray" not in text:
        print("[dashed-boundary] %s" % p.name)
    shown = " ".join("".join(t.itertext()) for t in root.iter() if t.tag.endswith("}text"))
    shown = re.sub(r"\s+", " ", shown)
    for c in dia["cells"]:
        if c.get("shape") == "flow":
            lab = (c.get("labels") or [{}])[0].get("attrs", {}).get("label", {}).get("text") or c["data"]["name"]
        else:
            lab = c["data"]["name"]
        # Labels wrap onto several text lines; compare on the words in order.
        words = re.sub(r"\s+", " ", lab).strip()
        if words not in shown:
            print("[missing-label] %s: %s" % (p.name, words))
PY
}

# 1 the committed model renders clean
out="$(verify "$work/a" "$model")"
if [[ -z $out ]]; then pass "fresh render passes every content check"; else fail "fresh render: $out"; fi

# 2 deterministic
if diff -r "$work/a" "$work/b" >/dev/null; then pass "two renders are identical"; else fail "renders differ"; fi

# 3 three files, expected names
for n in publishing reader secrets; do
    [[ -s "$work/a/threat-model-$n.svg" ]] || fail "missing threat-model-$n.svg"
done
pass "three files rendered"

# 4 committed files equal a fresh render (the drift guard)
if python3 -I "$render" --root "$root" --check >"$work/drift.log" 2>&1; then
    pass "committed SVGs match a fresh render"
else
    fail "committed SVGs drifted: $(head -3 "$work/drift.log")"
fi

# --- negative cases: each check must bite ---
bites() { # bites <name> <the complete expected list of finding codes, comma separated> <dir>
    local out codes
    out="$(verify "$3" "$model")"
    codes="$(sed -E -n 's/^\[([a-z-]+)\].*/\1/p' <<<"$out" | sort -u | paste -sd, -)"
    if [[ "$codes" == "$2" ]]; then pass "$1"; else fail "$1 (codes '$codes', want '$2'; got: ${out:-nothing})"; fi
}

cp -r "$work/a" "$work/n1"
sed -i 's|</svg>|<script>1</script></svg>|' "$work/n1/threat-model-reader.svg"
bites "script element is caught" script "$work/n1"

cp -r "$work/a" "$work/n2"
sed -i '0,/<rect /s|<rect |<rect href="#x" |' "$work/n2/threat-model-reader.svg"
bites "href is caught" href-or-handler "$work/n2"

cp -r "$work/a" "$work/n3"
sed -i 's|<desc id="d">|<desc id="d">https://example.invalid/x |' "$work/n3/threat-model-secrets.svg"
bites "external URL is caught" external-url "$work/n3"

cp -r "$work/a" "$work/n4"
sed -i 's|Public visitor|Visitor|' "$work/n4/threat-model-reader.svg"
bites "a missing cell label is caught" missing-label "$work/n4"

cp -r "$work/a" "$work/n5"
echo '<svg' >"$work/n5/threat-model-publishing.svg"
bites "malformed XML is caught" well-formed "$work/n5"

cp -r "$work/a" "$work/n8"
sed -i 's|font-size="17"|font-size="12"|' "$work/n8/threat-model-reader.svg"
bites "small text is caught" legibility-font "$work/n8"

cp -r "$work/a" "$work/n9"
sed -i '0,/viewBox="0 0 900 /s|viewBox="0 0 900 |viewBox="0 0 1200 |' "$work/n9/threat-model-reader.svg"
bites "a wide viewBox is caught" legibility-viewbox "$work/n9"

# drift guard: a hand edit of a committed-style file, and a changed model
mkdir -p "$work/n6"
cp "$work/a"/*.svg "$work/n6/"
sed -i 's|Public visitor|Public visitors|' "$work/n6/threat-model-reader.svg"
if python3 -I "$render" --root "$root" --out "$work/n6" --check >"$work/n6.log" 2>&1; then
    fail "drift guard accepted an edited SVG"
elif grep -q '^\[svg-drift\]' "$work/n6.log"; then
    pass "drift guard catches an edited SVG"
else
    fail "drift guard failed without [svg-drift]"
fi

python3 -I - "$model" "$work/model2.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for c in m["detail"]["diagrams"][0]["cells"]:
    if c.get("shape") == "actor":
        c["data"]["name"] += " renamed"
        c["attrs"]["text"]["text"] += " renamed"
        break
json.dump(m, open(sys.argv[2], "w"))
PY
if python3 -I "$render" --root "$root" --model "$work/model2.json" --check >"$work/n7.log" 2>&1; then
    fail "drift guard accepted a changed model"
elif grep -q '^\[svg-drift\]' "$work/n7.log"; then
    pass "drift guard catches a model that changed without a re-render"
else
    fail "model drift failed without [svg-drift]"
fi

# the content check's SVG allowlist accepts every fresh render, and rejects a tampered one
svg_rule() { # svg_rule <svg file>: prints the allowlist findings
    python3 -I - "$root/scripts/check-content.py" "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cc", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print("\n".join(m.svg_findings(open(sys.argv[2], "rb").read())))
PY
}
bad_rule=""
for n in publishing reader secrets; do bad_rule+="$(svg_rule "$work/a/threat-model-$n.svg")"; done
if [[ -z $bad_rule ]]; then pass "check-content's SVG allowlist accepts the renders"; else fail "allowlist rejects a render: $bad_rule"; fi
sed 's|</svg>|<script>1</script></svg>|' "$work/a/threat-model-reader.svg" >"$work/tampered.svg"
if [[ "$(svg_rule "$work/tampered.svg")" == "[svg-element] <script> is not an allowed element" ]]; then pass "allowlist rejects a tampered render"; else fail "allowlist accepted a tampered render"; fi

# --- layout geometry (assertions on the computed layout, not the picture) ---
geo() { # geo <mutation name or none>
    python3 -I - "$render" "$model" "$1" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("rtd", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
model = json.load(open(sys.argv[2]))
mut = sys.argv[3]
out = []
for d in model["detail"]["diagrams"]:
    lay = m.build(d)
    if mut == "node-onto-route":
        rt = lay["routes"][0]
        a, b = rt["points"][0], rt["points"][1]
        victim = [n for n in lay["nodes"].values() if n["id"] not in (rt["src"], rt["dst"])][0]
        victim["rect"] = (min(a[0], b[0]) - 20, min(a[1], b[1]) - 20, 250, 90)
    elif mut == "chip-on-node":
        n = next(iter(lay["nodes"].values()))
        lay["chips"][0]["rect"] = n["rect"]
    elif mut == "chips-overlap":
        lay["chips"][1]["rect"] = lay["chips"][0]["rect"]
    elif mut == "node-outside-boundary":
        n = next(x for x in lay["nodes"].values() if x["group"] is not None)
        n["rect"] = (n["rect"][0], -500, n["rect"][2], n["rect"][3])
    elif mut == "chip-off-route":
        lay["chips"][0]["center"] = (1, 1)
    out += m.geometry_problems(lay)
    if mut == "none" and any(len(n["lines"]) > 3 for n in lay["nodes"].values()):
        out.append("[too-many-lines]")
print("\n".join(sorted(set(out))))
PY
}
out="$(geo none)"
if [[ -z $out ]]; then pass "layout: nodes inside boundaries, no segment crosses a node, chips clear and on their route"; else fail "layout: $out"; fi
for pair in node-onto-route:chip-overlap,node-outside-boundary,segment-crosses-node chip-on-node:chip-overlap chips-overlap:chip-overlap node-outside-boundary:node-outside-boundary chip-off-route:chip-off-route; do
    mut="${pair%%:*}"
    rule="${pair##*:}"
    out="$(geo "$mut")"
    codes="$(sed -E -n 's/^\[([a-z-]+)\].*/\1/p' <<<"$out" | sort -u | paste -sd, -)"
    if [[ "$codes" == "$rule" ]]; then pass "layout check bites: $mut"; else fail "layout check on $mut gave '$codes', want '$rule' (got: ${out:-nothing})"; fi
done

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all render-threat-diagram checks passed"
