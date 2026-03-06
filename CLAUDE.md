# CLAUDE.md - Homelab Infrastructure

Consolidated homelab repository covering Proxmox hosts, VMs, networking, storage, and automation.

## Infrastructure Overview

### Network Architecture

| Network     | Subnet           | VLAN | Purpose                                   |
| ----------- | ---------------- | ---- | ----------------------------------------- |
| Management  | 192.168.1.0/24   | 1    | Gateway, APs, default devices             |
| Trusted     | 192.168.2.0/24   | 2    | Personal devices (phones, laptops)        |
| Guests      | 192.168.3.0/24   | 3    | Guest WiFi                                |
| IoT         | 192.168.4.0/24   | 4    | Smart home, Alexa, cameras, sensors       |
| Multimedia  | 192.168.5.0/24   | 5    | Sonos, Sky Q, media players               |
| Infra       | 192.168.100.0/20 | 100  | Proxmox hosts, VMs, LXCs, services        |
| DMZ         | 192.168.7.0/24   | 7    | Internet-facing services (Traefik)        |
| Storage LAN | 192.168.200.0/24 | —    | Dedicated NFS/backup traffic (not on UFG) |

### Hosts & VMs

| Host/VM                         | IP                           | Role                                                                   |
| ------------------------------- | ---------------------------- | ---------------------------------------------------------------------- |
| UniFi Fiber Gateway (UCG-Fiber) | 192.168.1.1                  | Router, firewall, UniFi OS 10.1 controller                             |
| winston                         | 192.168.100.38 / .200.38     | Primary Proxmox VE 9.1.6 host (32 GB, SR-IOV active: 7 VFs)            |
| reginald                        | 192.168.100.4 / .200.4       | Secondary Proxmox VE 9.1.5 host (8 GB)                                 |
| flatcar-media (VM 100)          | .100.100 / .7.119 / .200.100 | Media stack (Sonarr, Radarr, qBittorrent)                              |
| homeassistant (VM 102)          | .100.102 / .4.102 / .5.102   | Home Assistant (multi-VLAN: Infra+IoT+Multimedia)                      |
| PBS                             | 192.168.100.187              | Proxmox Backup Server (on QNAP)                                        |
| PDM (LXC 106)                   | 192.168.100.106              | Proxmox Datacenter Manager (manages winston, reginald, nwlab-thinkpad) |
| QNAP NAS                        | 192.168.100.254 / .200.254   | Storage (MinIO S3, NFS)                                                |
| nwlab-thinkpad (remote)         | 10.21.21.99                  | nwlab Proxmox VE 9.1.5 host (managed via WG tunnel)                    |

### Services by Location

**Flatcar VM 100** (`ssh core@192.168.100.100`):

- Media stack: gluetun (ProtonVPN), prowlarr, qbittorrent, sabnzbd, radarr, sonarr, lidarr, bazarr, seerr, tautulli, flaresolverr, watchtower (nickfedor fork)
- Caddy reverse proxy (`/srv/docker/caddy/`) — internal `*.home.disconnesso.com` routing
- Technitium DNS (secondary node, `/srv/docker/dns/`, separate `dns-compose.yml`)
- Traefik (DMZ IP: 192.168.7.119) — public services via Cloudflare Tunnel
- CrowdSec + Bouncer
- Cloudflared tunnel
- Kido (Docker app, `kido.giulyart.it`)
- Vaultwarden (`/opt/vaultwarden/`) — password manager
- CouchDB (`/srv/docker/couchdb/`) — Obsidian LiveSync backend

**QNAP NAS** (`192.168.100.254`):

- Technitium DNS (primary node, via Container Station)
- Watchtower (nickfedor fork, daily 4 AM auto-updates)

**VMs (winston)**:

- 100: flatcar-media — Media stack (Infra .100.100, DMZ .7.119, Storage .200.100)
- 102: homeassistant — Home Assistant (192.168.100.102, IoT .4.102, Multimedia .5.102)

**LXC Containers (winston)**:

- 101: Nextcloud (192.168.100.101)
- 103: Immich (192.168.100.103)
- 104: WireGuard (192.168.100.104)
- 105: Plex (192.168.100.105)
- 106: PDM — Proxmox Datacenter Manager (192.168.100.106)

**LXC Containers (reginald)**:

- 120: Technitium DNS (secondary node, native install) (192.168.100.120)
- 123: Samba file share (192.168.100.123)

### DNS Architecture (Technitium Cluster)

3-node Technitium DNS cluster with native zone replication. Replaced Pi-hole + Nebula Sync.

| Node                               | IP              | Role      | Deployment                  |
| ---------------------------------- | --------------- | --------- | --------------------------- |
| qnap.dns.disconnesso.home.arpa     | 192.168.100.254 | Primary   | Docker (Container Station)  |
| flatcar.dns.disconnesso.home.arpa  | 192.168.100.100 | Secondary | Docker (`/srv/docker/dns/`) |
| reginald.dns.disconnesso.home.arpa | 192.168.100.120 | Secondary | Native (Debian 12 LXC)      |

- Cluster domain: `dns.disconnesso.home.arpa`
- Web UI: `http://<node-ip>:5380`
- Clustering port: 53443/tcp (HTTPS API)
- Blocklists: StevenBlack/hosts + Hagezi Pro (~265K domains)
- Local zone: `home.disconnesso.com` with wildcard CNAME → 192.168.100.100
- DNSSEC: enabled
- Media containers use `/srv/docker/resolv.conf` pointing to all 3 nodes

### Reverse Proxy Architecture

Two-proxy split: Caddy handles internal LAN routing, Traefik handles public internet traffic.

```
LAN clients → Caddy (192.168.100.100:443)
                  │  *.home.disconnesso.com wildcard cert
                  │  (Let's Encrypt via Cloudflare DNS challenge)
                  │
                  ├── localhost ports (media stack, vaultwarden, portainer)
                  └── remote IPs (LXCs, Proxmox hosts, NAS)

Internet → Cloudflare Tunnel → Traefik (192.168.7.119)
```

| Proxy   | Scope    | Cert                       | Config Location        |
| ------- | -------- | -------------------------- | ---------------------- |
| Caddy   | Internal | `*.home.disconnesso.com`   | `/srv/docker/caddy/`   |
| Traefik | Public   | Per-service via Cloudflare | `/srv/docker/traefik/` |

Caddy proxies 21 services across 3 site files: `media.caddy` (9), `apps.caddy` (6), `infrastructure.caddy` (6).

### Cross-Site WireGuard Routing (winston ↔ nwlab)

Winston runs a WireGuard client (`wg-nwlab`) connecting to the nwlab office wg-easy server, enabling PDM to manage the remote nwlab-thinkpad Proxmox host.

```
PDM (LXC 106, .100.106)
  → static route: 10.21.21.0/24 via 192.168.100.38
    → winston MASQUERADE (src → 10.0.0.5)
      → wg-nwlab tunnel (Endpoint: 80.210.114.192:51820)
        → nwlab wg-easy (LXC 100, 10.21.21.100) MASQUERADE
          → thinkpad (10.21.21.99:8006)
```

| Component      | Config                             | Notes                                                |
| -------------- | ---------------------------------- | ---------------------------------------------------- |
| WG interface   | `/etc/wireguard/wg-nwlab.conf`     | Overlay IP: 10.0.0.5/32, MTU 1420                    |
| WG service     | `wg-quick@wg-nwlab`                | Enabled on boot                                      |
| IP forwarding  | `/etc/sysctl.d/99-wg-forward.conf` | `net.ipv4.ip_forward=1`                              |
| PDM route      | LXC 106 `/etc/network/interfaces`  | `up ip route add 10.21.21.0/24 via 192.168.100.38`   |
| Routed subnets | AllowedIPs                         | `10.0.0.0/24` (overlay), `10.21.21.0/24` (nwlab LAN) |

**Note**: LXC 104 on winston is the personal homelab WG **server** (wg-easy for remote access) — completely separate from `wg-nwlab`.

## Directory Structure

```
homelab/
├── docs/                    # Documentation
│   ├── sr-iov/              # GPU SR-IOV guides
│   ├── migrations/          # Migration docs (LXC→Docker, MinIO→Garage)
│   └── guides/              # Deployment guides
├── dns/
│   └── technitium/          # Technitium DNS (QNAP primary compose + env)
├── qnap/                    # QNAP NAS Container Station services
│   └── watchtower/          # Auto-update all QNAP containers
├── hosts/                   # Proxmox host configs (winston, reginald)
├── vms/
│   ├── flatcar-media/       # VM 100 - Media stack
│   │   ├── butane/          # Butane configs (.bu)
│   │   ├── ignition/        # Compiled Ignition (.ign)
│   │   └── docker-compose.yml
│   └── pbs/                 # Proxmox Backup Server
├── networking/
│   ├── caddy/               # Internal reverse proxy (*.home.disconnesso.com)
│   ├── traefik/             # External reverse proxy + CrowdSec
│   └── cloudflare-tunnel/   # Cloudflare tunnel config
├── storage/
│   ├── minio/               # Current S3 storage
│   ├── garage/              # Target S3 storage (migration)
│   └── nfs/                 # NFS configuration
├── scripts/
│   ├── hosts/               # Host management scripts
│   ├── vms/                 # VM deployment scripts
│   ├── network/             # Network discovery (UniFi inventory)
│   ├── migrations/          # Migration scripts
│   └── monitoring/          # GPU monitoring scripts
├── automation/
│   ├── ansible/             # Ansible playbooks
│   └── terraform/           # Terraform IaC
├── apps/
│   ├── couchdb/             # CouchDB (Obsidian LiveSync)
│   ├── kido/                # Kido web app
│   └── vaultwarden/         # Vaultwarden password manager
├── systemd/                 # Systemd units
└── tools/
    └── bitwarden-manager/   # Credential management UI
```

### Repo → VM Path Mapping

| Repo Path                                         | Deployed Path (Flatcar)                      | Deploy Method                 |
| ------------------------------------------------- | -------------------------------------------- | ----------------------------- |
| `vms/flatcar-media/docker-compose.yml`            | `/srv/docker/media-stack/docker-compose.yml` | rsync/scp                     |
| `networking/caddy/`                               | `/srv/docker/caddy/`                         | rsync/scp                     |
| `networking/traefik/`                             | `/srv/docker/traefik/`                       | rsync/scp                     |
| `networking/cloudflare-tunnel/`                   | `/srv/docker/cloudflare-tunnel/`             | rsync/scp                     |
| `scripts/vms/*.sh`                                | `/opt/bin/`                                  | deploy-media-scripts.sh       |
| `apps/couchdb/`                                   | `/srv/docker/couchdb/`                       | rsync/scp                     |
| `apps/couchdb/couchdb-stack.service`              | `/etc/systemd/system/couchdb-stack.service`  | scp + systemctl enable        |
| `apps/kido/`                                      | `/srv/docker/kido/`                          | rsync/scp                     |
| `apps/vaultwarden/docker-compose.yml`             | `/opt/vaultwarden/docker-compose.yml`        | scp                           |
| `apps/vaultwarden/backup.sh`                      | `/opt/vaultwarden/backup.sh`                 | scp + chmod +x                |
| `systemd/*.mount`                                 | `/etc/systemd/system/`                       | Ignition or manual            |
| `hosts/winston/ksm-enable.service`                | `/etc/systemd/system/ksm-enable.service`     | scp + systemctl enable        |
| `apps/nextcloud/backup-nextcloud.sh`              | LXC 101 `/root/backup-nextcloud.sh`          | `pct push`                    |
| `apps/nextcloud/nextcloud-backup.{service,timer}` | LXC 101 `/etc/systemd/system/`               | `pct push` + systemctl enable |
| `apps/immich/backup-immich.sh`                    | LXC 103 `/root/backup-immich.sh`             | `pct push`                    |
| `apps/immich/immich-backup.{service,timer}`       | LXC 103 `/etc/systemd/system/`               | `pct push` + systemctl enable |

