#!/usr/bin/env bash
# Usage: scripts/verify-live.sh HOST [--resolve-ip IP] [--public DIR] [--env staging|production]
#
# Read-only verification of a DEPLOYED host (GET requests only, curl only for the
# network, every request bounded by connect and total timeouts). Intended for the
# staging host now and for the apex after cutover (docs/cutover.md). It prints
# one "ok:" or "FAIL:" line per check and exits 1 if any check failed.
#
#   HOST          bare host (example.com), host:port, or https://host. http://
#                 is refused unless VERIFY_ALLOW_HTTP=1 (tests only).
#   --resolve-ip  connect to this address instead of the resolver's answer
#                 (curl --resolve), for a name the local resolver cannot see yet.
#   --public DIR  the built site to compare with. Default: build it with the
#                 repository's own layouts (hugo on PATH) into a throwaway dir
#                 under the repository's tmp/.
#   --env         staging or production. Default: read from the host's
#                 robots.txt. Given, a host that disagrees fails (env-mismatch).
#
# Expectations come from the build, so they follow the site:
#   redirect         every rule in <public>/_redirects answers with its declared
#                    status (301 or 302; any other status is refused) and the
#                    expected Location (relative, or absolute on this host)
#   status           the home page and every template page below answer 200
#   not-found        a missing path answers 404 with the noindex 404 page
#   header-*         on every page checked, each header in <public>/_headers
#                    (from static/_headers) is present exactly once, equal to
#                    the build's value; the Content-Security-Policy first
#   sitemap / feed   /sitemap.xml and the feed are well-formed XML of the right
#                    kind, and name only this host; the feed carries exactly one
#                    atom:link rel=self on this host. The feed path is read from
#                    the build's home page (<link rel=alternate type=
#                    application/rss+xml>) or set with VERIFY_FEED_PATH.
#   robots           /robots.txt (its User-agent: * group decides, as in
#                    scripts/check-output.sh) matches the environment (staging: Disallow all,
#                    no sitemap, noindex meta on pages; production: Allow all,
#                    Sitemap line for this host, no robots meta on the home page)
#   copy-js          the served /copy.js has the bytes of the build's copy.js
#   third-party      no page, the sitemap, the feed or the stylesheet loads
#                    anything from another host (scripts/scan-markup.py rules
#                    external-asset and http-reference, plus a stylesheet scan)
#
# Exit: 0 all checks passed, 1 a check failed, 2 bad input.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scan_py="$root/scripts/scan-markup.py"

usage() {
    echo "usage: verify-live.sh HOST [--resolve-ip IP] [--public DIR] [--env staging|production]"
    exit 2
}

host_arg="" resolve_ip="" public_dir="" want_env=""
while (($#)); do
    case "$1" in
        --resolve-ip)
            [[ $# -ge 2 ]] || usage
            resolve_ip="$2"
            shift 2
            ;;
        --public)
            [[ $# -ge 2 ]] || usage
            public_dir="$2"
            shift 2
            ;;
        --env)
            [[ $# -ge 2 ]] || usage
            want_env="$2"
            shift 2
            ;;
        -h | --help) usage ;;
        -*)
            echo "input: unknown option $1"
            exit 2
            ;;
        *)
            [[ -z "$host_arg" ]] || usage
            host_arg="$1"
            shift
            ;;
    esac
done
[[ -n "$host_arg" ]] || usage

scheme=https
hostport="${host_arg%/}"
case "$hostport" in
    https://*) hostport="${hostport#https://}" ;;
    http://*)
        if [[ "${VERIFY_ALLOW_HTTP:-}" != 1 ]]; then
            echo "input: the host must be https (got ${host_arg})"
            exit 2
        fi
        scheme=http
        hostport="${hostport#http://}"
        ;;
esac
if [[ ! "$hostport" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]]; then
    echo "input: HOST must be a bare host name or host:port (got ${host_arg})"
    exit 2
fi
host="${hostport%%:*}"
if [[ "$hostport" == *:* ]]; then
    port="${hostport##*:}"
elif [[ "$scheme" == https ]]; then
    port=443
else
    port=80
fi
base="${scheme}://${hostport}"
if [[ -n "$resolve_ip" && ! "$resolve_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f:]+$ ]]; then
    echo "input: --resolve-ip must be an IPv4 or IPv6 address (got ${resolve_ip})"
    exit 2
fi
case "$want_env" in "" | staging | production) ;; *)
    echo "input: --env must be staging or production"
    exit 2
    ;;
esac

for tool in curl python3 awk sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "input: ${tool} is not on PATH"
        exit 2
    }
done

mkdir -p "$root/tmp"
work="$(mktemp -d "$root/tmp/verify-live.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [[ -z "$public_dir" ]]; then
    command -v hugo >/dev/null 2>&1 || {
        echo "input: hugo is not on PATH and no --public DIR was given"
        exit 2
    }
    public_dir="$work/build"
    if ! hugo --quiet --source "$root" --destination "$public_dir" >"$work/build.log" 2>&1; then
        echo "input: the site did not build: $(tail -n 3 "$work/build.log")"
        exit 2
    fi
fi
dir="$public_dir"

# --- read the expectations from the build --------------------------------------
header_names=() header_values=()
if [[ -f "$dir/_headers" ]]; then
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]+([A-Za-z][A-Za-z0-9-]*):[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]]; then
            header_names+=("${BASH_REMATCH[1]}")
            header_values+=("${BASH_REMATCH[2]}")
        fi
    done <"$dir/_headers"
