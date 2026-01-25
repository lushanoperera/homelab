# Flatcar Media Stack (VM 100)

Flatcar Container Linux VM running the media stack with Docker.

## Access

```bash
ssh core@192.168.100.100
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| NordLynx | - | WireGuard VPN |
| Prowlarr | 9696 | Indexer manager |
| qBittorrent | 8080 | Torrent client |
| SABnzbd | 8080 | Usenet client |
| Radarr | 7878 | Movie manager |
| Sonarr | 8989 | TV show manager |
| Lidarr | 8686 | Music manager |
| Bazarr | 6767 | Subtitle manager |
| Overseerr | 5055 | Request management |
| Tautulli | 8181 | Plex analytics |

## Directory Structure

```
├── butane/           # Butane configuration sources (.bu)
├── ignition/         # Compiled Ignition files (.ign) - DO NOT EDIT
└── docker-compose.yml
```

## Ignition Workflow

```bash
# Compile Butane → Ignition
docker run --rm -i quay.io/coreos/butane:latest --strict < butane/config.bu > ignition/config.ign

# Validate
cat ignition/config.ign | jq '.'
```

## Docker Paths on VM

- Docker Compose: `/opt/bin/docker-compose` (standalone binary)
- Media stack: `/srv/docker/media-stack/`
- Media data: `/mnt/media/`

## Common Operations

```bash
# Check container status
docker ps --format 'table {{.Names}}\t{{.Status}}'

# Restart media stack
cd /srv/docker/media-stack && /opt/bin/docker-compose up -d --remove-orphans

# Check VPN IP
docker exec nordlynx curl -s https://ipinfo.io/ip
```
