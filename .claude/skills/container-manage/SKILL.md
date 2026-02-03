---
name: container-manage
description: Container lifecycle management - restart, logs, updates, stack operations
allowed-tools: Bash, Read
---

# Container Management

Manage Docker containers on Flatcar media VM.

## When to Use

- Service not responding
- Need to view container logs
- Applying configuration changes
- Pulling updates

## Container Stacks

### Media Stack (`/srv/docker/media-stack`)

- gluetun, qbittorrent, sabnzbd
- prowlarr, sonarr, radarr, lidarr, bazarr
- overseerr, tautulli

### Traefik Stack (`/srv/docker/traefik`)

- traefik, crowdsec, crowdsec-bouncer

## Instructions

### Restart Single Container

```bash
ssh core@192.168.100.100 'docker restart [container-name]'
```

Example:

```bash
ssh core@192.168.100.100 'docker restart sonarr'
```

### Restart with Dependencies

Some containers depend on gluetun (VPN). Restart in order:

```bash
ssh core@192.168.100.100 'docker restart gluetun && sleep 10 && docker restart qbittorrent prowlarr'
```

### View Logs

Recent logs:

```bash
ssh core@192.168.100.100 'docker logs [container] --tail 100'
```

Follow logs:

```bash
ssh core@192.168.100.100 'docker logs [container] -f --tail 50'
```

Search logs for errors:

```bash
ssh core@192.168.100.100 'docker logs [container] 2>&1 | grep -i error | tail -20'
```

### Full Stack Restart

Media stack:

```bash
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose restart'
```

Traefik stack:

```bash
ssh core@192.168.100.100 'cd /srv/docker/traefik && /opt/bin/docker-compose restart'
```

### Pull Updates

Update single container:

```bash
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose pull [service] && /opt/bin/docker-compose up -d [service]'
```

Update all containers:

```bash
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose pull && /opt/bin/docker-compose up -d'
```

### Check Container Health

```bash
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
```

Check specific container:

```bash
ssh core@192.168.100.100 'docker inspect [container] --format "{{.State.Status}} ({{.State.Health.Status}})"'
```

### Stop/Start Container

Stop:

```bash
ssh core@192.168.100.100 'docker stop [container]'
```

Start:

```bash
ssh core@192.168.100.100 'docker start [container]'
```

### View Container Resources

```bash
ssh core@192.168.100.100 'docker stats --no-stream'
```

### Clean Up

Remove stopped containers:

```bash
ssh core@192.168.100.100 'docker container prune -f'
```

Remove unused images:

```bash
ssh core@192.168.100.100 'docker image prune -f'
```

Remove all unused data (careful!):

```bash
ssh core@192.168.100.100 'docker system prune -f'
```

## Container Dependencies

```
gluetun (VPN gateway)
  └── qbittorrent (uses gluetun network)
  └── prowlarr (uses gluetun network for trackers)

All media apps use /mnt/media NFS mount
```

## Common Issues

### Container Won't Start

Check logs:

```bash
ssh core@192.168.100.100 'docker logs [container] 2>&1 | tail -50'
```

Check if port is in use:

```bash
ssh core@192.168.100.100 'netstat -tlnp | grep [port]'
```

### Out of Memory

Check container memory usage:

```bash
ssh core@192.168.100.100 'docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"'
```

### Volume Permission Issues

Check volume mounts:

```bash
ssh core@192.168.100.100 'docker inspect [container] --format "{{json .Mounts}}" | jq'
```

## Output Format

```
## Container Operation Report

### Action
[What was requested]

### Result
| Container | Action | Status |
|-----------|--------|--------|
| sonarr | restart | Success |

### Logs (if relevant)
```

[relevant log output]

```

### Current State
[Output of docker ps for affected containers]
```
