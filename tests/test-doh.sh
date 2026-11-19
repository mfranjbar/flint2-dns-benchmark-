#!/bin/ash
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/reports"
: > "$TMP/ca.pem"
cat > "$TMP/bin/kdig" <<'MOCK'
#!/bin/sh
if [ "${1:-}" = "-h" ]; then
    echo 'kdig test build: +https supported'
    exit 0
fi
i=0
while [ "$i" -lt 36 ]; do
    echo ";; ->>HEADER<<- opcode: QUERY; status: NOERROR; id: $i"
    echo ";; Query time: $((i % 9 + 1)) msec"
    i=$((i + 1))
done
exit 0
MOCK
chmod 755 "$TMP/bin/kdig"
export PATH="$TMP/bin:$PATH"
export DNSTEST_DIR="$TMP/reports"
export DNSTEST_KDIG="$TMP/bin/kdig"
export DNSTEST_CA_FILE="$TMP/ca.pem"

busybox ash "$ROOT/doh-bench.sh" --check
busybox ash "$ROOT/doh-bench.sh"
REPORT="$TMP/reports/latest-doh.txt"
test -s "$REPORT"
grep -q 'DNS OVER HTTPS BENCHMARK / FLINT 2' "$REPORT"
test "$(grep -c '24/24' "$REPORT")" -eq 16
# Verify average ordering is ascending.
awk '/^[[:space:]]*[0-9]+[[:space:]]/ { avg=$5+0; if (seen && avg < prev) exit 1; prev=avg; seen=1; count++ } END { if (count != 16) exit 1 }' "$REPORT"
echo 'DoH mock integration test: PASS'
