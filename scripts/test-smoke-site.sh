#!/usr/bin/env bash
# Test for scripts/smoke-site.sh against a local fake server (no real network).
#
# One fake server per mode runs on 127.0.0.1 with an OS-chosen port. The good
# mode must pass; each bad mode must fail with its expected rule name.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smoke="$root/scripts/smoke-site.sh"
mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/smoke-site.XXXXXX")"
server_pid=""
stop_server() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=""
    fi
}
trap 'stop_server; rm -rf "$work"' EXIT

csp="default-src 'none'; script-src 'none'"
pub="$work/public"
mkdir -p "$pub"
printf '/*\n  Content-Security-Policy: %s\n  X-Content-Type-Options: nosniff\n' "$csp" >"$pub/_headers"
printf '# generated\n/2023/02/10/sample-post/ /posts/sample-post/ 301\n/2023/02/10/sample-post /posts/sample-post/ 301\n' >"$pub/_redirects"

# start_server <mode>: sets $url
start_server() {
    stop_server
    rm -f "$work/port"
    MODE="$1" CSP="$csp" PORTFILE="$work/port" python3 -I -c '
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

mode, csp = os.environ["MODE"], os.environ["CSP"]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/2023/02/10/sample-post/":
            if mode == "no-redirect":
                self.send_response(200)
            elif mode == "wrong-redirect":
                self.send_response(301)
                self.send_header("Location", "/elsewhere/")
            else:
                self.send_response(301)
                self.send_header("Location", "/posts/sample-post/")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(404 if mode == "bad-status" else 200)
        if mode != "no-csp":
            value = "default-src *" if mode == "weak-csp" else csp
            self.send_header("Content-Security-Policy", value)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")


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
    [[ -s "$work/port" ]] || {
        echo "FAIL: fake server did not start"
        exit 1
    }
    url="http://127.0.0.1:$(cat "$work/port")"
}

failures=0

# expect <name> <pass|rule> <mode> [dir]
expect() {
    local name="$1" want="$2" mode="$3" dir="${4:-$pub}" out rc=0
    start_server "$mode"
    out="$(SMOKE_ALLOW_HTTP=1 SMOKE_RETRIES=0 "$smoke" "$url" "$dir" 2>&1)" || rc=$?
    if [[ "$want" == pass ]]; then
        if [[ $rc -eq 0 ]]; then
            echo "ok: $name"
        else
            echo "FAIL: $name (rc=$rc)"
            echo "$out"
            failures=$((failures + 1))
        fi
    elif [[ $rc -ne 0 && "$out" == *"$want"* ]]; then
        echo "ok: $name"
    else
        echo "FAIL: $name (rc=$rc, wanted rule $want)"
        echo "$out"
        failures=$((failures + 1))
    fi
}

expect good pass good
expect bad-status status bad-status
expect no-csp missing-csp no-csp
expect weak-csp missing-csp weak-csp
expect no-redirect redirect no-redirect
expect wrong-redirect redirect wrong-redirect

# The expectations come from the build, so a build without them must fail.
mkdir -p "$work/nohdr" "$work/noredir"
cp "$pub/_redirects" "$work/nohdr/"
cp "$pub/_headers" "$work/noredir/"
printf '# nothing\n' >"$work/noredir/_redirects"
expect no-headers-file input good "$work/nohdr"
expect no-redirect-line input good "$work/noredir"

# Plain http is refused unless the test switch is set.
rc=0
out="$(SMOKE_RETRIES=0 "$smoke" "http://127.0.0.1:1" "$pub" 2>&1)" || rc=$?
if [[ $rc -ne 0 && "$out" == *"https"* ]]; then
    echo "ok: http refused"
else
    echo "FAIL: http was not refused"
    failures=$((failures + 1))
fi

if [[ $failures -gt 0 ]]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all smoke tests passed"
