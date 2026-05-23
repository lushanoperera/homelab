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
| Cluster dashboard "Parameter 'token' missing"   | UI dropdown to switch dashboard view to a secondary cluster node fires a browser-side fetch at `https://<node>.dns.disconnesso.home.arpa:53443/`. The cluster.config bakes these URLs in. Client must resolve those FQDNs **and** have a valid session for that node. Fastest fix: `/etc/hosts` on the client with `<node>.dns.disconnesso.home.arpa` → node IP. Cluster DNS replication, blocklists, and normal queries are unaffected — only this cross-node UI navigation breaks |
| Catalog member zones invisible externally       | Adding A records to a `catalog:` member zone (like `dns.disconnesso.home.arpa` under `cluster-catalog.dns.disconnesso.home.arpa`) only answers queries from the cluster subnet (192.168.100.0/24), not from other VLANs. Setting `overrideCatalogQueryAccess=true` + `queryAccess=Allow` + empty ACL on both the member zone and the catalog zone does not unlock external clients (observed 2026-05-23). Source-IP gating is enforced somewhere internal to the catalog model. Use a non-catalog zone for client-visible records |
