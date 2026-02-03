---
name: nfs-check
description: NFS mount verification across Flatcar, Winston, and Reginald
allowed-tools: Bash, Read
---

# NFS Mount Check

Verify NFS storage is healthy across all hosts.

## Architecture

```
Reginald (Source) → Winston (NFS Client) → Flatcar VM (NFS Client)
  /media              /mnt/nfs_media          /mnt/media
```

## When to Use

- Media files not appearing in Sonarr/Radarr/Plex
- Stale file handle errors
- After storage maintenance
- Write permission issues

## Instructions

### Phase 1: Source Health (Reginald)

Check ZFS is mounted correctly:

```bash
ssh root@192.168.100.4 'zfs list -o name,mountpoint,mounted | grep media'
```

All should show `mounted: yes` with correct mountpoints.

Check NFS exports:

```bash
ssh root@192.168.100.4 'exportfs -v | grep media'
```

Should show `/media` with `crossmnt` option.

### Phase 2: Winston NFS Mount

Check mount status:

```bash
ssh root@192.168.100.38 'mount | grep nfs_media'
ssh root@192.168.100.38 'df -h /mnt/nfs_media'
```

Test read access:

```bash
ssh root@192.168.100.38 'ls /mnt/nfs_media | head'
```

### Phase 3: Flatcar VM Mount

Check systemd mount unit:

```bash
ssh core@192.168.100.100 'systemctl status mnt-media.mount --no-pager'
```

Check mount is present:

```bash
ssh core@192.168.100.100 'mount | grep /mnt/media'
ssh core@192.168.100.100 'df -h /mnt/media'
```

### Phase 4: Write Test

Test write permissions through the stack:

```bash
# Create test file from Flatcar (via container)
ssh core@192.168.100.100 'docker exec sonarr touch /tv/.nfs-test && docker exec sonarr rm /tv/.nfs-test && echo "Write OK"'

# Or directly
ssh core@192.168.100.100 'touch /mnt/media/tv/.nfs-test && rm /mnt/media/tv/.nfs-test && echo "Write OK"'
```

### Phase 5: Data Consistency

Verify file counts match across hosts:

```bash
echo "Reginald:"
ssh root@192.168.100.4 'ls /media/tv | wc -l'

echo "Winston:"
ssh root@192.168.100.38 'ls /mnt/nfs_media/tv | wc -l'

echo "Flatcar:"
ssh core@192.168.100.100 'ls /mnt/media/tv | wc -l'
```

All three counts should match.

### Phase 6: Check for Stale Handles

Look for stale NFS errors in logs:

```bash
ssh core@192.168.100.100 'dmesg | grep -i "stale\|nfs" | tail -20'
```

## Troubleshooting

### Stale File Handle

Remount on Flatcar:

```bash
ssh core@192.168.100.100 'sudo systemctl restart mnt-media.mount'
```

If that fails, remount on Winston first:

```bash
ssh root@192.168.100.38 'umount /mnt/nfs_media && mount /mnt/nfs_media'
```

Then reload exports on Reginald:

```bash
ssh root@192.168.100.4 'exportfs -ra'
```

### Mount Shows Empty

Check if ZFS child datasets are mounted:

```bash
ssh root@192.168.100.4 'zfs get mountpoint -r rpool/shared/media'
```

All should show `SOURCE: inherited`. If not:

```bash
ssh root@192.168.100.4 'zfs inherit mountpoint [dataset-name]'
```

### Permission Denied

Check NFS user mapping:

```bash
# On Flatcar
ssh core@192.168.100.100 'id'

# On Reginald, check export options
ssh root@192.168.100.4 'cat /etc/exports'
```

Ensure `no_root_squash` or appropriate user mapping.

### Slow Performance

Check mount options:

```bash
ssh core@192.168.100.100 'mount | grep /mnt/media'
```

Should include:

- `hard` (not soft)
- `actimeo=60` or lower (not 600)
- `vers=4.2`

## Output Format

```
## NFS Health Report

### Mount Status
| Host | Mount Point | Status | Space Free |
|------|-------------|--------|------------|
| Reginald | /media | Mounted | XXX GB |
| Winston | /mnt/nfs_media | Mounted | XXX GB |
| Flatcar | /mnt/media | Mounted | XXX GB |

### Data Consistency
| Path | Reginald | Winston | Flatcar | Match |
|------|----------|---------|---------|-------|
| /tv | X files | X files | X files | Yes |
| /movies | X files | X files | X files | Yes |

### Write Test
- Result: Pass/Fail

### Issues
1. [Issue if any]

### Actions Taken
1. [Action if any]
```
