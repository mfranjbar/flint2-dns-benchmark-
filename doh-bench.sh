#!/bin/ash
# FLINT 2 DNS OVER HTTPS BENCHMARK
# Independent implementation of the warm-up + DoH latency methodology.
# No DNS, firewall, network, or service configuration changes.

DIR="${DNSTEST_DIR:-/root/dnstest}"
REPORT="$DIR/latest-doh.txt"
KDIG="${DNSTEST_KDIG:-/usr/bin/kdig}"
CA_FILE="${DNSTEST_CA_FILE:-/etc/ssl/cert.pem}"
[ -s "$CA_FILE" ] || CA_FILE='/etc/ssl/certs/ca-certificates.crt'
ROUNDS=2
WARMUP_ROUNDS=1
QUERY_TIMEOUT=5
SERVER_LIMIT=240
TIMEOUT_PENALTY=5000
DOMAINS='google.com youtube.com facebook.com instagram.com chatgpt.com x.com whatsapp.com reddit.com wikipedia.org amazon.com tiktok.com pinterest.com'
DOH_SERVERS='
Cloudflare|1.1.1.1|cloudflare-dns.com|/dns-query
Google|8.8.8.8|dns.google|/dns-query
Quad9|9.9.9.9|dns.quad9.net|/dns-query
AdGuard|94.140.14.14|dns.adguard-dns.com|/dns-query
DNS-SB|185.222.222.222|doh.dns.sb|/dns-query
Mullvad|194.242.2.2|dns.mullvad.net|/dns-query
LibreDNS|116.202.176.26|doh.libredns.gr|/dns-query
ControlD|76.76.2.0|freedns.controld.com|/p0
OpenDNS|208.67.222.222|doh.opendns.com|/dns-query
Digitale-Gesellschaft|185.95.218.42|dns.digitale-gesellschaft.ch|/dns-query
DNS4EU|86.54.11.100|unfiltered.joindns4.eu|/dns-query
IIJ|203.180.164.45|public.dns.iij.jp|/dns-query
UncensoredDNS|91.239.100.100|anycast.uncensoreddns.org|/dns-query
Switch|130.59.31.248|dns.switch.ch|/dns-query
OpenBLD|146.112.41.2|ada.openbld.net|/dns-query
Canadian-Shield|149.112.121.10|private.canadianshield.cira.ca|/dns-query
'
TMP="/tmp/flint-doh-$$"
RAW="$TMP.raw"
OUTPUT="$TMP.output"
LOCK='/tmp/flint-doh-benchmark.lock'
TOTAL_DOMAINS=12
TOTAL_SAMPLES=$((TOTAL_DOMAINS * ROUNDS))
WARMUP_COUNT=$((TOTAL_DOMAINS * WARMUP_ROUNDS))

say() { printf '%s\n' "$*"; }
fail() { say "ERROR: $*" >&2; exit 1; }

cleanup() {
    rm -f "$RAW" "$OUTPUT" "$TMP.samples" "$TMP.sorted" "$TMP.report" "$TMP.servers" "$TMP.values"
    rmdir "$TMP" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
}

check_dependencies() {
    for cmd in kdig awk sort grep sed head date mkdir rmdir rm mv timeout wc tr; do
        command -v "$cmd" >/dev/null 2>&1 || {
            say "Missing command: $cmd"
            return 1
        }
    done
    [ -x "$KDIG" ] || { say "kdig not executable at $KDIG"; return 1; }
    [ -s "$CA_FILE" ] || { say 'CA certificate bundle missing.'; return 1; }
    "$KDIG" -h 2>&1 | grep -qi 'https' || {
        say 'This kdig build does not advertise DoH (+https) support.'
        say 'A kdig build compiled with libnghttp2 is required.'
        return 1
    }
    timeout 1 sh -c 'exit 0' >/dev/null 2>&1 || {
        say 'timeout command failed its execution check.'
        return 1
    }
    return 0
}

print_report() {
    printf '\n'
    printf '%s\n' '=========================================================================='
    printf '%s\n' '                 DNS OVER HTTPS BENCHMARK / FLINT 2'
    printf '%s\n' '=========================================================================='
    printf '%-3s %-23s %-8s %-8s %-8s %-8s %-8s %s\n' '#' 'DNS' 'MIN' 'MEDIAN' 'AVG' 'MAX' 'OK' 'IPv4'
    printf '%s\n' '--------------------------------------------------------------------------'
    if [ -s "$RAW" ]; then
        sort -t '|' -k1,1n "$RAW" | awk -F'|' '
        { printf "%-3d %-23.23s %-8s %-8s %-8s %-8s %-8s %s\n", NR, $7, $3, $2, $1, $4, $5, $6 }'
    else
        say 'No successful DoH results.'
    fi
    printf '%s\n' '--------------------------------------------------------------------------'
    say "Domains: $DOMAINS"
    say "Warm-up: $WARMUP_COUNT queries per resolver"
    say "Measured: $TOTAL_SAMPLES queries per resolver"
    say "Failed measured queries are scored as ${TIMEOUT_PENALTY}ms."
    say "Last test: $LAST_TEST"
}

