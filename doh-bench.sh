#!/bin/ash
# FLINT 2 DNS OVER HTTPS BENCHMARK
# Independent native implementation of the warm-up + DoH RTT methodology.
# Uses curl wire-format DoH, connection reuse, TLS verification and DNS response checks.
# No DNS, firewall, network, or service configuration changes.

DIR="${DNSTEST_DIR:-/root/dnstest}"
REPORT="$DIR/latest-doh.txt"
CURL="${DNSTEST_CURL:-curl}"
CA_FILE="${DNSTEST_CA_FILE:-/etc/ssl/cert.pem}"
[ -s "$CA_FILE" ] || CA_FILE='/etc/ssl/certs/ca-certificates.crt'

ROUNDS="${DNSTEST_ROUNDS:-2}"
WARMUP_ROUNDS="${DNSTEST_WARMUP_ROUNDS:-1}"
QUERY_TIMEOUT="${DNSTEST_QUERY_TIMEOUT:-5}"
SERVER_LIMIT="${DNSTEST_SERVER_LIMIT:-25}"
TIMEOUT_PENALTY=5000
VERSION='2.0.0'
DEFAULT_DOMAINS='google.com youtube.com facebook.com instagram.com chatgpt.com x.com whatsapp.com reddit.com wikipedia.org amazon.com tiktok.com pinterest.com'
DOMAINS="${DNSTEST_DOMAINS:-$DEFAULT_DOMAINS}"

# Name|IPv4|TLS hostname|DoH path|HTTP method
# RFC 8484 wire-format DoH over HTTPS GET, matching the reference site's browser fallback.
DEFAULT_DOH_SERVERS='
AdGuard|94.140.14.14|dns.adguard-dns.com|/dns-query|GET
AliDNS|223.5.5.5|dns.alidns.com|/dns-query|GET
OpenDNS|208.67.222.222|doh.opendns.com|/dns-query|GET
CleanBrowsing|185.228.168.9|doh.cleanbrowsing.org|/doh/family-filter/|GET
Cloudflare|1.1.1.1|cloudflare-dns.com|/dns-query|GET
ControlD|76.76.2.0|freedns.controld.com|/p0|GET
DNS.SB|185.222.222.222|doh.dns.sb|/dns-query|GET
DNSPod|119.29.29.29|dns.pub|/dns-query|GET
Google|8.8.8.8|dns.google|/dns-query|GET
NextDNS|45.90.28.0|dns.nextdns.io|/|GET
OpenBLD|146.112.41.2|ada.openbld.net|/dns-query|GET
DNS4EU|86.54.11.100|unfiltered.joindns4.eu|/dns-query|GET
Quad9|9.9.9.9|dns.quad9.net|/dns-query|GET
360|101.226.4.6|doh.360.cn|/dns-query|GET
Canadian Shield|149.112.121.10|private.canadianshield.cira.ca|/dns-query|GET
Digitale-Gesellschaft|185.95.218.42|dns.digitale-gesellschaft.ch|/dns-query|GET
DNS for Family|94.130.180.225|dns-doh.dnsforfamily.com|/dns-query|GET
Restena|158.64.1.29|dnspub.restena.lu|/dns-query|GET
IIJ|203.180.164.45|public.dns.iij.jp|/dns-query|GET
LibreDNS|116.202.176.26|doh.libredns.gr|/dns-query|GET
Switch|130.59.31.248|dns.switch.ch|/dns-query|GET
Foundation for Applied Privacy|146.255.56.98|doh.applied-privacy.net|/query|GET
UncensoredDNS|91.239.100.100|anycast.uncensoreddns.org|/dns-query|GET
RethinkDNS|104.21.83.62|sky.rethinkdns.com|/dns-query|GET
Comcast Xfinity|75.75.75.75|doh.xfinity.com|/dns-query|GET
Mullvad|194.242.2.2|dns.mullvad.net|/dns-query|GET
'
DOH_SERVERS="${DNSTEST_DOH_SERVERS:-$DEFAULT_DOH_SERVERS}"

TMP="/tmp/flint-doh-$$"
RAW="$TMP.raw"
METRICS="$TMP.metrics"
ERRORS="$TMP.errors"
LOCK='/tmp/flint-doh-benchmark.lock'
TOTAL_DOMAINS="$(printf '%s\n' "$DOMAINS" | awk '{print NF}')"
TOTAL_SAMPLES=$((TOTAL_DOMAINS * ROUNDS))
WARMUP_COUNT=$((TOTAL_DOMAINS * WARMUP_ROUNDS))
HTTP2_ENABLED=0

