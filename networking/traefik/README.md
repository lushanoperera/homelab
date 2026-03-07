# Traefik Reverse Proxy (Public)

Public-facing reverse proxy running on the DMZ macvlan network, secured with CrowdSec.

## Status: Active

## Architecture

```
Internet → Cloudflare Tunnel → cloudflared (Docker) → Traefik (192.168.7.119)
                                                          │
                                                          ├── CrowdSec bouncer (inline threat blocking)
                                                          └── CrowdSec engine (log analysis + CAPI)
```

Traefik runs on a dedicated DMZ macvlan interface (`eth1`) with IP `192.168.7.119`, isolated from the LAN. Because macvlan containers **cannot reach host IPs** on the same NIC (Linux kernel limitation), backend services are routed via the shared `traefik_internal` Docker bridge network using container hostnames instead of IPs.

## Services

| Service           | Hostname                    | Backend (Docker DNS) |
| ----------------- | --------------------------- | -------------------- |
| Immich            | immich.lushanoperera.com    | immich_server:2283   |
| Nextcloud         | nextcloud.lushanoperera.com | nextcloud-web:80     |
| Traefik Dashboard | traefik.lushanoperera.com   | api@internal         |

## Deployment

Managed by systemd on Flatcar VM 100:

```bash
# Service unit
systemctl status traefik-stack

# The service creates Docker networks on startup:
#   - dmz_macvlan: macvlan on eth1, subnet 192.168.7.0/24, IP 192.168.7.119
#   - traefik_internal: shared network for Traefik ↔ backends + CrowdSec
```

## Configuration Files

| File               | Purpose                                                         |
| ------------------ | --------------------------------------------------------------- |
| docker-compose.yml | Container definitions (Traefik, CrowdSec, bouncer, cloudflared) |
| services.yml       | Dynamic router and service definitions                          |
| config.yml         | Middleware and dynamic configuration                            |

## Common Operations

```bash
# Stack management (on Flatcar VM)
cd /srv/docker/traefik && /opt/bin/docker-compose ps
cd /srv/docker/traefik && /opt/bin/docker-compose logs --tail 50

# Check DMZ IP assignment
docker exec traefik ip addr show eth1 | grep inet

# CrowdSec operations
docker exec crowdsec cscli decisions list                                           # View bans
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 24h --reason "manual ban"  # Ban
docker exec crowdsec cscli decisions delete --ip 1.2.3.4                            # Unban
```
