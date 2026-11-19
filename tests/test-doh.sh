#!/bin/ash
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/reports"
: > "$TMP/ca.pem"

cat > "$TMP/bin/curl" <<'MOCK'
#!/bin/sh
case "${1:-}" in
    --version)
        echo 'curl 8.10.1 fake Protocols: https Features: HTTP2'
        exit 0
        ;;
    --help)
        echo '--resolve --next --cacert --write-out'
        exit 0
        ;;
esac

POSTS=0
GETS=0
OUTPUTS=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --data-binary)
            POSTS=$((POSTS + 1))
            shift 2
            ;;
        -o)
            out="$2"
            id="${out##*.}"
            hi=$((id / 256))
            lo=$((id % 256))
            if [ "${FAKE_CURL_ALL_FAIL:-0}" = 1 ] || [ "$id" -eq 14 ] || [ "$id" -eq 22 ]; then
                flags2=130
            else
                flags2=128
            fi
            printf "\\$(printf '%03o' "$hi")\\$(printf '%03o' "$lo")\\201\\$(printf '%03o' "$flags2")\\000\\001\\000\\000\\000\\000\\000\\000" > "$out"
            OUTPUTS=$((OUTPUTS + 1))
            printf '0.001000|200\n'
            shift 2
            ;;
        -w)
            shift 2
            ;;
        https://*)
            case "$1" in
                *'?dns='*)
                    GETS=$((GETS + 1))
                    b64="${1##*dns=}"
                    case $(("${#b64}" % 4)) in
                        2) b64="$b64==";;
                        3) b64="$b64=";;
                    esac
                    request="$out.request"
                    printf '%s' "$b64" | tr '_-' '/+' | base64 -d > "$request"
                    ( set -- $(od -An -tu1 -N6 "$request"); \
                      [ "$#" -eq 6 ] && [ "$1" -eq "$hi" ] && [ "$2" -eq "$lo" ] && \
                      [ "$3" -eq 1 ] && [ "$4" -eq 0 ] && [ "$5" -eq 0 ] && [ "$6" -eq 1 ] ) || exit 1
                    size="$(wc -c < "$request" | tr -d ' ')"
                    offset=$((size - 4))
                    ( set -- $(od -An -tu1 -j "$offset" -N4 "$request"); \
                      [ "$#" -eq 4 ] && [ "$1" -eq 0 ] && [ "$2" -eq 1 ] && \
                      [ "$3" -eq 0 ] && [ "$4" -eq 1 ] ) || exit 1
                    ;;
            esac
            shift
            ;;
        *)
            shift
            ;;
    esac
done
[ -z "${FAKE_CURL_LOG:-}" ] || echo "$POSTS $GETS $OUTPUTS" >> "$FAKE_CURL_LOG"
exit 0
MOCK
chmod 755 "$TMP/bin/curl"

export PATH="$TMP/bin:$PATH"
export DNSTEST_DIR="$TMP/reports"
export DNSTEST_CURL="$TMP/bin/curl"
export DNSTEST_CA_FILE="$TMP/ca.pem"
export FAKE_CURL_LOG="$TMP/curl.log"

busybox ash "$ROOT/doh-bench.sh" --check
busybox ash "$ROOT/doh-bench.sh"

REPORT="$TMP/reports/latest-doh.txt"
test -s "$REPORT"
grep -q 'DNS OVER HTTPS BENCHMARK / FLINT 2' "$REPORT"
test "$(grep -c '22/24' "$REPORT")" -eq 26
grep -q '5000.0' "$REPORT"
awk '/^[[:space:]]*[0-9]+[[:space:]]/ { avg=$5+0; if (seen && avg < prev) exit 1; prev=avg; seen=1; count++ } END { if (count != 26) exit 1 }' "$REPORT"
awk '{ p+=$1; g+=$2; o+=$3; n++ } END { if (n != 26 || p != 0 || g != 936 || o != 936) exit 1 }' "$FAKE_CURL_LOG"
cp "$REPORT" "$TMP/previous-report.txt"
: > "$FAKE_CURL_LOG"
export FAKE_CURL_ALL_FAIL=1
if busybox ash "$ROOT/doh-bench.sh"; then
    echo 'Expected all-failed DoH test to return nonzero.' >&2
    exit 1
fi
cmp -s "$REPORT" "$TMP/previous-report.txt"
echo 'DoH mock integration and report-preservation tests: PASS'
