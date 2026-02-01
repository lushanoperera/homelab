# Homelab Infrastructure

Consolidated infrastructure-as-code repository for a Proxmox-based homelab environment.

## Overview

This repository contains configurations, scripts, and documentation for:

- **Proxmox VE hosts** (winston, reginald)
- **Flatcar Container Linux VMs** with Docker stacks
- **Reverse proxy** (Traefik) with security hardening (CrowdSec)
- **S3 storage** (MinIO → Garage migration)
- **Infrastructure automation** (Ansible, Terraform)

## Architecture

```
                    Internet
                        │
                   Cloudflare
                        │
              ┌─────────┴─────────┐
              │   Traefik (DMZ)   │
              │  192.168.7.119    │
              └─────────┬─────────┘
                        │
     ┌──────────────────┼──────────────────┐
     │                  │                  │
┌────┴────┐       ┌─────┴─────┐      ┌─────┴─────┐
│ winston │       │  Flatcar  │      │ reginald  │
│ .100.38 │       │  VM 100   │      │  .100.4   │
│         │       │  .100.100 │      │           │
│ LXC:    │       │           │      │ NFS       │
│ - Nextcloud     │ Docker:   │      │ Server    │
│ - Immich │      │ - Media   │      └───────────┘
│ - Plex   │      │ - Traefik │
│ - WireGuard     │ - CrowdSec│
└─────────┘       └───────────┘
     │                  │
     └────────┬─────────┘
              │
      ┌───────┴───────┐
      │   QNAP NAS    │
      │   .100.254    │
      │               │
      │ - MinIO S3    │
      │ - PBS VM      │
      └───────────────┘
```

## Quick Start

### SSH Access

```bash
ssh root@192.168.100.38   # winston (Proxmox)
ssh root@192.168.100.4    # reginald (Proxmox)
ssh core@192.168.100.100  # Flatcar VM
```

### Deploy a new Flatcar VM

```bash
./scripts/vms/deploy-flatcar-vm.sh --vm-id 105 --vm-ip 10.21.21.105
```

### Check container status

```bash
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}"'
```

## Directory Structure

```
├── docs/                    # Documentation
│   ├── sr-iov/              # GPU SR-IOV guides
│   ├── migrations/          # Migration docs
│   └── guides/              # Deployment guides
├── hosts/                   # Proxmox host configs
├── vms/
│   ├── flatcar-media/       # Media stack VM
│   └── pbs/                 # Backup server
├── networking/
│   ├── traefik/             # Reverse proxy
│   └── cloudflare-tunnel/   # Tunnel config
├── storage/
│   ├── minio/               # Current S3
│   ├── garage/              # Target S3
│   └── nfs/                 # NFS config
├── scripts/                 # Automation scripts
├── automation/
│   ├── ansible/             # Playbooks
│   └── terraform/           # IaC
├── systemd/                 # Systemd units
└── tools/                   # Utilities
```

## Networks

| Network     | Subnet           | Purpose              |
| ----------- | ---------------- | -------------------- |
| Infra VLAN  | 192.168.100.0/24 | Management, services |
| Storage LAN | 192.168.200.0/24 | NFS, backups         |
| DMZ VLAN    | 192.168.7.0/24   | Internet-facing      |

## Services

### Media Stack (Flatcar VM 100)

- qBittorrent, SABnzbd (downloaders)
- Radarr, Sonarr, Lidarr (media managers)
- Prowlarr (indexer)
- Overseerr (requests)
- Tautulli (Plex analytics)
- NordLynx (VPN)

### LXC Containers (winston)

- Nextcloud (101)
- Immich (103)
- WireGuard (104)
- Plex (105)

### Storage

- MinIO S3 (192.168.200.210) - current
- Garage S3 (192.168.200.211) - migration target
- Proxmox Backup Server (192.168.100.187)

## Hardware

### Winston (Primary Compute)

| Component | Specification                                   |
| --------- | ----------------------------------------------- |
| Chassis   | Minisforum MS-01                                |
| CPU       | Intel i9-13900H (14C/20T, up to 5.2 GHz)        |
| Features  | SR-IOV GPU passthrough, Quick Sync HW transcode |
| Thermal   | powersave governor, thermald                    |

### Reginald (Storage Server)

| Component | Specification                     |
| --------- | --------------------------------- |
| Chassis   | Zimaboard 832                     |
| CPU       | Intel Celeron N3450 (4C/4T)       |
| Storage   | 7x SSD in ZFS RAIDZ2 pool         |
| Role      | NFS server for LXC container data |

### QNAP NAS (TS-251+)

| Service | IP              | Description           |
| ------- | --------------- | --------------------- |
| PBS VM  | 192.168.100.187 | Proxmox Backup Server |
| MinIO   | 192.168.200.210 | S3-compatible storage |

## Documentation

- [Backups](docs/backups.md)
- [Thermal Management](docs/thermal-management.md)
- [GPU SR-IOV Guide](docs/sr-iov/igpu-guide.md)
- [LXC to Docker Migration](docs/migrations/lxc-to-docker.md)
- [MinIO to Garage Migration](docs/migrations/minio-to-garage.md)
- [GPU Passthrough](docs/guides/gpu-passthrough.md)
- [Flatcar Automation](docs/guides/flatcar-automation.md)