fi
csp_seen=0
for n in "${header_names[@]}"; do [[ "${n,,}" == content-security-policy ]] && csp_seen=1; done
if [[ $csp_seen -eq 0 ]]; then
    echo "input: no Content-Security-Policy in ${dir}/_headers"
    exit 2
fi
if [[ ! -f "$dir/_redirects" ]]; then
    echo "input: no _redirects in ${dir}"
    exit 2
fi

first_page() { # first_page <section>: /section/slug/ of the first page, or nothing
    local p
    p="$(find "$dir/$1" -mindepth 2 -maxdepth 2 -name index.html 2>/dev/null | sort | head -n 1)" || true
    [[ -n "$p" ]] || return 0
    p="${p#"$dir"}"
    printf '%s/\n' "${p%/index.html}"
}
pages=(/)
for s in about support privacy products social resume posts journal; do
    [[ -f "$dir/$s/index.html" ]] && pages+=("/$s/")
done
for s in posts journal; do
    p="$(first_page "$s")"
    [[ -n "$p" ]] && pages+=("$p")
done
missing_page=/verify-live-missing-page/

# --- reporting ------------------------------------------------------------------
checks=0 failures=0
ok() {
    checks=$((checks + 1))
    echo "ok: $1: $2"
}
bad() {
    checks=$((checks + 1))
    failures=$((failures + 1))
    echo "FAIL: $1: $2"
}

# --- fetching -------------------------------------------------------------------
curl_opts=(-sS --max-time 15 --connect-timeout 10 --max-filesize 5242880 --proto "=${scheme}")
[[ -n "$resolve_ip" ]] && curl_opts+=(--resolve "${host}:${port}:${resolve_ip}")
hdr="$work/hdr" body="$work/body" code=""
# fetch <path>: GET, never following redirects. Sets $code, $hdr and $body.
fetch() {
    : >"$hdr"
    : >"$body"
    code=""
    code="$(curl "${curl_opts[@]}" -o "$body" -D "$hdr" -w '%{http_code}' "${base}$1")" || {
        code=""
        return 1
    }
}

