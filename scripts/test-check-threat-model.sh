#!/usr/bin/env bash
# Tests for scripts/check-threat-model.py: the committed model passes, and the check
# bites on each kind of break (bad JSON, a missing key, a duplicate id, a threat
# without a mitigation, an unknown status or severity, a type the element cannot
# carry, a dangling flow end, a wrong hasOpenThreats flag, a threatTop that is too
# low, a diagram with no trust boundary, a cited path that does not exist, a
# Mitigated threat that cites no path and an em dash), while good edits of the
# same shapes still pass.
#
# Fixtures are copies of the committed model under the repository's gitignored
# tmp/, never /tmp. Each case edits one thing with a small python3 -I program.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/check-threat-model.XXXXXX")"
trap 'rm -rf "$work"' EXIT

model="$root/docs/threat-model/no-php-no-cry.threat-model.json"
check="$root/scripts/check-threat-model.py"
failures=0
pass() { echo "ok: $1"; }
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# expect <name> <exit 0|1> <rule-or-empty> <fixture-file>
expect() {
    local name="$1" want="$2" rule="$3" file="$4" rc=0
    python3 -I "$check" --root "$root" --model "$file" >"$work/out.log" 2>&1 || rc=$?
    if [[ $rc -ne $want ]]; then
        fail "$name (exit $rc, want $want): $(head -3 "$work/out.log")"
    elif [[ -n $rule ]] && ! grep -q "^\[$rule\]" "$work/out.log"; then
        fail "$name (exit ok but no [$rule] finding): $(head -3 "$work/out.log")"
    else
        pass "$name"
    fi
}

# mutate <name> <python statements acting on m (the model) and t (first Open threat's cell data)>
mutate() {
    local name="$1" code="$2" out="$work/$1.json"
    cp "$model" "$out"
    MODEL_FILE="$out" python3 -I - "$code" <<'PY'
import json, os, sys
path = os.environ["MODEL_FILE"]
m = json.load(open(path))
cells = [c for d in m["detail"]["diagrams"] for c in d["cells"]]
nodes = [c for c in cells if c["data"].get("threats")]
# the first node whose first threat is Mitigated, and one whose first is Open
mit = next(c for c in nodes if c["data"]["threats"][0]["status"] == "Mitigated")
opn = next(c for c in nodes if c["data"]["threats"][0]["status"] == "Open")
th = mit["data"]["threats"][0]
flows = [c for c in cells if c["shape"] == "flow"]
exec(sys.argv[1])
raw = json.dumps(m, indent=2)
if "RAW_OVERRIDE" in globals():
    raw = RAW_OVERRIDE
open(path, "w").write(raw)
PY
    echo "$out"
}

# --- the committed model -----------------------------------------------------
if python3 -I "$check" >"$work/repo.log" 2>&1; then
    pass "the committed model passes: $(tail -1 "$work/repo.log")"
else
    fail "the committed model fails: $(head -3 "$work/repo.log")"
fi
if grep -q "3 diagrams" "$work/repo.log"; then pass "the check really read three diagrams"; else fail "the check did not report three diagrams"; fi

# --- good edits of the same shapes still pass ---------------------------------
expect "good: a new mitigation that cites an existing file" 0 "" \
    "$(mutate good-path 'th["mitigation"] = "Checked by scripts/check-threat-model.py and docs/threat-model/README.md."')"
expect "good: a url and a nonexistent-looking host are ignored" 0 "" \
    "$(mutate good-url 'th["mitigation"] = "See https://example.test/no/such/file.md and scripts/check-threat-model.py."')"
expect "good: NotApplicable with a reason" 0 "" \
    "$(mutate good-na 'th["status"] = "NotApplicable"; th["mitigation"] = "Not applicable: nothing ships this."')"
expect "good: Accepted" 0 "" \
    "$(mutate good-accepted 'th["status"] = "Accepted"')"

