# Flint 2 DNS Benchmark

A sequential DNS benchmark for GL.iNet Flint 2 / OpenWrt.

## Features

- Tests 25 DNS resolvers over UDP and TCP, sequentially.
- Tests 13 DNS-over-TLS (DoT) endpoints separately.
- Uses two rounds and three query domains: `github.com`, `nasa.gov`, and `openwrt.org`.
- Displays the four fastest successful DNS results and the best DoT result.
- Saves the report to `/root/dnstest/latest-top4.txt`.
- Shows the latest report on SSH login through an `/etc/profile.d` dashboard.
- Includes a dependency pre-check that sends no DNS queries.

## Install on Flint 2

Run as root:

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/mfranjbar/flint2-dns-benchmark-/main/install.sh && ash /tmp/install.sh
```

The installer downloads the benchmark and dashboard, checks shell syntax and server counts, backs up existing files, and creates the `dnstest` command.

It does **not** install packages, start a benchmark, or change DNS, firewall, network, or service settings.

## Usage

```sh
dnstest --check
dnstest --help
dnstest
```

The benchmark requires `kdig`, `timeout`, `nl`, standard BusyBox tools, and a CA certificate bundle at either:

- `/etc/ssl/cert.pem`
- `/etc/ssl/certs/ca-certificates.crt`

## Installed paths

- Benchmark: `/root/dnstest/dns-bench.sh`
- Report: `/root/dnstest/latest-top4.txt`
- Command: `/usr/bin/dnstest`
- SSH dashboard: `/etc/profile.d/40-dnstest-dashboard.sh`
- Backups: `/root/backup/dns/`

## Notes

The benchmark is sequential by design. It does not modify the router's DNS configuration. Results depend on current routing, ISP conditions, resolver load, and network latency.
