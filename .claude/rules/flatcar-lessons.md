---
paths:
  - "vms/flatcar-media/**"
  - "**/butane/**"
  - "**/ignition/**"
  - "**/docker-compose*"
  - "systemd/**"
recall:
  - flatcar
  - butane
  - ignition
  - systemd-sysext
---

# Flatcar Lessons

| Issue                         | Solution                                                                                                                                                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Network interface naming      | Always use `eth0` (not `ens18`) in Butane configs                                                                                                                                                                                                                         |
| Ignition only applies once    | Manual fixes needed for post-boot changes                                                                                                                                                                                                                                 |
| Docker Compose location       | `/opt/bin/docker-compose` (standalone binary)                                                                                                                                                                                                                             |
| Watchtower image              | `nickfedor/watchtower` (containrrr discontinued)                                                                                                                                                                                                                          |
| VPN secrets                   | Docker secrets in `./secrets/`, not env vars                                                                                                                                                                                                                              |
| Compose .env missing vars     | All vars must be in `.env`; see `.env.example`                                                                                                                                                                                                                            |
| Compose plugin not installed  | Flatcar `/usr/lib` is read-only; Butane download fails silently                                                                                                                                                                                                           |
| Systemd `\|\| true` syntax    | Use `-` prefix: `ExecStartPre=-/usr/bin/docker ...`                                                                                                                                                                                                                       |
| SSH heredoc corrupts shebang  | Pipe from local heredoc instead of remote heredoc                                                                                                                                                                                                                         |
| Butane → Ignition recompile   | Requires Docker: `docker run --rm -i quay.io/coreos/butane:latest --strict`                                                                                                                                                                                               |
| Redis maxmemory > mem_limit   | Redis `--maxmemory` must be **less than** container `mem_limit` — otherwise OOM-killed before eviction triggers                                                                                                                                                           |
| Tunnel tokens in compose      | Never hardcode secrets in compose files — use `${VAR}` referencing `.env`; token was exposed in git history                                                                                                                                                               |
| All containers need mem_limit | Unbounded containers can OOM the VM — always set `mem_limit` based on measured usage + headroom                                                                                                                                                                           |
| Gluetun recreate orphans deps | `up -d gluetun` assigns new container ID; dependents using `network_mode: service:gluetun` still reference old ID. `restart` fails ("No such container"). **Always `up -d` the whole stack** (or at minimum all dependents) after recreating a network-provider container |
| `restart` vs `up -d`          | `restart` reuses the same container (preserves ID). `up -d` recreates if config changed (new ID). Containers sharing network namespace MUST be recreated together — never restart dependents after recreating their network provider                                      |
| PUBLICIP_PERIOD for gluetun   | Without `PUBLICIP_PERIOD`, gluetun fetches public IP once at startup — if DNS (DoT → Cloudflare) isn't ready, empty IP cached permanently. Set `PUBLICIP_PERIOD=12h` for self-healing                                                                                     |
| Gluetun `restart` stuns deps  | Even simple `docker-compose restart gluetun` (container ID preserved) leaves dependents with dead HTTP listeners — namespace survives but routes/interfaces are torn down and re-added, and apps like qBittorrent don't recover. **Always restart dependents after any gluetun restart**: `docker-compose restart gluetun qbittorrent prowlarr sabnzbd`. Observed 2026-05-20: gluetun restarted, qBit `/api/v2` returned empty for 60s+ until explicit dep restart |
| Gluetun NAT-PMP can die silent | ProtonVPN port-forward can fail with `recvfrom: connection refused` on UDP 5351 and gluetun loops without re-acquiring. Forwarded-port file goes empty, `/v1/portforward` returns `{"port":0}`, qBit keeps stale port indefinitely. No healthcheck signal. **Detect via** `/v1/portforward` cron alert or homepage widget; **fix via** gluetun + deps restart. Observed 2026-05-19 → 41h dead before noticed                                                       |
