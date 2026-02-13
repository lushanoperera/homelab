# Backup Configuration

## Overview

The homelab uses multiple backup strategies:

| Layer        | Tool             | Target   | Scope                      |
| ------------ | ---------------- | -------- | -------------------------- |
| VM/Container | PBS              | QNAP NAS | All VMs and LXC containers |
| Application  | Restic           | MinIO S3 | Nextcloud, Immich data     |

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

| Setting  | Value                      |
| -------- | -------------------------- |
| Server   | 192.168.100.187            |
| Location | VM on QNAP TS-251+         |
| Scope    | All VMs and LXC containers |

PBS provides VM-level backups with deduplication and integrity verification.

---

## Restic Backups (Application-Level)

### Container 101: Nextcloud

| Setting    | Value                                             |
| ---------- | ------------------------------------------------- |
| Repository | `s3:http://192.168.200.210:9000/restic-nextcloud` |
| Schedule   | Daily at 00:00 (cron)                             |
| Script     | `/root/backup-nextcloud.sh`                       |
| Config     | `/root/.restic-env`                               |

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

| Setting    | Value                                          |
| ---------- | ---------------------------------------------- |
| Repository | `s3:http://192.168.200.210:9000/restic-immich` |
| Schedule   | Daily at 00:00 (cron)                          |
| Script     | `/root/backup-immich.sh`                       |
| Config     | `/root/.restic-env`                            |

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

| Setting  | Value                               |
| -------- | ----------------------------------- |
| Endpoint | `192.168.200.210:9000`              |
| Network  | Storage LAN (192.168.200.0/24)      |
| Buckets  | `restic-nextcloud`, `restic-immich` |

**Restic Settings:**

- Compression: `max`
- Cache: Disabled (`--no-cache`)
- Version: 0.12.1

**Planned:** MinIO → Garage migration (see `minio-to-garage` project)

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

---

## Backup Summary

| Service              | PBS | Restic   | File-level |
| -------------------- | --- | -------- | ---------- |
| flatcar-media (100)  | ✅  | —        | —          |
| Nextcloud (101)      | ✅  | ✅ Daily | —          |
| homeassistant (102)  | ✅  | —        | —          |
| Immich (103)         | ✅  | ✅ Daily | —          |
| WireGuard (104)      | ✅  | —        | —          |
| Plex (105)           | ✅  | —        | —          |
