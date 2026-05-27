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

| Host/VM                         | IP                                                 | Role                                                                   |
| ------------------------------- | -------------------------------------------------- | ---------------------------------------------------------------------- |
| UniFi Fiber Gateway (UCG-Fiber) | 192.168.1.1                                        | Router, firewall, UniFi OS 10.1 controller                             |
| winston                         | 192.168.100.38 / .200.38                           | Primary Proxmox VE 9.1.6 host (32 GB, SR-IOV active: 7 VFs)            |
| reginald                        | 192.168.100.4 / .200.4                             | Secondary Proxmox VE 9.1.5 host (8 GB)                                 |
| flatcar-media (VM 100)          | .100.100 / .100.101 / .100.103 / .7.119 / .200.100 | Media stack + Nextcloud + Immich                                       |
| homeassistant (VM 102)          | .100.102 / .4.102 / .5.102                         | Home Assistant (multi-VLAN: Infra+IoT+Multimedia)                      |
| PBS                             | 192.168.100.187                                    | Proxmox Backup Server (VM on QNAP, 2 GB). Datastores on local virtio disks: `pbs-backups` (vdb 768 GB), `nwlab-backup` (vdc 250 GB). NFS-backed `*-legacy` kept alongside until ~2026-07 for historical restores |
| PDM (LXC 106)                   | 192.168.100.106                                    | Proxmox Datacenter Manager (manages winston, reginald, nwlab-thinkpad) |
| QNAP NAS                        | 192.168.100.254 / .200.254                         | Storage (MinIO S3, NFS)                                                |
| nwlab-thinkpad (remote)         | 10.21.21.99                                        | nwlab Proxmox VE 9.2.2 / kernel 7.0.2-6 host (managed via WG tunnel)   |

### Services by Location

**Flatcar VM 100** (`ssh core@192.168.100.100`):

- Homepage dashboard (`/srv/docker/homepage/`) — single-pane service overview
- Media stack: gluetun (ProtonVPN), prowlarr, qbittorrent, sabnzbd, radarr, sonarr, lidarr, bazarr, seerr, tautulli, flaresolverr, watchtower (nickfedor fork), autoheal (restarts unhealthy containers after gluetun reconnects)
- Caddy reverse proxy (`/srv/docker/caddy/`) — internal `*.home.disconnesso.com` routing
- Technitium DNS (secondary node, `/srv/docker/dns/`, separate `dns-compose.yml`)
- Traefik (DMZ IP: 192.168.7.119) — public services via Cloudflare Tunnel + Cloudflared
- CrowdSec + Bouncer (Metabase dashboard removed 2026-03-07, use `cscli` CLI)
- Vaultwarden (`/opt/vaultwarden/`) — password manager
- Forgejo (`/srv/docker/forgejo/`) — private Git server (dotfiles, configs)
- CouchDB (`/srv/docker/couchdb/`) — Obsidian LiveSync backend
- Nextcloud (`/srv/docker/nextcloud/`) — standard Nextcloud (nginx + FPM + Postgres + Redis)
- Immich (`/srv/docker/immich/`) — photo management with ML

**QNAP NAS** (`192.168.100.254`): Technitium DNS (primary), Watchtower (daily 4 AM).

**VMs (winston)**: 100 flatcar-media, 102 homeassistant.

**LXC (winston)**: 104 WireGuard, 105 Plex, 106 PDM.

**LXC (reginald)**: 120 Technitium DNS, 123 Samba.

### DNS Architecture (Technitium Cluster)

3-node cluster with native zone replication. Replaced Pi-hole + Nebula Sync.

| Node                               | IP              | Role      | Deployment                  |
| ---------------------------------- | --------------- | --------- | --------------------------- |
| qnap.dns.disconnesso.home.arpa     | 192.168.100.254 | Primary   | Docker (Container Station)  |
| flatcar.dns.disconnesso.home.arpa  | 192.168.100.100 | Secondary | Docker (`/srv/docker/dns/`) |
| reginald.dns.disconnesso.home.arpa | 192.168.100.120 | Secondary | Native (Debian 12 LXC)      |

Blocklists: StevenBlack/hosts + Hagezi Pro (~265K). Local zone: `home.disconnesso.com` → 192.168.100.100. DNSSEC enabled.

### Reverse Proxy Architecture

Two-proxy split: Caddy (internal LAN, `*.home.disconnesso.com` wildcard cert via Cloudflare DNS challenge) and Traefik (public, DMZ macvlan 192.168.7.119, via Cloudflare Tunnel + cloudflared). Caddy proxies 22 services across 3 site files.

### Security Posture

Host-level Proxmox firewall **configured but staged at `enable: 0`** on winston + reginald as of 2026-04-20. Configs live in `hosts/common/cluster.fw` + `hosts/<host>/firewall/host.fw`; rollout runbook at `hosts/firewall.md`. Rollout is log-first → drop-later with a dead-man cron auto-disable and a 30 min dwell per phase. Per-VM firewall stays off (multicast/mDNS). UniFi UCG-Fiber handles perimeter; intra-VLAN 100 traffic is unfiltered until FW is flipped live. Deploy: `./scripts/hosts/deploy-firewall.sh <host>`.