## Quick Reference

### SSH Access

```bash
# Proxmox hosts
ssh root@192.168.100.38   # winston
ssh root@192.168.100.4    # reginald

# Flatcar VM (media stack)
ssh core@192.168.100.100

# PBS on QNAP
ssh root@192.168.100.187
```

### Flatcar VM Operations

```bash
# Container status
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}"'

# Media stack management
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose ps'

# Traefik stack
ssh core@192.168.100.100 'cd /srv/docker/traefik && /opt/bin/docker-compose ps'

# VPN verification (ProtonVPN via gluetun)
ssh core@192.168.100.100 'docker exec gluetun wget -qO- https://ipinfo.io/ip'

# Check forwarded port
ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port'

# Check qBittorrent listening port matches
ssh core@192.168.100.100 'docker exec gluetun wget -qO- "http://localhost:8080/api/v2/app/preferences" 2>/dev/null | grep -oP "\"listen_port\":\s*\K\d+"'

# Manual port sync (usually automatic via timer)
ssh core@192.168.100.100 '/opt/bin/qbt-port-sync.sh'

# NFS mount status
ssh core@192.168.100.100 'systemctl status mnt-media.mount'

# Media library audit (find orphans and duplicates)
ssh core@192.168.100.100 '/opt/bin/media-audit.sh'
ssh core@192.168.100.100 '/opt/bin/media-audit.sh --no-plex'  # Skip Plex sync check

# View audit results
ssh core@192.168.100.100 'cat /tmp/media-audit/summary.json'
ssh core@192.168.100.100 'cat /tmp/media-audit/orphaned_tv.txt'
ssh core@192.168.100.100 'cat /tmp/media-audit/duplicates.txt'

# Duplicate cleanup (safe deletion with trash + *arr sync)
ssh core@192.168.100.100 '/opt/bin/media-cleanup.sh --dry-run'      # Preview deletions
ssh core@192.168.100.100 '/opt/bin/media-cleanup.sh --auto'         # Auto-delete safe duplicates
ssh core@192.168.100.100 '/opt/bin/media-cleanup.sh --interactive'  # Manual review each

# View cleanup results and trash
ssh core@192.168.100.100 'cat /tmp/media-cleanup/proposed_deletions.txt'
ssh core@192.168.100.100 'cat /tmp/media-cleanup/cleanup_log.txt'
ssh core@192.168.100.100 'ls -la /mnt/media/.trash/'

# Recover from trash (within 7 days)
ssh core@192.168.100.100 'cat /mnt/media/.trash/deletion_log.txt'  # Find original paths
```

### CouchDB (Obsidian LiveSync)

```bash
ssh core@192.168.100.100 'cd /srv/docker/couchdb && /opt/bin/docker-compose ps'
ssh core@192.168.100.100 'curl -s http://localhost:5984/_up'
ssh core@192.168.100.100 'curl -s http://localhost:5984/obsidian-livesync | jq .doc_count'
```

### Immich (LXC 103)

```bash
# Access
ssh root@192.168.100.38 'pct exec 103 -- bash'

# Container status
ssh root@192.168.100.38 'pct exec 103 -- docker ps --format "table {{.Names}}\t{{.Status}}"'

# Check version (public endpoint, no auth needed)
ssh root@192.168.100.38 'pct exec 103 -- curl -s http://localhost:2283/api/server/version'

# Update (uses :release rolling tag, not pinned)
ssh root@192.168.100.38 'pct exec 103 -- bash -c "cd /home && docker compose pull && docker compose up -d"'

# Cleanup old images
ssh root@192.168.100.38 'pct exec 103 -- docker image prune -f'
```

Key paths inside LXC 103:

- Compose + .env: `/home/`
- Database: `/mnt/database` (NFS from reginald)
- Photo library: `/mnt/upload` (NFS from reginald)
- GPU: Intel iGPU VF 2 (00:02.3) via udev+bind mount — HW transcoding (QuickSync) enabled

