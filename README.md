# Proxmox Homelab

Scripts and configuration for managing Proxmox VE hosts.

## Infrastructure

### Network Architecture

| Network | Subnet | Purpose |
|---------|--------|---------|
| Infra VLAN | 192.168.100.0/24 | Management, services |
| Storage LAN | 192.168.200.0/24 | Dedicated storage traffic |

Storage LAN uses a separate physical interface on each host connected via dedicated unmanaged switch.

### Proxmox Hosts

| Host | Infra IP | Storage IP | Description |
|------|----------|------------|-------------|
| winston | 192.168.100.38 | 192.168.200.38 | Primary Proxmox host (MS-01, i9-13900H) |
| reginald | 192.168.100.4 | 192.168.200.4 | Storage host (Zimaboard 832, 7x SSD ZFS RAIDZ2) |
| QNAP NAS | 192.168.100.254 | 192.168.200.254 | TS-251+, PBS VM, MinIO |

### Hardware Details

**Winston (Primary Compute)**

| Component | Specification |
|-----------|---------------|
| Chassis | Minisforum MS-01 |
| CPU | Intel i9-13900H (14C/20T, up to 5.2 GHz) |
| Features | SR-IOV GPU passthrough, Quick Sync HW transcode |
| Thermal | powersave governor, thermald ([docs](docs/thermal-management.md)) |

**Reginald (Storage Server)**

| Component | Specification |
|-----------|---------------|
| Chassis | Zimaboard 832 |
| CPU | Intel Celeron N3450 (4C/4T) |
| Expansion | SATA PCIe controller card |
| Storage | 7x SSD in ZFS RAIDZ2 pool |
| Role | NFS server for LXC container data |

### QNAP NAS (TS-251+)

| Service | IP | Description |
|---------|------|-------------|
| PBS VM | 192.168.100.187 | Proxmox Backup Server |
| MinIO | (container) | S3-compatible storage for Restic backups |

**Docker containers** running on QNAP for backup infrastructure.

### Storage Architecture

```
LXC Containers (Nextcloud, Immich, Vaultwarden)
        ↓
   NFS Shares (192.168.100.4 / reginald)
        ↓
   CacheFS (192.168.100.38 / winston)
        ↓
   Restic Backups → MinIO S3 buckets
```

CacheFS on winston reduces bottlenecks from reginald's 2.5GbE networking.

### Reverse Proxy Architecture

| Proxy | Scope | Location |
|-------|-------|----------|
| Traefik | External (internet-facing) | See `traefik` project |
| Nginx Proxy Manager | Internal (LAN only) | Docker on Flatcar VM |

## Directory Structure

```
├── docs/
│   ├── backups.md           # Backup configuration (PBS, Restic)
│   └── thermal-management.md # CPU governor, thermald config
├── scripts/
│   └── check-nfs-mounts.sh  # NFS mount verification script
├── systemd/
│   └── nfs-mount-check.service  # Systemd service for NFS checks
├── reports/                 # Generated reports, logs
├── .env.example             # Environment template
└── CLAUDE.md                # AI assistant instructions
```

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/lushanoperera/homelab.git
   cd homelab
   ```

2. Copy environment template:
   ```bash
   cp .env.example .env
   ```

3. Fill in credentials in `.env` (never commit this file)

## Scripts

### scripts/check-nfs-mounts.sh
Verifies NFS mounts are accessible and healthy.

### systemd/nfs-mount-check.service
Systemd service unit for automated NFS mount monitoring (uses `scripts/check-nfs-mounts.sh`).

## Documentation

| Doc | Description |
|-----|-------------|
| [Backups](docs/backups.md) | PBS and Restic backup configuration |
| [Thermal Management](docs/thermal-management.md) | CPU governor, thermald, Intel P-State tuning |

## Related Projects

| Project | Description |
|---------|-------------|
| [flatcar-homelab](../flatcar-homelab) | Flatcar Linux VM hosting NPM and other Docker containers |
| [lxc-to-docker-migration](../lxc-to-docker-migration) | Migration scripts for LXC to Docker |
| [proxmox-sr-iov](../proxmox-sr-iov) | SR-IOV configuration for Proxmox |
| [traefik](../traefik) | Traefik reverse proxy for external/internet access |
| [minio-to-garage](../minio-to-garage) | MinIO to Garage S3 migration (planned) |
