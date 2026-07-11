# AGENTS.md — homelab

Consolidated infrastructure-as-code repository for a Proxmox-based homelab: Proxmox VE hosts
(winston, reginald), Flatcar Container Linux VMs running Docker stacks (media + Nextcloud + Immich +
reverse proxies), a 3-node Technitium DNS cluster, Caddy/Traefik reverse proxies with CrowdSec, S3
storage (MinIO current → RustFS migration; Garage abandoned, never deployed), PBS backups, and
Ansible/Terraform automation. This is a
config + scripts + docs repo — there is no application build/test toolchain.

> Subdirectory `CLAUDE.md` / `AGENTS.md` and the conditional rules under `.claude/rules/` carry
> deeper, scope-local detail (Flatcar, NFS/ZFS, DNS, GPU SR-IOV, networking, media APIs, etc.) and
> still apply when working in those trees. This file is the top-level source of truth.

## Production URLs

Mostly LAN-internal. Public services are exposed via Cloudflare Tunnel → Traefik (DMZ).

| Service              | URL / Endpoint                               | Platform                          |
| -------------------- | -------------------------------------------- | --------------------------------- |
| Internal services    | `*.home.disconnesso.com`                     | Caddy (LAN, CF DNS-challenge cert)|
| Nextcloud (public)   | https://nextcloud.lushanoperera.com          | Traefik + CF Tunnel (Flatcar VM)  |
| Immich (public)      | https://immich.lushanoperera.com             | Traefik + CF Tunnel (Flatcar VM)  |
| Technitium DNS (web) | http://192.168.100.120:5380 (primary)        | Native, Debian LXC 120 (reginald) |
| Homepage dashboard   | Flatcar VM `/srv/docker/homepage/`           | Caddy (internal)                  |
| Proxmox VE (winston) | https://192.168.100.38:8006                  | Proxmox VE 9.2.2                  |
| Proxmox VE (reginald)| https://192.168.100.4:8006                   | Proxmox VE 9.2.4                  |
| Proxmox Backup Server| https://192.168.100.187:8007                 | PBS VM on QNAP                     |

### Network architecture

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
| winston                         | 192.168.100.38 / .200.38                           | Primary Proxmox VE 9.2.2 host (64 GB, SR-IOV active: 7 VFs)             |
| reginald                        | 192.168.100.4 / .200.4                             | Secondary Proxmox VE 9.2.4 host (8 GB, ZFS NFS server)                 |
| flatcar-media (VM 100)          | .100.100 / .101 / .103 / .7.119 / .200.100         | Media stack + Nextcloud + Immich + reverse proxies                     |
| homeassistant (VM 102)          | .100.102 / .4.102 / .5.102                         | Home Assistant (multi-VLAN: Infra+IoT+Multimedia)                      |
| PBS                             | 192.168.100.187                                    | Proxmox Backup Server (VM on QNAP). Datastores `pbs-backups`/`nwlab-backup` on local virtio disks |
| PDM (LXC 106)                   | 192.168.100.106                                    | Proxmox Datacenter Manager (manages winston, reginald, nwlab-thinkpad) |
| QNAP NAS (TS-251+)              | 192.168.100.254 / .200.254                         | Storage (MinIO S3, NFS), DNS secondary, PBS host                       |
| nwlab-thinkpad (remote)         | 10.21.21.99                                        | nwlab Proxmox VE 9.2.2 host (managed via WireGuard tunnel)             |

**LXC (winston)**: 104 WireGuard, 105 Plex, 106 PDM.
**LXC (reginald)**: 120 Technitium DNS, 123 Samba.

## Repo layout

