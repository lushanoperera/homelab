---
name: vpn-status
description: VPN and port forwarding verification for gluetun/ProtonVPN
allowed-tools: Bash, Read
---

# VPN Status Check

Verify VPN connectivity and port forwarding for the media stack.

## When to Use

- Downloads failing or slow
- Connectivity issues
- After ProtonVPN maintenance
- Periodic security verification

## Instructions

### Phase 1: VPN Connection

Check gluetun container health:

```bash
ssh core@192.168.100.100 'docker inspect gluetun --format "{{.State.Health.Status}}"'
```

Expected: `healthy`

Get current VPN IP and location:

```bash
ssh core@192.168.100.100 'docker exec gluetun wget -qO- https://ipinfo.io'
```

Verify this is NOT your home IP. Should show ProtonVPN server location.

### Phase 2: Port Forwarding

Get the forwarded port:

```bash
ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port'
```

This port should be:

1. Non-zero
2. Synced to qBittorrent

Check qBittorrent's configured port:

```bash
ssh core@192.168.100.100 'docker exec gluetun wget -qO- "http://localhost:8080/api/v2/app/preferences" 2>/dev/null | grep -oP "\"listen_port\":\s*\K\d+"'
```

### Phase 3: Port Sync

If ports don't match, sync them:

```bash
ssh core@192.168.100.100 '/opt/bin/qbt-port-sync.sh'
```

Check the sync timer is active:

```bash
ssh core@192.168.100.100 'systemctl status qbt-port-sync.timer --no-pager'
```

### Phase 4: Port Connectivity Test

Test if the port is actually reachable from outside:

```bash
# Get current port
PORT=$(ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port')

# Test via external service (from gluetun's perspective)
ssh core@192.168.100.100 "docker exec gluetun wget -qO- 'https://portchecker.co/check' --post-data='port=$PORT' 2>/dev/null | grep -o 'open\|closed'"
```

Alternative using netcat (if available):

```bash
# From another machine or using a port check service
curl "https://ports.yougetsignal.com/port-check.php" --data "remoteAddress=$(ssh core@192.168.100.100 'docker exec gluetun wget -qO- https://ipinfo.io/ip')&portNumber=$PORT"
```

### Phase 5: DNS Leak Test

Verify DNS is going through VPN:

```bash
ssh core@192.168.100.100 'docker exec gluetun cat /etc/resolv.conf'
```

Should show gluetun's internal DNS, not ISP DNS.

## Troubleshooting

### VPN Not Connected

Restart gluetun:

```bash
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose restart gluetun'
```

Check logs:

```bash
ssh core@192.168.100.100 'docker logs gluetun --tail 50'
```

### Port Forwarding Failed

1. Check ProtonVPN credentials are valid
2. Verify port forwarding is enabled in gluetun config
3. Check gluetun logs for port forwarding errors

```bash
ssh core@192.168.100.100 'docker logs gluetun 2>&1 | grep -i "port forward"'
```

### Port Changes Frequently

ProtonVPN rotates ports. The qbt-port-sync timer should handle this:

```bash
# Check timer is running
ssh core@192.168.100.100 'systemctl list-timers qbt-port-sync.timer'

# Check last sync
ssh core@192.168.100.100 'cat /tmp/qbt-port-sync.state'
```

## Output Format

```
## VPN Status Report

### Connection
- Status: Connected/Disconnected
- VPN IP: x.x.x.x
- Location: [City, Country]
- Provider: ProtonVPN

### Port Forwarding
- Forwarded Port: XXXXX
- qBittorrent Port: XXXXX
- Synced: Yes/No
- Port Reachable: Yes/No/Unknown

### Health
- gluetun container: healthy/unhealthy
- DNS: VPN/Leaked

### Issues
1. [Issue if any]

### Actions Taken
1. [Action if any]
```