say() { printf '%s\n' "$*"; }
fail() { say "ERROR: $*" >&2; exit 1; }

cleanup() {
    rm -f "$RAW" "$METRICS" "$ERRORS" "$TMP.report" "$TMP.servers" "$TMP.values" "$TMP.sorted" "$TMP"/query.* "$TMP"/response.*
    rmdir "$TMP" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
}

check_dependencies() {
    for cmd in curl base64 od awk sort grep sed head date mkdir rmdir rm mv timeout wc tr; do
        command -v "$cmd" >/dev/null 2>&1 || {
            say "Missing command: $cmd"
            return 1
        }
    done

    command -v "$CURL" >/dev/null 2>&1 || {
        say "curl not found: $CURL"
        return 1
    }

    [ -s "$CA_FILE" ] || {
        say 'CA certificate bundle missing.'
        return 1
    }

    "$CURL" --version 2>&1 | grep -qi 'https' || {
        say 'curl was built without HTTPS/TLS support.'
        return 1
    }

    "$CURL" --help all 2>&1 | grep -q -- '--noproxy' || {
        say 'curl does not support --noproxy; direct endpoint testing cannot be guaranteed.'
        return 1
    }

    "$CURL" --help all 2>&1 | grep -q -- '--resolve' || {
        say 'curl does not support --resolve; direct-IP TLS testing is unavailable.'
        return 1
    }

    "$CURL" --help all 2>&1 | grep -q -- '--next' || {
        say 'curl does not support --next; connection reuse cannot be guaranteed.'
        return 1
    }

    "$CURL" --help all 2>&1 | grep -q -- '--write-out' || {
        say 'curl does not support --write-out timing output.'
        return 1
    }

    "$CURL" --version 2>&1 | grep -q 'HTTP2' && HTTP2_ENABLED=1
    return 0
}

build_dns_query() {
    BQ_FILE="$1"
    BQ_DOMAIN="$2"
    BQ_ID="$3"
    BQ_HI=$((BQ_ID / 256))
    BQ_LO=$((BQ_ID % 256))

    printf "\\$(printf '%03o' "$BQ_HI")\\$(printf '%03o' "$BQ_LO")\\001\\000\\000\\001\\000\\000\\000\\000\\000\\000" > "$BQ_FILE" || return 1

    BQ_OLDIFS="$IFS"
    IFS='.'
    set -- $BQ_DOMAIN
    IFS="$BQ_OLDIFS"

    for BQ_LABEL in "$@"; do
        BQ_LEN=${#BQ_LABEL}
        [ "$BQ_LEN" -gt 0 ] && [ "$BQ_LEN" -le 63 ] || return 1
        printf "\\$(printf '%03o' "$BQ_LEN")" >> "$BQ_FILE" || return 1
        printf '%s' "$BQ_LABEL" >> "$BQ_FILE" || return 1
    done

    printf '\000\000\001\000\001' >> "$BQ_FILE"
}

verify_dns_response() {
    VR_FILE="$1"
    VR_ID="$2"
    [ -s "$VR_FILE" ] || return 1

    set -- $(od -An -tu1 -N4 "$VR_FILE" 2>/dev/null)
    [ "$#" -ge 4 ] || return 1

    VR_HI=$((VR_ID / 256))
    VR_LO=$((VR_ID % 256))
    [ "$1" -eq "$VR_HI" ] && [ "$2" -eq "$VR_LO" ] || return 1
    [ $(( $3 & 128 )) -ne 0 ] || return 1
    VR_RCODE=$(( $4 & 15 ))
    [ "$VR_RCODE" -eq 0 ] || [ "$VR_RCODE" -eq 3 ] || return 1
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
    say "HTTP protocol: $HTTP_PROTOCOL"
    say "Last test: $LAST_TEST"
}

if [ "${1:-}" = '--version' ]; then
    say "Flint 2 DNS Benchmark DoH module v$VERSION"
    exit 0
fi

if [ "${1:-}" = '--check' ]; then
    check_dependencies || exit 1
    say 'DoH pre-check: OK'
    say "curl: $("$CURL" --version | head -n 1)"
    say "HTTP/2 support: $HTTP2_ENABLED"
    say "CA bundle: $CA_FILE"
    say 'No DNS queries were performed.'
    exit 0
fi

if [ "${1:-}" = '--help' ]; then
    say 'Usage: dnstest --doh [--version|--check|--help]'
    say 'Runs the DoH benchmark only; classic UDP/TCP/DoT tests are unchanged.'
    exit 0
fi

[ "$#" -eq 0 ] || fail 'Unknown argument. Use --help.'
check_dependencies || exit 1

for N in "$ROUNDS" "$WARMUP_ROUNDS" "$QUERY_TIMEOUT" "$SERVER_LIMIT"; do
    case "$N" in ''|*[!0-9]*) fail 'Numeric DoH timing settings are invalid.';; esac
