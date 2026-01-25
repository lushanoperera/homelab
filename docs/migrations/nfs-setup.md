# NFS Setup Guide for Docker Media Stack

## Architecture Overview

```
┌─────────────────────────────────────┐
│  NFS Server (192.168.200.4)         │
│  Path: /rpool/shared/media          │
│    ├─ downloads/                    │
│    ├─ movies/                       │
│    ├─ tv/                           │
│    └─ music/                        │
└─────────────┬───────────────────────┘
              │ NFS Export
              ↓
┌─────────────────────────────────────┐
│  Flatcar VM (192.168.100.100)       │
│  Mount: /mnt/nfs_shared/media       │
│         ↓                           │
│  Link:  /mnt/media  ────────────┐   │
│                                 │   │
│  ┌──────────────────────────────┼─┐ │
│  │  Docker Containers           │ │ │
│  │  - qbittorrent: /downloads ──┘ │ │
│  │  - sabnzbd:     /downloads     │ │
│  │  - radarr:      /downloads     │ │
│  │  - sonarr:      /downloads     │ │
│  │  - lidarr:      /downloads     │ │
│  │  All: PUID=1000, PGID=1000     │ │
│  │       UMASK=002                 │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
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

## NFS Server Setup (192.168.200.4)

### 1. Create Directory Structure
```bash
# Create base directory if it doesn't exist
mkdir -p /rpool/shared/media/{downloads,movies,tv,music,incomplete-downloads}
```

### 2. Set Ownership
```bash
# All media directories must be owned by UID:GID 1000:1000
chown -R 1000:1000 /rpool/shared/media
```

### 3. Set Permissions
```bash
# Directories: 775 (rwxrwxr-x) - group write enabled
find /rpool/shared/media -type d -exec chmod 775 {} \;

# Files: 664 (rw-rw-r--) - group write enabled
find /rpool/shared/media -type f -exec chmod 664 {} \;
```

### 4. Configure NFS Export

Edit `/etc/exports` and add:
```
/rpool/shared/media 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash)
```

**Export Options Explained:**
- `rw`: Read-write access
- `sync`: Write changes to disk before responding
- `no_subtree_check`: Improves reliability
- `no_root_squash`: Allows root on client to write as root (needed for Docker)

**Alternative (more restrictive):**
If you want to force all access as UID/GID 1000:
```
/rpool/shared/media 192.168.100.0/24(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
```

### 5. Apply Export Configuration
```bash
# Reload NFS exports
exportfs -ra

# Verify exports are active
exportfs -v | grep media
showmount -e localhost
```

## Flatcar VM Setup (192.168.100.100)

### 1. Create Mount Points
```bash
sudo mkdir -p /mnt/nfs_shared/media
sudo mkdir -p /mnt/media
```

### 2. Mount NFS Share

**Temporary Mount (for testing):**
```bash
sudo mount -t nfs -o rw,hard,intr,vers=3 192.168.200.4:/rpool/shared/media /mnt/nfs_shared/media
```

**Permanent Mount:**
Add to `/etc/systemd/system/mnt-nfs_shared-media.mount`:
```ini
[Unit]
Description=NFS mount for media storage
Requires=network-online.target
After=network-online.target

[Mount]
What=192.168.200.4:/rpool/shared/media
Where=/mnt/nfs_shared/media
Type=nfs
Options=rw,hard,intr,vers=3

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable mnt-nfs_shared-media.mount
sudo systemctl start mnt-nfs_shared-media.mount
```

### 3. Create Docker Path Link

If `/mnt/media` should point to `/mnt/nfs_shared/media`:

**Option A: Symlink**
```bash
sudo ln -s /mnt/nfs_shared/media /mnt/media
```

**Option B: Bind Mount**
```bash
sudo mount --bind /mnt/nfs_shared/media /mnt/media
```

**Option C: Direct NFS Mount**
Mount NFS directly to `/mnt/media` instead of `/mnt/nfs_shared/media`

### 4. Verify Mount
```bash
# Check mount
mount | grep media

# Test permissions
ls -la /mnt/media/
ls -la /mnt/nfs_shared/media/

# Test write access as UID 1000
sudo -u '#1000' touch /mnt/media/downloads/test.txt
sudo -u '#1000' rm /mnt/media/downloads/test.txt
```

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
  qbittorrent:
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - UMASK=${UMASK}
    volumes:
      - ${CONFIG_ROOT}/qbittorrent:/config
      - ${DOWNLOADS_ROOT}:/downloads
      - ${DOWNLOADS_ROOT}/incomplete-downloads:/incomplete-downloads
      - ${MEDIA_ROOT}:/media
```

All services must use consistent `PUID`, `PGID`, and `UMASK` settings.

## Diagnostic and Fix Scripts

### Diagnose Issues
```bash
cd /path/to/lxc-to-docker-migration
./scripts/diagnose-nfs-permissions.sh
```

This script checks:
- Connectivity to NFS server and Flatcar
- Mount configuration
- Permissions at all layers (NFS server, Flatcar mount, Docker path)
- NFS export configuration
- Docker container settings
- Write access from each container

### Apply Fixes

**Dry-run mode (safe, shows what would be done):**
```bash
./scripts/fix-nfs-permissions.sh
```

**Apply fixes:**
```bash
./scripts/fix-nfs-permissions.sh --apply
```

This script:
1. Sets correct ownership (1000:1000) on NFS server
2. Sets correct permissions (dirs: 775, files: 664)
3. Verifies/updates NFS export configuration
4. Remounts NFS on Flatcar with correct options
5. Restarts Docker containers
6. Verifies write access from all containers

## Troubleshooting

### Issue: "Permission denied" when writing

**Check 1: Ownership on NFS server**
```bash
ssh root@192.168.200.4 "ls -lnd /rpool/shared/media /rpool/shared/media/downloads"
```
Should show: `drwxrwxr-x ... 1000 1000 ...`

**Check 2: NFS export options**
```bash
ssh root@192.168.200.4 "exportfs -v | grep media"
```
Should include: `rw`, `no_root_squash` (or `all_squash,anonuid=1000,anongid=1000`)

**Check 3: NFS mount on Flatcar**
```bash
ssh core@192.168.100.100 "mount | grep media"
```
Should show: `type nfs` with `rw` option

**Check 4: Container configuration**
```bash
ssh core@192.168.100.100 "docker exec qbittorrent env | grep -E '(PUID|PGID|UMASK)'"
```
Should show: `PUID=1000`, `PGID=1000`, `UMASK=002`

### Issue: Changes not reflected in containers

**Restart containers:**
```bash
ssh core@192.168.100.100 "cd /srv/docker/media-stack && docker compose restart"
```

**Or individual service:**
```bash
ssh core@192.168.100.100 "docker restart qbittorrent"
```

### Issue: "Stale file handle" errors

NFS mount became stale, remount:
```bash
ssh core@192.168.100.100 "sudo umount -f /mnt/nfs_shared/media && sudo mount /mnt/nfs_shared/media"
```

### Issue: Only root can write, UID 1000 cannot

**Problem**: NFS export has `root_squash` or wrong `all_squash` settings

**Fix on NFS server**:
```bash
# Edit /etc/exports, change to:
/rpool/shared/media 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash)

# Reload
exportfs -ra
```

### Issue: Some services can write, others cannot

**Problem**: Inconsistent PUID/PGID/UMASK across containers

**Fix**: Verify all services have same environment variables in docker-compose.yml:
```bash
ssh core@192.168.100.100 "cd /srv/docker/media-stack && grep -A 3 'environment:' docker-compose.yml | grep -E '(PUID|PGID|UMASK)'"
```

All should show `1000`, `1000`, `002`

## Testing Write Access

### From Flatcar Host
```bash
# As root
ssh core@192.168.100.100 "sudo touch /mnt/media/downloads/test-root && sudo rm /mnt/media/downloads/test-root"

# As UID 1000
ssh core@192.168.100.100 "sudo -u '#1000' touch /mnt/media/downloads/test-user && sudo rm /mnt/media/downloads/test-user"
```

### From Docker Containers
```bash
# qbittorrent
ssh core@192.168.100.100 "docker exec qbittorrent touch /downloads/test && docker exec qbittorrent rm /downloads/test"

# Test all download clients
for service in qbittorrent sabnzbd radarr sonarr lidarr; do
    echo "Testing $service..."
    ssh core@192.168.100.100 "docker exec $service touch /downloads/test-$service && docker exec $service rm /downloads/test-$service"
done
```

## Security Considerations

### UID/GID 1000 Consistency
- Using UID/GID 1000 across all containers ensures consistent permissions
- Create a dedicated user on NFS server (optional but recommended):
  ```bash
  # On NFS server
  useradd -u 1000 -g 1000 mediauser
  ```

### Network Security
- NFS export is restricted to `192.168.100.0/24` subnet
- Consider firewall rules to further restrict access to Flatcar VM only:
  ```bash
  # On NFS server (example using iptables)
  iptables -A INPUT -p tcp --dport 2049 -s 192.168.100.100 -j ACCEPT
  iptables -A INPUT -p tcp --dport 2049 -j DROP
  ```

### no_root_squash Implications
- `no_root_squash` allows root on client to write as root on server
- Only enable for trusted clients
- Alternative: Use `all_squash,anonuid=1000,anongid=1000` to force all access as UID 1000

## Performance Tuning

### NFS Mount Options
Add these options for better performance:
```bash
mount -t nfs -o rw,hard,intr,vers=3,rsize=8192,wsize=8192,timeo=14 \
    192.168.200.4:/rpool/shared/media /mnt/nfs_shared/media
```

Options:
- `rsize=8192,wsize=8192`: Read/write buffer size
- `timeo=14`: Timeout in deciseconds (1.4 seconds)
- `vers=3`: Use NFSv3 (more compatible)

### NFS Server Tuning
Edit `/etc/nfs.conf` (or similar) to increase threads:
```ini
[nfsd]
threads=16
```

## Quick Reference Commands

```bash
# Diagnostic
./scripts/diagnose-nfs-permissions.sh

# Fix (dry-run)
./scripts/fix-nfs-permissions.sh

# Fix (apply)
./scripts/fix-nfs-permissions.sh --apply

# Check NFS exports
ssh root@192.168.200.4 "exportfs -v"

# Check mounts
ssh core@192.168.100.100 "mount | grep media"

# Test write from container
ssh core@192.168.100.100 "docker exec qbittorrent touch /downloads/test.txt"

# Restart all containers
ssh core@192.168.100.100 "cd /srv/docker/media-stack && docker compose restart"

# Check container logs
ssh core@192.168.100.100 "docker logs qbittorrent --tail 50"
```

## Further Reading

- [NFS Server Configuration](https://wiki.archlinux.org/title/NFS)
- [LinuxServer.io Docker Images](https://docs.linuxserver.io/)
- [Docker Volumes Documentation](https://docs.docker.com/storage/volumes/)
- [Flatcar Linux Documentation](https://www.flatcar.org/docs/latest/)
