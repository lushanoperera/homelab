#!/bin/bash
# NFS Mount Check Script for Proxmox
# Ensures NFS shares are mounted before LXC containers/VMs start

NFS_SERVER="192.168.200.4"
MAX_RETRIES=30
RETRY_INTERVAL=2

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Wait for NFS server to be reachable
log "Waiting for NFS server $NFS_SERVER..."
for i in $(seq 1 $MAX_RETRIES); do
    if ping -c 1 -W 1 "$NFS_SERVER" &>/dev/null; then
        log "NFS server $NFS_SERVER is reachable"
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        log "ERROR: NFS server $NFS_SERVER not reachable after $MAX_RETRIES attempts"
        exit 1
    fi
    log "Waiting for NFS server... attempt $i/$MAX_RETRIES"
    sleep $RETRY_INTERVAL
done

# Mount all NFS shares
log "Mounting NFS shares..."
mount -a -t nfs,nfs4

# Brief pause to allow mounts to settle
sleep 2

# Verify critical mounts
MOUNTS=(
    "/mnt/nfs_media"
    "/mnt/nfs_nextcloud"
    "/mnt/nfs_vaultwarden"
    "/mnt/nfs_immich_db"
    "/mnt/nfs_immich_library"
)

FAILED=0
for mnt in "${MOUNTS[@]}"; do
    if mountpoint -q "$mnt"; then
        log "OK: $mnt is mounted"
    else
        log "WARN: $mnt is NOT mounted"
        FAILED=$((FAILED + 1))
    fi
done

if [ "$FAILED" -gt 0 ]; then
    log "WARNING: $FAILED mount(s) failed"
else
    log "All NFS mounts successful"
fi

exit 0
