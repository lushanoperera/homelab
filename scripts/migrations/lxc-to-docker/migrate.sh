#!/usr/bin/env bash
# Main migration script for LXC to Docker migration
# This script performs the actual migration from LXC containers to Docker

set -euo pipefail

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-192.168.100.38}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_PASSWORD="${PROXMOX_PASSWORD:-281188password}"
FLATCAR_HOST="${FLATCAR_HOST:-192.168.100.100}"
FLATCAR_USER="${FLATCAR_USER:-core}"
STAGING_DIR="${STAGING_DIR:-/tmp/docker-migration}"
LOG_FILE="${LOG_FILE:-migration-$(date +%Y%m%d_%H%M%S).log}"
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

# Data paths mapping for each service
declare -A DATA_PATHS=(
    ["qbittorrent"]="/var/lib/qbittorrent"
    ["sabnzbd"]="/var/lib/sabnzbd"
    ["radarr"]="/var/lib/radarr"
    ["sonarr"]="/var/lib/sonarr"
    ["lidarr"]="/var/lib/lidarr"
    ["bazarr"]="/var/lib/bazarr"
    ["flaresolver"]="/opt/flaresolverr/config"
    ["prowlarr"]="/var/lib/prowlarr"
    ["overseerr"]="/var/lib/overseerr"
    ["tautulli"]="/var/lib/tautulli"
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

setup_macvlan_network() {
    log "Setting up macvlan network on Flatcar..."

    local create_network_cmd='
        # Remove existing network if it exists
        docker network rm media_macvlan 2>/dev/null || true

        # Create macvlan network
        docker network create -d macvlan \
            --subnet=192.168.100.0/24 \
            --gateway=192.168.100.1 \
            --ip-range=192.168.100.96/27 \
            -o parent=eth0 media_macvlan
    '

    if dry_run_check "Create macvlan network"; then
        return 0
    fi

    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "$create_network_cmd" || {
        log "ERROR: Failed to create macvlan network"
        return 1
    }

    log "Macvlan network created successfully"
}

stop_lxc_container() {
    local ctid="$1"
    local name="$2"

    log "Stopping LXC container $ctid ($name)..."

    if dry_run_check "Stop LXC container $ctid"; then
        return 0
    fi

    # Check current status
    local status
    status=$(sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct status $ctid" | awk '{print $2}')

    if [[ "$status" == "stopped" ]]; then
        log "Container $ctid is already stopped"
        return 0
    fi

    # Graceful shutdown first
    sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct shutdown $ctid" || {
        log "Graceful shutdown failed, forcing stop..."
        sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct stop $ctid"
    }

    # Wait for stop confirmation
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        status=$(sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct status $ctid" | awk '{print $2}')
        if [[ "$status" == "stopped" ]]; then
            log "Container $ctid stopped successfully"
            return 0
        fi
        sleep 2
        ((attempts++))
    done

    log "ERROR: Container $ctid failed to stop within timeout"
    return 1
}

sync_container_data() {
    local ctid="$1"
    local name="$2"
    local source_path="${DATA_PATHS[$name]}"

    log "Syncing data for $name (CT $ctid)..."

    if dry_run_check "Sync data for $name from $source_path"; then
        return 0
    fi

    # Create staging directory
    local staging_path="$STAGING_DIR/$name"
    mkdir -p "$staging_path"

    # Sync from Proxmox to local staging
    log "Syncing from Proxmox CT $ctid:$source_path to $staging_path"
    sshpass -p "$PROXMOX_PASSWORD" rsync -avz --delete --numeric-ids \
        -e "ssh -o StrictHostKeyChecking=no" \
        "$PROXMOX_USER@$PROXMOX_HOST:$source_path/" "$staging_path/" || {
        log "WARNING: Failed to sync $source_path from container $ctid"
        return 1
    }

    # Create target directory on Flatcar and sync
    local target_path="/srv/docker/media-stack/config/$name"
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "sudo mkdir -p '$target_path'"

    log "Syncing from $staging_path to Flatcar:$target_path"
    rsync -avz --delete --numeric-ids \
        -e "ssh -o StrictHostKeyChecking=no" \
        "$staging_path/" "$FLATCAR_USER@$FLATCAR_HOST:$target_path/" || {
        log "ERROR: Failed to sync data to Flatcar for $name"
        return 1
    }

    # Fix ownership on Flatcar
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "sudo chown -R 1000:1000 '$target_path'"

    log "Data sync completed for $name"
}

start_docker_container() {
    local name="$1"

    log "Starting Docker container for $name..."

    if dry_run_check "Start Docker container $name"; then
        return 0
    fi

    # Use docker compose to start specific service
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "
        cd /srv/docker/media-stack &&
        docker compose up -d $name
    " || {
        log "ERROR: Failed to start Docker container for $name"
        return 1
    }

    # Wait for container to be healthy
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        local status
        status=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "docker ps --filter name=$name --format '{{.Status}}'")

        if [[ "$status" =~ "Up" ]]; then
            log "Docker container $name is running"
            return 0
        fi

        sleep 5
        ((attempts++))
    done

    log "WARNING: Docker container $name may not be fully ready"
}

