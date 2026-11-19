#!/bin/ash
# FLINT 2 DNS BENCHMARK - GITHUB INSTALLER
# Installs kdig (if missing), benchmark + SSH login dashboard.
# Does not change DNS, firewall, network or service configuration.

set -u

REPO='mfranjbar/flint2-dns-benchmark-'
BRANCH='main'
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
DIR='/root/dnstest'
SCRIPT="$DIR/dns-bench.sh"
DASHBOARD='/etc/profile.d/40-dnstest-dashboard.sh'
DOH_SCRIPT="$DIR/doh-bench.sh"
BACKUP_ROOT='/root/backup/dns'
STAMP="$(date '+%Y%m%d-%H%M%S')"
WORK_BASE='/tmp/flint2-dns-install'

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*"; exit 1; }



install_nl() {
    if command -v nl >/dev/null 2>&1; then
        say "nl already installed: $(command -v nl)"
        return 0
    fi

    say 'nl is missing. Installing package coreutils-nl...'
    if command -v apk >/dev/null 2>&1; then
        apk add coreutils-nl || die 'Could not install coreutils-nl with apk. Check package repository/index and internet access, then rerun the installer.'
    elif command -v opkg >/dev/null 2>&1; then
        opkg install coreutils-nl || die 'Could not install coreutils-nl with opkg. Check package feeds and internet access, then rerun the installer.'
    else
        die 'Neither apk nor opkg was found; cannot install nl automatically.'
    fi

    command -v nl >/dev/null 2>&1 || die 'Package installation finished, but nl was not found.'
    say "nl installed: $(command -v nl)"
}

install_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 1 sh -c 'exit 0' >/dev/null 2>&1 || die 'timeout exists but failed its execution test.'
        say "timeout already installed: $(command -v timeout)"
        return 0
    fi

    say 'timeout is missing. Installing package coreutils-timeout...'
    if command -v apk >/dev/null 2>&1; then
        apk add coreutils-timeout || die 'Could not install coreutils-timeout with apk. Check package repository/index and internet access, then rerun the installer.'
    elif command -v opkg >/dev/null 2>&1; then
        opkg install coreutils-timeout || die 'Could not install coreutils-timeout with opkg. Check package feeds and internet access, then rerun the installer.'
    else
        die 'Neither apk nor opkg was found; cannot install timeout automatically.'
    fi

    command -v timeout >/dev/null 2>&1 || die 'Package installation finished, but timeout was not found.'
    timeout 1 sh -c 'exit 0' >/dev/null 2>&1 || die 'timeout was installed but failed its execution test.'
    say "timeout installed and verified: $(command -v timeout)"
}

install_curl() {
    if command -v curl >/dev/null 2>&1; then
        curl --version 2>&1 | grep -qi 'https' || die 'curl exists but has no HTTPS/TLS support.'
        curl --help all 2>&1 | grep -q -- '--resolve' || die 'curl lacks --resolve support.'
        curl --help all 2>&1 | grep -q -- '--next' || die 'curl lacks --next support required for connection reuse.'
        curl --help all 2>&1 | grep -q -- '--write-out' || die 'curl lacks --write-out timing support.'
        say "curl already installed: $(command -v curl)"
        return 0
    fi

    say 'curl is missing. Installing package curl (without apk update)...'
    if command -v apk >/dev/null 2>&1; then
        apk add curl || die 'Could not install curl with apk. Check package repository/index and internet access, then rerun the installer.'
    elif command -v opkg >/dev/null 2>&1; then
        opkg install curl || die 'Could not install curl with opkg. Check package feeds and internet access, then rerun the installer.'
    else
        die 'Neither apk nor opkg was found; cannot install curl automatically.'
    fi

    command -v curl >/dev/null 2>&1 || die 'curl package installed but executable was not found.'
    curl --version 2>&1 | grep -qi 'https' || die 'Installed curl has no HTTPS/TLS support.'
    curl --help all 2>&1 | grep -q -- '--resolve' || die 'Installed curl lacks --resolve support.'
    curl --help all 2>&1 | grep -q -- '--next' || die 'Installed curl lacks --next support.'
    curl --help all 2>&1 | grep -q -- '--write-out' || die 'Installed curl lacks --write-out timing support.'
    say "curl installed and verified: $(command -v curl)"
}