header_count() { # header_count <name>: how many times the last response set it
    awk -v want="${1,,}" '{ sub(/\r$/, "") }
        index($0, ":") && tolower(substr($0, 1, index($0, ":") - 1)) == want { n++ }
        END { print n + 0 }' "$hdr"
}
header_first() { # header_first <name>: the first value of that header
    awk -v want="${1,,}" '{ sub(/\r$/, "") }
        index($0, ":") && tolower(substr($0, 1, index($0, ":") - 1)) == want {
            v = substr($0, index($0, ":") + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit
        }' "$hdr"
}

# check_headers <label>: every header the build sets is on the last response once, equal.
check_headers() {
    local i name want n got failed=0
    for i in "${!header_names[@]}"; do
        name="${header_names[$i]}"
        want="${header_values[$i]}"
        n="$(header_count "$name")"
        if [[ "$n" -eq 0 ]]; then
            bad "header-missing" "$1 has no ${name} header"
            failed=1
        elif [[ "$n" -gt 1 ]]; then
            bad "header-duplicate" "$1 has ${n} ${name} headers, wanted 1"
            failed=1
        else
            got="$(header_first "$name")"
            if [[ "$got" != "$want" ]]; then
                bad "header-wrong" "$1 ${name} is '${got}', wanted '${want}'"
                failed=1
            fi
        fi
    done
    [[ $failed -eq 1 ]] || ok "headers" "$1 carries all ${#header_names[@]} headers of _headers exactly"
}

# third_party <label> <mode>: reads $body with the build check's parser (mode
# html or markup) and reports a load from another host.
third_party() {
    local opts=() found rule bad_any=0
    [[ "$2" == markup ]] && opts=(--markup)
    if ! found="$(python3 -I "$scan_py" "${opts[@]}" "$host" "$body")"; then
        bad "third-party" "$1 could not be parsed"
        return
    fi
    while IFS= read -r rule; do
        case "$rule" in
            http-reference)
                # http:// to the own host only matters when the site is https (tests run on http)
                if [[ "$scheme" == https ]]; then
                    bad "third-party" "$1 serves 'http-reference' (an http:// URL)"
                    bad_any=1
                fi
                ;;
            external-asset)
                bad "third-party" "$1 serves '${rule}' (loads from another host or over http)"
                bad_any=1
                ;;
        esac
    done <<<"$found"
    [[ $bad_any -eq 1 ]] || ok "third-party" "$1 loads nothing from another host"
}

