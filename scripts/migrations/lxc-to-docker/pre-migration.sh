#!/usr/bin/env bash
# Pre-migration script for LXC to Docker migration
# This script backs up LXC containers and prepares the Docker environment

set -euo pipefail

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-192.168.100.38}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_PASSWORD="${PROXMOX_PASSWORD:-281188password}"
FLATCAR_HOST="${FLATCAR_HOST:-192.168.100.100}"
FLATCAR_USER="${FLATCAR_USER:-core}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/lxc-migration-backup}"
LOG_FILE="${LOG_FILE:-migration-$(date +%Y%m%d_%H%M%S).log}"

# Container list - adjust as needed
CONTAINERS=(109 110 111 112 113 114 115 116 117 121)
CONTAINER_NAMES=(qbittorrent sabnzbd radarr sonarr lidarr bazarr flaresolver prowlarr overseerr tautulli)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_dependencies() {
    log "Checking dependencies..."
    command -v sshpass >/dev/null 2>&1 || { log "ERROR: sshpass is required but not installed."; exit 1; }
    command -v rsync >/dev/null 2>&1 || { log "ERROR: rsync is required but not installed."; exit 1; }
    command -v ssh >/dev/null 2>&1 || { log "ERROR: ssh is required but not installed."; exit 1; }
    log "All dependencies found."
}

test_connections() {
    log "Testing SSH connections..."

    # Test Proxmox connection
    if sshpass -p "$PROXMOX_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "echo 'Proxmox connection OK'" >/dev/null 2>&1; then
        log "Proxmox connection: OK"
    else
        log "ERROR: Cannot connect to Proxmox host $PROXMOX_HOST"
        exit 1
    fi

    # Test Flatcar connection
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "echo 'Flatcar connection OK'" >/dev/null 2>&1; then
        log "Flatcar connection: OK"
    else
        log "ERROR: Cannot connect to Flatcar host $FLATCAR_HOST"
        exit 1
    fi
}

inventory_containers() {
    log "Inventorying LXC containers on Proxmox..."

    for i in "${!CONTAINERS[@]}"; do
        local ctid="${CONTAINERS[$i]}"
        local name="${CONTAINER_NAMES[$i]}"

        log "Checking container $ctid ($name)..."

        # Check if container exists and get status
        local status
        status=$(sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct status $ctid 2>/dev/null || echo 'not found'")

        if [[ "$status" == "not found" ]]; then
            log "WARNING: Container $ctid ($name) not found on Proxmox"
            continue
        fi

        log "Container $ctid ($name): $status"

        # Get container configuration
        sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct config $ctid" > "container-$ctid-config.txt" 2>/dev/null || {
            log "WARNING: Could not get config for container $ctid"
        }
    done
}

create_backup_snapshots() {
    log "Creating backup snapshots of LXC containers..."

    for i in "${!CONTAINERS[@]}"; do
        local ctid="${CONTAINERS[$i]}"
        local name="${CONTAINER_NAMES[$i]}"
        local snapshot_name="pre-docker-migration-$(date +%Y%m%d)"

        log "Creating snapshot for container $ctid ($name)..."

        # Create snapshot
        if sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "pct snapshot $ctid $snapshot_name"; then
            log "Snapshot created: $ctid -> $snapshot_name"
        else
            log "WARNING: Failed to create snapshot for container $ctid"
        fi
    done
}

prepare_flatcar_environment() {
    log "Preparing Flatcar Docker environment..."

    # Create necessary directories on Flatcar
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "
        sudo mkdir -p /srv/docker/media-stack/{config,downloads} /srv/media/{movies,tv,music} /var/log/docker-migration
        sudo chown -R core:core /srv/docker /srv/media /var/log/docker-migration
    " || {
        log "ERROR: Failed to create directories on Flatcar"
        exit 1
    }

    # Check Docker and Docker Compose
    ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "
        docker --version && docker compose version
    " || {
        log "ERROR: Docker or Docker Compose not available on Flatcar"
        exit 1
    }

    log "Flatcar environment prepared successfully"
}

backup_container_data() {
    log "Creating data backup directory structure..."
    mkdir -p "$BACKUP_DIR"

    for i in "${!CONTAINERS[@]}"; do
        local ctid="${CONTAINERS[$i]}"
        local name="${CONTAINER_NAMES[$i]}"

        log "Backing up data for container $ctid ($name)..."

        local backup_path="$BACKUP_DIR/$name-$ctid"
        mkdir -p "$backup_path"

        # Common data paths to backup - adjust based on actual container configurations
        local data_paths=""
        case "$name" in
            "qbittorrent")
                data_paths="/var/lib/qbittorrent /home/*/.config/qBittorrent"
                ;;
            "sabnzbd")
                data_paths="/var/lib/sabnzbd /home/*/.sabnzbd"
                ;;
            "radarr")
                data_paths="/var/lib/radarr /home/*/.config/Radarr"
                ;;
            "sonarr")
                data_paths="/var/lib/sonarr /home/*/.config/NzbDrone"
                ;;
            "lidarr")
                data_paths="/var/lib/lidarr /home/*/.config/Lidarr"
                ;;
            "bazarr")
                data_paths="/var/lib/bazarr /home/*/.config/bazarr"
                ;;
            "flaresolver")
                data_paths="/opt/flaresolverr/config"
                ;;
            "prowlarr")
                data_paths="/var/lib/prowlarr /home/*/.config/Prowlarr"
                ;;
            "overseerr")
                data_paths="/var/lib/overseerr /opt/overseerr/config"
                ;;
            "tautulli")
                data_paths="/var/lib/tautulli /home/*/.config/Tautulli"
                ;;
        esac

        # Create initial rsync backup (dry run first)
        for path in $data_paths; do
            log "Backing up $path from container $ctid..."
            sshpass -p "$PROXMOX_PASSWORD" rsync -avz --dry-run -e "ssh -o StrictHostKeyChecking=no" \
                "$PROXMOX_USER@$PROXMOX_HOST:$path" "$backup_path/" 2>/dev/null || {
                log "NOTE: Path $path not found or accessible in container $ctid"
            }
        done
    done
}

generate_migration_plan() {
    log "Generating migration plan file..."

    cat > migration-plan.txt << EOF
# LXC to Docker Migration Plan
# Generated on $(date)

## Containers to migrate:
EOF

    for i in "${!CONTAINERS[@]}"; do
        local ctid="${CONTAINERS[$i]}"
        local name="${CONTAINER_NAMES[$i]}"
        local ip="192.168.100.$ctid"

        echo "- Container $ctid: $name (IP: $ip)" >> migration-plan.txt
    done

    cat >> migration-plan.txt << EOF

## Migration steps:
1. Stop all LXC containers
2. Sync data to Flatcar staging area
3. Start Docker containers with macvlan network
4. Validate services
5. Update DNS/firewall rules as needed

## Rollback plan:
1. Stop Docker containers
2. Start LXC containers
3. Restore from snapshots if needed

EOF

    log "Migration plan saved to migration-plan.txt"
}

main() {
    log "Starting pre-migration preparation..."

    check_dependencies
    test_connections
    inventory_containers
    create_backup_snapshots
    prepare_flatcar_environment
    backup_container_data
    generate_migration_plan

    log "Pre-migration preparation completed successfully!"
    log "Next steps:"
    log "1. Review migration-plan.txt"
    log "2. Verify container configurations in container-*-config.txt files"
    log "3. Run the main migration script when ready"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi