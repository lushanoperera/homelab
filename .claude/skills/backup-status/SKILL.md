---
name: backup-status
description: Backup verification - PBS snapshots, Restic repos, S3 connectivity
allowed-tools: Bash, Read
---

# Backup Status Check

Verify backup health across PBS, Restic, and S3 storage.

## Backup Architecture

```
LXC/VM Data → PBS (192.168.100.187) → Retention policies
     ↓
NFS Data → Restic → MinIO S3 (192.168.200.210)
                        ↓
               (migrating to Garage 192.168.200.211)
```

## When to Use

- Verify backups are running
- Check backup freshness
- Before major changes
- Monthly backup audit

## Instructions

### Phase 1: Proxmox Backup Server (PBS)

Check PBS is accessible:

```bash
ssh root@192.168.100.187 'proxmox-backup-manager datastore list'
```

Check recent backups:

```bash
ssh root@192.168.100.187 'proxmox-backup-client list --repository local'
```

From Proxmox host, check backup schedule:

```bash
ssh root@192.168.100.38 'cat /etc/pve/jobs.cfg | grep -A5 vzdump'
```

Check last backup job:

```bash
ssh root@192.168.100.38 'tail -50 /var/log/vzdump/*.log | tail -30'
```

### Phase 2: PBS Storage Usage

```bash
ssh root@192.168.100.187 'proxmox-backup-manager datastore status'
```

Check garbage collection status:

```bash
ssh root@192.168.100.187 'proxmox-backup-manager gc-status'
```

### Phase 3: Restic Backups

Check latest Restic snapshots (from host running restic):

```bash
# Set environment for MinIO
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
export RESTIC_REPOSITORY="s3:http://192.168.200.210:9000/restic"
export RESTIC_PASSWORD="your-restic-password"

restic snapshots --last 10
```

Check repository health:

```bash
restic check --read-data-subset=1%
```

### Phase 4: MinIO S3 Health

Check MinIO is accessible:

```bash
ssh root@192.168.100.254 'docker exec minio mc admin info local'
```

Or from any host with mc configured:

```bash
mc admin info minio
```

Check bucket sizes:

```bash
mc du minio/restic
mc du minio/nextcloud
```

### Phase 5: Garage S3 (if migrated)

Check Garage status:

```bash
ssh root@192.168.100.254 'docker exec garage garage status'
```

Check bucket info:

```bash
ssh root@192.168.100.254 'docker exec garage garage bucket info restic'
```

### Phase 6: LXC Container Backups

List backups for specific container:

```bash
# From Proxmox host
ssh root@192.168.100.38 'pvesh get /nodes/winston/storage/pbs/content --vmid 101'
```

Check backup schedule:

```bash
ssh root@192.168.100.38 'pvesh get /cluster/backup'
```

## Backup Freshness Thresholds

| Backup Type  | Warning  | Critical  |
| ------------ | -------- | --------- |
| PBS VMs/LXCs | > 1 day  | > 3 days  |
| Restic NFS   | > 1 day  | > 7 days  |
| MinIO data   | > 1 week | > 1 month |

## Troubleshooting

### PBS Connection Failed

Check PBS service:

```bash
ssh root@192.168.100.187 'systemctl status proxmox-backup.service'
```

### Restic Errors

Check for lock files:

```bash
restic unlock
```

Check repository:

```bash
restic check
```

### MinIO Connection Failed

Check container:

```bash
ssh root@192.168.100.254 'docker ps | grep minio'
ssh root@192.168.100.254 'docker logs minio --tail 20'
```

## Output Format

```
## Backup Status Report

### PBS (Proxmox Backup Server)
| VM/LXC | Last Backup | Age | Status |
|--------|-------------|-----|--------|
| 101 (Nextcloud) | 2024-01-15 | 1d | OK |
| 103 (Immich) | 2024-01-15 | 1d | OK |

Storage: XX% used (XXX GB / XXX GB)

### Restic Backups
| Repository | Last Snapshot | Age | Status |
|------------|---------------|-----|--------|
| NFS Media | 2024-01-15 | 1d | OK |

### S3 Storage
| Endpoint | Status | Used |
|----------|--------|------|
| MinIO | Online | XXX GB |
| Garage | Online | XXX GB |

### Issues
1. [Issue if any]

### Recommendations
1. [Action if any]
```
