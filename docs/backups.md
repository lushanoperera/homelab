# Backup Configuration

## Overview

The homelab uses multiple backup strategies:

| Layer | Tool | Target | Scope |
|-------|------|--------|-------|
| VM/Container | PBS | QNAP NAS | All VMs and LXC containers |
| Application | Restic | MinIO S3 | Nextcloud, Immich data |
| Application | (not configured) | — | Vaultwarden (manual only) |

```
┌─────────────────────────────────────────────────────────────┐
│                     Backup Architecture                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  winston / reginald                                          │
│  ┌──────────────┐    PBS     ┌─────────────────────────┐    │
│  │ VMs & LXCs   │ ─────────→ │ PBS (192.168.100.187)   │    │
│  └──────────────┘            │ on QNAP TS-251+         │    │
│                              └─────────────────────────┘    │
│                                                              │
│  LXC 101, 103                                               │
│  ┌──────────────┐   Restic   ┌─────────────────────────┐    │
│  │ App Data     │ ─────────→ │ MinIO (192.168.200.210) │    │
│  └──────────────┘            │ on QNAP TS-251+         │    │
│                              └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## PBS (Proxmox Backup Server)

| Setting | Value |
|---------|-------|
| Server | 192.168.100.187 |
| Location | VM on QNAP TS-251+ |
| Scope | All VMs and LXC containers |

PBS provides VM-level backups with deduplication and integrity verification.

---

## Restic Backups (Application-Level)

### Container 101: Nextcloud

| Setting | Value |
|---------|-------|
| Repository | `s3:http://192.168.200.210:9000/restic-nextcloud` |
| Schedule | Daily at 00:00 (cron) |
| Script | `/root/backup-nextcloud.sh` |
| Config | `/root/.restic-env` |

**Backup Scope:**
- `/mnt/ncdata/` - Config, user data, app data

**Retention:** 24 hourly, 7 daily, 4 weekly, 6 monthly

**Features:**
- Lock file prevents concurrent runs
- Nextcloud maintenance mode during backup
- Per-user segmented backups
- Weekly full integrity check (Sundays)

---

### Container 103: Immich

| Setting | Value |
|---------|-------|
| Repository | `s3:http://192.168.200.210:9000/restic-immich` |
| Schedule | Daily at 00:00 (cron) |
| Script | `/root/backup-immich.sh` |
| Config | `/root/.restic-env` |

**Backup Scope:**
- PostgreSQL dump (Phase 1)
- `/mnt/upload/` - Media, profiles, thumbs (Phase 2)

**Retention:** 7 daily, 4 weekly, 6 monthly

**Features:**
- Docker Compose stop/start during backup
- Two-phase backup (DB first, then media)
- Weekly full integrity check (Sundays)

---

### MinIO S3 Backend

| Setting | Value |
|---------|-------|
| Endpoint | `192.168.200.210:9000` |
| Network | Storage LAN (192.168.200.0/24) |
| Buckets | `restic-nextcloud`, `restic-immich` |

**Restic Settings:**
- Compression: `max`
- Cache: Disabled (`--no-cache`)
- Version: 0.12.1

**Planned:** MinIO → Garage migration (see `minio-to-garage` project)

---

## Flatcar VM: Vaultwarden

| Setting | Value |
|---------|-------|
| VM IP | 10.21.21.104 |
| SSH | `ssh core@10.21.21.104` |
| Data Path | `/opt/vaultwarden/data/` |
| Database | SQLite (`db.sqlite3`) |

### Current Backup Status

| Method | Status |
|--------|--------|
| PBS (VM-level) | ✅ Configured |
| File-level (Restic/rclone) | ❌ Not configured |

**PBS** backs up the entire Flatcar VM, which includes Vaultwarden.

**File-level backup** is not currently automated. Only manual tar command exists:

```bash
ssh core@10.21.21.104 "sudo tar -czf /tmp/vaultwarden-backup.tar.gz -C /opt/vaultwarden data"
```

### Critical Data to Back Up

| Path | Content |
|------|---------|
| `/opt/vaultwarden/data/` | Database, attachments |
| `/opt/vaultwarden/.env` | SMTP credentials |
| `/opt/infrastructure/.env` | Cloudflare tunnel token |
| `/opt/crowdsec/.env` | CrowdSec API key |

### Other Services on Flatcar

| Service | Data Location |
|---------|---------------|
| Traefik | Volume: `traefik_logs` |
| Cloudflared | Token in `.env` |
| CrowdSec | `/opt/crowdsec/db/` |
| n8n | Named volumes |
| Portainer | Named volume |
| NPM | Docker container (internal proxy) |

---

## Manual Operations

### Restic (LXC containers)

```bash
# SSH to container
ssh root@192.168.100.38
pct exec 101 -- bash  # Nextcloud
pct exec 103 -- bash  # Immich

# Load environment
source /root/.restic-env

# Common commands
restic snapshots      # List snapshots
restic check          # Verify integrity
restic unlock         # Unlock stuck repo
```

### Vaultwarden (Flatcar)

```bash
# Manual backup
ssh core@10.21.21.104 "sudo tar -czf /tmp/vaultwarden-backup.tar.gz -C /opt/vaultwarden data"

# Copy backup locally
scp core@10.21.21.104:/tmp/vaultwarden-backup.tar.gz .

# Check data directory
ssh core@10.21.21.104 "ls -lah /opt/vaultwarden/data/"
```

---

## Backup Summary

| Service | PBS | Restic | File-level |
|---------|-----|--------|------------|
| Nextcloud (101) | ✅ | ✅ Daily | — |
| Immich (103) | ✅ | ✅ Daily | — |
| Vaultwarden | ✅ (VM) | ❌ | ❌ Manual |
| WireGuard (104) | ✅ | — | — |
| Plex (105) | ✅ | — | — |

**Recommendation:** Consider adding automated file-level backup for Vaultwarden (Restic to MinIO or rclone to ZFS on reginald) for faster granular recovery.