# --- each break must fail -----------------------------------------------------
expect "bad JSON" 1 parse "$(mutate bad-json 'RAW_OVERRIDE = "{ not json"')"
expect "missing detail" 1 top-level "$(mutate no-detail 'del m["detail"]')"
expect "missing diagramTop" 1 detail "$(mutate no-top 'del m["detail"]["diagramTop"]')"
expect "empty diagram list" 1 detail "$(mutate no-diagrams 'm["detail"]["diagrams"] = []')"
expect "diagram without a thumbnail" 1 diagram "$(mutate no-thumb 'del m["detail"]["diagrams"][0]["thumbnail"]')"
expect "diagram type not STRIDE" 1 diagram "$(mutate not-stride 'm["detail"]["diagrams"][0]["diagramType"] = "LINDDUN"')"
expect "duplicate cell id" 1 cell "$(mutate dup-cell 'cells[1]["id"] = cells[0]["id"]')"
expect "cell without zIndex" 1 cell "$(mutate no-z 'del cells[0]["zIndex"]')"
expect "dangling flow source" 1 flow "$(mutate dangling 'flows[0]["source"] = {"cell": "no-such-cell"}')"
expect "threat without a mitigation" 1 threat "$(mutate no-mit 'del th["mitigation"]')"
expect "threat with an empty mitigation" 1 threat "$(mutate empty-mit 'th["mitigation"] = "  "')"
expect "threat without a title" 1 threat "$(mutate no-title 'th["title"] = ""')"
expect "unknown status" 1 threat "$(mutate bad-status 'th["status"] = "Fixed"')"
expect "unknown severity" 1 threat "$(mutate bad-sev 'th["severity"] = "Urgent"')"
expect "type not allowed on an actor" 1 threat "$(mutate bad-type 'a = next(c for c in cells if c["data"]["type"] == "tm.Actor" and c["data"].get("threats")); a["data"]["threats"][0]["type"] = "Tampering"')"
expect "duplicate threat number" 1 threat "$(mutate dup-number 'opn["data"]["threats"][0]["number"] = th["number"]')"
expect "threatTop below the highest number" 1 detail "$(mutate low-top 'm["detail"]["threatTop"] = 1')"
expect "hasOpenThreats wrong" 1 cell "$(mutate wrong-open 'opn["data"]["hasOpenThreats"] = False')"
expect "diagram without a trust boundary" 1 diagram "$(mutate no-boundary 'd = m["detail"]["diagrams"][0]; d["cells"] = [c for c in d["cells"] if not c["data"].get("isTrustBoundary")]')"
expect "cited path that does not exist" 1 bad-path "$(mutate missing-file 'th["mitigation"] = "Covered by scripts/no-such-check.sh and static/_headers."')"
expect "cited top-level file that does not exist" 1 bad-path "$(mutate missing-docs 'th["mitigation"] = "See docs/threat-model/NOPE.md."')"
expect "bare file name that exists nowhere" 1 bad-path "$(mutate missing-bare 'th["mitigation"] = "See nothere-anywhere.mjs and static/_headers."')"
expect "citation that climbs out of the repository" 1 bad-path "$(mutate escape 'th["mitigation"] = "See docs/../../../../../../../../../../../../etc/passwd and static/_headers."')"
expect "dot-slash citation of a missing file" 1 bad-path "$(mutate dotslash 'th["mitigation"] = "See ./scripts/no-such-thing.sh and static/_headers."')"
expect "good: dot-slash citation of an existing file" 0 "" "$(mutate dotslash-ok 'th["mitigation"] = "See ./scripts/check-threat-model.py."')"
expect "top-level version over 10 characters" 1 top-level "$(mutate long-version 'm["version"] = "2.6.2.12345"')"
expect "diagram version over 10 characters" 1 diagram "$(mutate long-dversion 'm["detail"]["diagrams"][0]["version"] = "2.6.2.12345"')"
expect "cell size under 10" 1 cell "$(mutate small-size 'n = next(c for c in cells if "size" in c); n["size"]["width"] = 5')"
expect "cell position without y" 1 cell "$(mutate no-y 'n = next(c for c in cells if "position" in c); del n["position"]["y"]')"
expect "attrs.body without strokeWidth" 1 cell "$(mutate no-stroke 'n = next(c for c in cells if "body" in c.get("attrs", {})); del n["attrs"]["body"]["strokeWidth"]')"
expect "flow line without targetMarker" 1 cell "$(mutate no-marker 'del flows[0]["attrs"]["line"]["targetMarker"]')"
expect "cell id shorter than 2 characters" 1 cell "$(mutate short-id 'cells[0]["id"] = "x"')"
expect "contributor that is not an object" 1 detail "$(mutate bad-contrib 'm["detail"]["contributors"] = ["name"]')"
expect "Mitigated with no repository path" 1 mitigated-path "$(mutate no-control 'th["mitigation"] = "We are careful about this."')"
expect "em dash" 1 em-dash "$(mutate em-dash 'th["description"] = th["description"] + " — note"')"

# usage error
rc=0
python3 -I "$check" --bogus >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then pass "unknown option exits 2"; else fail "unknown option exit $rc, want 2"; fi

if [[ $failures -gt 0 ]]; then
    echo "$failures test(s) failed"
    exit 1
fi
echo "all threat model check tests passed"