# --- redirects --------------------------------------------------------------------
rules=0 rule_fail=0
while read -r from to status extra; do
    [[ -n "$from" ]] || continue
    if [[ "$from" != /* || "$to" != /* || -n "$extra" || ! "$status" =~ ^30[12]$ ]]; then
        bad "redirect" "unsupported _redirects rule '${from} ${to} ${status}${extra:+ ${extra}}' (wanted '/from /to 301|302')"
        rules=$((rules + 1))
        rule_fail=$((rule_fail + 1))
        continue
    fi
    rules=$((rules + 1))
    if ! fetch "$from"; then
        bad "redirect" "${from} got no response"
        rule_fail=$((rule_fail + 1))
        continue
    fi
    loc="$(header_first location)"
    loc="${loc#"$base"}"
    if [[ "$code" != "$status" || "$loc" != "$to" ]]; then
        bad "redirect" "${from} answered '${code}' Location '$(header_first location)', wanted ${status} to ${to}"
        rule_fail=$((rule_fail + 1))
    fi
done < <(grep -v '^#' "$dir/_redirects" || true)
if [[ $rules -eq 0 ]]; then
    bad "redirect" "${dir}/_redirects holds no rule to check"
elif [[ $rule_fail -eq 0 ]]; then
    ok "redirect" "all ${rules} rules answer with their declared status and the expected Location"
fi

# --- robots (decides the environment) ---------------------------------------------
# robots_wildcard <file>: the same parse as scripts/check-output.sh. Only the
# User-agent: * group decides the environment; a rule under another crawler's
# group, or before any User-agent line, says nothing about everyone else.
# Prints "<has-group> <disallow-all> <allow> <other-disallow>" as 0/1 flags.
robots_wildcard() {
    awk '
        { sub(/#.*/, ""); gsub(/\r/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
        $0 == "" { next }
        {
            i = index($0, ":")
            if (i == 0) next
            key = tolower(substr($0, 1, i - 1)); val = substr($0, i + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
        }
        key == "user-agent" {
            if (!prev_ua) wild = 0
            if (val == "*") { wild = 1; has = 1 }
            prev_ua = 1; seen_ua = 1
            next
        }
        { prev_ua = 0 }
        !seen_ua { next }
        !wild { next }
        key == "disallow" && val == "/" { dis_all = 1 }
        key == "disallow" && val != "" && val != "/" { dis_other = 1 }
        key == "allow" && val != "" { allow = 1 }
        END { printf "%d %d %d %d\n", has, dis_all, allow, dis_other }
    ' "$1"
}

detected=""
if fetch /robots.txt && [[ "$code" == 200 ]]; then
    robots="$(tr -d '\r' <"$body")"
    read -r has_wild dis_all allow_any dis_other < <(robots_wildcard "$body")
    if [[ $has_wild -eq 0 ]]; then
        bad "robots" "/robots.txt has no 'User-agent: *' group"
    elif [[ $dis_all -eq 1 ]]; then
        detected=staging
    elif [[ $allow_any -eq 1 ]]; then
        detected=production
    else
        bad "robots" "/robots.txt has neither 'Disallow: /' nor 'Allow: /' for 'User-agent: *'"
    fi
    if [[ -z "$detected" ]]; then
        : # the fault is already reported
    elif [[ -n "$want_env" && "$want_env" != "$detected" ]]; then
        bad "env-mismatch" "/robots.txt says ${detected}, wanted ${want_env}"
    elif [[ "$detected" == staging ]]; then
        if [[ $allow_any -eq 1 ]] || grep -qi '^Sitemap:' <<<"$robots"; then
            bad "robots" "staging /robots.txt re-opens something for 'User-agent: *' or names a sitemap"
        else
            ok "robots" "staging: Disallow all, no sitemap"
        fi
    elif [[ $dis_other -eq 1 ]]; then
        bad "robots" "production /robots.txt disallows a path for 'User-agent: *'"
    elif ! grep -qx "Sitemap: ${base}/sitemap.xml" <<<"$robots"; then
        bad "robots" "production /robots.txt lacks 'Sitemap: ${base}/sitemap.xml'"
    else
        ok "robots" "production: Allow all, Sitemap line for ${host}"
    fi
else
    bad "robots" "/robots.txt answered '${code}', wanted 200"
fi
env_now="${want_env:-$detected}"

# --- pages ----------------------------------------------------------------------------
home_css=""
for page in "${pages[@]}"; do
    if ! fetch "$page"; then
        bad "status" "${page} got no response"
        continue
    fi
    if [[ "$code" == 200 ]]; then
        ok "status" "${page} answers 200"
    else
        bad "status" "${page} answered '${code}', wanted 200"
        continue
    fi
    check_headers "$page"
    third_party "$page" html
    if [[ "$page" == / ]]; then
        home_css="$(sed -nE 's/.*href="?(\/[^" >]+\.css).*/\1/p' "$body" | head -n 1)"
        meta=0
        grep -Eiq '<meta[^>]+name="?robots"?' "$body" && meta=1
        if [[ "$env_now" == production && $meta -eq 1 ]]; then
            bad "robots-meta" "production home page carries a robots meta"
        elif [[ "$env_now" == staging ]] && ! grep -Eiq '<meta[^>]+name="?robots"?[^>]+content="?[^">]*noindex' "$body"; then
            bad "robots-meta" "staging home page has no noindex robots meta"
        elif [[ -n "$env_now" ]]; then
            ok "robots-meta" "home page robots meta fits ${env_now}"
        fi
    fi
done

# --- 404 -------------------------------------------------------------------------------
if fetch "$missing_page"; then
    if [[ "$code" != 404 ]]; then
        bad "not-found" "${missing_page} answered '${code}', wanted 404"
    elif ! grep -Eiq '<meta[^>]+name="?robots"?[^>]+content="?[^">]*noindex' "$body"; then
        bad "not-found" "the 404 page has no noindex robots meta"
    else
        ok "not-found" "a missing path answers 404 with the noindex page"
    fi
    check_headers "$missing_page (404)"
    third_party "$missing_page (404)" html
else
    bad "not-found" "${missing_page} got no response"
fi

# --- sitemap and feed --------------------------------------------------------------------
# xml_check <kind> <expected-base>: reads $body. Prints a detail line; exit 1 on a fault.
xml_check() {
    python3 -I - "$1" "$2" "$body" <<'PY'
import sys
import xml.etree.ElementTree as ET

kind, base, path = sys.argv[1:4]
raw = open(path, "rb").read()
if b"<!DOCTYPE" in raw or b"<!ENTITY" in raw:
    print("a DOCTYPE or ENTITY declaration is not allowed")
    sys.exit(1)
try:
    root = ET.fromstring(raw)
except ET.ParseError as e:
    print("not well-formed XML: %s" % e)
    sys.exit(1)
tag = root.tag.rsplit("}", 1)[-1]
if kind == "sitemap":
    if tag != "urlset":
        print("root element is %s, wanted urlset" % tag)
        sys.exit(1)
    locs = [e.text or "" for e in root.iter() if e.tag.rsplit("}", 1)[-1] == "loc"]
    if not locs:
        print("no url entries")
        sys.exit(1)
    off = [l for l in locs if not l.startswith(base + "/")]
    if off:
        print("%d url(s) outside %s, first: %s" % (len(off), base, off[0]))
        sys.exit(1)
    print("%d urls, all on %s" % (len(locs), base))
else:
    if tag != "rss":
        print("root element is %s, wanted rss" % tag)
        sys.exit(1)
    ch = root.find("channel")
    if ch is None:
        print("no channel element")
        sys.exit(1)
    link = (ch.findtext("link") or "").strip()
    if link != base + "/":
        print("channel link is '%s', wanted %s/" % (link, base))
        sys.exit(1)
    atom = "{http://www.w3.org/2005/Atom}"
    selfs = [l for l in root.iter(atom + "link") if l.get("rel") == "self"]
    if len(selfs) != 1:
        print("%d atom:link rel=self elements, wanted 1" % len(selfs))
        sys.exit(1)
    if not (selfs[0].get("href") or "").startswith(base + "/"):
        print("atom:link rel=self is '%s', wanted a URL on %s" % (selfs[0].get("href"), base))
        sys.exit(1)
    items = ch.findall("item")
    if not items:
        print("no items")
        sys.exit(1)
    off = [i.findtext("link") for i in items if not (i.findtext("link") or "").startswith(base + "/")]
    if off:
        print("%d item link(s) outside %s, first: %s" % (len(off), base, off[0]))
        sys.exit(1)
    print("%d items, all on %s" % (len(items), base))
PY
}
# The feed path follows the build: VERIFY_FEED_PATH, else the home page's
# <link rel=alternate type=application/rss+xml href=...> (path part only).
feed_path="${VERIFY_FEED_PATH:-}"
if [[ -z "$feed_path" && -f "$dir/index.html" ]]; then
    feed_path="$(grep -Eio '<link[^>]*application/rss\+xml[^>]*>' "$dir/index.html" | head -n 1 |
        sed -nE 's/.*href="?([^" >]+).*/\1/p' | sed -E 's#^https?://[^/]+##')" || true
fi
if [[ "$feed_path" != /* ]]; then
    bad "feed" "no feed path: the build's home page has no rss alternate link and VERIFY_FEED_PATH is unset"
    feed_path=""
fi
specs=("sitemap:/sitemap.xml:sitemap")
[[ -z "$feed_path" ]] || specs+=("feed:${feed_path}:feed")
for spec in "${specs[@]}"; do
    IFS=: read -r kind path label <<<"$spec"
    if ! fetch "$path"; then
        bad "$kind" "${path} got no response"
    elif [[ "$code" != 200 ]]; then
        bad "$kind" "${path} answered '${code}', wanted 200"
    elif ! detail="$(xml_check "$label" "$base")"; then
        bad "$kind" "${path}: ${detail}"
    else
        ok "$kind" "${path} parses: ${detail}"
        third_party "$path" markup
    fi
done

# --- the stylesheet and the one script --------------------------------------------------
if [[ -n "$home_css" ]]; then
    if fetch "$home_css" && [[ "$code" == 200 ]]; then
        css_hosts="$(grep -Eo '(https?:)?//[A-Za-z0-9][A-Za-z0-9.:-]*' "$body" | sed -E 's#^(https?:)?//##; s#:[0-9]*$##' | sort -u | grep -vxF "$host" || true)"
        if [[ -n "$css_hosts" ]]; then
            bad "third-party" "${home_css} references another host: $(head -n 1 <<<"$css_hosts")"
        else
            ok "third-party" "${home_css} references no other host"
        fi
    else
        bad "status" "${home_css} answered '${code}', wanted 200"
    fi
fi
if [[ -f "$dir/copy.js" ]]; then
    if fetch /copy.js && [[ "$code" == 200 ]]; then
        if [[ "$(sha256sum <"$body" | cut -d' ' -f1)" == "$(sha256sum <"$dir/copy.js" | cut -d' ' -f1)" ]]; then
            ok "copy-js" "/copy.js has the bytes of the build"
        else
            bad "copy-js" "/copy.js does not match the build's copy.js"
        fi
    else
        bad "copy-js" "/copy.js answered '${code}', wanted 200"
    fi
fi

echo "verify-live: ${checks} checks on ${base}, ${failures} failed"
((failures == 0)) || exit 1