install_kdig() {
    if [ -x /usr/bin/kdig ]; then
        say 'kdig already installed: /usr/bin/kdig'
        return 0
    fi

    say 'kdig is missing. Installing package knot-dig...'
    if command -v apk >/dev/null 2>&1; then
        apk add knot-dig || die 'Could not install knot-dig with apk. Check package repository/index and internet access, then rerun the installer.'
    elif command -v opkg >/dev/null 2>&1; then
        opkg install knot-dig || die 'Could not install knot-dig with opkg. Check package feeds and internet access, then rerun the installer.'
    else
        die 'Neither apk nor opkg was found; cannot install kdig automatically.'
    fi

    [ -x /usr/bin/kdig ] || die 'Package installation finished, but /usr/bin/kdig was not found.'
    say 'kdig installed: /usr/bin/kdig'
}

fetch() {
    URL="$1"; OUT="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$OUT" "$URL" && [ -s "$OUT" ] && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$URL" -o "$OUT" && [ -s "$OUT" ] && return 0
    fi
    return 1
}

say
say '========================================'
say '   FLINT 2 DNS BENCHMARK INSTALLER'
say '========================================'
say

[ "$(id -u 2>/dev/null)" = 0 ] || die 'Run this installer as root.'

WORK="$(mktemp -d "$WORK_BASE.XXXXXX")" || die 'Could not create unique work directory.'
RUN_ID="${WORK##*.}"
BACKUP="$BACKUP_ROOT/flint2-$STAMP-$RUN_ID"

