#!/usr/bin/env bash
# Test for .gitleaks.toml: the allowlist for content-hash manifests must stay
# narrow. Runs the pinned gitleaks (the version the shared security workflow
# installs) over scratch trees and checks that
#   1. a bare 64-hex value keyed "discord" in an allowed path is not flagged,
#   2. the same line in any other path is flagged,
#   3. other secret shapes in an allowed path are still flagged (the allowlist
#      is scoped to the rule id discord-api-token, and to the path AND value),
#   4. the config has exactly one allowlist and exactly the three paths.
# All secret-shaped values are generated at run time, so this file carries none.
# Scratch lives under the repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/.gitleaks.toml"
# Same pin as the security workflow that ci.yml calls (its gitleaks-version and
# gitleaks-sha256 defaults).
version="8.30.1"
sha256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
dev="${NPNC_DEV_DIR:-$HOME/.local/share/no-php-no-cry-dev}"

mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/gitleaks.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
ok() { printf 'ok   %s\n' "$1"; }
bad() {
    printf 'FAIL %s\n' "$1"
    failures=$((failures + 1))
}

# find_gitleaks: print the path of a gitleaks of the pinned version, installing
# it (checksum verified) under $dev when none is on PATH.
find_gitleaks() {
    local candidate
    for candidate in "${GITLEAKS_BIN:-}" "$(command -v gitleaks 2>/dev/null)" "$dev/gitleaks-$version/gitleaks"; do
        if [[ -n "$candidate" && -x "$candidate" ]] && [[ "$("$candidate" version 2>/dev/null)" == *"$version" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    local dest="$dev/gitleaks-$version" archive="$work/gitleaks.tar.gz"
    mkdir -p "$dest"
    curl -sSfL --retry 3 -o "$archive" \
        "https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_linux_x64.tar.gz"
    echo "${sha256}  ${archive}" | sha256sum -c - >&2
    tar -xzf "$archive" -C "$dest" gitleaks
    chmod 0755 "$dest/gitleaks"
    printf '%s\n' "$dest/gitleaks"
}
gl="$(find_gitleaks)"

# Run-time generated values (never literals in this file).
hex64="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
rand32="$(head -c 48 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 32)"
rand36="$(head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 36)"
pfx="gh"
pfx="${pfx}p_"

count_findings() { python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$1"; }

# scan_with <config> <relative-path> <line>: write one file in a fresh tree and
# scan it. Prints the number of findings.
scan_with() {
    local cfg="$1" rel="$2" line="$3" tree
    tree="$(mktemp -d "$work/tree.XXXXXX")"
    mkdir -p "$tree/$(dirname "$rel")"
    printf '%s\n' "$line" >"$tree/$rel"
    "$gl" dir --no-banner --redact --exit-code 0 --config "$cfg" \
        --report-format json --report-path "$tree.json" "$tree" >/dev/null 2>&1
    count_findings "$tree.json"
}

expect_count() { # <name> <want> <got>
    if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1 (want $2 finding(s), got $3)"; fi
}

if [[ ! -f "$config" ]]; then
    bad ".gitleaks.toml exists"
    printf '%s failure(s)\n' "$failures"
    exit 1
fi

# The line shape the build record and generator carry.
hash_line="\"discord\": \"$hex64\","

# Sanity: the default rules flag this line when nothing is allowlisted, so a
# zero below means the allowlist worked, not that the rule never fires.
defaults="$work/defaults.toml"
printf 'title = "defaults"\n\n[extend]\nuseDefault = true\n' >"$defaults"
expect_count "defaults alone flag a discord-keyed 64-hex line" 1 \
    "$(scan_with "$defaults" brand/assets-build.json "$hash_line")"

for p in brand/assets-build.json scripts/gen-brand-assets.py brand/approved-assets.txt; do
    expect_count "1. $p: discord-keyed 64-hex line is not flagged" 0 \
        "$(scan_with "$config" "$p" "$hash_line")"
done
expect_count "2. other path: same line is flagged" 1 \
    "$(scan_with "$config" docs/notes.md "$hash_line")"
expect_count "2. a path that only resembles an allowed one is flagged" 1 \
    "$(scan_with "$config" other/brand/assets-build.json.bak "$hash_line")"
expect_count "3. allowed path: discord client secret shape is still flagged" 1 \
    "$(scan_with "$config" brand/assets-build.json "discord_client_secret = \"$rand32\"")"
expect_count "3. allowed path: GitHub token shape is still flagged" 1 \
    "$(scan_with "$config" scripts/gen-brand-assets.py "token = \"$pfx$rand36\"")"

# 4. The config is exactly one allowlist with exactly the three paths.
shape="$(
    python3 -I - "$config" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
lists = cfg.get("allowlists", [])
paths = sorted(p for a in lists for p in a.get("paths", []))
first = lists[0] if lists else {}
print(len(lists), cfg.get("extend", {}).get("useDefault"), first.get("targetRules"), first.get("condition"), len(paths))
want = sorted(
    "(^|/)" + p.replace(".", r"\.") + "$"
    for p in ("brand/assets-build.json", "scripts/gen-brand-assets.py", "brand/approved-assets.txt")
)
print("paths-ok" if paths == want else "paths-differ: " + repr(paths))
PY
)"
if [[ "$(sed -n 1p <<<"$shape")" == "1 True ['discord-api-token'] AND 3" ]]; then
    ok "4. one allowlist, defaults on, rule discord-api-token, condition AND, three paths"
else bad "4. allowlist shape: $(sed -n 1p <<<"$shape")"; fi
if [[ "$(sed -n 2p <<<"$shape")" == "paths-ok" ]]; then
    ok "4. the paths are exactly the three manifests"
else bad "4. $(sed -n 2p <<<"$shape")"; fi

if ((failures > 0)); then
    printf '%s failure(s)\n' "$failures"
    exit 1
fi
echo "all gitleaks config checks passed"
