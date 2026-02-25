#!/bin/bash
# Vaultwarden backup script - syncs to NFS for RAIDZ2 redundancy

BACKUP_DIR="/mnt/nfs_vaultwarden/backups"
SOURCE_DIR="/opt/vaultwarden/data"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG="/var/log/vaultwarden-backup.log"

# Ensure NFS is mounted
if ! mountpoint -q /mnt/nfs_vaultwarden; then
    echo "$(date): ERROR - NFS not mounted, attempting mount..." >> "$LOG"
    systemctl start mnt-nfs_vaultwarden.mount
    sleep 5
    if ! mountpoint -q /mnt/nfs_vaultwarden; then
        echo "$(date): ERROR - Failed to mount NFS, aborting backup" >> "$LOG"
        exit 1
    fi
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Stop container for consistent backup
echo "$(date): Stopping Vaultwarden for backup..." >> "$LOG"
docker stop vaultwarden

# Create timestamped backup
BACKUP_FILE="$BACKUP_DIR/vaultwarden-backup-$TIMESTAMP.tar.gz"
tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" . 2>> "$LOG"

# Restart container
docker start vaultwarden
echo "$(date): Vaultwarden restarted" >> "$LOG"

# Also sync latest copy for quick restore
rsync -a --delete "$SOURCE_DIR/" "$BACKUP_DIR/latest/"

# Keep only last 7 daily backups
find "$BACKUP_DIR" -name "vaultwarden-backup-*.tar.gz" -mtime +7 -delete

echo "$(date): Backup completed - $BACKUP_FILE" >> "$LOG"
