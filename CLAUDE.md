# CLAUDE.md - Homelab Infrastructure

Consolidated homelab repository covering Proxmox hosts, VMs, networking, storage, and automation.

## Infrastructure Overview

### Network Architecture

| Network | Subnet | Purpose |
|---------|--------|---------|
| Infra VLAN | 192.168.100.0/24 | Management, services, general traffic |
| Storage LAN | 192.168.200.0/24 | Dedicated storage traffic (NFS, backups) |
| DMZ VLAN | 192.168.7.0/24 | Internet-facing services (Traefik) |

### Hosts & VMs

| Host/VM | IP | Role |
|---------|-----|------|
| winston | 192.168.100.38 / .200.38 | Primary Proxmox VE host |
| reginald | 192.168.100.4 / .200.4 | Secondary Proxmox VE host (NFS source) |
| flatcar-media (VM 100) | 192.168.100.100 | Media stack (Sonarr, Radarr, qBittorrent) |
| PBS | 192.168.100.187 | Proxmox Backup Server (on QNAP) |
| QNAP NAS | 192.168.100.254 / .200.254 | Storage (MinIO S3, NFS) |

### Services by Location

**Flatcar VM 100** (`ssh core@192.168.100.100`):
- Media stack: nordlynx, prowlarr, qbittorrent, sabnzbd, radarr, sonarr, lidarr, bazarr, overseerr, tautulli
- Traefik (DMZ IP: 192.168.7.119)
- CrowdSec + Bouncer
- Cloudflared tunnel

**LXC Containers (winston)**:
- 101: Nextcloud
- 103: Immich
- 104: WireGuard
- 105: Plex

## Directory Structure

```
homelab/
├── docs/                    # Documentation
│   ├── sr-iov/              # GPU SR-IOV guides
│   ├── migrations/          # Migration docs (LXC→Docker, MinIO→Garage)
│   └── guides/              # Deployment guides
├── hosts/                   # Proxmox host configs (winston, reginald)
├── vms/
│   ├── flatcar-media/       # VM 100 - Media stack
│   │   ├── butane/          # Butane configs (.bu)
│   │   ├── ignition/        # Compiled Ignition (.ign)
│   │   └── docker-compose.yml
│   └── pbs/                 # Proxmox Backup Server
├── networking/
│   ├── traefik/             # External reverse proxy + CrowdSec
│   └── cloudflare-tunnel/   # Cloudflare tunnel config
├── storage/
│   ├── minio/               # Current S3 storage
│   ├── garage/              # Target S3 storage (migration)
│   └── nfs/                 # NFS configuration
├── scripts/
│   ├── hosts/               # Host management scripts
│   ├── vms/                 # VM deployment scripts
│   ├── migrations/          # Migration scripts
│   └── monitoring/          # GPU monitoring scripts
├── automation/
│   ├── ansible/             # Ansible playbooks
│   └── terraform/           # Terraform IaC
├── systemd/                 # Systemd units
└── tools/
    └── bitwarden-manager/   # Credential management UI
```

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

# VPN verification
ssh core@192.168.100.100 'docker exec nordlynx curl -s https://ipinfo.io/ip'
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

### Traefik & CrowdSec

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

| Service | Hostname | Backend |
|---------|----------|---------|
| Immich | immich.lushanoperera.com | 192.168.100.103:2283 |
| Nextcloud | nextcloud.lushanoperera.com | 192.168.100.101:11000 |
| Traefik Dashboard | traefik.lushanoperera.com | 192.168.7.119:8080 |
| CrowdSec Dashboard | crowdsec.lushanoperera.com | crowdsec-metabase:3001 |

## Storage Architecture

```
LXC data → NFS (reginald) → CacheFS (winston) → Restic → MinIO S3
                                                           ↓
                                                     (migrating to Garage)
```

| Service | IP | Ports |
|---------|-----|-------|
| MinIO | 192.168.200.210 | 9000 (S3), 9001 (Console) |
| Garage | 192.168.200.211 | 3900 (S3), 3902 (Web), 3903 (Admin) |

## Lessons Learned

### Flatcar-Specific
| Issue | Solution |
|-------|----------|
| Network interface naming | Always use `eth0` (not `ens18`) in Butane configs |
| Ignition only applies once | Manual fixes needed for post-boot changes |
| Docker Compose location | `/opt/bin/docker-compose` (standalone binary) |

### GPU SR-IOV
Intel iGPU SR-IOV passthrough to Flatcar **not working** - guest requires patched `i915-sriov-dkms` driver. See `docs/sr-iov/` for details.

### AWS SDK (Garage)
```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
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
