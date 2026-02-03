---
name: traefik-crowdsec
description: Traefik reverse proxy and CrowdSec security management
allowed-tools: Bash, Read
---

# Traefik & CrowdSec Management

Manage reverse proxy and security for internet-facing services.

## Architecture

```
Internet → Cloudflare → Traefik (DMZ: 192.168.7.119)
                             ↓
                        CrowdSec ← CrowdSec Hub
                             ↓
                     CrowdSec Bouncer
                             ↓
                    Backend Services
```

## Services Behind Traefik

| Service           | Hostname                    | Backend                |
| ----------------- | --------------------------- | ---------------------- |
| Immich            | immich.lushanoperera.com    | 192.168.100.103:2283   |
| Nextcloud         | nextcloud.lushanoperera.com | 192.168.100.101:11000  |
| Traefik Dashboard | traefik.lushanoperera.com   | 192.168.7.119:8080     |
| CrowdSec          | crowdsec.lushanoperera.com  | crowdsec-metabase:3001 |

## Instructions

### Traefik Status

Check container:

```bash
ssh core@192.168.100.100 'docker ps | grep traefik'
```

View current routers:

```bash
ssh core@192.168.100.100 'curl -s http://localhost:8080/api/rawdata/routers | jq ".[] | {name, status, rule}"'
```

View current services:

```bash
ssh core@192.168.100.100 'curl -s http://localhost:8080/api/rawdata/services | jq ".[] | {name, status}"'
```

Check DMZ IP:

```bash
ssh core@192.168.100.100 'docker exec traefik ip addr show eth1 | grep inet'
```

### SSL Certificates

Check certificate status:

```bash
ssh core@192.168.100.100 'docker exec traefik cat /etc/traefik/acme.json | jq ".letsencrypt.Certificates[] | {domain: .domain.main, expires: .certificate}"' 2>/dev/null | head -20
```

Force certificate renewal (if issues):

```bash
ssh core@192.168.100.100 'docker exec traefik rm /etc/traefik/acme.json && docker restart traefik'
```

### CrowdSec Decisions

List current bans:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli decisions list'
```

List with details:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli decisions list -o json | jq ".[] | {ip: .value, reason: .scenario, duration: .duration, origin: .origin}"'
```

### Ban/Unban IP

Ban an IP:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli decisions add --ip [IP] --duration 24h --reason "manual ban"'
```

Unban an IP:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli decisions delete --ip [IP]'
```

Ban a range:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli decisions add --range [CIDR] --duration 24h --reason "manual ban"'
```

### CrowdSec Alerts

View recent alerts:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli alerts list --limit 20'
```

View alert details:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli alerts inspect [alert-id]'
```

### CrowdSec Metrics

View parser metrics:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli metrics'
```

### CrowdSec Hub

Update scenarios:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli hub update && docker exec crowdsec cscli hub upgrade'
```

List installed scenarios:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli scenarios list'
```

### Bouncer Status

Check bouncer is connected:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli bouncers list'
```

### Traefik Access Logs

View recent requests:

```bash
ssh core@192.168.100.100 'docker logs traefik --tail 100 2>&1 | grep -v "level=debug"'
```

View blocked requests:

```bash
ssh core@192.168.100.100 'docker logs traefik 2>&1 | grep -E "403|401|blocked"'
```

### Reload Traefik

Without restart:

```bash
ssh core@192.168.100.100 'docker kill --signal=USR1 traefik'
```

Full restart:

```bash
ssh core@192.168.100.100 'cd /srv/docker/traefik && /opt/bin/docker-compose restart traefik'
```

### Configuration Files

View Traefik config:

```bash
ssh core@192.168.100.100 'cat /srv/docker/traefik/traefik.yml'
```

View dynamic config:

```bash
ssh core@192.168.100.100 'cat /srv/docker/traefik/dynamic/*.yml'
```

## Troubleshooting

### 502 Bad Gateway

Check backend service is running:

```bash
ssh core@192.168.100.100 'docker ps | grep [service-name]'
```

Check Traefik can reach backend:

```bash
ssh core@192.168.100.100 'docker exec traefik wget -qO- http://[backend-ip]:[port]/health'
```

### Certificate Issues

Check Let's Encrypt rate limits:

```bash
ssh core@192.168.100.100 'docker logs traefik 2>&1 | grep -i "acme\|certificate"'
```

### CrowdSec Not Blocking

Check bouncer is active:

```bash
ssh core@192.168.100.100 'docker exec crowdsec cscli bouncers list'
```

Check bouncer logs:

```bash
ssh core@192.168.100.100 'docker logs crowdsec-bouncer --tail 50'
```

### Cloudflare Issues

Verify Cloudflare tunnel:

```bash
ssh core@192.168.100.100 'docker logs cloudflared --tail 20'
```

## Output Format

```
## Traefik & CrowdSec Report

### Traefik Status
- Container: Running/Stopped
- DMZ IP: 192.168.7.119
- Active Routers: X
- Active Services: X

### SSL Certificates
| Domain | Expires | Status |
|--------|---------|--------|
| example.com | 2024-03-01 | Valid |

### CrowdSec Status
- Active Bans: X
- Alerts (24h): X
- Bouncer: Connected/Disconnected

### Recent Bans
| IP | Reason | Duration |
|----|--------|----------|
| x.x.x.x | ssh-bf | 4h |

### Issues
1. [Issue if any]

### Actions Taken
1. [Action if any]
```
