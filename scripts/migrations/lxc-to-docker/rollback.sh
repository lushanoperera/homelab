#!/usr/bin/env bash
# Rollback script for LXC to Docker migration
# This script reverts the migration by stopping Docker containers and starting LXC containers

set -euo pipefail

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-192.168.100.38}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_PASSWORD="${PROXMOX_PASSWORD:-281188password}"
FLATCAR_HOST="${FLATCAR_HOST:-192.168.100.100}"
FLATCAR_USER="${FLATCAR_USER:-core}"
LOG_FILE="${LOG_FILE:-rollback-$(date +%Y%m%d_%H%M%S).log}"
DRY_RUN="${DRY_RUN:-false}"

# Container mapping
declare -A CONTAINER_MAP=(
    ["109"]="qbittorrent"
    ["110"]="sabnzbd"
    ["111"]="radarr"
    ["112"]="sonarr"
    ["113"]="lidarr"
    ["114"]="bazarr"
    ["115"]="flaresolver"
    ["116"]="prowlarr"
    ["117"]="overseerr"
    ["121"]="tautulli"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

dry_run_check() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: $1"
        return 0
    fi
    return 1
}

stop_docker_containers() {
    log "Stopping Docker containers on Flatcar..."

    if dry_run_check "Stop all Docker containers"; then
        return 0
    fi

    # Stop the entire Docker Compose stack
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "
        cd /srv/docker/media-stack 2>/dev/null && docker compose down || {
            echo 'Compose stack not found, stopping individual containers...'
            for container in qbittorrent sabnzbd radarr sonarr lidarr bazarr flaresolver prowlarr overseerr tautulli; do
                docker stop \$container 2>/dev/null || true
                docker rm \$container 2>/dev/null || true
            done
        }
    " || {
        log "ERROR: Failed to stop Docker containers"
        return 1
    }

    log "Docker containers stopped successfully"
}

cleanup_docker_network() {
    log "Cleaning up Docker macvlan network..."

    if dry_run_check "Remove macvlan network"; then
        return 0
    fi

    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "
        docker network rm media_macvlan 2>/dev/null || true
    " || {
        log "WARNING: Failed to remove macvlan network (may not exist)"
    }

    log "Docker network cleanup completed"
}

backup_docker_data() {
    log "Creating backup of Docker data before rollback..."

    local backup_dir="/srv/docker-backup-$(date +%Y%m%d_%H%M%S)"

    if dry_run_check "Backup Docker data to $backup_dir"; then
        return 0
    fi

    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "
        if [[ -d /srv/docker/media-stack ]]; then
            sudo mkdir -p '$backup_dir'
            sudo cp -r /srv/docker/media-stack '$backup_dir/'
            sudo chown -R core:core '$backup_dir'
            echo 'Docker data backed up to $backup_dir'
        else
            echo 'No Docker data found to backup'
        fi
    " || {
        log "WARNING: Failed to backup Docker data"
    }

    log "Docker data backup completed"
}

