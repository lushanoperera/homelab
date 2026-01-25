# Proxmox Homelab

Scripts and configuration for managing Proxmox VE hosts.

## Hosts

| Host | IP | Description |
|------|------|-------------|
| winston | 192.168.100.38 | Primary Proxmox host |
| reginald | 192.168.100.4 | Secondary Proxmox host |

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
