#!/usr/bin/env bash
# Tests for scripts/check-reach-around-drift.sh. Offline: fixture copies only,
# plus a dead local API address to prove a fetch failure is not a pass.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/check-reach-around-drift.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
commit="0123456789abcdef0123456789abcdef01234567"

# run <label> <want-exit> <must-contain|-> args...
run() {
    local label="$1" want="$2" needle="$3" rc=0
    shift 3
    "$checker" "$@" >"$work/out" 2>&1 || rc=$?
    if [[ $rc -ne $want ]]; then
        echo "FAIL: $label (exit $rc, want $want)"
        cat "$work/out"
        fail=1
    elif [[ "$needle" != - ]] && ! grep -qF -- "$needle" "$work/out"; then
        echo "FAIL: $label (output lacks: $needle)"
        cat "$work/out"
        fail=1
    else
        echo "ok: $label"
    fi
}

# vendor <name> <python-edit>: write a vendored copy and a lock with a correct pin
vendor() {
    python3 -I - "$root/brand/tokens.json" "$work/$1.json" "$work/$1.lock.json" "$2" "$commit" <<'PY'
import hashlib, json, sys
src, out, lock, edit, commit = sys.argv[1:6]
doc = json.load(open(src))
tok = doc["groups"][0]["tokens"]
exec(edit)
data = (json.dumps(doc, indent=2) + "\n").encode()
open(out, "wb").write(data)
json.dump({"source": {"commit": commit}, "sha256": hashlib.sha256(data).hexdigest()}, open(lock, "w"))
PY
}

vendor same "pass"
vendor changed 'tok["accent"] = "#000001"'
vendor added 'tok["brand-new"] = "#123456"'
vendor removed 'del tok["accent"]'

run "identical copy passes and names the pin" 0 "$commit" --ra-tokens "$work/same.json" --ra-lock "$work/same.lock.json"
run "changed key is reported" 1 "changed token:accent" --ra-tokens "$work/changed.json" --ra-lock "$work/changed.lock.json"
run "added key is reported" 1 "added on Reach Around (not in blog): token:brand-new" --ra-tokens "$work/added.json" --ra-lock "$work/added.lock.json"
run "removed key is reported" 1 "removed on Reach Around (in blog only): token:accent" --ra-tokens "$work/removed.json" --ra-lock "$work/removed.lock.json"
run "drift output names the pinned commit" 1 "$commit" --ra-tokens "$work/changed.json" --ra-lock "$work/changed.lock.json"

# A stale pin on the other side is drift even when the keys agree.
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["sha256"]="0"*64; json.dump(d,open(sys.argv[1],"w"))' "$work/same.lock.json"
run "stale pin in the other lock is drift" 1 "pin is stale" --ra-tokens "$work/same.json" --ra-lock "$work/same.lock.json"

run "--offline skips with a message" 0 "skip:" --offline
RA_DRIFT_API="http://127.0.0.1:9/none" run "dead API address exits 3 and names --offline" 3 "--offline" --timeout 2
run "unknown flag is a usage error" 2 - --bogus
run "one of --ra-tokens/--ra-lock alone is a usage error" 2 - --ra-tokens "$work/same.json"
echo '{not json' >"$work/bad.json"
run "unparseable file exits 3" 3 "cannot read or parse" --ra-tokens "$work/bad.json" --ra-lock "$work/same.lock.json"

if [[ $fail -ne 0 ]]; then
    echo "some drift check tests failed"
    exit 1
fi
echo "all drift check tests passed"
