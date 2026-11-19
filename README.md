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

Connect to Flint 2 over SSH and run this command as root:

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/mfranjbar/flint2-dns-benchmark-/main/install.sh && ash /tmp/install.sh
```

The installer automatically installs **nl** (the `coreutils-nl` package) and **kdig** (the `knot-dig` package) if either is missing, then downloads the benchmark and SSH dashboard. It checks shell syntax and server counts, creates and verifies `/root/dnstest`, backs up existing project files, and creates the `dnstest` command.

On OpenWrt 25.12, it uses `apk add coreutils-nl` and `apk add knot-dig` as needed. It does not run `apk update`; if a required package index is unavailable, refresh the package index and rerun the installer.

The installer does **not** start a benchmark or change DNS, firewall, network, or service settings. Installing `knot-dig` may install its required package dependencies.

## Uninstall

To remove only the benchmark script, its command symlink, and the SSH dashboard, run:

```sh
wget -O /tmp/uninstall.sh https://raw.githubusercontent.com/mfranjbar/flint2-dns-benchmark-/main/uninstall.sh && ash /tmp/uninstall.sh
```

The uninstaller requires typing `YES` for confirmation. It preserves `/root/dnstest/`, benchmark reports, `/root/backup/dns/`, and installed packages (including `knot-dig`). It does not change DNS, firewall, network, or service settings.

## Usage

After installation:

```sh
dnstest --check
dnstest --help
dnstest
```

The benchmark also requires `nl`, `timeout`, `awk`, standard BusyBox tools, and a CA certificate bundle at either:

- `/etc/ssl/cert.pem`
- `/etc/ssl/certs/ca-certificates.crt`

## Installed paths

- Benchmark directory: `/root/dnstest/`
- Benchmark: `/root/dnstest/dns-bench.sh`
- Report: `/root/dnstest/latest-top4.txt`
- Command: `/usr/bin/dnstest`
- SSH dashboard: `/etc/profile.d/40-dnstest-dashboard.sh`
- Backups: `/root/backup/dns/`

## Notes

The benchmark is sequential by design. It does not modify the router's DNS configuration. Results depend on current routing, ISP conditions, resolver load, and network latency.
