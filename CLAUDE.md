# CLAUDE.md - Proxmox Homelab Project

## Infrastructure Inventory

### Network Architecture

| Network | Subnet | Purpose |
|---------|--------|---------|
| Infra VLAN | 192.168.100.0/24 | Management, services, general traffic |
| Storage LAN | 192.168.200.0/24 | Dedicated storage traffic (NFS, backups) |

Storage LAN: separate physical interface per host, dedicated unmanaged switch.

### Proxmox Hosts

| Host | Infra IP | Storage IP | Role |
|------|----------|------------|------|
| winston | 192.168.100.38 | 192.168.200.38 | Primary Proxmox VE host |
| reginald | 192.168.100.4 | 192.168.200.4 | Secondary Proxmox VE host (NFS source) |

### QNAP NAS (TS-251+)

| Interface | IP |
|-----------|-----|
| Infra VLAN | 192.168.100.254 |
| Storage LAN | 192.168.200.254 |

| Service | IP | Role |
|---------|-----|------|
| PBS VM | 192.168.100.187 | Proxmox Backup Server |
| MinIO | 192.168.200.210:9000 | S3 storage for Restic backups |

### Key LXC Containers (winston)

| CTID | Service | Backup | Schedule |
|------|---------|--------|----------|
| 101 | Nextcloud | Restic → `restic-nextcloud` | Daily 00:00 |
| 103 | Immich | Restic → `restic-immich` | Daily 00:00 |
| 104 | WireGuard | — | — |
| 105 | Plex | — | — |

See `docs/backups.md` for full backup configuration.

### Storage Flow

```
LXC data → NFS (reginald) → CacheFS (winston) → Restic → MinIO S3
```

CacheFS on winston mitigates 2.5GbE bottleneck from reginald.

### Flatcar Linux VM

| Setting | Value |
|---------|-------|
| IP | 10.21.21.104 |
| SSH | `ssh core@10.21.21.104` |
| Host | Proxmox VM (PBS backed up) |

**Services:**
- Vaultwarden (password manager)
- Traefik (external reverse proxy)
- Cloudflared (Cloudflare tunnel)
- CrowdSec (security)
- n8n (workflow automation)
- Portainer (Docker management)
- NPM (internal LAN proxy)

### Reverse Proxies

| Proxy | Scope | Location |
|-------|-------|----------|
| Traefik | External (internet) | Exposes services outside LAN |
| Nginx Proxy Manager | Internal (LAN) | Docker container on Flatcar VM |

### Planned Migration

MinIO → Garage (see `minio-to-garage` project)

## SSH Access

```bash
# Proxmox hosts
ssh root@192.168.100.38  # winston
ssh root@192.168.100.4   # reginald

# PBS VM on QNAP
ssh root@192.168.100.187  # pbs
```

## Common Operations

```bash
# Check Proxmox version
pveversion

# List VMs
qm list

# List containers
pct list

# Check storage
pvesm status

# Check cluster status
pvecm status
```

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

## Related Projects

| Project | Path | Description |
|---------|------|-------------|
| flatcar-homelab | `../flatcar-homelab` | Flatcar VM with NPM + Docker containers |
| lxc-to-docker-migration | `../lxc-to-docker-migration` | LXC to Docker migration |
| proxmox-sr-iov | `../proxmox-sr-iov` | SR-IOV configuration |
| traefik | `../traefik` | External reverse proxy (internet-facing) |
| minio-to-garage | `../minio-to-garage` | S3 migration (planned) |
