---
name: deploy-compose
description: Safe deployment of docker-compose changes to Flatcar VM 100 with dependency-aware recreation
tools: Bash, Read
---

# Deploy Compose

Safe deployment of docker-compose file changes to Flatcar VM 100. Handles SCP, dependency-aware container recreation, and post-deploy verification.

## When to Use

- After editing any `docker-compose.yml` in the repo
- Deploying config changes to media stack, traefik, caddy, couchdb, nextcloud, immich
- When user says "deploy", "push to flatcar", "update the stack"

## Stack → Path Mapping

| Repo Path                              | Remote Path                | Stack Name  |
| -------------------------------------- | -------------------------- | ----------- |
| `vms/flatcar-media/docker-compose.yml` | `/srv/docker/media-stack/` | media-stack |
| `networking/caddy/`                    | `/srv/docker/caddy/`       | caddy       |
| `networking/traefik/`                  | `/srv/docker/traefik/`     | traefik     |
| `apps/couchdb/`                        | `/srv/docker/couchdb/`     | couchdb     |
| `apps/nextcloud/`                      | `/srv/docker/nextcloud/`   | nextcloud   |
| `apps/immich/`                         | `/srv/docker/immich/`      | immich      |
| `homepage/`                            | `/srv/docker/homepage/`    | homepage    |

## Instructions

### Phase 1: Pre-flight

Before deploying, validate the compose file locally:

```bash
# Validate YAML syntax
docker compose -f <local-compose-path> config --quiet 2>&1 && echo "Valid" || echo "INVALID"
```

For Caddy config:

```bash
ssh core@192.168.100.100 'docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile'
```

### Phase 2: Deploy (SCP)

```bash
scp <local-file> core@192.168.100.100:<remote-path>
```

For directories (Caddy site files, Homepage config):

```bash
scp -r <local-dir>/* core@192.168.100.100:<remote-dir>/
```

### Phase 3: Apply Changes

**CRITICAL RULE — Network Namespace Dependencies:**

The media stack has containers sharing gluetun's network namespace via `network_mode: service:gluetun`. If gluetun's config changed, you MUST `up -d` the full stack — not just gluetun.

**If gluetun config changed (env vars, ports, image):**

```bash
# MUST recreate full stack — gluetun gets new container ID, orphaning dependents
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose up -d'
```

**If only a non-gluetun service changed:**

```bash
# Safe to target just the changed service
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose up -d <service>'
```

**For Caddy (config-only, no recreate needed):**

```bash
ssh core@192.168.100.100 'docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile'
```

**For Traefik stack:**

```bash
ssh core@192.168.100.100 'cd /srv/docker/traefik && /opt/bin/docker-compose up -d'
```

### Phase 4: Verify

Run verification appropriate to the stack:

**Media stack:**

```bash
# All containers healthy
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "gluetun|qbittorrent|sabnzbd|prowlarr|sonarr|radarr|lidarr|bazarr|seerr|tautulli"'

# VPN still working
ssh core@192.168.100.100 'docker exec gluetun wget -qO- https://ipinfo.io/ip'

# Public IP cached (Homepage widget)
ssh core@192.168.100.100 'curl -s http://localhost:8001/v1/publicip/ip'

# Port forwarding intact
ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port'

# Web UIs responding (via host-mapped ports)
ssh core@192.168.100.100 'curl -s -o /dev/null -w "qbt:%{http_code} " http://localhost:8080 && curl -s -o /dev/null -w "prowlarr:%{http_code} " http://localhost:9696 && curl -s -o /dev/null -w "sabnzbd:%{http_code}\n" http://localhost:8081'
```

**Caddy:**

```bash
ssh core@192.168.100.100 'docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile'
# Test a known route
curl -sk https://homepage.home.disconnesso.com -o /dev/null -w "%{http_code}"
```

**Traefik:**

```bash
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "traefik|crowdsec|cloudflared"'
```

## Common Mistakes to Avoid

| Mistake                                     | Consequence                                       | Prevention                                                          |
| ------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------- |
| `up -d gluetun` alone                       | Orphans qbt/prowlarr/sabnzbd (stale container ID) | Always `up -d` full stack if gluetun changed                        |
| `restart` after `up -d` of network provider | "No such container" error                         | Use `up -d`, never `restart` for dependents of recreated containers |
| Deploying without YAML validation           | Compose fails to parse, stack down                | Always `docker compose config --quiet` first                        |
| Forgetting to verify post-deploy            | Silent failures go unnoticed                      | Always run Phase 4 checks                                           |
| SCP to wrong remote path                    | Config in wrong location, ignored                 | Check mapping table above                                           |

## Output Format

```
## Deploy Report

### Files Deployed
| Local | Remote | Method |
|-------|--------|--------|
| path  | path   | scp    |

### Services Affected
- [service]: recreated / reloaded / unchanged

### Verification
| Check | Result |
|-------|--------|
| Containers healthy | X/Y |
| VPN IP | x.x.x.x |
| Port forwarding | XXXXX |
| Web UIs | all responding |

### Status
[Deployed successfully / Partial failure / Rolled back]
```
