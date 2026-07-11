# Backup Configuration

## Overview

The homelab uses multiple backup strategies:

| Layer        | Tool            | Target    | Scope                              |
| ------------ | --------------- | --------- | ---------------------------------- |
| VM/Container | PBS             | QNAP NAS  | All VMs and LXC containers         |
| Application  | Restic          | MinIO S3  | Nextcloud, Immich data             |
| Application  | tar + rsync     | VM-local  | Vaultwarden (no offsite — flagged) |
| Cross-site   | PBS sync (push) | nwlab PBS | Offsite copy to nwlab              |

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Backup Architecture                            │
├──────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  winston / reginald            PBS (192.168.100.187)                   │
│  ┌──────────────┐    vzdump   ┌──────────────────────┐                │
│  │ VMs & LXCs   │ ─────────→ │ pbs-backups          │                │
│  └──────────────┘             │ (homelab backups)    │                │
│                               ├──────────────────────┤   push (WG)    │
│                               │ nwlab-backup (NEW)   │ ←──────────── │
│                               │ (nwlab offsite copy) │   from nwlab   │
│                               └──────┬───────────────┘                │
│                                      │ push (WG)                       │
│                                      ▼                                 │
│                               nwlab PBS (10.0.0.6)                     │
│                               homelab-sync datastore                   │
│                               (receives homelab push)                  │
│                                                                        │
│  Flatcar VM 100 (systemd timers)                                       │
│  ┌──────────────┐   Restic   ┌─────────────────────────┐              │
│  │ App Data     │ ─────────→ │ MinIO (192.168.200.210) │              │
│  └──────────────┘            │ on QNAP TS-251+         │              │
│                              └─────────────────────────┘              │
└──────────────────────────────────────────────────────────────────────┘
```

---

## PBS (Proxmox Backup Server)

| Setting  | Value                              |
| -------- | ---------------------------------- |
| Server   | 192.168.100.187                    |
| Location | VM on QNAP TS-251+ (4 vCPUs, 2 GB) |
| Scope    | All VMs and LXC containers         |

PBS provides VM-level backups with deduplication and integrity verification.

### PBS Datastores

| Datastore             | Storage            | Purpose                         | Content                              |
| --------------------- | ------------------ | ------------------------------- | ------------------------------------ |
| `pbs-backups`         | local vdb (755 GB) | Homelab local backups           | All local VMs and LXC containers     |
| `nwlab-backup`        | local vdc (246 GB) | nwlab offsite copies (incoming) | nwlab ct/100, ct/101, ct/102, vm/104 |
| `pbs-backups-legacy`  | NFS (read-only)    | Historical restores             | Pre-2026-04-15 snapshots             |
| `nwlab-backup-legacy` | NFS (read-only)    | Historical restores             | Pre-2026-04-15 snapshots             |

> Legacy datastores kept for historical restores until ~2026-07, then removed along with NFS exports.

### Scheduled Backup Jobs

| Job ID               | Node     | VMIDs         | Schedule | Retention                                 |
| -------------------- | -------- | ------------- | -------- | ----------------------------------------- |
| dd9d470e             | winston  | 104, 105, 106 | 04:00    | keep-last=3, daily=7, weekly=4, monthly=2 |
| 92d5a969             | winston  | 100, 102      | 05:00    | (same)                                    |
| backup-631cad5e-fea6 | reginald | 120, 123      | 08:00    | (same)                                    |

All jobs: storage `pbs-backupnas`, compress `zstd`, mode `snapshot`, mail on failure.
(LXC 101/103 were folded into VM 100 as Docker stacks and dropped from the winston jobs;
reginald's job picked up LXC 123 Samba. Verified live 2026-07-11.)

**Backup gap (Oct 2025 – Mar 2026):** Winston vzdump jobs were lost during the
October 2025 bare-metal rebuild (`/etc/pve/jobs.cfg` not preserved in pmxcfs).
Jobs were recreated on 2026-03-01. All VMIDs now have fresh backups.

### Scheduled Verify Jobs

| Job ID           | Datastore    | Schedule   | Outdated After | Ignore Verified |
| ---------------- | ------------ | ---------- | -------------- | --------------- |
| v-b23a385a-7b31  | pbs-backups  | daily 03:00 | 30 days        | yes             |
| v-nwlab-weekly   | nwlab-backup | sat 02:30   | 30 days        | yes             |

Both jobs skip snapshots already verified within the outdated-after window.
Verify runs before backup jobs (04:00/05:00/08:00) to avoid I/O contention.

### Known Issues

**~~PBS Storage LAN intermittent timeouts~~ (resolved 2026-04-15)**: Previously,
pvestatd logged frequent `read timeout` errors caused by NFS-backed datastores
walking `.chunks/` over the network stack. Resolved by migrating to local virtio
disks — see [`docs/migrations/pbs-nfs-to-local.md`](./migrations/pbs-nfs-to-local.md).

**PBS mail notifications**: `mail-to-root` errors (`no recipients`) on backup
completion. Pre-existing, not blocking — backup jobs complete successfully.

### Cross-Site Sync (nwlab ↔ homelab)

Both sites push backups to each other for offsite redundancy:

| Direction       | Source                | Target                 | Schedule | Via                      |
| --------------- | --------------------- | ---------------------- | -------- | ------------------------ |
| nwlab → homelab | nwlab `home-backup`   | homelab `nwlab-backup` | 04:00    | WireGuard (10.0.0.6)     |
| homelab → nwlab | homelab `pbs-backups` | nwlab `homelab-sync`   | 21:00    | WireGuard (10.21.21.101) |

**Sync job details**:

- Homelab push job ID: `s-24a0eca7-78f5`
- Remote: `pbs-nwdesigns` (10.21.21.101)
- Direction: push, remove-vanished: false

**WireGuard connectivity**: Homelab PBS reaches nwlab via WG overlay. nwlab PBS LXC at `10.21.21.101`, reachable as `10.0.0.6` sees it through the WG tunnel. The same WG tunnel (`wg-nwlab` on winston) also carries PDM management traffic to nwlab-thinkpad (10.21.21.99).

**Storage**: `nwlab-backup` datastore on local virtio disk vdc (`/mnt/pbs-local/nwlab`, 246 GB). Legacy NFS-backed datastore `nwlab-backup-legacy` retained at `/mnt/nwlab-backup` (read-only) until ~2026-07.

---

## Restic Backups (Application-Level)

Restic runs on **Flatcar VM 100** (LXC 101/103 no longer exist — their apps run as Docker
stacks on the VM). Scripts deploy to `/opt/bin/`; env files are root:root 0600.

### Nextcloud (Flatcar VM 100)

| Setting    | Value                                                  |
| ---------- | ------------------------------------------------------ |
| Repository | `s3:http://192.168.200.210:9000/restic-nextcloud`      |
| Schedule   | Daily at 00:00 (systemd timer `nextcloud-backup.timer`)|
| Script     | `/opt/bin/backup-nextcloud.sh` (repo: `apps/nextcloud/backup-nextcloud.sh`) |
| Config     | `/srv/docker/nextcloud/.restic-env`                    |
| Units      | `/etc/systemd/system/nextcloud-backup.{service,timer}` |

