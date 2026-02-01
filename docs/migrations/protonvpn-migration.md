# NordVPN to ProtonVPN (gluetun) Migration

**Date**: 2026-02-01
**Status**: ✅ Complete

## Overview

Migrated from NordVPN (nordlynx container) to ProtonVPN via gluetun to enable NAT-PMP port forwarding for improved torrent performance.

## Why ProtonVPN?

| Feature         | NordVPN          | ProtonVPN            |
| --------------- | ---------------- | -------------------- |
| Port Forwarding | ❌ Not supported | ✅ NAT-PMP (dynamic) |
| WireGuard       | ✅ NordLynx      | ✅ Native            |
| Kill Switch     | ✅ Via container | ✅ Via gluetun       |
| Cost            | ~€5/mo           | ~€10/mo              |

Port forwarding enables incoming torrent connections, improving:

- Download speeds (can connect to more peers)
- Upload ratios (seeders can reach you directly)
- Swarm health (better tracker connectivity)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flatcar VM 100 (192.168.100.100)                          │
│                                                             │
│  ┌─────────────┐                                           │
│  │   gluetun   │ ← ProtonVPN WireGuard tunnel              │
│  │  (VPN box)  │   Exit IP: ProtonVPN server               │
│  │             │   Port forward: NAT-PMP (dynamic)         │
│  └──────┬──────┘                                           │
│         │ network_mode: service:gluetun                    │
│         │                                                  │
│  ┌──────┴──────┬──────────────┬──────────────┐            │
│  │ qbittorrent │   sabnzbd    │   prowlarr   │            │
│  │   :8080     │    :7777     │    :9696     │            │
│  └─────────────┴──────────────┴──────────────┘            │
│                                                             │
│  Direct network (host bridge):                             │
│  radarr, sonarr, lidarr, bazarr, overseerr, tautulli      │
└─────────────────────────────────────────────────────────────┘
```

## Configuration

### Required Environment Variables

```bash
# In /srv/docker/media-stack/.env
PROTON_WIREGUARD_KEY=<your-private-key>
PROTON_WIREGUARD_ADDRESS=10.2.0.x/32
VPN_COUNTRY=Netherlands  # or Italy, Switzerland, etc.
```

### Generating ProtonVPN WireGuard Config

1. Go to https://account.protonvpn.com/downloads
2. Select **WireGuard** configuration
3. **Enable "Moderate NAT"** (required for port forwarding)
4. Download config and extract:
   - `PrivateKey` → `PROTON_WIREGUARD_KEY`
   - `Address` (IPv4 only) → `PROTON_WIREGUARD_ADDRESS`

### Docker Compose (gluetun service)

```yaml
gluetun:
  image: qmcgaw/gluetun:latest
  container_name: gluetun
  cap_add:
    - NET_ADMIN
  devices:
    - /dev/net/tun:/dev/net/tun
  ports:
    - "${QBITTORRENT_PORT}:8080"
    - "${SABNZBD_PORT}:7777"
    - "${PROWLARR_PORT}:9696"
    - "6881:6881"
    - "6881:6881/udp"
    - "8001:8000" # Control server for port forward info
  environment:
    - VPN_SERVICE_PROVIDER=protonvpn
    - VPN_TYPE=wireguard
    - WIREGUARD_PRIVATE_KEY=${PROTON_WIREGUARD_KEY}
    - WIREGUARD_ADDRESSES=${PROTON_WIREGUARD_ADDRESS}
    - VPN_PORT_FORWARDING=on
    - PORT_FORWARD_ONLY=on
    - SERVER_COUNTRIES=${VPN_COUNTRY:-Netherlands}
    - TZ=${TZ}
  volumes:
    - ${CONFIG_ROOT}/gluetun:/gluetun
  sysctls:
    - net.ipv6.conf.all.disable_ipv6=1
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "/gluetun-entrypoint", "healthcheck"]
    interval: 30s
    timeout: 10s
    retries: 5
    start_period: 60s
```

## Port Forwarding Automation

ProtonVPN assigns a dynamic port via NAT-PMP. To sync it with qBittorrent:

### Manual Check

```bash
# Get forwarded port from gluetun
curl -s http://localhost:8001/v1/portforward | jq '.port'

# Or read from file
docker exec gluetun cat /tmp/gluetun/forwarded_port
```

### Automated Sync

Deploy the port sync script and systemd timer:

```bash
# Copy script to Flatcar
scp scripts/vms/qbt-port-sync.sh core@192.168.100.100:/opt/bin/
ssh core@192.168.100.100 'chmod +x /opt/bin/qbt-port-sync.sh'

# Copy systemd units
scp systemd/qbt-port-sync.{service,timer} core@192.168.100.100:/etc/systemd/system/

# Create credentials file
ssh core@192.168.100.100 'echo "QBT_PASS=your-qbt-password" | sudo tee /srv/docker/media-stack/.env.qbt'

# Enable and start timer
ssh core@192.168.100.100 'sudo systemctl daemon-reload && sudo systemctl enable --now qbt-port-sync.timer'
```

The timer runs every 5 minutes and updates qBittorrent's listening port if it changes.

## Verification

### 1. VPN Connection

```bash
# Check exit IP
docker exec gluetun wget -qO- https://ipinfo.io/ip
# Should return ProtonVPN IP, not your home IP

# Check VPN status
docker logs gluetun 2>&1 | grep -i "vpn"
```

### 2. Port Forwarding

```bash
# Check forwarded port
curl -s http://localhost:8001/v1/portforward
# {"port":36756}

# Check firewall rule
docker logs gluetun 2>&1 | grep -i "port"
# INFO [firewall] setting allowed input port 36756 through interface tun0
```

### 3. qBittorrent Connectivity

```bash
# Check qBittorrent listening port matches forwarded port
cat /srv/docker/media-stack/config/qbittorrent/qBittorrent.conf | grep "Session\\\\Port"
```

### 4. External Reachability Test

1. Add a well-seeded torrent
2. Check qBittorrent peer list for incoming connections (↓ indicator)
3. Use https://ipleak.net torrent detection

## Service Communication

VPN-protected services share gluetun's network stack:

| Service     | Reachable At                           |
| ----------- | -------------------------------------- |
| qbittorrent | `gluetun:8080` (from other containers) |
| sabnzbd     | `gluetun:7777`                         |
| prowlarr    | `gluetun:9696`                         |

Direct network services use their own hostnames:

- `radarr:7878`, `sonarr:8989`, `lidarr:8686`, etc.

## Rollback

If issues occur:

```bash
ssh core@192.168.100.100
cd /srv/docker/media-stack

# Restore backups (if created before migration)
cp docker-compose.yml.nordvpn-backup docker-compose.yml
cp .env.nordvpn-backup .env

# Restart stack
/opt/bin/docker-compose down
/opt/bin/docker-compose up -d
```

## Known Limitations

1. **Dynamic Port**: ProtonVPN changes the forwarded port periodically (on reconnect). The sync script handles this.

2. **Server Selection**: `PORT_FORWARD_ONLY=on` limits server choice to those supporting port forwarding. Some countries may have limited options.

3. **IPv6**: Disabled (`net.ipv6.conf.all.disable_ipv6=1`) as ProtonVPN WireGuard doesn't fully support it.

## Cost

- ProtonVPN Plus: €10/month (required for port forwarding)
- Annual plan: ~€100/year (save ~€20)
