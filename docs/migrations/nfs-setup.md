# NFS Setup Guide for Docker Media Stack

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ REGINALD (192.168.100.4 / 192.168.200.4)                    │
│ ZFS Pool: rpool/shared/media → /media                       │
│                                                             │
│ ZFS Datasets (all inherit /media mountpoint):               │
│   rpool/shared/media           → /media                     │
│   rpool/shared/media/downloads → /media/downloads           │
│   rpool/shared/media/movies    → /media/movies              │
│   rpool/shared/media/music     → /media/music               │
│   rpool/shared/media/tv        → /media/tv                  │
│                                                             │
│ NFS Export: /media                                          │
│   192.168.100.0/24 (Infra VLAN) - Flatcar, LXCs             │
│   192.168.200.0/24 (Storage VLAN) - Winston                 │
│   Options: rw,async,no_subtree_check,no_root_squash,crossmnt│
│                                                             │
│ User: mediauser (1000:1000)                                 │
└─────────────────────────┬───────────────────────────────────┘
                          │ NFSv4.2
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ FLATCAR VM 100  │ │ WINSTON         │ │ PLEX LXC 105    │
│ 192.168.100.100 │ │ 192.168.200.38  │ │ (via Winston)   │
│                 │ │                 │ │                 │
│ Direct mount:   │ │ Mount:          │ │ Bind mount:     │
│ 192.168.100.4:  │ │ 192.168.200.4:  │ │ /mnt/nfs_media  │
│ /media          │ │ /media          │ │ → /mnt/media    │
│ → /mnt/media    │ │ → /mnt/nfs_media│ │                 │
│                 │ │                 │ │                 │
│ Docker (PUID=   │ │ Re-exports to   │ │                 │
│ 1000, PGID=1000)│ │ 192.168.100.0/24│ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

## Requirements

### Common Configuration (Critical!)
All Docker containers **must** use the same user/group IDs:
- **PUID**: 1000
- **PGID**: 1000
- **UMASK**: 002 (directories: 775, files: 664)

This ensures all services can read and write to shared directories.

### Services Using Shared Storage
- **qbittorrent, sabnzbd**: Write to `/downloads`, `/incomplete-downloads`
- **radarr**: Write to `/downloads`, `/movies`
- **sonarr**: Write to `/downloads`, `/tv`
- **lidarr**: Write to `/downloads`, `/music`
- **bazarr**: Write to `/movies`, `/tv`

## NFS Server Setup (Reginald - 192.168.100.4)

### 1. ZFS Dataset Structure

**Critical**: All child datasets must inherit their mountpoint from the parent.

```bash
# Check current mountpoints
zfs list -o name,mountpoint,mounted | grep media

# Correct output should show:
# rpool/shared/media            /media           yes
# rpool/shared/media/downloads  /media/downloads yes
# rpool/shared/media/movies     /media/movies    yes
# rpool/shared/media/music      /media/music     yes
# rpool/shared/media/tv         /media/tv        yes
```

If a child dataset has a custom mountpoint (not inherited), fix it:
```bash
# Check if mountpoint is inherited
zfs get mountpoint rpool/shared/media/tv

# If SOURCE shows "local" instead of "inherited", fix it:
zfs inherit mountpoint rpool/shared/media/tv
```

### 2. Set Ownership
```bash
# All media directories must be owned by UID:GID 1000:1000
chown -R 1000:1000 /media
```

### 3. Set Permissions
```bash
# Directories: 775 (rwxrwxr-x) - group write enabled
find /media -type d -exec chmod 775 {} \;

# Files: 664 (rw-rw-r--) - group write enabled
find /media -type f -exec chmod 664 {} \;
```

### 4. Configure NFS Export

Edit `/etc/exports`:
```bash
# Media content (async for performance, crossmnt for ZFS child datasets)
/media 192.168.100.0/24(rw,async,no_subtree_check,no_root_squash,crossmnt) \
       192.168.200.0/24(rw,async,no_subtree_check,no_root_squash,crossmnt)
```

**Export Options Explained:**
- `rw`: Read-write access
- `async`: Improves performance (data written to disk asynchronously)
- `no_subtree_check`: Improves reliability
- `no_root_squash`: Allows root on client to write as root (needed for Docker)
- `crossmnt`: **Critical** - Allows NFS to traverse into ZFS child dataset mountpoints

### 5. Apply Export Configuration
```bash
# Reload NFS exports
exportfs -ra

# Verify exports are active
exportfs -v | grep media

# Should show crossmnt option:
# /media 192.168.100.0/24(async,wdelay,hide,crossmnt,no_subtree_check,...)
```

## Flatcar VM Setup (192.168.100.100)

### Direct Mount from Reginald (Recommended)

Flatcar should mount directly from Reginald, not via Winston re-export. This avoids NFS re-export limitations with ZFS child mounts.