validate_container() {
    local ctid="$1"
    local name="$2"
    local ip="192.168.100.$ctid"

    log "Validating container $name at $ip..."

    if dry_run_check "Validate container $name at $ip"; then
        return 0
    fi

    # Test basic connectivity
    if ping -c 3 -W 5 "$ip" >/dev/null 2>&1; then
        log "Ping test passed for $name at $ip"
    else
        log "WARNING: Ping test failed for $name at $ip"
        return 1
    fi

    # Test HTTP connectivity based on service type
    local port=""
    case "$name" in
        "qbittorrent") port="8080" ;;
        "sabnzbd") port="8080" ;;
        "radarr") port="7878" ;;
        "sonarr") port="8989" ;;
        "lidarr") port="8686" ;;
        "bazarr") port="6767" ;;
        "flaresolver") port="8191" ;;
        "prowlarr") port="9696" ;;
        "overseerr") port="5055" ;;
        "tautulli") port="8181" ;;
    esac

    if [[ -n "$port" ]]; then
        if curl -s --connect-timeout 10 "http://$ip:$port" >/dev/null 2>&1; then
            log "HTTP test passed for $name at $ip:$port"
        else
            log "WARNING: HTTP test failed for $name at $ip:$port"
            return 1
        fi
    fi

    log "Validation completed for $name"
}

migrate_container() {
    local ctid="$1"
    local name="${CONTAINER_MAP[$ctid]}"

    log "Starting migration for container $ctid ($name)..."

    # Step 1: Stop LXC container
    stop_lxc_container "$ctid" "$name" || return 1

    # Step 2: Sync data
    sync_container_data "$ctid" "$name" || return 1

    # Step 3: Start Docker container
    start_docker_container "$name" || return 1

    # Step 4: Validate
    validate_container "$ctid" "$name" || return 1

    log "Migration completed successfully for $name (CT $ctid)"
}

main() {
    log "Starting LXC to Docker migration..."

    # Check if docker-compose.yml exists
    if [[ ! -f "docker-compose.yml" ]]; then
        log "ERROR: docker-compose.yml not found in current directory"
        exit 1
    fi

    # Copy docker-compose.yml and .env to Flatcar
    log "Copying Docker Compose configuration to Flatcar..."
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "sudo mkdir -p /srv/docker/media-stack"

    if ! dry_run_check "Copy docker-compose.yml to Flatcar"; then
        rsync -av -e "ssh -o StrictHostKeyChecking=no" \
            docker-compose.yml .env \
            "$FLATCAR_USER@$FLATCAR_HOST:/srv/docker/media-stack/"
    fi

    # Set up networking
    setup_macvlan_network || exit 1

    # Create staging directory
    mkdir -p "$STAGING_DIR"

    # Migrate each container
    local failed_migrations=()

    for ctid in "${!CONTAINER_MAP[@]}"; do
        log "Processing container $ctid (${CONTAINER_MAP[$ctid]})..."

        if migrate_container "$ctid"; then
            log "✓ Successfully migrated container $ctid (${CONTAINER_MAP[$ctid]})"
        else
            log "✗ Failed to migrate container $ctid (${CONTAINER_MAP[$ctid]})"
            failed_migrations+=("$ctid")
        fi
    done

    # Report results
    if [[ ${#failed_migrations[@]} -eq 0 ]]; then
        log "🎉 All containers migrated successfully!"
    else
        log "⚠️  Migration completed with failures:"
        for failed_ctid in "${failed_migrations[@]}"; do
            log "   - Container $failed_ctid (${CONTAINER_MAP[$failed_ctid]})"
        done
    fi

    # Cleanup staging directory
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "$STAGING_DIR"
    fi

    log "Migration process completed. Check individual container status in Docker."
}

# Show usage if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
Usage: $0 [--dry-run]

Options:
    --dry-run    Show what would be done without making changes
    --help, -h   Show this help message

Environment variables:
    DRY_RUN=true         Same as --dry-run flag
    PROXMOX_HOST         Proxmox host IP (default: 192.168.100.38)
    PROXMOX_USER         Proxmox username (default: root)
    PROXMOX_PASSWORD     Proxmox password (default: 281188password)
    FLATCAR_HOST         Flatcar host IP (default: 192.168.100.100)
    FLATCAR_USER         Flatcar username (default: core)
    STAGING_DIR          Local staging directory (default: /tmp/docker-migration)

EOF
    exit 0
fi

# Handle command line arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="true"
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi