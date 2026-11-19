#!/bin/ash
# FLINT 2 DNS BENCHMARK
# Sequential UDP + TCP + separate DoT
# No DNS/service/firewall configuration changes

DIR='/root/dnstest'
REPORT="$DIR/latest-top4.txt"
LOCK='/tmp/flint-dnstest.lock'
KDIG='/usr/bin/kdig'

ROUNDS=2
QUERY_TIMEOUT=3
DOT_TIMEOUT=4
HARD_LIMIT=8

DOMAINS='github.com nasa.gov openwrt.org'
DOT_DOMAIN='example.com'

CA_FILE='/etc/ssl/cert.pem'
[ -s "$CA_FILE" ] || CA_FILE='/etc/ssl/certs/ca-certificates.crt'

DNS_SERVERS='
Cloudflare|1.1.1.1
Cloudflare-Security|1.1.1.2
Google|8.8.8.8
Google-Secondary|8.8.4.4
Quad9|9.9.9.9
Quad9-Secondary|149.112.112.112
OpenDNS|208.67.222.222
OpenDNS-Secondary|208.67.220.220
AdGuard|94.140.14.14
Cloudflare-Secondary|1.0.0.1
AdGuard-Secondary|94.140.15.15
Quad9-Unfiltered|9.9.9.10
Quad9-Unfiltered-Secondary|149.112.112.10
Quad9-ECS-Secure|9.9.9.11
Quad9-ECS-Secure-Secondary|149.112.112.11
Quad9-ECS-Unfiltered|9.9.9.12
Quad9-ECS-Unfiltered-Secondary|149.112.112.12
ControlD-Unfiltered|76.76.2.0
ControlD-Unfiltered-Secondary|76.76.10.0
DNS-WATCH|84.200.69.80
DNS-WATCH-Secondary|84.200.70.40
Verisign|64.6.64.6
Verisign-Secondary|64.6.65.6
DNS-SB|185.222.222.222
DNS-SB-Secondary|45.11.45.11
'

DOT_SERVERS='
Cloudflare-DoT|1.1.1.1|cloudflare-dns.com
Cloudflare-Security-DoT|1.1.1.2|security.cloudflare-dns.com
Google-DoT|8.8.8.8|dns.google
Google-Secondary-DoT|8.8.4.4|dns.google
Quad9-DoT|9.9.9.9|dns.quad9.net
Quad9-Secondary-DoT|149.112.112.112|dns.quad9.net
AdGuard-DoT|94.140.14.14|dns.adguard-dns.com
AdGuard-Secondary-DoT|94.140.15.15|dns.adguard-dns.com
LibreDNS-DoT|116.202.176.26|dot.libredns.gr
Mullvad-DoT|194.242.2.2|dns.mullvad.net
DNS-SB-DoT|185.222.222.222|dot.sb
DNS-SB-Secondary-DoT|45.11.45.11|dot.sb
ControlD-Unfiltered-DoT|76.76.2.0|p0.freedns.controld.com
'

TMP="/tmp/flint-dns-$$"
RAW="$TMP.raw"
DOT_RAW="$TMP.dot"
TOP="$TMP.top"
REPORT_TMP="$TMP.report"

cleanup() {
    rm -f "$RAW" "$DOT_RAW" "$TOP" "$REPORT_TMP" \
        "$TMP.servers" "$TMP.dotservers"
    rmdir "$LOCK" 2>/dev/null
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

check_dependencies() {
    for cmd in kdig nl timeout awk grep sort head sed date mkdir rmdir rm mv cat; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "Missing command: $cmd"
            return 1
        }
    done

    [ -x "$KDIG" ] || {
        echo "kdig not executable at $KDIG"
        return 1
    }

    [ -s "$CA_FILE" ] || {
        echo 'CA certificate bundle missing.'
        return 1
    }

    [ -d "$DIR" ] && [ -w "$DIR" ] || {
        echo "Directory not writable: $DIR"
        return 1
    }

    NL_TEST="$(printf 'test\n' | nl -w2 -s'|' 2>/dev/null)"
    [ "$NL_TEST" = ' 1|test' ] || {
        echo 'nl format check failed.'
        return 1
    }

    timeout 1 sh -c 'exit 0' >/dev/null 2>&1
    [ "$?" -eq 0 ] || {
        echo 'timeout invocation check failed.'
        return 1
    }

    return 0
}

