---
paths:
  - "dns/**"
  - "**/dns-compose*"
  - "**/resolv.conf"
recall:
  - technitium
  - dns
  - cluster
  - resolv.conf
---

# Technitium DNS Lessons

| Issue                                            | Solution                                                              |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| Docker image has no wget/curl                    | Use `bash -c '</dev/tcp/localhost/5380'` for healthcheck              |
| Cluster join needs domain URL, not IP            | `primaryNodeUrl` must use domain; pass IP via `primaryNodeIpAddress`  |
| Secondary nodes don't see each other             | Normal until primary syncs config to all nodes                        |
| `DNS_SERVER_DOMAIN` becomes node FQDN            | Set to short name (e.g. `flatcar`), cluster appends domain            |
| Reginald service name is `dns` not `technitium`  | Technitium installer creates `dns.service`                            |
| QNAP port 53 conflict with dnsmasq              | Bind to management IP: `192.168.100.254:53:53` instead of `0.0.0.0`  |
| Compose healthcheck only proves UI up           | Probe `</dev/tcp/localhost/53 && </dev/tcp/localhost/5380` — UI can be up while port 53 binding failed (Technitium silently fails-soft) |
| Stats API duplicate metric names                | Technitium `stats.get` keys overlap window labels — Prometheus exporter must emit one `# HELP/# TYPE` per metric and use `window="1h"\|"1d"` labels (duplicate HELP lines = scrape rejected) |
| API login `pass` is Python kw                   | `urllib.parse.urlencode({'pass': ...})` works; `pass_=...` does not — Technitium expects the literal key `pass`                              |
| Reverse zone needs explicit creation            | `100.168.192.in-addr.arpa` does not auto-spawn — create as Primary first; the "auto-create PTR" toggle only writes into an existing reverse zone |
| DoH backend cert                                | Technitium 53443 serves self-signed cert; Caddy must use `transport http { tls tls_insecure_skip_verify }` (LAN hop only)               |
| `DNS_SERVER_DOMAIN` UI verification             | Open cluster page in UI — if names show as `dns.disconnesso.home.arpa.dns.disconnesso.home.arpa` it's a known double-suffix bug. With current short-suffix config, expect 3 distinct nodes — verify before treating naming-drift as live. |
| Homepage customapi needs file-served JSON       | Homepage container doesn't serve arbitrary host files. Mount `/srv/docker/homepage/data:/app/public/data:ro` in homepage compose so the drift cron's JSON is reachable at `http://localhost:3000/data/dns-cluster.json` |
