#!/bin/ash
# FLINT 2 DNS BENCHMARK - GITHUB INSTALLER
# Installs benchmark + SSH login dashboard. No package, DNS,
# firewall, network or service configuration changes.

set -u

REPO='mfranjbar/flint2-dns-benchmark-'
BRANCH='main'
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
DIR='/root/dnstest'
SCRIPT="$DIR/dns-bench.sh"
DASHBOARD='/etc/profile.d/40-dnstest-dashboard.sh'
BACKUP_ROOT='/root/backup/dns'
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP="$BACKUP_ROOT/flint2-$STAMP"
WORK="/tmp/flint2-dns-install-$$"

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*"; exit 1; }

fetch() {
    URL="$1"; OUT="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$OUT" "$URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL "$URL" -o "$OUT"
    else
        return 1
    fi
}

say
say '========================================'
say '   FLINT 2 DNS BENCHMARK INSTALLER'
say '========================================'
say

[ "$(id -u 2>/dev/null)" = 0 ] || die 'Run this installer as root.'
mkdir -p "$DIR" "$BACKUP_ROOT" /etc/profile.d "$WORK" || die 'Could not create required directories.'

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say 'Downloading project files...'
fetch "$RAW_BASE/dns-bench.sh" "$WORK/dns-bench.sh" || die 'Could not download dns-bench.sh.'
fetch "$RAW_BASE/40-dnstest-dashboard.sh" "$WORK/40-dnstest-dashboard.sh" || die 'Could not download dashboard.'

[ -s "$WORK/dns-bench.sh" ] || die 'Downloaded benchmark is empty.'
[ -s "$WORK/40-dnstest-dashboard.sh" ] || die 'Downloaded dashboard is empty.'

say 'Checking shell syntax...'
ash -n "$WORK/dns-bench.sh" || die 'Benchmark shell syntax check failed.'
ash -n "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard shell syntax check failed.'

DNS_COUNT="$(sed -n "/^DNS_SERVERS='/,/^'$/p" "$WORK/dns-bench.sh" | grep -c '|')"
DOT_COUNT="$(sed -n "/^DOT_SERVERS='/,/^'$/p" "$WORK/dns-bench.sh" | grep -c '|')"
[ "$DNS_COUNT" = 25 ] || die "DNS server count mismatch: $DNS_COUNT (expected 25)."
[ "$DOT_COUNT" = 13 ] || die "DoT server count mismatch: $DOT_COUNT (expected 13)."

if [ -f "$SCRIPT" ] || [ -f "$DASHBOARD" ]; then
    mkdir -p "$BACKUP" || die 'Could not create backup directory.'
    [ ! -f "$SCRIPT" ] || cp -p "$SCRIPT" "$BACKUP/dns-bench.sh" || die 'Could not back up existing benchmark.'
    [ ! -f "$DASHBOARD" ] || cp -p "$DASHBOARD" "$BACKUP/40-dnstest-dashboard.sh" || die 'Could not back up existing dashboard.'
    say "Previous files backed up to: $BACKUP"
fi

cp "$WORK/dns-bench.sh" "$SCRIPT" || die 'Could not install benchmark.'
cp "$WORK/40-dnstest-dashboard.sh" "$DASHBOARD" || die 'Could not install dashboard.'
chmod 755 "$SCRIPT" || die 'Could not set benchmark permissions.'
chmod 644 "$DASHBOARD" || die 'Could not set dashboard permissions.'
ln -sf "$SCRIPT" /usr/bin/dnstest || die 'Could not create /usr/bin/dnstest symlink.'

[ "$(readlink /usr/bin/dnstest 2>/dev/null)" = "$SCRIPT" ] || die 'Command symlink verification failed.'
ash -n "$SCRIPT" || die 'Installed benchmark syntax check failed.'
ash -n "$DASHBOARD" || die 'Installed dashboard syntax check failed.'

say
say '===== SERVER COUNTS ====='
say "DNS servers: $DNS_COUNT"
say "DoT servers: $DOT_COUNT"
say
say '===== PRE-CHECK ====='
if dnstest --check; then
    say 'Pre-check: OK'
else
    say 'WARNING: Files installed, but dependency pre-check failed.'
    say 'Review the missing dependency or CA bundle message above.'
fi

say
say '========================================'
say '       INSTALLATION FINISHED'
say '========================================'
say "Main script: $SCRIPT"
say "Dashboard:   $DASHBOARD"
say 'Command:     dnstest'
[ -d "$BACKUP" ] && say "Backup:      $BACKUP"
say
say 'DNS benchmark was NOT started.'
say 'No package, DNS, firewall, network or service settings were changed.'
say 'Run dnstest when you want to start a benchmark.'
say '========================================'
