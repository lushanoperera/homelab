# Flatcar Media Stack (VM 100)

Flatcar Container Linux VM running the media stack with Docker.

## Access

```bash
ssh core@192.168.100.100
```

## Services

| Service      | Port  | Description                                            |
| ------------ | ----- | ------------------------------------------------------ |
| Gluetun      | -     | VPN client (ProtonVPN)                                 |
| Prowlarr     | 9696  | Indexer manager                                        |
| qBittorrent  | 8080  | Torrent client                                         |
| SABnzbd      | 8081  | Usenet client                                          |
| Radarr       | 7878  | Movie manager                                          |
| Sonarr       | 8989  | TV show manager                                        |
| Lidarr       | 8686  | Music manager                                          |
| Bazarr       | 6767  | Subtitle manager                                       |
| Seerr        | 5055  | Request management                                     |
| Tautulli     | 8181  | Plex analytics                                         |
| Flaresolverr | 8191  | CAPTCHA solving for Prowlarr                           |
| Technitium   | 5380  | DNS server (secondary)                                 |
| Caddy        | 443   | Internal reverse proxy (`*.home.disconnesso.com`)      |
| Traefik      | 443   | Public reverse proxy (DMZ 192.168.7.119)               |
| CrowdSec     | -     | Security engine (Traefik bouncer)                      |
| Cloudflared  | -     | Cloudflare Tunnel connector                            |
| Nextcloud    | 11000 | Nextcloud (FPM + nginx, `nextcloud.lushanoperera.com`) |
| Immich       | 2283  | Photo management (`immich.lushanoperera.com`)          |
| CouchDB      | 5984  | Obsidian LiveSync backend                              |
| Vaultwarden  | 8200  | Password manager                                       |
| Portainer    | 9443  | Container management UI                                |

## Directory Structure

```
├── butane/           # Butane configuration sources (.bu)
├── ignition/         # Compiled Ignition files (.ign) - DO NOT EDIT
├── dns-compose.yml   # Technitium DNS compose (secondary node)
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
- Caddy (internal proxy): `/srv/docker/caddy/`
- Traefik (public proxy): `/srv/docker/traefik/`
- DNS stack: `/srv/docker/dns/`
- Nextcloud: `/srv/docker/nextcloud/`
- Immich: `/srv/docker/immich/`
- CouchDB: `/srv/docker/couchdb/`
- Vaultwarden: `/opt/vaultwarden/`
- Media data: `/mnt/media/`
- Nextcloud data: `/mnt/ncdata` (NFS)
- Immich uploads: `/mnt/immich/upload` (NFS)
- Immich database: `/mnt/immich/database` (NFS)

## Common Operations

```bash
# Check container status
docker ps --format 'table {{.Names}}\t{{.Status}}'

# Restart media stack
cd /srv/docker/media-stack && /opt/bin/docker-compose up -d --remove-orphans

# Check VPN IP
docker exec gluetun wget -qO- https://ipinfo.io/ip
```

> **Note:** The media stack uses `/opt/bin/docker-compose` (standalone binary). Nextcloud and Immich stacks use `docker compose` plugin (available in newer Flatcar). Both work — use whichever matches the stack's compose file.
