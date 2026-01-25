# Proxmox Homelab

Scripts and configuration for managing Proxmox VE hosts.

## Infrastructure

### Proxmox Hosts

| Host | IP | Description |
|------|------|-------------|
| winston | 192.168.100.38 | Primary Proxmox host |
| reginald | 192.168.100.4 | Secondary Proxmox host |

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

## Directory Structure

```
├── docs/                    # Documentation
├── reports/                 # Generated reports, logs
├── check-nfs-mounts.sh      # NFS mount verification script
├── nfs-mount-check.service  # Systemd service for NFS checks
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

### check-nfs-mounts.sh
Verifies NFS mounts are accessible and healthy.

### nfs-mount-check.service
Systemd service unit for automated NFS mount monitoring.

## Related Projects

| Project | Description |
|---------|-------------|
| [flatcar-homelab](../flatcar-homelab) | Flatcar Linux container host configuration |
| [lxc-to-docker-migration](../lxc-to-docker-migration) | Migration scripts for LXC to Docker |
| [proxmox-sr-iov](../proxmox-sr-iov) | SR-IOV configuration for Proxmox |
| [traefik](../traefik) | Traefik reverse proxy configuration |
| [minio-to-garage](../minio-to-garage) | MinIO to Garage S3 migration (planned) |
