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
bites() { # bites <name> <rule> <dir>
    local out
    out="$(verify "$3" "$model")"
    if grep -q "^\[$2\]" <<<"$out"; then pass "$1"; else fail "$1 (no [$2] finding; got: ${out:-nothing})"; fi
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

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)"
    exit 1
fi
echo "all render-threat-diagram checks passed"