```
docs/                       # sr-iov guides, migrations, deployment guides, backups, thermal
dns/technitium/             # QNAP primary DNS compose + env
qnap/watchtower/            # Auto-update QNAP Container Station services
hosts/                      # Proxmox host firewall configs (common/cluster.fw, <host>/firewall/host.fw)
  firewall.md               # Host-firewall rollout runbook (log-first → drop-later)
vms/
  flatcar-media/            # VM 100: butane/, ignition/, sysext/, docker-compose.yml
  pbs/                      # Proxmox Backup Server config
networking/
  caddy/                    # Internal reverse proxy (*.home.disconnesso.com wildcard)
  traefik/                  # Public reverse proxy + CrowdSec (DMZ macvlan .7.119)
  cloudflare-tunnel/        # Cloudflared tunnel config
storage/{minio,garage,rustfs,nfs}/  # S3 (MinIO current → RustFS target; garage/ = abandoned plan) + NFS
apps/{couchdb,forgejo,vaultwarden,nextcloud,immich,technitium}/  # Docker stacks + restic backup
homepage/                   # Homepage dashboard config
scripts/{hosts,vms,network,migrations,monitoring,dns,backup}/    # Automation
automation/{ansible,terraform}/  # Playbooks + IaC
systemd/                    # Systemd .mount units
tools/bitwarden-manager/    # Credential management UI
hardware-purchases/         # Hardware planning notes (e.g. 3-node MS01 Ceph cluster)
.env / .env.example         # Root infra vars (gitignored .env; see Deployment)
```

### Repo → VM path mapping

| Repo Path                                    | Deployed Path (Flatcar VM 100)               | Deploy Method           |
| -------------------------------------------- | -------------------------------------------- | ----------------------- |
| `vms/flatcar-media/docker-compose.yml`       | `/srv/docker/media-stack/docker-compose.yml` | rsync/scp               |
| `networking/caddy/`                          | `/srv/docker/caddy/`                         | rsync/scp               |
| `networking/traefik/`                        | `/srv/docker/traefik/`                       | rsync/scp               |
| `networking/cloudflare-tunnel/`              | `/srv/docker/cloudflare-tunnel/`             | rsync/scp               |
| `apps/*/docker-compose.yml`                  | `/srv/docker/<app>/docker-compose.yml`       | rsync/scp               |
| `homepage/config/*`                          | `/srv/docker/homepage/config/`               | rsync/scp               |
| `scripts/vms/*.sh`                           | `/opt/bin/`                                  | deploy-media-scripts.sh |
| `scripts/dns/*.sh`, `scripts/backup/*.sh`    | `/opt/bin/`                                  | rsync + chmod 0755      |
| `systemd/*.mount`                            | `/etc/systemd/system/`                       | Ignition or manual      |
| `apps/*/restic-env.example`                  | `/srv/docker/<app>/.restic-env` (VM 100)     | manual, chmod 0600      |
| `hosts/common/cluster.fw`, `hosts/<h>/firewall/host.fw` | `/etc/pve/...` on the host        | `scripts/hosts/deploy-firewall.sh` |

## Local development

This is config/IaC — there is no app dev server. "Local dev" means editing configs and validating
them before deploying to hosts.

```bash
ssh root@192.168.100.38   # winston (Proxmox)
ssh root@192.168.100.4    # reginald (Proxmox)
ssh core@192.168.100.100  # Flatcar VM 100

# Inspect running containers on the Flatcar VM
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}"'

# Deploy a new Flatcar VM
./scripts/vms/deploy-flatcar-vm.sh --vm-id 105 --vm-ip 10.21.21.105
```

Scripts that need credentials (UniFi, *arr APIs, restic) source a `.env` file located **next to the
script/stack** — e.g. `scripts/network/.env`, `scripts/vms/.env`, `apps/immich/.env`. Copy the
adjacent `.env.example`, fill in values, and the script loads it via `set -a; source .env; set +a`.

## Deployment

Deployment is rsync/scp of config files to the target host, then a service reload — there is no CI
pipeline. The repo → VM mapping table above is authoritative for paths and methods.