start_lxc_container() {
    local ctid="$1"
    local name="$2"

    log "Starting LXC container $ctid ($name)..."

    if dry_run_check "Start LXC container $ctid"; then
        return 0
    fi

    # Check current status
    local status
    status=$(sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct status $ctid" 2>/dev/null | awk '{print $2}' || echo "unknown")

    if [[ "$status" == "running" ]]; then
        log "Container $ctid is already running"
        return 0
    fi

    if [[ "$status" == "unknown" ]]; then
        log "ERROR: Container $ctid not found on Proxmox"
        return 1
    fi

    # Start the container
    sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct start $ctid" || {
        log "ERROR: Failed to start container $ctid"
        return 1
    }

    # Wait for container to be fully running
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        status=$(sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct status $ctid" | awk '{print $2}')
        if [[ "$status" == "running" ]]; then
            log "Container $ctid started successfully"
            return 0
        fi
        sleep 2
        ((attempts++))
    done

    log "WARNING: Container $ctid may not be fully ready"
}

restore_from_snapshot() {
    local ctid="$1"
    local snapshot_name="${2:-pre-docker-migration-$(date +%Y%m%d)}"

    log "Checking for snapshot to restore for container $ctid..."

    if dry_run_check "Restore container $ctid from snapshot $snapshot_name"; then
        return 0
    fi

    # Check if snapshot exists
    local snapshot_exists
    snapshot_exists=$(sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" \
        "pct listsnapshot $ctid 2>/dev/null | grep -c '$snapshot_name' || echo '0'")

    if [[ "$snapshot_exists" == "0" ]]; then
        log "No snapshot '$snapshot_name' found for container $ctid, skipping restore"
        return 0
    fi

    log "Restoring container $ctid from snapshot $snapshot_name..."

    # Stop container first
    sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct stop $ctid" 2>/dev/null || true

    # Restore from snapshot
    sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" \
        "pct rollback $ctid $snapshot_name" || {
        log "ERROR: Failed to restore container $ctid from snapshot"
        return 1
    }

    log "Container $ctid restored from snapshot successfully"
}

validate_lxc_container() {
    local ctid="$1"
    local name="$2"
    local ip="192.168.100.$ctid"

    log "Validating LXC container $ctid ($name)..."

    if dry_run_check "Validate LXC container $ctid at $ip"; then
        return 0
    fi

    # Test ping connectivity
    if ping -c 3 -W 5 "$ip" >/dev/null 2>&1; then
        log "✓ Container $ctid is reachable at $ip"
    else
        log "⚠️  Container $ctid may not be fully ready at $ip"
        return 1
    fi

    # Check if container is actually running
    local status
    status=$(sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct status $ctid" | awk '{print $2}')

    if [[ "$status" == "running" ]]; then
        log "✓ Container $ctid is running on Proxmox"
    else
        log "✗ Container $ctid is not running (status: $status)"
        return 1
    fi

    log "Validation completed for container $ctid"
}

rollback_container() {
    local ctid="$1"
    local name="${CONTAINER_MAP[$ctid]}"
    local restore_snapshot="${RESTORE_SNAPSHOTS:-false}"

    log "Rolling back container $ctid ($name)..."

    if [[ "$restore_snapshot" == "true" ]]; then
        # Restore from snapshot first
        restore_from_snapshot "$ctid" || {
            log "WARNING: Snapshot restore failed, attempting regular start"
        }
    fi

    # Start the container
    start_lxc_container "$ctid" "$name" || return 1

    # Validate the container
    validate_lxc_container "$ctid" "$name" || return 1

    log "Rollback completed successfully for $name (CT $ctid)"
}

clear_arp_cache() {
    log "Clearing ARP cache to prevent IP conflicts..."

    if dry_run_check "Clear ARP cache"; then
        return 0
    fi

    # Clear local ARP cache
    sudo ip neigh flush all 2>/dev/null || {
        log "WARNING: Could not clear local ARP cache (may require sudo)"
    }

    # Clear ARP cache on Flatcar
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "
        sudo ip neigh flush all
    " || {
        log "WARNING: Could not clear ARP cache on Flatcar"
    }

    log "ARP cache clearing completed"
}

main() {
    log "Starting rollback from Docker to LXC..."

    # Verify we can connect to both hosts
    log "Testing connections..."
    if ! sshpass -p "$PROXMOX_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "echo 'Proxmox OK'" >/dev/null 2>&1; then
        log "ERROR: Cannot connect to Proxmox host"
        exit 1
    fi

    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "echo 'Flatcar OK'" >/dev/null 2>&1; then
        log "ERROR: Cannot connect to Flatcar host"
        exit 1
    fi

    # Step 1: Backup Docker data
    backup_docker_data

    # Step 2: Stop Docker containers
    stop_docker_containers || {
        log "ERROR: Failed to stop Docker containers"
        exit 1
    }

    # Step 3: Clean up Docker network
    cleanup_docker_network

    # Step 4: Clear ARP cache to prevent conflicts
    clear_arp_cache

    # Step 5: Roll back each container
    local failed_rollbacks=()

    for ctid in "${!CONTAINER_MAP[@]}"; do
        log "Processing rollback for container $ctid (${CONTAINER_MAP[$ctid]})..."

        if rollback_container "$ctid"; then
            log "✓ Successfully rolled back container $ctid (${CONTAINER_MAP[$ctid]})"
        else
            log "✗ Failed to roll back container $ctid (${CONTAINER_MAP[$ctid]})"
            failed_rollbacks+=("$ctid")
        fi
    done

    # Report results
    if [[ ${#failed_rollbacks[@]} -eq 0 ]]; then
        log "🎉 All containers rolled back successfully!"
        log "LXC containers should now be running with their original IP addresses"
    else
        log "⚠️  Rollback completed with failures:"
        for failed_ctid in "${failed_rollbacks[@]}"; do
            log "   - Container $failed_ctid (${CONTAINER_MAP[$failed_ctid]})"
        done
        log "You may need to manually start the failed containers"
    fi

    log "Rollback process completed."
    log "Verify that all services are accessible at their original IP addresses"
}

show_usage() {
    cat << EOF
Usage: $0 [options]

Options:
    --restore-snapshots    Restore containers from pre-migration snapshots
    --dry-run             Show what would be done without making changes
    --help, -h            Show this help message

Environment variables:
    DRY_RUN=true             Same as --dry-run flag
    RESTORE_SNAPSHOTS=true   Same as --restore-snapshots flag
    PROXMOX_HOST            Proxmox host IP (default: 192.168.100.38)
    PROXMOX_USER            Proxmox username (default: root)
    PROXMOX_PASSWORD        Proxmox password (default: 281188password)
    FLATCAR_HOST            Flatcar host IP (default: 192.168.100.100)
    FLATCAR_USER            Flatcar username (default: core)

This script will:
1. Stop all Docker containers
2. Remove Docker network configuration
3. Start LXC containers (optionally restore from snapshots)
4. Validate LXC container connectivity

EOF
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --restore-snapshots)
            RESTORE_SNAPSHOTS="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log "ERROR: Unknown argument: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi