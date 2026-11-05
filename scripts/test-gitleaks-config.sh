#!/usr/bin/env bash
# Test for .gitleaks.toml: the allowlist for content-hash manifests must stay
# narrow. Runs the pinned gitleaks (the version the shared security workflow
# installs) over scratch trees and checks that
#   1. a bare 64-hex value keyed "discord" in an allowed path is not flagged,
#   2. the same line in any other path is flagged,
#   3. other secret shapes in an allowed path are still flagged (the allowlist
#      is scoped to the rule id discord-api-token, and to the path AND value),
#   4. the config has exactly one allowlist with exactly the three anchored
#      paths, the secret regex target and the exact 64-hex regex, and a set of
#      mutated configs each fail that structural check.
# Any gitleaks binary used (GITLEAKS_BIN, PATH, cache) is verified against the
# pinned sha256 of the release binary; none matching means a checksum-verified
# download, and a failed check aborts the test (fail closed).
# All secret-shaped values are generated at run time, so this file carries none.
# Scratch lives under the repository's gitignored tmp/, never /tmp.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/.gitleaks.toml"
# Same pin as the security workflow that ci.yml calls (its gitleaks-version and
# gitleaks-sha256 defaults).
version="8.30.1"
sha256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
# sha256 of the extracted gitleaks binary from that (checksum-verified) tarball.
bin_sha256="88f91962aa2f93ac6ab281d553b9e125f5197bbbce38f9f2437f7299c32e5509"
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

# is_pinned <file>: true when the file's sha256 equals the pinned binary hash.
is_pinned() {
    local got
    [[ -f "$1" && -x "$1" ]] || return 1
    got="$(sha256sum "$1" | cut -d' ' -f1)"
    [[ "$got" == "$bin_sha256" ]]
}

# find_gitleaks: print the path of a gitleaks binary whose sha256 matches the
# pinned release binary. Candidates (GITLEAKS_BIN, PATH, cache) that do not
# match are ignored, never executed; with none left, download the pinned
# release (tarball checksum verified, then the binary checked too). Any
# verification failure exits non-zero.
find_gitleaks() {
    local candidate
    for candidate in "${GITLEAKS_BIN:-}" "$(command -v gitleaks 2>/dev/null || true)" "$dev/gitleaks-$version/gitleaks"; do
        if [[ -n "$candidate" ]] && is_pinned "$candidate"; then
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
    is_pinned "$dest/gitleaks" || {
        echo "downloaded gitleaks does not match the pinned binary hash" >&2
        return 1
    }
    printf '%s\n' "$dest/gitleaks"
}
gl="$(find_gitleaks)" || {
    echo "no verified gitleaks binary" >&2
    exit 1
}

# Run-time generated values (never literals in this file).
hex64="$(python3 -I -c 'import secrets; print(secrets.token_hex(32))')"
# Fixed-length values come from Python (no truncating pipe, so no SIGPIPE
# under pipefail).
rand32="$(python3 -I -c 'import secrets,string; print("".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(32)))')"
rand36="$(python3 -I -c 'import secrets,string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(36)))')"
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
    (cd "$tree" && "$gl" dir --no-banner --redact --exit-code 0 --config "$cfg" \
        --report-format json --report-path "$tree.json" . >/dev/null 2>&1)
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
for p in other/brand/assets-build.json other/scripts/gen-brand-assets.py other/brand/approved-assets.txt; do
    expect_count "2. nested same-basename path $p is flagged" 1 \
        "$(scan_with "$config" "$p" "$hash_line")"
done
expect_count "3. allowed path: discord client secret shape is still flagged" 1 \
    "$(scan_with "$config" brand/assets-build.json "discord_client_secret = \"$rand32\"")"
expect_count "3. allowed path: GitHub token shape is still flagged" 1 \
    "$(scan_with "$config" scripts/gen-brand-assets.py "token = \"$pfx$rand36\"")"

# 4. Structural check, run on the real config and on mutated copies.
# check_shape <config>: prints one problem per line; empty output means OK.
check_shape() {
    python3 -I - "$1" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
lists = cfg.get("allowlists", [])
bad = []
if cfg.get("extend", {}).get("useDefault") is not True:
    bad.append("useDefault is not true")
if len(lists) != 1:
    bad.append("allowlist count %d" % len(lists))
else:
    a = lists[0]
    if a.get("targetRules") != ["discord-api-token"]:
        bad.append("targetRules %r" % (a.get("targetRules"),))
    if a.get("condition") != "AND":
        bad.append("condition %r" % (a.get("condition"),))
    if a.get("regexTarget") != "secret":
        bad.append("regexTarget %r" % (a.get("regexTarget"),))
    if a.get("regexes") != [r"(?i)\b[0-9a-f]{64}\b"]:
        bad.append("regexes %r" % (a.get("regexes"),))
    want = sorted(
        "^" + p.replace(".", r"\.") + "$"
        for p in ("brand/assets-build.json", "scripts/gen-brand-assets.py", "brand/approved-assets.txt")
    )
    if sorted(a.get("paths", [])) != want:
        bad.append("paths %r" % (sorted(a.get("paths", [])),))
    for k in ("stopwords", "commits"):
        if a.get(k):
            bad.append("unexpected " + k)
print("\n".join(bad))
PY
}

shape="$(check_shape "$config")"
if [[ -z "$shape" ]]; then
    ok "4. one allowlist: defaults on, rule discord-api-token, AND, anchored three paths, secret target, exact 64-hex regex"
else bad "4. allowlist shape: $shape"; fi

# Mutations: each must make check_shape report a problem (the check bites).
# mutate <name> <old> <new>: replace old with new (literal) in a copy.
mutate() {
    local m="$work/mut.toml"
    python3 -I - "$config" "$m" "$2" "$3" <<'PY'
import sys
s = open(sys.argv[1]).read()
if sys.argv[3] not in s:
    sys.exit("mutation target not found")
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4]))
PY
    if [[ -n "$(check_shape "$m")" ]]; then ok "4. mutation caught: $1"; else bad "4. mutation NOT caught: $1"; fi
}
mutate "regex widened to .*" '(?i)\b[0-9a-f]{64}\b' '.*'
mutate "regex removed" 'regexes = [' 'xregexes = ['
mutate "regexTarget removed" 'regexTarget = "secret"' ''
mutate "regexTarget changed to line" '"secret"' '"line"'
mutate "rule id changed" 'discord-api-token"]' 'generic-api-key"]'
mutate "condition OR" '"AND"' '"OR"'
mutate "path unanchored at start" "'''^brand/assets-build" "'''brand/assets-build"
mutate "path loosened to (^|/)" '^scripts/gen' '(^|/)scripts/gen'
mutate "path added" "]
regexTarget" "  '''^x\$''',
]
regexTarget"

if ((failures > 0)); then
    printf '%s failure(s)\n' "$failures"
    exit 1
fi
echo "all gitleaks config checks passed"