done
[ "$ROUNDS" -ge 1 ] || fail 'ROUNDS must be at least 1.'
[ "$WARMUP_ROUNDS" -ge 1 ] || fail 'WARMUP_ROUNDS must be at least 1.'
[ "$QUERY_TIMEOUT" -ge 1 ] || fail 'QUERY_TIMEOUT must be at least 1.'
[ "$SERVER_LIMIT" -ge 1 ] || fail 'SERVER_LIMIT must be at least 1.'
[ "$TOTAL_DOMAINS" -ge 1 ] || fail 'No test domains configured.'
printf '%s\\n' "$DOH_SERVERS" | grep -q '|' || fail 'No DoH servers configured.'

if [ "$HTTP2_ENABLED" -eq 1 ]; then
    HTTP_PROTOCOL='HTTP/2 when negotiated (HTTP/1.1 fallback)'
else
    HTTP_PROTOCOL='HTTP/1.1'
fi

mkdir "$LOCK" 2>/dev/null || fail 'Another DoH benchmark is running.'
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

mkdir "$TMP" || fail 'Could not create temporary directory.'
: > "$RAW"
TOTAL_OK=0

say
say 'DNS OVER HTTPS BENCHMARK / FLINT 2'
say "Providers: $(printf '%s\n' "$DOH_SERVERS" | grep -c '|')"
say "Warm-up: $WARMUP_COUNT per provider | Measured: $TOTAL_SAMPLES per provider"
say "Timeout: ${QUERY_TIMEOUT}s | Failure penalty: ${TIMEOUT_PENALTY}ms"
say 'Sequential provider testing; curl reuses one HTTPS connection per provider.'
say 'Please wait...'

printf '%s\n' "$DOH_SERVERS" > "$TMP.servers"