### nwlab WireGuard Tunnel

```bash
# Tunnel status
ssh root@192.168.100.38 'wg show wg-nwlab'

# Test connectivity to nwlab
ssh root@192.168.100.38 'ping -c 2 10.21.21.99'

# Test PDM → thinkpad (full chain)
ssh root@192.168.100.38 'pct exec 106 -- curl -sk https://10.21.21.99:8006/api2/json/version'

# Restart tunnel
ssh root@192.168.100.38 'systemctl restart wg-quick@wg-nwlab'
```

### NFS Operations

```bash
# Check NFS exports on Reginald
ssh root@192.168.100.4 'exportfs -v'

# Check ZFS mountpoints (ensure all inherited)
ssh root@192.168.100.4 'zfs list -o name,mountpoint,mounted | grep media'

# Check movies bind mount
ssh root@192.168.100.4 'systemctl status media-movies.mount'

# Verify data consistency across all hosts
ssh root@192.168.100.4 'ls /media/tv | wc -l'           # Reginald
ssh root@192.168.100.38 'ls /mnt/nfs_media/tv | wc -l'  # Winston
ssh core@192.168.100.100 'ls /mnt/media/tv | wc -l'     # Flatcar

# Verify movies visible on all hosts
ssh root@192.168.100.4 'ls /media/movies | wc -l'           # Reginald
ssh root@192.168.100.38 'ls /mnt/nfs_media/movies | wc -l'  # Winston
ssh core@192.168.100.100 'ls /mnt/media/movies | wc -l'     # Flatcar

# Write test through full chain
ssh core@192.168.100.100 'docker exec sonarr touch /tv/test && docker exec sonarr rm /tv/test'

# Reload NFS exports
ssh root@192.168.100.4 'exportfs -ra'

# Remount NFS on Flatcar (if stale)
ssh core@192.168.100.100 'sudo systemctl restart mnt-media.mount'
ssh core@192.168.100.100 'sudo systemctl restart mnt-media-movies.mount'

# Check all NFS mounts on Flatcar (all via Storage LAN 192.168.200.x)
ssh core@192.168.100.100 'mount -t nfs4'
```

### Technitium DNS Operations

```bash
# Cluster status (from any node)
ssh core@192.168.100.100 'curl -s "http://localhost:5380/api/admin/cluster/state?token=TOKEN"'

# Test DNS resolution from each node
dig @192.168.100.254 google.com +short  # QNAP
dig @192.168.100.100 google.com +short  # Flatcar
dig @192.168.100.120 google.com +short  # Reginald

# Test local zone
dig @192.168.100.100 home.disconnesso.com +short
dig @192.168.100.100 test.home.disconnesso.com +short

# Technitium container on Flatcar
ssh core@192.168.100.100 'cd /srv/docker/dns && /opt/bin/docker-compose ps'
ssh core@192.168.100.100 'cd /srv/docker/dns && /opt/bin/docker-compose logs --tail 50'

# Technitium service on Reginald (native install, service=dns)
ssh root@192.168.100.4 'pct exec 120 -- systemctl status dns'

# Web admin UIs
# QNAP:     http://192.168.100.254:5380
# Flatcar:  http://192.168.100.100:5380
# Reginald: http://192.168.100.120:5380

# Update media container DNS (resolv.conf)
ssh core@192.168.100.100 'cat /srv/docker/resolv.conf'
```

### UniFi Gateway Inventory

```bash
# Requires: scripts/network/.env (copy .env.example, fill in credentials)

# Full inventory (clients, devices, networks, health)
./scripts/network/unifi-inventory.sh

# Specific sections
./scripts/network/unifi-inventory.sh --health
./scripts/network/unifi-inventory.sh --clients
./scripts/network/unifi-inventory.sh --networks
./scripts/network/unifi-inventory.sh --devices

# WiFi radio details and channel assessment
./scripts/network/unifi-inventory.sh --wifi
./scripts/network/unifi-inventory.sh --wifi --json | jq '.[].radios'

# Raw JSON output (for piping to jq)
./scripts/network/unifi-inventory.sh --all --json
./scripts/network/unifi-inventory.sh --clients --json | jq '.data[] | {ip, hostname, mac}'
```