**Systemd Mount Unit** (`/etc/systemd/system/mnt-media.mount`):
```ini
[Unit]
Description=NFS mount for media storage from reginald
Requires=network-online.target
After=network-online.target
Before=docker.service media-stack-compose.service

[Mount]
What=192.168.100.4:/media
Where=/mnt/media
Type=nfs4
Options=rw,relatime,vers=4.2,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,_netdev
TimeoutSec=300

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable mnt-media.mount
sudo systemctl start mnt-media.mount
```

### Verify Mount
```bash
# Check mount
mount | grep media

# Test all subdirectories are accessible
ls /mnt/media/tv/
ls /mnt/media/movies/
ls /mnt/media/downloads/

# Test write access
docker exec sonarr touch /tv/test && docker exec sonarr rm /tv/test
```

## Winston Setup (192.168.200.38)

Winston mounts from Reginald via Storage VLAN and optionally re-exports to Infra VLAN for LXC containers.

### Client Mount Configuration

**fstab entry**:
```bash
192.168.200.4:/media /mnt/nfs_media nfs nofail,_netdev,hard,timeo=150,retrans=3,rw,noatime,actimeo=60,vers=4,rsize=1048576,wsize=1048576,fsc,nconnect=4 0 0
```

**Mount Options Explained:**
- `hard`: Retry indefinitely on server failure (safer than `soft`)
- `timeo=150`: 15 second timeout
- `actimeo=60`: 60 second attribute cache (balance between performance and freshness)
- `fsc`: Enable FS-Cache (if cachefilesd is running)
- `nconnect=4`: Use 4 parallel connections for better throughput

### Re-export Configuration (for LXC containers)

**exports**:
```bash
/mnt/nfs_media 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash,crossmnt,fsid=1)
```

**Note**: NFS re-export has limitations. LXC containers accessing `/mnt/nfs_media` will see the content correctly because Winston's mount includes `crossmnt` from Reginald. However, for Docker containers, prefer direct mount from Reginald.

## Docker Configuration

### Environment Variables (.env)
```bash
# User and permissions
PUID=1000
PGID=1000
UMASK=002

# Paths
CONFIG_ROOT=/srv/docker/media-stack/config
DOWNLOADS_ROOT=/mnt/media/downloads
MEDIA_ROOT=/mnt/media
```

### docker-compose.yml Volume Mounts
```yaml
services:
  sonarr:
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - UMASK=${UMASK}
    volumes:
      - ${CONFIG_ROOT}/sonarr:/config
      - ${DOWNLOADS_ROOT}:/downloads
      - ${MEDIA_ROOT}/tv:/tv
      - ${MEDIA_ROOT}:/media
```

## Troubleshooting

### Issue: "Not a directory" when accessing subdirectories

**Symptom**: `ls /mnt/media/tv/` returns "Not a directory" but `ls -la /mnt/media/` shows `tv` as a directory.

**Cause**: NFS export missing `crossmnt` option, so child ZFS dataset mounts are not traversed.

**Fix on Reginald**:
```bash
# Add crossmnt to export
sed -i 's|no_root_squash)|no_root_squash,crossmnt)|g' /etc/exports
exportfs -ra
```

### Issue: ZFS child dataset has wrong mountpoint

**Symptom**: `zfs get mountpoint rpool/shared/media/tv` shows a custom path instead of inherited.

**Cause**: The dataset was created with explicit mountpoint or modified later.

**Fix**:
```bash
# Make dataset inherit mountpoint from parent
zfs inherit mountpoint rpool/shared/media/tv

# Verify
zfs list -o name,mountpoint rpool/shared/media/tv
# Should show: /media/tv
```

### Issue: Data visible locally but not via NFS

**Symptom**: Content exists at `/media/tv/` on Reginald but NFS clients see empty directory.

**Cause**: ZFS child dataset mounted at wrong location, NFS shows underlying empty directory.

**Diagnosis**:
```bash
# Check if path is a mountpoint
mountpoint /media/tv
# Should say "is a mountpoint"

# Check ZFS dataset mountpoint
zfs get mountpoint rpool/shared/media/tv
# SOURCE should be "inherited from rpool/shared/media"
```

### Issue: Stale file handle errors

**Symptom**: `ls: cannot open directory '/mnt/media/movies': Stale file handle` - but other paths like `/mnt/media/tv` work fine.

**Cause**: NFS server restarted, export changed, or ZFS dataset modified while client had cached file handles.

**Fix** (try in order):

```bash
# 1. First try: Refresh exports on NFS server (often sufficient)
ssh root@192.168.100.4 'exportfs -ra'

# 2. Test if the path is now accessible
ls /mnt/media/movies

# 3. If still stale, remount on client
sudo systemctl restart mnt-media.mount

# 4. Restart affected containers to pick up refreshed mount
cd /srv/docker/media-stack && /opt/bin/docker-compose restart radarr bazarr
```

**Note**: `exportfs -ra` on the NFS server often clears stale handles without requiring client-side remount. Always try this first as it's less disruptive.

### Issue: Empty ZFS child dataset shadowing real data

