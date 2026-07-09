---
paths:
  - "vms/flatcar-media/**"
  - "networking/**"
  - "apps/**"
  - "homepage/**"
recall:
  - deploy
  - scp
  - rsync
  - compose deploy
---

# Deployment Lessons

## Compose Deployment to Flatcar

| Issue                                 | Solution                                                                                                                                                                                             |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Network namespace orphaning           | When `up -d` recreates a network-provider container (gluetun), dependents using `network_mode: service:X` get stale container IDs. Always `up -d` the **entire stack**, not just the changed service |
| `restart` vs `up -d` confusion        | `restart` = same container, same ID. `up -d` = recreate if config changed (new ID). After recreating network providers, dependents need `up -d` too, not `restart`                                   |
| Deploying invalid YAML                | Always validate locally first: `docker compose -f <file> config --quiet` before SCP                                                                                                                  |
| SCP to wrong path                     | Consult repo→remote path mapping in CLAUDE.md before deploying. Media stack = `/srv/docker/media-stack/`, NOT `/srv/docker/`                                                                         |
| Forgetting post-deploy verification   | Always verify: container health, VPN IP, port forwarding, web UI responses. Use `/media-health` or `/vpn-status` skills                                                                              |
| Caddy reload vs recreate              | Caddy supports hot reload: `docker exec caddy caddy reload ...`. No need to recreate container for config changes                                                                                    |
| Compose on Flatcar needs `/opt/bin/`  | Use `/opt/bin/docker-compose`, not `docker compose` (plugin not installed on read-only Flatcar)                                                                                                      |
| Gluetun public IP empty after restart | DNS (DoT → Cloudflare) may not be ready at startup. `PUBLICIP_PERIOD=12h` ensures periodic retry. Without it, empty IP cached permanently                                                            |
| Homepage widget API error             | Usually means gluetun's `/v1/publicip/ip` returns empty. Check with `curl -s http://localhost:8001/v1/publicip/ip`                                                                                   |

## Nextcloud Config Management

| Issue                                  | Solution                                                                                                                                                |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Env var vs config.php key names differ | `OVERWRITECLIURL` → `overwrite.cli.url`, `OVERWRITEHOST` → `overwritehost`. `occ config:system:delete` uses config.php keys                             |
| Env var removal doesn't fix config     | Docker env vars only set config.php on first install. Once persisted, must use `occ config:system:delete` with the correct key                          |
| `overwritehost` breaks multi-domain    | Forces ALL URLs to one hostname regardless of incoming Host header. Delete it for multi-domain setups — Nextcloud will respect each proxy's Host header |

## General Deployment Safety

| Rule                                    | Detail                                                                                                                       |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Backup before destructive changes       | For compose changes that remove volumes or change storage paths, verify PBS backup exists first                              |
| Config files are root-owned             | `/srv/docker/{immich,nextcloud}/` need `sudo` for edits on Flatcar. SCP as `core` user works (writes to user-writable paths) |
| Test connectivity after network changes | After any change touching ports, networks, or VPN config, verify the full chain: container → gluetun → internet              |
| Watchtower scope awareness              | Watchtower auto-updates containers. If you pin a version, set `com.centurylinklabs.watchtower.enable=false` label            |
| Systemd units need `/opt/bin` in PATH   | restic (and other user-installed binaries) live in `/opt/bin` on Flatcar; systemd's default PATH omits it. Backup units silently broke 2026-03-07→07-09 ("restic: command not found"). Set `Environment=PATH=/opt/bin:...` in every unit calling scripts that use bare binary names |
| Backup scripts must propagate failure   | A script that logs "fallito" but exits 0 keeps the systemd unit green — Immich backups failed unnoticed for 4 months. Always `exit 1` on failed final STATUS so `systemctl status`/monitoring can see it |
