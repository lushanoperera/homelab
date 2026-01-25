# Restic Backup Configuration

## Overview

Restic backups run on LXC containers 101 (Nextcloud) and 103 (Immich) on winston, storing data to MinIO S3 buckets on the Storage LAN.

```
LXC Containers → Restic → MinIO (192.168.200.210:9000)
```

## Container 101: Nextcloud

| Setting | Value |
|---------|-------|
| Repository | `s3:http://192.168.200.210:9000/restic-nextcloud` |
| Schedule | Daily at 00:00 (cron) |
| Script | `/root/backup-nextcloud.sh` |
| Config | `/root/.restic-env` |

### Backup Scope

- `/mnt/ncdata/` - Main data directory
  - Config files (tagged: `config`)
  - User data (tagged: `user_*`)
  - App data (tagged: `appdata_*`)

### Retention Policy

| Type | Keep |
|------|------|
| Hourly | 24 |
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |

### Features

- Lock file prevents concurrent runs
- Nextcloud maintenance mode during backup
- Per-user segmented backups
- Weekly full integrity check (Sundays)
- Cleanup script: `/root/cleanup-snapshots.sh`

---

## Container 103: Immich

| Setting | Value |
|---------|-------|
| Repository | `s3:http://192.168.200.210:9000/restic-immich` |
| Schedule | Daily at 00:00 (cron) |
| Script | `/root/backup-immich.sh` |
| Config | `/root/.restic-env` |

### Backup Scope

**Phase 1: Database**
- PostgreSQL dump via `docker exec immich_postgres pg_dump`
- Stored to `/tmp/immich_backup_tmp/` then backed up

**Phase 2: Media**
- `/mnt/upload/library` (tagged: `upload_library`)
- `/mnt/upload/profile` (tagged: `upload_profile`)
- `/mnt/upload/encoded-video`
- `/mnt/upload/thumbs`
- `/mnt/upload/backups`

### Retention Policy

| Type | Keep |
|------|------|
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |

### Features

- Docker Compose stop/start during backup
- Two-phase backup (DB first, then media)
- Weekly full integrity check (Sundays)

---

## Common Configuration

### S3 Backend (MinIO)

| Setting | Value |
|---------|-------|
| Endpoint | `192.168.200.210:9000` |
| Network | Storage LAN (192.168.200.0/24) |
| Buckets | `restic-nextcloud`, `restic-immich` |

### Restic Settings

- **Compression**: `max`
- **Cache**: Disabled (`--no-cache`) for stability
- **Version**: 0.12.1

### Email Notifications

- **Provider**: Gmail via msmtp
- **Config**: `/root/.msmtprc`
- **Status**: Logging only (disabled to avoid Gmail rate limits)

---

## Manual Operations

```bash
# SSH to container
ssh root@192.168.100.38
pct exec 101 -- bash  # Nextcloud
pct exec 103 -- bash  # Immich

# Inside container, load environment
source /root/.restic-env

# List snapshots
restic snapshots

# Check repository integrity
restic check

# Unlock stuck repository
restic unlock

# Manual cleanup (Nextcloud)
/root/cleanup-snapshots.sh
```

---

## Planned Migration

MinIO → Garage (see `minio-to-garage` project)
