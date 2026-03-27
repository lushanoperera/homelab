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