get_ms() {
    printf '%s\n' "$1" | sed -n \
        -e 's/.* in \([0-9][0-9.]*\) ms.*/\1/p' \
        -e 's/.*Query time: \([0-9][0-9.]*\) msec.*/\1/p' |
        head -n 1
}

run_query() {
    IP="$1"
    DOMAIN="$2"
    TYPE="$3"

    if [ "$TYPE" = UDP ]; then
        MODE='+notcp'
    else
        MODE='+tcp'
    fi

    QUERY_OUTPUT="$(timeout "$HARD_LIMIT" "$KDIG" \
        "@$IP" "$DOMAIN" A "$MODE" \
        "+timeout=$QUERY_TIMEOUT" +retry=0 +stats 2>&1)"
    QUERY_RC=$?

    QUERY_OK=0
    QUERY_MS=''

    if [ "$QUERY_RC" -eq 0 ] &&
       printf '%s\n' "$QUERY_OUTPUT" | grep -q 'status: NOERROR'; then

        QUERY_MS="$(get_ms "$QUERY_OUTPUT")"

        case "$QUERY_MS" in
            ''|*[!0-9.]*)
                QUERY_MS=''
                ;;
            *)
                QUERY_OK=1
                ;;
        esac
    fi
}

run_dot_query() {
    IP="$1"
    HOST="$2"

    QUERY_OUTPUT="$(timeout "$HARD_LIMIT" "$KDIG" \
        "@$IP" "$DOT_DOMAIN" A \
        +tls "+tls-ca=$CA_FILE" "+tls-hostname=$HOST" \
        "+timeout=$DOT_TIMEOUT" +retry=0 +stats 2>&1)"
    QUERY_RC=$?

    QUERY_OK=0
    QUERY_MS=''

    if [ "$QUERY_RC" -eq 0 ] &&
       printf '%s\n' "$QUERY_OUTPUT" | grep -q 'status: NOERROR'; then

        QUERY_MS="$(get_ms "$QUERY_OUTPUT")"

        case "$QUERY_MS" in
            ''|*[!0-9.]*)
                QUERY_MS=''
                ;;
            *)
                QUERY_OK=1
                ;;
        esac
    fi
}