**Symptom**: Directory appears empty via NFS but data exists on the ZFS server. For example, `/media/movies/` shows 0 files via NFS but `ls /rpool/shared/media/movies/` on Reginald shows hundreds of files.

**Cause**: An empty ZFS child dataset (e.g., `rpool/shared/media/movies`) is mounted at `/media/movies`, shadowing the actual data that exists in the parent dataset's directory at `/rpool/shared/media/movies`.

**Diagnosis**:
```bash
# Check if the dataset has any data
zfs list -o name,used,refer rpool/shared/media/movies
# If "refer" is very small (e.g., 24K) but you expect GBs, the dataset is empty

# Check where real data is
ls -la /rpool/shared/media/movies/
# This shows the actual directory in the parent dataset's filesystem
```

**Fix** (when data is in parent, child dataset is empty):
```bash
# 1. Verify the child dataset is truly empty and can be destroyed
zfs list -o name,used,refer rpool/shared/media/movies

# 2. Destroy the empty shadowing dataset
zfs destroy rpool/shared/media/movies

# 3. Create bind mount to expose the real data at expected path
mount --bind /rpool/shared/media/movies /media/movies

# 4. Persist in fstab
echo "/rpool/shared/media/movies /media/movies none bind 0 0" >> /etc/fstab

# 5. Verify NFS clients now see the data
ssh core@192.168.100.100 'ls /mnt/media/movies | wc -l'
```

**Note**: This situation typically occurs when a ZFS child dataset was created but data was written to the parent's directory before the child was mounted. The `zfs inherit mountpoint` fix won't work here because the dataset itself is empty—the data lives in the parent's filesystem.

### Issue: Permission denied when writing

**Check 1: Ownership on NFS server**
```bash
ssh root@192.168.100.4 "ls -lnd /media /media/tv"
# Should show: drwxrwxr-x ... 1000 1000 ...
```

**Check 2: NFS export options**
```bash
ssh root@192.168.100.4 "exportfs -v | grep media"
# Should include: rw, no_root_squash, crossmnt
```

**Check 3: Container PUID/PGID**
```bash
docker exec sonarr env | grep -E '(PUID|PGID)'
# Should show: PUID=1000, PGID=1000
```

## Testing Write Access

### Full Chain Test
```bash
# Create test file from container
TIMESTAMP=$(date +%s)
docker exec sonarr touch /tv/chain_test_$TIMESTAMP

# Verify on Reginald
ssh root@192.168.100.4 "ls /media/tv/chain_test_* && rm /media/tv/chain_test_*"
```

### Test All Containers
```bash
for service in qbittorrent sabnzbd radarr sonarr lidarr; do
    echo "Testing $service..."
    docker exec $service touch /downloads/test-$service
    docker exec $service rm /downloads/test-$service
    echo "$service: OK"
done
```

## Lessons Learned

| Issue | Root Cause | Solution |
|-------|------------|----------|
| Child datasets invisible via NFS | Missing `crossmnt` in export | Add `crossmnt` option |
| ZFS child mounted at wrong path | Explicit mountpoint set | Use `zfs inherit mountpoint` |
| Data split between locations | Child dataset hiding underlying directory | Merge data, fix mountpoint |
| Empty ZFS child shadowing real data | ZFS child dataset mounted over directory with actual content | Destroy empty dataset, use bind mount |
| NFS re-export failing for children | NFSv4 re-export limitations | Mount directly from source |
| `soft` mount causing silent failures | Network interruptions drop writes | Use `hard` mount option |
| Stale data due to aggressive caching | `actimeo=600` too long | Reduce to `actimeo=60` |
| Partial stale handles (some paths work) | Cached file handles invalid after export changes | `exportfs -ra` on server, then restart containers |

## Quick Reference Commands

```bash
# Check NFS exports on Reginald
ssh root@192.168.100.4 "exportfs -v | grep media"

# Check ZFS mountpoints
ssh root@192.168.100.4 "zfs list -o name,mountpoint,mounted | grep media"

# Check mounts on Flatcar
ssh core@192.168.100.100 "mount | grep media"

# Check mounts on Winston
ssh root@192.168.100.38 "mount | grep nfs_media"

# Test write from container
ssh core@192.168.100.100 "docker exec sonarr touch /tv/test && docker exec sonarr rm /tv/test"

# Restart NFS mount on Flatcar
ssh core@192.168.100.100 "sudo systemctl restart mnt-media.mount"

# Reload NFS exports on Reginald
ssh root@192.168.100.4 "exportfs -ra"

# Check container health
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "sonarr|radarr"'
```

## Security Considerations

### UID/GID 1000 Consistency
- Using UID/GID 1000 across all containers ensures consistent permissions
- Dedicated user on Reginald: `mediauser` (UID 1000, GID 1000)

### Network Security
- NFS export restricted to specific subnets
- Infra VLAN (192.168.100.0/24): Flatcar, LXC containers
- Storage VLAN (192.168.200.0/24): Winston (dedicated storage traffic)

### no_root_squash Implications
- Allows root on client to write as root on server
- Only enable for trusted clients on isolated VLANs
