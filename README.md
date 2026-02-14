# Homelab Infrastructure

Consolidated infrastructure-as-code repository for a Proxmox-based homelab environment.

## Overview

This repository contains configurations, scripts, and documentation for:

- **Proxmox VE hosts** (winston, reginald)
- **Flatcar Container Linux VMs** with Docker stacks
- **DNS** (Technitium 3-node cluster)
- **Reverse proxies** — Caddy (internal LAN) + Traefik (public DMZ) with CrowdSec
- **S3 storage** (MinIO → Garage migration)
- **Infrastructure automation** (Ansible, Terraform)

## Architecture

```
                    Internet
                        │
                   Cloudflare
                        │
           ┌────────────┴────────────┐
           │  UCG-Fiber (Gateway)    │  WiFi: 2x U7-Pro-Wall
           │  192.168.1.1            │  (.1.77, .1.226)
           │  UniFi OS 10.1          │
           │  7 VLANs managed        │
           └────────────┬────────────┘
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
│ VM 102: │       │           │      │ NFS       │
│ - HA    │       │ Docker:   │      │ Server    │
│         │       │ - Media   │      │           │
│ LXC:    │       │ - Caddy   │      │ LXC 120:  │
│ - Nextcloud     │ - Traefik │      │ - DNS     │
│ - Immich │      │ - CrowdSec│      │           │
│ - Plex   │      │ - DNS     │      │ LXC 123:  │
│ - WireGuard     └───────────┘      │ - Samba   │
└─────────┘                          └───────────┘
     │                  │                  │
     └────────┬─────────┴──────────────────┘
              │
      ┌───────┴───────┐
      │   QNAP NAS    │
      │   .100.254    │
      │               │
      │ - MinIO S3    │
      │ - PBS VM      │
      │ - DNS (primary)│
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
├── dns/
│   └── technitium/          # DNS cluster (QNAP primary compose)
├── docs/                    # Documentation
│   ├── sr-iov/              # GPU SR-IOV guides
│   ├── migrations/          # Migration docs
│   └── guides/              # Deployment guides
├── hosts/                   # Proxmox host configs
├── vms/
│   ├── flatcar-media/       # Media stack VM
│   └── pbs/                 # Backup server
├── networking/
│   ├── caddy/               # Internal reverse proxy (*.home.disconnesso.com)
│   ├── traefik/             # Public reverse proxy + CrowdSec
│   └── cloudflare-tunnel/   # Tunnel config
├── storage/
│   ├── minio/               # Current S3
│   ├── garage/              # Target S3
│   └── nfs/                 # NFS config
├── scripts/                 # Automation & network discovery
├── automation/
│   ├── ansible/             # Playbooks
│   └── terraform/           # IaC
├── systemd/                 # Systemd units
└── tools/                   # Utilities
```

## Networks

| Network     | Subnet            | VLAN | Purpose                    |
| ----------- | ----------------- | ---- | -------------------------- |
| Management  | 192.168.1.0/24    | 1    | Gateway, APs, defaults     |
| Trusted     | 192.168.2.0/24    | 2    | Personal devices           |
| Guests      | 192.168.3.0/24    | 3    | Guest WiFi                 |
| IoT         | 192.168.4.0/24    | 4    | Smart home, cameras        |
| Multimedia  | 192.168.5.0/24    | 5    | Sonos, Sky Q, media        |
| Infra       | 192.168.100.0/20  | 100  | Proxmox, VMs, services     |
| DMZ         | 192.168.7.0/24    | 7    | Internet-facing (Traefik)  |
| Storage LAN | 192.168.200.0/24  | —    | NFS, backups (not on UFG)  |

## Services

### DNS (Technitium Cluster)

3-node Technitium DNS cluster with native zone replication.

| Node     | IP              | Role      | Web UI              |
| -------- | --------------- | --------- | ------------------- |
| QNAP     | 192.168.100.254 | Primary   | :5380               |
| Flatcar  | 192.168.100.100 | Secondary | :5380               |
| Reginald | 192.168.100.120 | Secondary | :5380               |

### Media Stack (Flatcar VM 100)

- qBittorrent, SABnzbd (downloaders)
- Radarr, Sonarr, Lidarr (media managers)
- Prowlarr (indexer)
- Overseerr (requests)
- Tautulli (Plex analytics)
- Gluetun (ProtonVPN)

### VMs (winston)

| VMID | Name          | IP              | Purpose        |
| ---- | ------------- | --------------- | -------------- |
| 100  | flatcar-media | 192.168.100.100 | Media stack    |
| 102  | homeassistant | .100.102 / .4.102 / .5.102 | Home Assistant (multi-VLAN) |

### LXC Containers (winston)

| CTID | Service   | IP              |
| ---- | --------- | --------------- |
| 101  | Nextcloud | 192.168.100.101 |
| 103  | Immich    | 192.168.100.103 |
| 104  | WireGuard | 192.168.100.104 |
| 105  | Plex      | 192.168.100.105 |

### LXC Containers (reginald)

| VMID | Service        | IP              |
| ---- | -------------- | --------------- |
| 120  | Technitium DNS | 192.168.100.120 |
| 123  | Samba          | 192.168.100.123 |

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
| RAM       | 32 GB                                           |
| Proxmox   | 9.1.4                                           |
| Features  | SR-IOV GPU passthrough, Quick Sync HW transcode |
| Thermal   | powersave governor, thermald                    |

### Reginald (Storage Server)

| Component | Specification                     |
| --------- | --------------------------------- |
| Chassis   | Zimaboard 832                     |
| CPU       | Intel Celeron N3450 (4C/4T)       |
| RAM       | 8 GB                              |
| Proxmox   | 9.1.5                             |
| Storage   | 7x SSD in ZFS RAIDZ2 (10.1 TB)   |
| Role      | NFS server for LXC container data |

### QNAP NAS (TS-251+)

| Service     | IP              | Description              |
| ----------- | --------------- | ------------------------ |
| Technitium  | 192.168.100.254 | DNS primary (port 53)    |
| PBS VM      | 192.168.100.187 | Proxmox Backup Server    |
| MinIO       | 192.168.200.210 | S3-compatible storage    |

## Documentation

- [Backups](docs/backups.md)
- [Thermal Management](docs/thermal-management.md)
- [GPU SR-IOV Guide](docs/sr-iov/igpu-guide.md)
- [LXC to Docker Migration](docs/migrations/lxc-to-docker.md)
- [MinIO to Garage Migration](docs/migrations/minio-to-garage.md)
- [GPU Passthrough](docs/guides/gpu-passthrough.md)
- [Flatcar Automation](docs/guides/flatcar-automation.md)