cleanup() {
    rm -f "$DIR/.dns-bench.sh.new-$RUN_ID" "$DIR/.doh-bench.sh.new-$RUN_ID" "/etc/profile.d/.40-dnstest-dashboard.sh.new-$RUN_ID"
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say '===== STEP 1: PREPARE DIRECTORIES ====='
mkdir -p "$DIR" "$BACKUP_ROOT" /etc/profile.d "$WORK" || die 'Could not create required directories.'
[ -d "$DIR" ] && [ -w "$DIR" ] || die "Benchmark directory is not writable: $DIR"
say "Benchmark directory ready: $DIR"

say
say '===== STEP 2: DOWNLOAD PROJECT FILES ====='
fetch "$RAW_BASE/dns-bench.sh" "$WORK/dns-bench.sh" || die 'Could not download dns-bench.sh.'
fetch "$RAW_BASE/40-dnstest-dashboard.sh" "$WORK/40-dnstest-dashboard.sh" || die 'Could not download dashboard.'
fetch "$RAW_BASE/doh-bench.sh" "$WORK/doh-bench.sh" || die 'Could not download DoH benchmark.'

[ -s "$WORK/dns-bench.sh" ] || die 'Downloaded benchmark is empty.'
[ -s "$WORK/40-dnstest-dashboard.sh" ] || die 'Downloaded dashboard is empty.'
[ -s "$WORK/doh-bench.sh" ] || die 'Downloaded DoH benchmark is empty.'

say
say '===== STEP 3: CHECK SHELL SYNTAX / SERVER COUNTS ====='
ash -n "$WORK/dns-bench.sh" || die 'Benchmark shell syntax check failed.'
ash -n "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard shell syntax check failed.'
ash -n "$WORK/doh-bench.sh" || die 'DoH benchmark shell syntax check failed.'

DNS_COUNT="$(sed -n "/^DNS_SERVERS='/,/^'$/p" "$WORK/dns-bench.sh" | grep -c '|')"
DOT_COUNT="$(sed -n "/^DOT_SERVERS='/,/^'$/p" "$WORK/dns-bench.sh" | grep -c '|')"
[ "$DNS_COUNT" = 25 ] || die "DNS server count mismatch: $DNS_COUNT (expected 25)."
[ "$DOT_COUNT" = 13 ] || die "DoT server count mismatch: $DOT_COUNT (expected 13)."
DOH_COUNT="$(sed -n "/^DOH_SERVERS='/,/^'$/p" "$WORK/doh-bench.sh" | grep -c '|')"
[ "$DOH_COUNT" = 16 ] || die "DoH server count mismatch: $DOH_COUNT (expected 16)."

# Verify that the downloaded files belong to this project version.
grep -q 'mkdir "\$TMP"' "$WORK/dns-bench.sh" || die 'Benchmark is missing temporary-directory creation.'
grep -q 'REPORT="$DIR/latest-top4.txt"' "$WORK/dns-bench.sh" || die 'Benchmark report path is not the expected path.'
grep -q 'REPORT="/root/dnstest/latest-top4.txt"' "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard report path does not match the benchmark.'
grep -q 'DNS benchmark SSH dashboard' "$WORK/40-dnstest-dashboard.sh" || die 'Downloaded SSH dashboard is not the expected dashboard.'
grep -q 'for cmd in .*nl' "$WORK/dns-bench.sh" || die 'Benchmark is missing the nl dependency check.'
grep -q 'TOP 4 DNS + BEST DoT' "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard title is missing.'
grep -Fq 'case "$-" in *i*)' "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard interactive-shell guard is missing.'
grep -Fq '[ -n "${SSH_CONNECTION:-}" ]' "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard SSH-only guard is missing.'
grep -q '\$1 <= 4' "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard TOP 4 filter is missing.'
grep -q 'No test date found.' "$WORK/40-dnstest-dashboard.sh" || die 'Dashboard missing-date handling is missing.'
grep -Fq -- '--next' "$WORK/doh-bench.sh" || die 'DoH connection reuse option is missing.'
grep -Fq -- '--resolve' "$WORK/doh-bench.sh" || die 'DoH direct endpoint resolution is missing.'
grep -Fq 'verify_dns_response' "$WORK/doh-bench.sh" || die 'DoH response verification is missing.'
grep -Fq -- '--data-binary' "$WORK/doh-bench.sh" || die 'DoH POST support is missing.'
grep -Fq -- '--doh' "$WORK/dns-bench.sh" || die 'Main command is missing DoH dispatch.'

say
say '===== STEP 4: CHECK / INSTALL NL ====='
install_nl

say
say '===== STEP 5: CHECK / INSTALL TIMEOUT ====='
install_timeout

say
say '===== STEP 6: CHECK / INSTALL CURL (DoH) ====='
install_curl

say '===== STEP 7: CHECK / INSTALL KDIG ====='
install_kdig

if [ -f "$SCRIPT" ] || [ -f "$DASHBOARD" ] || [ -f "$DOH_SCRIPT" ]; then
    mkdir -p "$BACKUP" || die 'Could not create backup directory.'
    [ ! -f "$SCRIPT" ] || cp -p "$SCRIPT" "$BACKUP/dns-bench.sh" || die 'Could not back up existing benchmark.'
    [ ! -f "$DASHBOARD" ] || cp -p "$DASHBOARD" "$BACKUP/40-dnstest-dashboard.sh" || die 'Could not back up existing dashboard.'
    [ ! -f "$DOH_SCRIPT" ] || cp -p "$DOH_SCRIPT" "$BACKUP/doh-bench.sh" || die 'Could not back up existing DoH benchmark.'
    say "Previous files backed up to: $BACKUP"
fi

say
say '===== STEP 8: BACK UP / INSTALL FILES ====='
# Stage both files on their destination filesystems, then replace the live files.
SCRIPT_STAGE="$DIR/.dns-bench.sh.new-$RUN_ID"
DASH_STAGE="/etc/profile.d/.40-dnstest-dashboard.sh.new-$RUN_ID"
DOH_STAGE="$DIR/.doh-bench.sh.new-$RUN_ID"
cp "$WORK/dns-bench.sh" "$SCRIPT_STAGE" || die 'Could not stage benchmark.'
cp "$WORK/40-dnstest-dashboard.sh" "$DASH_STAGE" || die 'Could not stage SSH dashboard.'
cp "$WORK/doh-bench.sh" "$DOH_STAGE" || die 'Could not stage DoH benchmark.'
chmod 755 "$SCRIPT_STAGE" || die 'Could not set benchmark permissions.'
chmod 644 "$DASH_STAGE" || die 'Could not set dashboard permissions.'
chmod 755 "$DOH_STAGE" || die 'Could not set DoH benchmark permissions.'
ash -n "$SCRIPT_STAGE" || die 'Staged benchmark syntax check failed.'
ash -n "$DASH_STAGE" || die 'Staged dashboard syntax check failed.'
ash -n "$DOH_STAGE" || die 'Staged DoH benchmark syntax check failed.'
mv -f "$SCRIPT_STAGE" "$SCRIPT" || die 'Could not install benchmark.'
mv -f "$DASH_STAGE" "$DASHBOARD" || die 'Could not install SSH dashboard.'
mv -f "$DOH_STAGE" "$DOH_SCRIPT" || die 'Could not install DoH benchmark.'
ln -sf "$SCRIPT" /usr/bin/dnstest || die 'Could not create /usr/bin/dnstest symlink.'

[ -x "$SCRIPT" ] || die 'Installed benchmark is not executable.'
[ -r "$DASHBOARD" ] || die 'Installed SSH dashboard is not readable.'
[ -x "$DOH_SCRIPT" ] || die 'Installed DoH benchmark is not executable.'
[ "$(readlink /usr/bin/dnstest 2>/dev/null)" = "$SCRIPT" ] || die 'Command symlink verification failed.'
ash -n "$SCRIPT" || die 'Installed benchmark syntax check failed.'
ash -n "$DASHBOARD" || die 'Installed dashboard syntax check failed.'
ash -n "$DOH_SCRIPT" || die 'Installed DoH benchmark syntax check failed.'
grep -q 'REPORT="/root/dnstest/latest-top4.txt"' "$DASHBOARD" || die 'Installed dashboard report path verification failed.'
[ -x /usr/bin/kdig ] || die 'kdig is not executable at /usr/bin/kdig.'

say
say '===== STEP 9: PRE-CHECK ====='
if dnstest --check; then
    say 'Classic DNS pre-check: OK'
else
    say 'WARNING: Classic DNS pre-check failed; review the dependency or CA bundle message above.'
fi

if dnstest --doh --check; then
    say 'DoH pre-check: OK'
else
    say 'WARNING: DoH pre-check failed; review the curl, CA bundle or utility message above.'
fi

say
say '========================================'
say '       INSTALLATION FINISHED'
say '========================================'
say "Main script: $SCRIPT"
say "Dashboard:   $DASHBOARD"
say "DoH script:  $DOH_SCRIPT"
say 'SSH login dashboard: installed and verified'
say 'Command:     dnstest'
[ -d "$BACKUP" ] && say "Backup:      $BACKUP"
say
say 'nl installation: verified'
say 'timeout installation: verified'
say 'kdig installation: verified'
say 'curl HTTPS/connection-reuse support: verified'
say 'Benchmark directory: created and verified'
say 'DNS benchmark was NOT started.'
say 'DoH benchmark was NOT started.'
say 'No DNS, firewall, network or service settings were changed.'
say 'Run dnstest when you want to start a benchmark.'
say '========================================'
