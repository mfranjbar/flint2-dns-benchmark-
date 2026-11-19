#!/bin/ash
# FLINT 2 DNS BENCHMARK - SAFE UNINSTALLER
# Removes only this project's installed script, command symlink, and SSH dashboard.
# Preserves reports, backups, /root/dnstest directory, and installed packages.

set -u

DIR='/root/dnstest'
SCRIPT="$DIR/dns-bench.sh"
COMMAND='/usr/bin/dnstest'
DASHBOARD='/etc/profile.d/40-dnstest-dashboard.sh'

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*"; exit 1; }

[ "$(id -u 2>/dev/null)" = 0 ] || die 'Run this uninstaller as root.'

say '========================================'
say ' FLINT 2 DNS BENCHMARK UNINSTALLER'
say '========================================'
say
say 'The following project files will be removed only if they match:'
say " - $SCRIPT"
say " - $COMMAND (only if it points to $SCRIPT)"
say " - $DASHBOARD (only if it is this project's dashboard)"
say
say 'Preserved:'
say " - $DIR/latest-top4.txt and all other report/data files"
say ' - /root/backup/dns/ and all backups'
say " - $DIR itself"
say ' - kdig / knot-dig and all installed packages'
say ' - DNS, firewall, network and service settings'
say

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    die 'Interactive confirmation is required; no files were removed.'
fi

printf 'Type YES to uninstall: ' >/dev/tty
IFS= read -r ANSWER </dev/tty || die 'Could not read confirmation.'
[ "$ANSWER" = 'YES' ] || die 'Cancelled; no files were removed.'

say
say '===== REMOVE PROJECT FILES ====='

if [ -f "$SCRIPT" ] && grep -Fq '# FLINT 2 DNS BENCHMARK' "$SCRIPT"; then
    rm -f "$SCRIPT" || die "Could not remove $SCRIPT"
    say "Removed: $SCRIPT"
else
    say "Kept (missing or not recognized): $SCRIPT"
fi

if [ -L "$COMMAND" ]; then
    TARGET="$(readlink "$COMMAND" 2>/dev/null || true)"
    if [ "$TARGET" = "$SCRIPT" ]; then
        rm -f "$COMMAND" || die "Could not remove $COMMAND"
        say "Removed: $COMMAND"
    else
        say "Kept (points elsewhere): $COMMAND"
    fi
else
    say "Kept (not this project's symlink): $COMMAND"
fi

if [ -f "$DASHBOARD" ] &&
   grep -Fq '# Flint 2 - DNS benchmark SSH dashboard' "$DASHBOARD" &&
   grep -Fq 'REPORT="/root/dnstest/latest-top4.txt"' "$DASHBOARD"; then
    rm -f "$DASHBOARD" || die "Could not remove $DASHBOARD"
    say "Removed: $DASHBOARD"
else
    say "Kept (missing or not recognized): $DASHBOARD"
fi

say
say '========================================'
say ' UNINSTALL FINISHED'
say '========================================'
say 'Reports, backups, data directory and packages were preserved.'
say 'No DNS, firewall, network or service settings were changed.'
say '========================================'
