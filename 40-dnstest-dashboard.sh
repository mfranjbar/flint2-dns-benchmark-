# Flint 2 - DNS benchmark SSH dashboard

REPORT="/root/dnstest/latest-top4.txt"

# Show the dashboard only in an interactive SSH login.
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
[ -n "${SSH_CONNECTION:-}" ] || return 0 2>/dev/null || exit 0

printf '\n'
printf '  ================================================\n'
printf '       DNS BENCHMARK / FLINT 2\n'
printf '       TOP 4 DNS + BEST DoT\n'
printf '  ================================================\n'
printf '\n'

if [ ! -r "$REPORT" ]; then
    printf '  DNS benchmark report not found.\n\n'
    return 0 2>/dev/null || exit 0
fi

awk '
BEGIN {
    printf "  %-1s  %-30s %-8s %-15s %-4s %-5s\\n", \\
           "#", "DNS", "AVG", "IP", "TYPE", "OK"
    printf "  ---------------------------------------------------------------\\n"
}
{
    if ($0 ~ /^[[:space:]]*[1-5][[:space:]]/ && $1 ~ /^[1-5]$/) {
        # Show TOP 4 and the best successful DoT row; hide the failure placeholder.
        if (($1 <= 4 || ($1 == 5 && $2 != "DNS")) && NF >= 6) {
            printf "  %-1s  %-30.30s %-8.8s %-15.15s %-4.4s %-5.5s\\n", \\
                   $1, $2, $6, $3, $4, $5
        }
    }

    if ($0 ~ /^Last test:/) {
        last_test = $0
    }
}
END {
    printf "  ---------------------------------------------------------------\\n"
    if (last_test != "")
        printf "\\n  %s\\n", last_test
    else
        printf "\\n  No test date found.\\n"
}
'' "$REPORT"

printf '\n'