## Directory Structure

```
homelab/
├── docs/                    # Documentation (sr-iov, migrations, guides)
├── dns/technitium/          # QNAP primary compose + env
├── qnap/watchtower/         # Auto-update QNAP containers
├── hosts/                   # Proxmox host configs (winston, reginald)
├── vms/
│   ├── flatcar-media/       # VM 100 (butane/, ignition/, sysext/, docker-compose.yml)
│   └── pbs/                 # Proxmox Backup Server
├── networking/{caddy,traefik}/ # Reverse proxies
├── storage/{minio,garage,nfs}/ # S3 + NFS config
├── scripts/{hosts,vms,network,migrations,monitoring}/
├── automation/{ansible,terraform}/
├── homepage/                # Homepage dashboard
├── apps/{couchdb,forgejo,vaultwarden,nextcloud,immich}/
├── systemd/                 # Systemd units
└── tools/bitwarden-manager/ # Credential management UI
```

### Repo → VM Path Mapping

| Repo Path                                         | Deployed Path (Flatcar)                      | Deploy Method           |
| ------------------------------------------------- | -------------------------------------------- | ----------------------- |
| `vms/flatcar-media/docker-compose.yml`            | `/srv/docker/media-stack/docker-compose.yml` | rsync/scp               |
| `networking/caddy/`                               | `/srv/docker/caddy/`                         | rsync/scp               |
| `networking/traefik/`                             | `/srv/docker/traefik/`                       | rsync/scp               |
| `networking/cloudflare-tunnel/`                   | `/srv/docker/cloudflare-tunnel/`             | rsync/scp               |
| `scripts/vms/*.sh`                                | `/opt/bin/`                                  | deploy-media-scripts.sh |
| `apps/*/docker-compose.yml`                       | `/srv/docker/<app>/docker-compose.yml`       | rsync/scp               |
| `systemd/*.mount`                                 | `/etc/systemd/system/`                       | Ignition or manual      |
| `homepage/config/*`                               | `/srv/docker/homepage/config/`               | rsync/scp               |
| `apps/technitium-exporter/*`                      | `/srv/docker/technitium-exporter/`           | rsync/scp               |
| `scripts/backup/technitium-config-backup.sh`      | `/opt/bin/technitium-config-backup.sh`       | rsync + chmod 0755      |
| `scripts/dns/*.sh`                                | `/opt/bin/`                                  | rsync + chmod 0755      |
| `apps/technitium/restic-env.example`              | `/etc/restic/technitium.env` (per node)      | manual, chmod 0600      |

## Lessons Learned

Moved to conditional rules (loaded on-demand by file pattern):

| Rule File                             | Topics                                 | Triggers                                                             |
| ------------------------------------- | -------------------------------------- | -------------------------------------------------------------------- |
| `.claude/rules/flatcar-lessons.md`    | Flatcar, Butane, Ignition, Compose     | `vms/flatcar-media/**`, `systemd/**`                                 |
| `.claude/rules/nfs-zfs-lessons.md`    | NFS, ZFS, mounts, exports              | `storage/nfs/**`, `systemd/*.mount`                                  |
| `.claude/rules/dns-lessons.md`        | Technitium DNS cluster                 | `dns/**`, `**/dns-compose*`                                          |
| `.claude/rules/infra-lessons.md`      | Proxmox networking, GPU SR-IOV, Garage | `hosts/**`, `networking/**`, `storage/garage/**`                     |
| `.claude/rules/networking-lessons.md` | UniFi API, WiFi, mesh, Radio AI        | `scripts/network/**`, `networking/**`                                |
| `.claude/rules/gpu-sriov-lessons.md`  | GPU SR-IOV build, deploy, containers   | `vms/flatcar-media/sysext/**`, `apps/immich/**`, `apps/nextcloud/**` |
| `.claude/rules/deployment-lessons.md` | Compose deployment, SCP, verification  | `vms/flatcar-media/**`, `networking/**`, `apps/**`, `homepage/**`    |
| `.claude/rules/media-api-lessons.md`  | Seerr CSRF, qBit via gluetun, *arr API | `vms/flatcar-media/**`, `scripts/vms/**`, `apps/**`                  |
| `.claude/rules/ops-reference.md`      | SSH, container ops, app management     | `vms/**`, `apps/**`, `scripts/**`, `homepage/**`, `networking/**`    |
| `.claude/rules/network-services.md`   | Services map, NFS, WG, backup, DNS ops | `networking/**`, `dns/**`, `hosts/**`, `storage/nfs/**`              |

## Verification

This is an infrastructure repo — no build/lint/test toolchain. Verify changes by:

1. Validate config syntax (Caddyfile, docker-compose, Butane)
2. `shellcheck` on modified shell scripts
3. SSH to target host and test the change
4. Check service health after deployment


## Secrets

This project uses varlock for secret management.
- Schema: `.env.schema` (committed, safe to read)
- Secrets resolved from Vaultwarden via rbw at runtime
- Run commands with: `varlock run -- <command>`
- Never create .env files or hardcode secrets