### Ignition Workflow

```bash
# Compile Butane → Ignition
docker run --rm -i quay.io/coreos/butane:latest --strict < vms/flatcar-media/butane/config.bu > vms/flatcar-media/ignition/config.ign

# Validate Ignition JSON
cat vms/flatcar-media/ignition/config.ign | jq '.'
```

### VM Deployment

```bash
# Deploy new Flatcar VM
./scripts/vms/deploy-flatcar-vm.sh --vm-id 105 --vm-ip 10.21.21.105

# With custom config
./scripts/vms/deploy-flatcar-vm.sh \
  --vm-id 106 --vm-ip 10.21.21.106 \
  --vm-name docker-node-1 --memory 8192 --cores 4
```

### Caddy (Internal Reverse Proxy)

```bash
# Caddy stack management
ssh core@192.168.100.100 'cd /srv/docker/caddy && /opt/bin/docker-compose ps'
ssh core@192.168.100.100 'cd /srv/docker/caddy && /opt/bin/docker-compose logs --tail 50'

# Validate Caddyfile syntax
ssh core@192.168.100.100 'docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile'

# Reload config without downtime
ssh core@192.168.100.100 'docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile'

# Check wildcard cert status
ssh core@192.168.100.100 'docker exec caddy caddy list-modules | grep dns'
ssh core@192.168.100.100 'docker logs caddy 2>&1 | grep -i certificate'

# Admin API (config inspection)
ssh core@192.168.100.100 'curl -s http://localhost:2019/config/ | jq .'

# Validate Caddyfile (syntax + reachability)
ssh core@192.168.100.100 'docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile'
```

### Traefik & CrowdSec (Public Reverse Proxy)

```bash
# Check Traefik DMZ IP
docker exec traefik ip addr show eth1 | grep inet

# CrowdSec decisions (bans)
docker exec crowdsec cscli decisions list

# Ban/unban IP
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 24h --reason "manual ban"
docker exec crowdsec cscli decisions delete --ip 1.2.3.4
```

### Proxmox Operations

```bash
pveversion          # Check version
qm list             # List VMs
pct list            # List containers
pvesm status        # Check storage
```

### MinIO → Garage Migration

```bash
# Run migration steps (on QNAP NAS)
./scripts/migrations/minio-to-garage/migrate.sh 1   # Create directories
./scripts/migrations/minio-to-garage/migrate.sh 2   # Start Garage
./scripts/migrations/minio-to-garage/migrate.sh 3   # Configure node/bucket/key
./scripts/migrations/minio-to-garage/migrate.sh 4   # Verify source
./scripts/migrations/minio-to-garage/migrate.sh 5   # Migrate with rclone
./scripts/migrations/minio-to-garage/migrate.sh 6   # Verify with Restic
```

## Network Services Map

| Service            | Hostname                           | Backend                   |
| ------------------ | ---------------------------------- | ------------------------- |
| Immich             | immich.lushanoperera.com           | 192.168.100.103:2283      |
| Nextcloud          | nextcloud.lushanoperera.com        | 192.168.100.101:11000     |
| Traefik Dashboard  | traefik.lushanoperera.com          | 192.168.7.119:8080        |
| CrowdSec Dashboard | crowdsec.lushanoperera.com         | crowdsec-metabase:3001    |
| Kido               | kido.giulyart.it                   | 192.168.100.100:3000/3001 |
| Obsidian Sync      | obsidian-sync.home.disconnesso.com | localhost:5984            |

## Storage Architecture

### NFS Media Storage

