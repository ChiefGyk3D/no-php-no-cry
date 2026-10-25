#!/usr/bin/env bash
# Test for scripts/ensure-pages-project.sh against a local fake API (no real
# network). The fake records every request so the test can check that a
# present project is left alone, a missing one is created once, and any other
# answer fails without creating anything.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/ensure-pages-project.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/ensure-pages.XXXXXX")"
server_pid=""
stop_server() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=""
    fi
}
trap 'stop_server; rm -rf "$work"' EXIT

account="0123456789abcdef0123456789abcdef"
token="test-token-value"

# start_server <get-status> <post-status>: sets $api and clears the request log.
start_server() {
    stop_server
    rm -f "$work/port" "$work/requests"
    GET_STATUS="$1" POST_STATUS="$2" PORTFILE="$work/port" LOG="$work/requests" python3 -I -c '
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

get_status, post_status = int(os.environ["GET_STATUS"]), int(os.environ["POST_STATUS"])
log = os.environ["LOG"]

class H(BaseHTTPRequestHandler):
    def _record(self, body=""):
        auth = self.headers.get("Authorization")
        with open(log, "a") as f:
            f.write(f"{self.command} {self.path} auth={auth} {body}\n")
    def _reply(self, code):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{}")
    def do_GET(self):
        self._record()
        self._reply(get_status)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        self._record(self.rfile.read(n).decode())
        self._reply(post_status)
    def log_message(self, *a):
        pass

srv = HTTPServer(("127.0.0.1", 0), H)
with open(os.environ["PORTFILE"], "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
' &
    server_pid=$!
    for _ in $(seq 1 50); do
        [[ -s "$work/port" ]] && break
        sleep 0.1
    done
    [[ -s "$work/port" ]] || { echo "fake API did not start" >&2; exit 1; }
    api="http://127.0.0.1:$(cat "$work/port")"
    : >"$work/requests"
}

# run <extra env...>: runs the script, stores output in $work/out, sets $rc.
run() {
    rc=0
    env CLOUDFLARE_API_TOKEN="$token" CLOUDFLARE_ACCOUNT_ID="$account" \
        CLOUDFLARE_PAGES_PROJECT="my-site" CF_API_BASE="$api" "$@" \
        bash "$script" >"$work/out" 2>&1 || rc=$?
}

fail() {
    echo "FAIL: $1" >&2
    sed 's/^/  | /' "$work/out" >&2 || true
    sed 's/^/  req| /' "$work/requests" >&2 || true
    exit 1
}

# present: one GET, no POST, exit 0
start_server 200 200
run
[[ "$rc" -eq 0 ]] || fail "existing project should pass (rc=$rc)"
grep -q "already exists" "$work/out" || fail "existing project should say so"
[[ "$(grep -c '^GET ' "$work/requests")" -eq 1 ]] || fail "expected one GET"
! grep -q '^POST ' "$work/requests" || fail "existing project must not be created again"
grep -q "auth=Bearer $token" "$work/requests" || fail "token should be sent as a bearer header"
echo "ok: existing project left alone"

# missing: GET 404 then one POST with the name and branch
start_server 404 200
run
[[ "$rc" -eq 0 ]] || fail "missing project should be created (rc=$rc)"
[[ "$(grep -c '^POST ' "$work/requests")" -eq 1 ]] || fail "expected exactly one POST"
grep -q '"name":"my-site"' "$work/requests" || fail "POST should name the project"
grep -q '"production_branch":"main"' "$work/requests" || fail "POST should set the production branch"
grep -q "/accounts/$account/pages/projects" "$work/requests" || fail "wrong API path"
echo "ok: missing project created once"

# create refused: non-zero, no success message
start_server 404 403
run
[[ "$rc" -ne 0 ]] || fail "a refused create must fail"
! grep -q "^Created" "$work/out" || fail "must not claim success"
grep -q "creating the project returned HTTP 403" "$work/out" || fail "should name the status"
echo "ok: refused create fails"

# lookup refused (bad token): fail, never create
start_server 403 200
run
[[ "$rc" -ne 0 ]] || fail "a refused lookup must fail"
! grep -q '^POST ' "$work/requests" || fail "must not create after a refused lookup"
echo "ok: refused lookup fails without creating"

# the token must not appear in the output
! grep -q "$token" "$work/out" || fail "token leaked into the output"

# bad inputs are rejected before any request
start_server 200 200
run CLOUDFLARE_ACCOUNT_ID="not-hex"
[[ "$rc" -ne 0 ]] || fail "bad account id must fail"
run CLOUDFLARE_PAGES_PROJECT="Bad Name"
[[ "$rc" -ne 0 ]] || fail "bad project name must fail"
[[ ! -s "$work/requests" ]] || fail "no request may be made for bad input"
echo "ok: bad input rejected before any request"

echo "all ensure-pages-project tests passed"