```bash
# Generic stack deploy (example: caddy)
rsync -az --exclude='.git' --exclude='.env' networking/caddy/ core@192.168.100.100:/srv/docker/caddy/
ssh core@192.168.100.100 'cd /srv/docker/caddy && docker compose up -d'

# Proxmox host firewall (copy + compile; does NOT flip enable unless --enable/--disable)
./scripts/hosts/deploy-firewall.sh winston            # copy + compile only
./scripts/hosts/deploy-firewall.sh winston --status   # read-only status
./scripts/hosts/deploy-firewall.sh winston --enable   # flip enable: 0 → 1
```

### Credentials — distributed `.env` files (plain env, gitignored)

Secrets live in **plain `.env` files**, one per component, never committed. The repo migrated off
varlock/rbw on 2026-05-20 — there is **no live varlock/vault dependency**; the `.env.schema` /
`.env.schema.bak` are inert migration leftovers. Each script or stack sources the `.env` that sits
next to it.

Canonical secret files and their KEY NAMES (values are real only inside the gitignored `.env`):

| Secret file (alongside its consumer)   | Key names                                                       |
| -------------------------------------- | -------------------------------------------------------------- |
| `.env` (repo root)                     | `WINSTON_IP`, `REGINALD_IP`, `PBS_PASSWORD`, `API_TOKEN`       |
| `scripts/network/.env`                 | `UNIFI_HOST`, `UNIFI_USER`, `UNIFI_PASS`                       |
| `scripts/vms/.env`                     | `SEERR_API_KEY`, `SONARR_API_KEY`, `RADARR_API_KEY`, `SEERR_URL`, `SONARR_URL`, `RADARR_URL`, `QBITTORRENT_URL` |
| `networking/cloudflare-tunnel/.env`    | `TUNNEL_TOKEN`                                                  |
| `networking/traefik/.env`              | `CROWDSEC_BOUNCER_API_KEY`, `TUNNEL_TOKEN`                     |
| `apps/immich/.env`                     | `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE_NAME`, `IMMICH_VERSION`, `IMMICH_MACHINE_LEARNING_HARDWARE_ACCELERATION`, `TZ` |
| `apps/nextcloud/.env`                  | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `NEXTCLOUD_VERSION`, `NEXTCLOUD_TRUSTED_DOMAINS`, `NEXTCLOUD_URL`, `TZ` |
| `/srv/docker/<app>/.restic-env` (VM 100, root:root 0600) | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `UPLOAD_LOCATION`, `DB_DATA_LOCATION`, `RESTIC_COMPRESSION` |

```env
# scripts/network/.env (placeholders — real values live only in the gitignored file)
UNIFI_HOST=<gateway-ip-or-host>
UNIFI_USER=<unifi-username>
UNIFI_PASS=<unifi-password>
```

How tooling loads it:

```bash
set -a; source .env; set +a   # scripts source the adjacent .env; never echo values to logs
```

Each `.env.example` (committed, safe) is the template — copy to `.env` and fill in. **Real values
live only in the gitignored `.env`; never commit or echo them.**

## Security posture

Host-level Proxmox firewall is **configured but staged at `enable: 0`** on winston + reginald (as of
2026-04-20). Configs: `hosts/common/cluster.fw` + `hosts/<host>/firewall/host.fw`; rollout runbook
in `hosts/firewall.md`. Rollout is log-first → drop-later with a dead-man cron auto-disable and a
30-minute dwell per phase. Per-VM firewall stays off (multicast/mDNS). The UniFi UCG-Fiber handles
the perimeter; intra-VLAN-100 traffic is unfiltered until the FW is flipped live. Public services
reach the LAN only through Cloudflare Tunnel → Traefik (DMZ) → CrowdSec.

## DNS architecture (Technitium cluster)

3-node cluster with native zone replication (replaced Pi-hole + Nebula Sync).