**Backup Scope:**

- `/mnt/ncdata/` - Config, user data, app data

**Retention:** 24 hourly, 7 daily, 4 weekly, 6 monthly

**Features:**

- Lock file prevents concurrent runs
- Nextcloud maintenance mode during backup
- Per-user segmented backups
- Weekly full integrity check (Sundays)

---

### Immich (Flatcar VM 100)

| Setting    | Value                                               |
| ---------- | --------------------------------------------------- |
| Repository | `s3:http://192.168.200.210:9000/restic-immich`      |
| Schedule   | Daily at 00:00 (systemd timer `immich-backup.timer`)|
| Script     | `/opt/bin/backup-immich.sh` (repo: `apps/immich/backup-immich.sh`) |
| Config     | `/srv/docker/immich/.restic-env`                    |
| Units      | `/etc/systemd/system/immich-backup.{service,timer}` |

**Backup Scope:**

- PostgreSQL dump (Phase 1)
- `/mnt/upload/` - Media, profiles, thumbs (Phase 2)

**Retention:** 7 daily, 4 weekly, 6 monthly

**Features:**

- Docker Compose stop/start during backup
- Two-phase backup (DB first, then media)
- Weekly full integrity check (Sundays)

**NFS scope note:** vzdump backs up the VM 100 disk only. NFS-mounted data (`/mnt/immich/*`, `/mnt/ncdata`) lives on reginald ZFS and is covered by Restic, not vzdump. This is by design.

**Historical gap:** Restic backups had an ~11-month gap (2025-03-16 to 2026-02-27) due to a failed backup approach transition (per-PG-subdirectory → pg_dump). The backup script was redesigned and re-enabled in February 2026. Current approach is healthy.

---

### Vaultwarden (Flatcar VM 100)

| Setting  | Value                                               |
| -------- | --------------------------------------------------- |
| Method   | tar + rsync to `$BACKUP_DIR/latest/` (file-level)   |
| Schedule | Daily at ~03:00 (systemd timer `vaultwarden-backup.timer`) |
| Script   | `/opt/vaultwarden/backup.sh` (repo: `apps/vaultwarden/backup.sh`) |

**⚠ No offsite copy** — this backup stays on VM 100 (covered only indirectly by the VM's
vzdump). Not restic, no S3. Known gap, tracked as a follow-up.

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

**Planned:** MinIO → RustFS migration — see
[`docs/migrations/minio-to-rustfs.md`](./migrations/minio-to-rustfs.md). MinIO
stays online read-only for 6 months post-cutover as rollback buffer. The older
Garage plan (`docs/migrations/minio-to-garage.md`) is archived.

---

## Manual Operations

### Restic (Flatcar VM 100)

```bash
ssh core@192.168.100.100

# Load environment (root-owned, needs sudo)
sudo bash -c 'source /srv/docker/nextcloud/.restic-env; /opt/bin/restic snapshots'
sudo bash -c 'source /srv/docker/immich/.restic-env;    /opt/bin/restic snapshots'

# Common commands (after sourcing the env)
restic snapshots      # List snapshots
restic check          # Verify integrity
restic unlock         # Unlock stuck repo
```

---

## Backup Summary

| Service                  | PBS | Restic   | File-level      |
| ------------------------ | --- | -------- | --------------- |
| flatcar-media (VM 100)   | ✅  | —        | —               |
| Nextcloud (on VM 100)    | via VM | ✅ Daily | —            |
| Immich (on VM 100)       | via VM | ✅ Daily | —            |
| Vaultwarden (on VM 100)  | via VM | —     | ✅ Daily (local) |
| homeassistant (VM 102)   | ✅  | —        | —               |
| WireGuard (104)          | ✅  | —        | —               |
| Plex (105)               | ✅  | —        | —               |
| PDM (106)                | ✅  | —        | —               |
| Technitium DNS (120)     | ✅  | —        | —               |
| Samba (123)              | ✅  | —        | —               |