print_top() {
    COLOR="$1"

    if [ "$COLOR" = yes ] && [ -t 1 ]; then
        CYAN="$(printf '\033[1;36m')"
        GREEN="$(printf '\033[1;32m')"
        YELLOW="$(printf '\033[1;33m')"
        PURPLE="$(printf '\033[1;35m')"
        BLUE="$(printf '\033[1;34m')"
        WHITE="$(printf '\033[1;97m')"
        DIM="$(printf '\033[0;90m')"
        BOLD="$(printf '\033[1m')"
        RESET="$(printf '\033[0m')"
    else
        CYAN=''
        GREEN=''
        YELLOW=''
        PURPLE=''
        BLUE=''
        WHITE=''
        DIM=''
        BOLD=''
        RESET=''
    fi

    echo
    printf '%s%s%s\n' "$CYAN" \
    '============================================================================' "$RESET"

    printf '%s%s  DNS BENCHMARK  /  TOP 4 DNS + BEST DoT  %s\n' \
        "$BOLD" "$WHITE" "$RESET"

    printf '%s%s%s\n' "$PURPLE" \
    '============================================================================' "$RESET"

    printf '%s%-2s  %-32s  %-15s  %-4s  %-5s  %8s%s\n' \
        "$CYAN" '#' DNS IP TYPE OK AVG "$RESET"

    printf '%s%s%s\n' "$BLUE" \
    '----------------------------------------------------------------------------' "$RESET"

    if [ -s "$TOP" ]; then
        nl -w2 -s'|' "$TOP" |
        while IFS='|' read -r RANK AVG NAME IP TYPE OK; do
            [ -n "$RANK" ] || continue

            RANK="$(printf '%s' "$RANK" | sed 's/ //g')"

            printf '%s%-2s%s  %-32.32s  %s%-15s%s  %s%-4s%s  %s%-5s%s  %s%6sms%s\n' \
                "$CYAN" "$RANK" "$RESET" \
                "$NAME" \
                "$PURPLE" "$IP" "$RESET" \
                "$CYAN" "$TYPE" "$RESET" \
                "$GREEN" "$OK" "$RESET" \
                "$YELLOW" "$AVG" "$RESET"
        done
    else
        printf '%sNo successful DNS results.%s\n' "$YELLOW" "$RESET"
    fi

    BEST_DOT="$(awk -F'|' '
        $6 == "OK" && $5 ~ /^[0-9]+([.][0-9]+)?$/ {
            if (!found || ($5 + 0) < (best + 0)) {
                best = $5
                line = $0
                found = 1
            }
        }
        END {
            if (found) print line
        }
    ' "$DOT_RAW")"

    if [ -n "$BEST_DOT" ]; then
        IFS='|' read -r DNAME DIP DHOST DOK DAVG DSTATUS <<EOF2
$BEST_DOT
EOF2

        printf '%s%-2s%s  %-32.32s  %s%-15s%s  %s%-4s%s  %s%-5s%s  %s%6sms%s\n' \
            "$CYAN" "5" "$RESET" \
            "$DNAME" \
            "$PURPLE" "$DIP" "$RESET" \
            "$CYAN" "DoT" "$RESET" \
            "$GREEN" "$DOK" "$RESET" \
            "$YELLOW" "$DAVG" "$RESET"
    else
        printf '%s%-2s%s  %-32s  %-15s  %-4s  %-5s  %8s%s\n' \
            "$YELLOW" "5" "$RESET" \
            "DNS OVER TLS DOWN" "-" "DoT" "0/26" "-" "$RESET"
    fi

    printf '%s%s%s\n' "$BLUE" \
    '----------------------------------------------------------------------------' "$RESET"

    printf '%sLast test: %s%s\n' "$DIM" "$LAST_TEST" "$RESET"

    printf '%s%s%s\n' "$CYAN" \
    '============================================================================' "$RESET"
}
print_dot() {
    COLOR="$1"

    BEST_DOT="$(awk -F'|' '
        $7 == "OK" && $6 ~ /^[0-9]+([.][0-9]+)?$/ {
            if (!found || ($6 + 0) < (best + 0)) {
                best = $6
                line = $0
                found = 1
            }
        }
        END {
            if (found) print line
        }
    ' "$DOT_RAW")"

    [ -n "$BEST_DOT" ] || return 0

    if [ "$COLOR" = yes ] && [ -t 1 ]; then
        GREEN="$(printf '\033[1;32m')"
        CYAN="$(printf '\033[1;36m')"
        RESET="$(printf '\033[0m')"
    else
        GREEN=''
        CYAN=''
        RESET=''
    fi

    echo
    printf '%s✦ BEST DNS OVER TLS%s\n' "$CYAN" "$RESET"

    while IFS='|' read -r NAME IP HOST OK AVG STATUS; do
        [ -n "$NAME" ] || continue

        printf '%s%-23s%s │ %-15s │ %-5s │ %s%sms%s\n' \
            "$GREEN" "$NAME" "$RESET" "$IP" "$OK" \
            "$GREEN" "$AVG" "$RESET"
    done <<EOF2
$BEST_DOT
EOF2
}
# CHECK MODE: no DNS requests
if [ "$1" = --check ]; then
    check_dependencies || exit 1

    echo 'Pre-check: OK'
    echo 'kdig: OK'
    echo 'nl numbering: OK'
    echo 'timeout invocation: OK'
    echo "CA bundle: $CA_FILE"
    echo "Report directory: $DIR"
    echo 'No DNS tests were performed.'
    exit 0
fi

if [ "$1" = --help ]; then
    echo 'Usage: dnstest [--check|--help]'
    exit 0
fi

[ "$#" -eq 0 ] || fail 'Unknown argument. Use --help.'

