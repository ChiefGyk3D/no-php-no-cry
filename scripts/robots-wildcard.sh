#!/usr/bin/env bash
# Shared robots.txt parser, sourced by scripts/check-output.sh (the build) and
# scripts/verify-live.sh (the live host) so both read robots.txt the same way.
# Defines robots_wildcard only; sourcing it runs nothing.
#
# Environment, from robots.txt. Only the wildcard (User-agent: *) group decides
# it: a rule under another crawler's group, or before any User-agent line, says
# nothing about everyone else. Consecutive User-agent lines share one group.
# robots_wildcard <file> prints "<has-group> <disallow-all> <allow> <other-disallow>"
# as 0/1 flags for the wildcard group(s); comments and CRLF are ignored.
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