| Node                               | IP              | Role      | Deployment                  |
| ---------------------------------- | --------------- | --------- | --------------------------- |
| reginald.dns.disconnesso.home.arpa | 192.168.100.120 | Primary   | Native (Debian 12 LXC)      |
| qnap.dns.disconnesso.home.arpa     | 192.168.100.254 | Secondary | Docker (Container Station)  |
| flatcar.dns.disconnesso.home.arpa  | 192.168.100.100 | Secondary | Docker (`/srv/docker/dns/`) |

Reginald was elevated to primary on 2026-07-11 (QNAP demoted to secondary — its console had
hung and the NAS is the slowest node). All nodes on Technitium 15.4.

Blocklists: StevenBlack/hosts + Hagezi Pro (~265K). Local zone `home.disconnesso.com` →
192.168.100.100. DNSSEC enabled.

## Reverse proxy architecture

Two-proxy split: **Caddy** (internal LAN, `*.home.disconnesso.com` wildcard cert via Cloudflare DNS
challenge — proxies ~22 services across 3 site files) and **Traefik** (public, DMZ macvlan
192.168.7.119, via Cloudflare Tunnel + cloudflared, with CrowdSec + bouncer). The CrowdSec Metabase
dashboard was removed 2026-03-07 — use the `cscli` CLI.

## Services by location

**Flatcar VM 100** (`ssh core@192.168.100.100`, stacks under `/srv/docker/`): Homepage dashboard;
media stack (gluetun/ProtonVPN, prowlarr, qbittorrent, sabnzbd, radarr, sonarr, lidarr, bazarr,
seerr, tautulli, flaresolverr, profilarr + profilarr-parser, watchtower [nickfedor fork], autoheal);
Caddy; Technitium DNS (secondary, separate `dns-compose.yml`); Traefik (DMZ .7.119) + CrowdSec +
cloudflared; Vaultwarden; Forgejo (private Git: dotfiles/configs); CouchDB (Obsidian LiveSync
backend); Nextcloud (nginx + FPM + Postgres + Redis + imaginary + appapi-harp); Immich (photo
management + ML); Portainer.

**QNAP NAS** (`192.168.100.254`): Technitium DNS (secondary), MinIO S3, PBS VM, Watchtower (daily 4 AM).

## Conditional rules (loaded on-demand by file pattern)

Lessons learned live in `.claude/rules/`, auto-loaded when matching files are touched:

| Rule file                             | Topics                                 | Triggers                                                             |
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

Skills under `.claude/skills/` cover operational runbooks (backup-status, container-manage,
deploy-compose, gpu-fix, media-health, media-remove, network-diagnostics, nfs-check, proxmox-manage,
quality-manage, retrigger-downloads, traefik-crowdsec, vpn-status).

## Verification

Infrastructure repo — no build/lint/test toolchain. Verify changes by:

1. Validate config syntax (Caddyfile, docker-compose, Butane, `pve-firewall compile`).
2. `shellcheck` on modified shell scripts.
3. SSH to the target host and apply/test the change.
4. Check service health after deployment (`docker ps`, service-specific runbook skills).

## Gotchas & conventions

- **Cloudways-style ops do not apply here** — these are self-managed Proxmox/Flatcar hosts; deploy is
  rsync/scp + `docker compose up -d`, no managed cache layer.
- **Secrets:** plain gitignored `.env` per component; never commit, never echo to logs. The
  `varlock`/rbw references in older docs are obsolete (migrated off 2026-05-20).
- **Restic env files** live at `/srv/docker/<app>/.restic-env` on VM 100 (root:root, `chmod 0600`);
  deployed manually, never committed.
- **Firewall rollout is deliberate** — `deploy-firewall.sh` never flips `enable:` without an explicit
  `--enable`/`--disable`; follow `hosts/firewall.md` (log-first, dwell, dead-man cron).
- Commits: short imperative / Conventional Commits (`feat:`, `fix:`, `docs:`). End AI commits with a
  brief why & how.
- The working tree runs chronically dirty (in-flight migrations: MinIO→Garage→RustFS, firewall
  staging, hardware planning) — stage explicit paths, never `git add -A`.
