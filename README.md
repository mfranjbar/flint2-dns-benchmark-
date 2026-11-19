# Flint 2 DNS Benchmark v2.0.0

A sequential DNS benchmark for GL.iNet Flint 2 / OpenWrt.

## Features

- Tests 25 DNS resolvers over UDP and TCP, sequentially.
- Tests 13 DNS-over-TLS (DoT) endpoints separately.
- Adds a DoH benchmark inspired by [dnsspeedtest.online](https://dnsspeedtest.online/).
- Tests 26 public DoH endpoints using RFC 8484 wire-format DNS over HTTPS.
- Uses the same 12 default test hostnames as the reference site, with one warm-up round and two measured rounds.
- Reuses an HTTPS connection per resolver, pins each endpoint to its IPv4 address, and validates TLS certificates and DNS responses.
- Reports DoH Min, Median, Average, Max and successful sample count; failed samples receive a 5000 ms penalty.
- Displays the four fastest classic DNS results, best DoT result, and DoH results on SSH login.
- Provides no-network pre-checks for both classic DNS and DoH.

## Install on Flint 2

Connect to Flint 2 over SSH and run as root:

```sh
wget -O /tmp/dnstest-install.sh https://raw.githubusercontent.com/mfranjbar/flint2-dns-benchmark-/main/install.sh &&
ash /tmp/dnstest-install.sh
```

The installer installs missing dependencies only: `coreutils-nl`, `coreutils-timeout`, `knot-dig`, and `curl`. It does not run `apk update`. It checks shell syntax, server counts, backs up existing project files, installs the benchmark and SSH dashboard, and runs local pre-checks. It does not run a benchmark or change DNS, firewall, routes, network, or DNS services.

DoH requires curl with HTTPS/TLS, `--resolve`, `--next`, and `--write-out` support, plus a CA bundle. HTTP/2 is used when the installed curl supports it; otherwise HTTP/1.1 is used. The DoH module does not depend on DoH support in `kdig`.

## Usage

```sh
dnstest --version
dnstest --check
dnstest
dnstest --doh --check
dnstest --doh
dnstest --all
```

- `dnstest`: existing UDP/TCP/DoT benchmark; unchanged default behavior.
- `dnstest --doh`: DoH benchmark only.
- `dnstest --all`: classic benchmark followed by DoH.
- `--check`: local prerequisite checks only; no DNS queries.

## DoH methodology

See [DOH.md](DOH.md) for the provider list, warm-up and measurement details, validation rules, timing interpretation, and report format.

## Installed paths

- Benchmark directory: `/root/dnstest/`
- Classic benchmark: `/root/dnstest/dns-bench.sh`
- DoH module: `/root/dnstest/doh-bench.sh`
- Classic report: `/root/dnstest/latest-top4.txt`
- DoH report: `/root/dnstest/latest-doh.txt`
- Command: `/usr/bin/dnstest`
- SSH dashboard: `/etc/profile.d/40-dnstest-dashboard.sh`
- Backups: `/root/backup/dns/`

## Uninstall

```sh
wget -O /tmp/dnstest-uninstall.sh https://raw.githubusercontent.com/mfranjbar/flint2-dns-benchmark-/main/uninstall.sh &&
ash /tmp/dnstest-uninstall.sh
```

The uninstaller requires typing `YES`. It preserves reports, backup files, and installed dependencies (including curl).

## Notes

Classic and DoH tests are sequential to avoid artificial contention on the router. DoH provider availability and latency vary by ISP, route, filtering policy, and server. The GitHub Actions live smoke test checks a small public DoH subset from the CI runner; it does not replace a real benchmark from the Flint 2 network.
