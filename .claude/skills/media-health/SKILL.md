---
name: media-health
description: Check health of entire media stack - containers, VPN, ports, NFS, disk space
allowed-tools: Bash, Read
---

# Media Health Check

Comprehensive health check for the Flatcar media VM (192.168.100.100).

## When to Use

- Morning check or before requesting new downloads
- After network/VPN issues
- When downloads aren't progressing
- Periodic health verification

## Quick Reference

| Service     | Port | Container   |
| ----------- | ---- | ----------- |
| gluetun     | -    | VPN gateway |
| qBittorrent | 8080 | Torrent     |
| SABnzbd     | 8081 | Usenet      |
| Prowlarr    | 9696 | Indexers    |
| Sonarr      | 8989 | TV          |
| Radarr      | 7878 | Movies      |
| Lidarr      | 8686 | Music       |
| Bazarr      | 6767 | Subtitles   |
| Overseerr   | 5055 | Requests    |
| Tautulli    | 8181 | Plex stats  |

## Instructions

### Phase 1: Container Health

Check all containers are running:

```bash
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "gluetun|qbittorrent|sabnzbd|prowlarr|sonarr|radarr|lidarr|bazarr|overseerr|tautulli|traefik|crowdsec"'
```

Look for:

- All containers "Up"
- No "(unhealthy)" status
- No containers restarting

### Phase 2: VPN Verification

Check VPN is working (should NOT be home IP):

```bash
# Get VPN IP
ssh core@192.168.100.100 'docker exec gluetun wget -qO- https://ipinfo.io'
```

Expected: IP should be a ProtonVPN exit node, not the home ISP IP.

### Phase 3: Port Forwarding

Verify forwarded port and qBittorrent sync:

```bash
# Get forwarded port from gluetun
ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port'

# Check qBittorrent is using the same port
ssh core@192.168.100.100 'docker exec gluetun wget -qO- "http://localhost:8080/api/v2/app/preferences" 2>/dev/null | grep -oP "\"listen_port\":\s*\K\d+"'
```

If ports don't match, run:

```bash
ssh core@192.168.100.100 '/opt/bin/qbt-port-sync.sh'
```

### Phase 4: NFS Mount

Verify media storage is mounted:

```bash
ssh core@192.168.100.100 'systemctl status mnt-media.mount --no-pager'
ssh core@192.168.100.100 'df -h /mnt/media'
ssh core@192.168.100.100 'ls /mnt/media | head'
```

### Phase 5: Disk Space

Check available space:

```bash
ssh core@192.168.100.100 'df -h /mnt/media /srv/docker'
```

Alerts:

- `/mnt/media` < 100GB: Clear completed downloads
- `/srv/docker` < 10GB: Clean docker volumes/logs

### Phase 6: Service Responsiveness

Quick API health checks:

```bash
# Test Sonarr
ssh core@192.168.100.100 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8989/api/v3/system/status -H "X-Api-Key: $(grep SONARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)"'

# Test Radarr
ssh core@192.168.100.100 'curl -s -o /dev/null -w "%{http_code}" http://localhost:7878/api/v3/system/status -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)"'

# Test Overseerr
ssh core@192.168.100.100 'curl -s -o /dev/null -w "%{http_code}" http://localhost:5055/api/v1/status'
```

Expected: All return `200`

## Output Format

Report findings as:

```
## Media Stack Health Report

### Container Status
| Container | Status | Issue |
|-----------|--------|-------|
| gluetun | Up | - |
| ... | ... | ... |

### VPN Status
- IP: x.x.x.x (ProtonVPN: [country])
- Port forwarding: [port] (synced: yes/no)

### Storage
- /mnt/media: XXX GB free
- /srv/docker: XXX GB free

### Issues Found
1. [Issue description]
2. [Issue description]

### Recommendations
1. [Action to take]
```