if [ "${1:-}" = '--check' ]; then
    check_dependencies || exit 1
    say 'DoH pre-check: OK'
    say 'kdig +https capability: advertised'
    say "CA bundle: $CA_FILE"
    say 'No DNS queries were performed.'
    exit 0
fi

if [ "${1:-}" = '--help' ]; then
    say 'Usage: dnstest --doh [--check|--help]'
    say 'Runs the DoH benchmark only; the normal UDP/TCP/DoT test is unchanged.'
    exit 0
fi
[ "$#" -eq 0 ] || fail 'Unknown argument. Use --help.'
check_dependencies || exit 1
mkdir "$LOCK" 2>/dev/null || fail 'Another DoH benchmark is running.'
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
mkdir "$TMP" || fail 'Could not create temporary directory.'
: > "$RAW"

say
say 'DNS OVER HTTPS BENCHMARK / FLINT 2'
say "Providers: $(printf '%s\n' "$DOH_SERVERS" | grep -c '|')"
say "Warm-up: $WARMUP_COUNT per provider | Measured: $TOTAL_SAMPLES per provider"
say "Timeout: ${QUERY_TIMEOUT}s | Failure penalty: ${TIMEOUT_PENALTY}ms"
say 'Sequential provider testing; one HTTPS connection is reused within each provider batch.'
say 'Please wait...'
printf '%s\n' "$DOH_SERVERS" > "$TMP.servers"

while IFS='|' read -r NAME IP TLS_HOST DOH_PATH; do
    [ -n "$NAME" ] || continue
    : > "$TMP.values"
    : > "$OUTPUT"

    # One kdig process keeps the HTTPS connection open across warm-up and measurements.
    set -- "@$IP" "+https=$DOH_PATH" "+tls-hostname=$TLS_HOST" "+tls-ca=$CA_FILE" \
        +keepopen +stats "+timeout=$QUERY_TIMEOUT" +retry=0

    ROUND=1
    while [ "$ROUND" -le "$WARMUP_ROUNDS" ]; do
        for DOMAIN in $DOMAINS; do set -- "$@" "$DOMAIN" A; done
        ROUND=$((ROUND + 1))
    done
    ROUND=1
    while [ "$ROUND" -le "$ROUNDS" ]; do
        for DOMAIN in $DOMAINS; do set -- "$@" "$DOMAIN" A; done
        ROUND=$((ROUND + 1))
    done

    say "Testing $NAME ($IP)..."
    timeout "$SERVER_LIMIT" "$KDIG" "$@" > "$OUTPUT" 2>&1
    KDIG_RC=$?

    awk -v warm="$WARMUP_COUNT" -v total="$TOTAL_SAMPLES" -v penalty="$TIMEOUT_PENALTY" '
        /status:/ {
            response++
            ok = ($0 ~ /status: NOERROR/)
        }
        /Query time:/ {
            ms = ""
            for (i = 1; i <= NF; i++) if ($i == "time:") ms = $(i + 1)
            if (response > warm) {
                if (ok && ms ~ /^[0-9]+([.][0-9]+)?$/) print "OK|" ms
                else print "FAIL|" penalty
                measured++
            }
            ok = 0
        }
        END {
            if (measured < total)
                for (i = measured + 1; i <= total; i++) print "FAIL|" penalty
        }
    ' "$OUTPUT" > "$TMP.samples"

    OK=0
    while IFS='|' read -r STATUS MS; do
        [ -n "$MS" ] || continue
        printf '%s\n' "$MS" >> "$TMP.values"
        [ "$STATUS" = OK ] && OK=$((OK + 1))
    done < "$TMP.samples"

    SAMPLE_COUNT="$(wc -l < "$TMP.values" | tr -d ' ')"
    while [ "$SAMPLE_COUNT" -lt "$TOTAL_SAMPLES" ]; do
        echo "$TIMEOUT_PENALTY" >> "$TMP.values"
        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    done

    if [ "$OK" -gt 0 ]; then
        sort -n "$TMP.values" > "$TMP.sorted"
        STATS="$(awk '
            { a[NR]=$1; sum += $1 }
            END {
                n=NR
                if (!n) exit 1
                mid=int((n+1)/2)
                if (n%2) median=a[mid]
                else median=(a[n/2]+a[n/2+1])/2
                printf "%.1f|%.1f|%.1f|%.1f", a[1], median, sum/n, a[n]
            }
        ' "$TMP.sorted")"
        IFS='|' read -r MIN MEDIAN AVG MAX <<EOF2
$STATS
EOF2
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$AVG" "$MEDIAN" "$MIN" "$MAX" \
            "$OK/$TOTAL_SAMPLES" "$IP" "$NAME" >> "$RAW"
    else
        say "  No verified DoH answers from $NAME (kdig exit: $KDIG_RC)"
    fi
done < "$TMP.servers"

[ -s "$RAW" ] || fail 'No DoH provider returned a verified NOERROR answer; previous report preserved.'
LAST_TEST="$(date '+%Y-%m-%d %H:%M:%S')"
print_report > "$TMP.report" || fail 'Could not create DoH report.'
[ -s "$TMP.report" ] || fail 'DoH report is empty.'
mv -f "$TMP.report" "$REPORT" || fail 'Could not replace DoH report; previous report preserved.'
cat "$REPORT"
say
say "Report saved: $REPORT"
exit 0
