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

while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            out="$2"
            id="${out##*.}"
            hi=$((id / 256))
            lo=$((id % 256))
            if [ "$id" -eq 14 ] || [ "$id" -eq 22 ]; then
                flags2=130
            else
                flags2=128
            fi
            printf "\\$(printf '%03o' "$hi")\\$(printf '%03o' "$lo")\\201\\$(printf '%03o' "$flags2")\\000\\001\\000\\000\\000\\000\\000\\000" > "$out"
            printf '0.001000|200\n'
            shift 2
            ;;
        -w)
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
exit 0
MOCK
chmod 755 "$TMP/bin/curl"

export PATH="$TMP/bin:$PATH"
export DNSTEST_DIR="$TMP/reports"
export DNSTEST_CURL="$TMP/bin/curl"
export DNSTEST_CA_FILE="$TMP/ca.pem"

busybox ash "$ROOT/doh-bench.sh" --check
busybox ash "$ROOT/doh-bench.sh"

REPORT="$TMP/reports/latest-doh.txt"
test -s "$REPORT"
grep -q 'DNS OVER HTTPS BENCHMARK / FLINT 2' "$REPORT"
test "$(grep -c '22/24' "$REPORT")" -eq 16
grep -q '5000.0' "$REPORT"
awk '/^[[:space:]]*[0-9]+[[:space:]]/ { avg=$5+0; if (seen && avg < prev) exit 1; prev=avg; seen=1; count++ } END { if (count != 16) exit 1 }' "$REPORT"
echo 'DoH mock integration test: PASS'