check_dependencies || exit 1

mkdir "$LOCK" 2>/dev/null || fail \
    'A benchmark lock exists. Check /tmp/flint-dnstest.lock before removing it.'

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

: > "$RAW"
: > "$DOT_RAW"

echo
echo "========================================"
echo "       DNS BENCHMARK / FLINT 2
       TOP 4 DNS + BEST DoT"
echo "========================================"
echo "Rounds: $ROUNDS | Timeout: ${QUERY_TIMEOUT}s"
echo "Domains: $DOMAINS"
echo "Testing 25 DNS servers - UDP and TCP"
echo "Please wait..."
echo "========================================"
echo

printf '%s\n' "$DNS_SERVERS" > "$TMP.servers"

while IFS='|' read -r NAME IP; do
    [ -n "$NAME" ] || continue

    for TYPE in UDP TCP; do
        OK=0
        TOTAL=0
        SUM='0'

        ROUND=1
        while [ "$ROUND" -le "$ROUNDS" ]; do
            for DOMAIN in $DOMAINS; do
                TOTAL=$((TOTAL + 1))

                run_query "$IP" "$DOMAIN" "$TYPE"

                if [ "$QUERY_OK" -eq 1 ]; then
                    OK=$((OK + 1))
                    SUM="$(awk -v a="$SUM" -v b="$QUERY_MS" \
                        'BEGIN { printf "%.4f", a+b }')"
                fi
            done

            ROUND=$((ROUND + 1))
        done

        if [ "$OK" -gt 0 ]; then
            AVG="$(awk -v s="$SUM" -v n="$OK" \
                'BEGIN { printf "%.1f", s/n }')"

            printf '%s|%s|%s|%s|%s/%s\n' \
                "$AVG" "$NAME" "$IP" "$TYPE" "$OK" "$TOTAL" >> "$RAW"
        fi
    done
done < "$TMP.servers"

[ -s "$RAW" ] || fail \
    'No successful UDP/TCP results; previous report preserved.'

sort -t '|' -k1,1n "$RAW" | head -n 4 > "$TOP"

awk -F'|' '
    NF != 5 { exit 1 }
    $1 !~ /^[0-9]+([.][0-9]+)?$/ { exit 1 }
    END { if (NR < 1 || NR > 4) exit 1 }
' "$TOP" || fail 'TOP 4 validation failed; previous report preserved.'

LAST_TEST="$(date '+%Y-%m-%d %H:%M:%S')"

printf '%s\n' "$DOT_SERVERS" > "$TMP.dotservers"

while IFS='|' read -r NAME IP HOST; do
    [ -n "$NAME" ] || continue

    OK=0
    TOTAL=0
    SUM='0'
    ROUND=1

    while [ "$ROUND" -le 2 ]; do
        TOTAL=$((TOTAL + 1))

        run_dot_query "$IP" "$HOST"

        if [ "$QUERY_OK" -eq 1 ]; then
            OK=$((OK + 1))
            SUM="$(awk -v a="$SUM" -v b="$QUERY_MS" \
                'BEGIN { printf "%.4f", a+b }')"
        fi

        ROUND=$((ROUND + 1))
    done

    if [ "$OK" -gt 0 ]; then
        AVG="$(awk -v s="$SUM" -v n="$OK" \
            'BEGIN { printf "%.1f", s/n }')"
        STATUS=OK
    else
        AVG='-'
        STATUS=FAILED
    fi

    printf '%s|%s|%s|%s/%s|%s|%s\n' \
        "$NAME" "$IP" "$HOST" "$OK" "$TOTAL" "$AVG" "$STATUS" >> "$DOT_RAW"

done < "$TMP.dotservers"

{
    print_top no
    echo
    echo 'Report saved:'
    echo " $REPORT"
} > "$REPORT_TMP" || fail 'Could not create report temporary file.'

[ -s "$REPORT_TMP" ] || fail 'Temporary report is empty.'

mv -f "$REPORT_TMP" "$REPORT" || fail \
    'Could not replace report; previous report preserved.'

print_top yes

echo
echo 'Report saved:'
echo " $REPORT"
echo

exit 0
