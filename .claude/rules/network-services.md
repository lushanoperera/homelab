---
paths:
  - "networking/**"
  - "dns/**"
  - "hosts/**"
  - "storage/nfs/**"
recall:
  - nfs
  - wireguard
  - wg-nwlab
  - dns
  - technitium
  - unifi
  - services map
  - storage architecture
  - backup
---

# Network Services & Storage Architecture

## Network Services Map

| Service           | Hostname                           | Traefik Backend        | Caddy Backend   |
| ----------------- | ---------------------------------- | ---------------------- | --------------- |
| Immich            | immich.lushanoperera.com           | immich_server:2283     | localhost:2283  |
| Nextcloud         | nextcloud.lushanoperera.com        | nextcloud-web:80       | localhost:11000 |
| Traefik Dashboard | traefik.lushanoperera.com          | api@internal           | —               |
| Obsidian Sync     | obsidian-sync.home.disconnesso.com | —                      | localhost:5984  |
| Homepage          | homepage.home.disconnesso.com      | —                      | localhost:3000  |
| Forgejo           | forgejo.home.disconnesso.com       | —                      | localhost:3100  |

Traefik (DMZ macvlan) routes via `traefik_internal` Docker network — macvlan cannot reach host IPs.

## NFS Media Storage

Reginald (192.168.200.4) exports via NFSv4.2 on Storage LAN only:
- `rpool/shared` (crossmnt, fsid=7) — pseudo-root
- `rpool/shared/media` (crossmnt) — child datasets (downloads, music, tv)
- `rpool/shared/media/movies` (fsid=6) — bind mount (not ZFS child)
- `rpool/shared/nextcloud`, `rpool/shared/immich`, `rpool/shared/vaultwarden`

Movies: parent dataset path, systemd bind mount `media-movies.mount`, separate NFS export with own fsid because `crossmnt` doesn't traverse bind mounts.

Flatcar mounts: `/mnt/media`, `/mnt/media/movies`, `/mnt/ncdata`, `/mnt/immich/{upload,database}`

## nwlab WireGuard Tunnel

PDM (.100.106) → winston MASQUERADE (10.0.0.5) → wg-nwlab tunnel → nwlab wg-easy → thinkpad (10.21.21.99)

Config: `/etc/wireguard/wg-nwlab.conf`, service `wg-quick@wg-nwlab`. LXC 104 is the separate personal WG server.

## Backup Flow

VM/LXC → PBS (.100.187) → pbs-backups + nwlab-backup datastores → push job over WG to nwlab PBS.
App data (Flatcar VM 100, `/srv/docker/<app>/.restic-env`) → Restic → MinIO S3 (migrating to RustFS).

| Service | IP              | Ports                                                |
| ------- | --------------- | ---------------------------------------------------- |
| MinIO   | 192.168.200.210 | 9000 (S3), 9001 (Console)                            |
| RustFS  | 192.168.200.212 | 9000 (S3), 9001 (Console) — target, not deployed yet |

## DNS Operations

```bash
dig @192.168.100.254 google.com +short  # QNAP primary
dig @192.168.100.100 google.com +short  # Flatcar secondary
dig @192.168.100.120 google.com +short  # Reginald secondary
```

## NFS Operations

```bash
ssh root@192.168.100.4 'exportfs -v'
ssh core@192.168.100.100 'mount -t nfs4'
ssh core@192.168.100.100 'sudo systemctl restart mnt-media.mount'
```

## UniFi Inventory

```bash
./scripts/network/unifi-inventory.sh --health|--clients|--networks|--devices|--wifi
./scripts/network/unifi-inventory.sh --all --json
```
