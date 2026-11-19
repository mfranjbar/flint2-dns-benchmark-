# DoH benchmark module

The optional DoH benchmark is an independent native OpenWrt implementation inspired by the warm-up and latency-statistics methodology of [dnsspeedtest.online](https://dnsspeedtest.online/) and its public [BrainicHQ/DoHSpeedTest](https://github.com/BrainicHQ/DoHSpeedTest) project (GPL-3.0). No upstream JavaScript is bundled.

## Commands

- `dnstest --doh` — run DoH only.
- `dnstest --doh --check` — check local prerequisites; sends no DNS queries.
- `dnstest --all` — run the existing UDP/TCP/DoT benchmark, then DoH.

The classic benchmark remains the default and is not replaced.

## Method

- 16 public DoH endpoints, addressed by IPv4 with the TLS hostname pinned through curl's `--resolve`; this avoids using the router's current DNS to bootstrap the resolver hostname.
- 12 test hostnames: google.com, youtube.com, facebook.com, instagram.com, chatgpt.com, x.com, whatsapp.com, reddit.com, wikipedia.org, amazon.com, tiktok.com, pinterest.com.
- One warm-up query per hostname, followed by two measured rounds (24 measured samples).
- All transfers for one resolver run inside a single curl process. curl's connection cache can therefore reuse the HTTPS connection between warm-up and measured requests.
- HTTP 200 plus DNS transaction-ID, response-bit and NOERROR checks are required for a successful sample.
- Failed measured requests receive the same 5000 ms penalty used by the reference site's methodology.
- The report includes Min, Median, Average, Max and success count, ranked by Average.

DoH timing includes the HTTPS request/response path and HTTP/TLS overhead. The first connection is warmed before scored samples; HTTP/2 is used when curl supports it and the server negotiates it, otherwise HTTP/1.1 is used. Providers are tested sequentially to avoid creating artificial contention on the router.

## Requirements

- curl with HTTPS/TLS, `--resolve`, `--next` and `--write-out` support.
- CA bundle at `/etc/ssl/cert.pem` or `/etc/ssl/certs/ca-certificates.crt`.
- BusyBox/core utilities `base64`, `od`, `awk`, `sort`, `tr`, `wc`, and `timeout`.

The standard OpenWrt `knot-dig` package is not used for DoH because the OpenWrt package recipe disables libnghttp2 in its build configuration.

## Report

`/root/dnstest/latest-doh.txt`

The module does not change DNS settings, dnsmasq, DNSCrypt, firewall, routes, or network services.