while IFS='|' read -r NAME IP TLS_HOST DOH_PATH METHOD; do
    [ -n "$NAME" ] || continue

    : > "$TMP.values"
    : > "$METRICS"
    : > "$ERRORS"

    SERVER_URL="https://$TLS_HOST$DOH_PATH"
    set --
    IDX=0

    ROUND=1
    while [ "$ROUND" -le "$WARMUP_ROUNDS" ]; do
        for DOMAIN in $DOMAINS; do
            IDX=$((IDX + 1))
            QUERY_FILE="$TMP/query.$IDX"
            RESPONSE_FILE="$TMP/response.$IDX"
            build_dns_query "$QUERY_FILE" "$DOMAIN" "$IDX" || fail "Could not build DNS query for $DOMAIN"
            DNS_B64="$(base64 < "$QUERY_FILE" | tr -d '\n' | tr '+/' '-_' | tr -d '=')"
            [ "$IDX" -eq 1 ] || set -- "$@" --next
            set -- "$@" --silent --show-error --connect-timeout "$QUERY_TIMEOUT" \
                --max-time "$QUERY_TIMEOUT" --noproxy '*' --resolve "$TLS_HOST:443:$IP" \
                --cacert "$CA_FILE" -H 'accept: application/dns-message' \
                -o "$RESPONSE_FILE" -w '%{time_total}|%{http_code}\n'
            [ "$HTTP2_ENABLED" -eq 0 ] || set -- "$@" --http2
            if [ "$METHOD" = POST ]; then
                set -- "$@" -H 'content-type: application/dns-message' --data-binary "@$QUERY_FILE" "$SERVER_URL"
            else
                set -- "$@" "$SERVER_URL?dns=$DNS_B64"
            fi
        done
        ROUND=$((ROUND + 1))
    done

    ROUND=1
    while [ "$ROUND" -le "$ROUNDS" ]; do
        for DOMAIN in $DOMAINS; do
            IDX=$((IDX + 1))
            QUERY_FILE="$TMP/query.$IDX"
            RESPONSE_FILE="$TMP/response.$IDX"
            build_dns_query "$QUERY_FILE" "$DOMAIN" "$IDX" || fail "Could not build DNS query for $DOMAIN"
            DNS_B64="$(base64 < "$QUERY_FILE" | tr -d '\n' | tr '+/' '-_' | tr -d '=')"
            set -- "$@" --next --silent --show-error --connect-timeout "$QUERY_TIMEOUT" \
                --max-time "$QUERY_TIMEOUT" --noproxy '*' --resolve "$TLS_HOST:443:$IP" \
                --cacert "$CA_FILE" -H 'accept: application/dns-message' \
                -o "$RESPONSE_FILE" -w '%{time_total}|%{http_code}\n'
            [ "$HTTP2_ENABLED" -eq 0 ] || set -- "$@" --http2
            if [ "$METHOD" = POST ]; then
                set -- "$@" -H 'content-type: application/dns-message' --data-binary "@$QUERY_FILE" "$SERVER_URL"
            else
                set -- "$@" "$SERVER_URL?dns=$DNS_B64"
            fi
        done
        ROUND=$((ROUND + 1))
    done

    say "Testing $NAME ($IP)..."
    timeout "$SERVER_LIMIT" "$CURL" "$@" > "$METRICS" 2> "$ERRORS"
    CURL_RC=$?
    if [ "$CURL_RC" -ne 0 ] && [ -s "$ERRORS" ]; then
        say "  curl diagnostic: $(tail -n 8 "$ERRORS" | tr '\\n' ' ')"
    fi

    IDX=0
    OK=0
    while IFS='|' read -r SECONDS HTTP_CODE; do
        [ -n "$SECONDS" ] || continue
        IDX=$((IDX + 1))
        [ "$IDX" -gt "$WARMUP_COUNT" ] || continue

        SAMPLE_ID="$IDX"
        RESPONSE_FILE="$TMP/response.$SAMPLE_ID"
        if [ "$HTTP_CODE" = 200 ] && verify_dns_response "$RESPONSE_FILE" "$SAMPLE_ID"; then
            MS="$(awk -v t="$SECONDS" 'BEGIN { if (t ~ /^[0-9]+([.][0-9]+)?$/) printf "%.3f", t*1000; else print "" }')"
            case "$MS" in
                ''|*[!0-9.]*)
                    echo "$TIMEOUT_PENALTY" >> "$TMP.values"
                    ;;
                *)
                    echo "$MS" >> "$TMP.values"
                    OK=$((OK + 1))
                    ;;
            esac
        else
            echo "$TIMEOUT_PENALTY" >> "$TMP.values"
        fi
    done < "$METRICS"

    SAMPLE_COUNT="$(wc -l < "$TMP.values" | tr -d ' ')"
    while [ "$SAMPLE_COUNT" -lt "$TOTAL_SAMPLES" ]; do
        echo "$TIMEOUT_PENALTY" >> "$TMP.values"
        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    done

    TOTAL_OK=$((TOTAL_OK + OK))
    if [ "$OK" -eq 0 ]; then
        DEBUG_IDX=$((WARMUP_COUNT + 1))
        DEBUG_FILE="$TMP/response.$DEBUG_IDX"
        DEBUG_METRIC="$(sed -n "${DEBUG_IDX}p" "$METRICS")"
        DEBUG_SIZE=0
        DEBUG_HEADER='no response body'
        if [ -s "$DEBUG_FILE" ]; then
            DEBUG_SIZE="$(wc -c < "$DEBUG_FILE" | tr -d ' ')"
            DEBUG_HEADER="$(od -An -tu1 -N12 "$DEBUG_FILE" 2>/dev/null | tr '\\n' ' ')"
        fi
        say "  No verified DoH answers from $NAME (curl exit: $CURL_RC)"
        say "  Debug first scored request: metric=$DEBUG_METRIC bytes=$DEBUG_SIZE DNS-header=$DEBUG_HEADER"
    fi

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
done < "$TMP.servers"

[ "$TOTAL_OK" -gt 0 ] || fail 'No DoH provider returned a valid DNS response; previous report preserved.'
LAST_TEST="$(date '+%Y-%m-%d %H:%M:%S')"
print_report > "$TMP.report" || fail 'Could not create DoH report.'
[ -s "$TMP.report" ] || fail 'DoH report is empty.'
mv -f "$TMP.report" "$REPORT" || fail 'Could not replace DoH report; previous report preserved.'
cat "$REPORT"
say
say "Report saved: $REPORT"
exit 0