```
┌─────────────────────────────────────────────────────────────┐
│ REGINALD (ZFS Source — 192.168.200.4)                       │
│                                                             │
│ rpool/shared/media → /media                                 │
│   ├─ /media/downloads  (ZFS child dataset)                  │
│   ├─ /media/movies     (systemd bind mount from             │
│   │                     /rpool/shared/media/movies)          │
│   │                     After=zfs-mount, Before=nfs-server   │
│   ├─ /media/music      (ZFS child dataset)                  │
│   └─ /media/tv         (ZFS child dataset)                  │
│                                                             │
│ NFS Exports (Storage LAN 192.168.200.0/24 only):            │
│   /rpool/shared        (crossmnt, fsid=7) — NFSv4 pseudo-root│
│   /rpool/shared/media  (crossmnt)         — child datasets  │
│   /rpool/shared/media/movies (fsid=6)     — bind mount      │
│   /rpool/shared/vaultwarden               — app data        │
└─────────────────────────┬───────────────────────────────────┘
                          │ NFSv4.2 (Storage LAN only)
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    Flatcar VM 100   Winston          Plex LXC 105
    (192.168.200.100)(192.168.200.38) (via Winston)
    /mnt/media       /mnt/nfs_media   /mnt/media
    /mnt/media/movies (separate mount for bind-mount subpath)
```

**Movies architecture note:** Movies live in the parent ZFS dataset `rpool/shared` at
path `media/movies/`, NOT as a ZFS child dataset. A systemd mount unit
(`media-movies.mount`) on Reginald bind mounts `/rpool/shared/media/movies` to
`/media/movies` with ordering deps (`After=zfs-mount.service`,
`Before=nfs-server.service`). NFS clients mount it separately because `crossmnt`
does not traverse non-ZFS (bind) mounts -- an explicit export with its own `fsid` is required.

### Backup Flow

```
VM/LXC backups → PBS (192.168.100.187) → pbs-backups datastore
                                        → nwlab-backup datastore (nwlab offsite copies)
                  PBS push job ──WG──→ nwlab PBS homelab-sync datastore

LXC data → NFS (reginald) → CacheFS (winston) → Restic → MinIO S3
                                                           ↓
                                                     (migrating to Garage)
```

| Service | IP              | Ports                               |
| ------- | --------------- | ----------------------------------- |
| MinIO   | 192.168.200.210 | 9000 (S3), 9001 (Console)           |
| Garage  | 192.168.200.211 | 3900 (S3), 3902 (Web), 3903 (Admin) |

## Lessons Learned

Moved to conditional rules (loaded on-demand by file pattern):

| Rule File                             | Topics                                 | Triggers                                         |
| ------------------------------------- | -------------------------------------- | ------------------------------------------------ |
| `.claude/rules/flatcar-lessons.md`    | Flatcar, Butane, Ignition, Compose     | `vms/flatcar-media/**`, `systemd/**`             |
| `.claude/rules/nfs-zfs-lessons.md`    | NFS, ZFS, mounts, exports              | `storage/nfs/**`, `systemd/*.mount`              |
| `.claude/rules/dns-lessons.md`        | Technitium DNS cluster                 | `dns/**`, `**/dns-compose*`                      |
| `.claude/rules/infra-lessons.md`      | Proxmox networking, GPU SR-IOV, Garage | `hosts/**`, `networking/**`, `storage/garage/**` |
| `.claude/rules/networking-lessons.md` | UniFi API, WiFi, mesh, Radio AI        | `scripts/network/**`, `networking/**`            |

## Verification

This is an infrastructure repo — no build/lint/test toolchain. Verify changes by:

1. Validate config syntax (Caddyfile, docker-compose, Butane)
2. `shellcheck` on modified shell scripts
3. SSH to target host and test the change
4. Check service health after deployment

## Safety Rules

**HARD BLOCK - Always confirm before:**

- `rm -rf` or any recursive deletion
- VM/container destruction (`qm destroy`, `pct destroy`)
- Storage removal
- Network configuration changes
- Cluster operations

**Never:**

- Run destructive commands without explicit user confirmation
- Modify production VMs without backup verification
- Change network settings that could cause connectivity loss
