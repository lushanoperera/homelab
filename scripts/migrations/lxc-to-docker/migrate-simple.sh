#!/usr/bin/env bash
# Simplified LXC to Docker migration script
# Single IP architecture with port mapping

set -euo pipefail

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-192.168.100.38}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_PASSWORD="${PROXMOX_PASSWORD:-}"
FLATCAR_HOST="${FLATCAR_HOST:-192.168.100.100}"
FLATCAR_USER="${FLATCAR_USER:-core}"
LOG_FILE="${LOG_FILE:-migration-simple-$(date +%Y%m%d_%H%M%S).log}"
DRY_RUN="${DRY_RUN:-false}"
KEEP_LXC_RUNNING="${KEEP_LXC_RUNNING:-false}"

# Service definitions (bash 3.2 compatible)
SERVICES="qbittorrent:8080 sabnzbd:8081 radarr:7878 sonarr:8989 lidarr:8686 bazarr:6767 flaresolverr:8191 prowlarr:9696 overseerr:5055 tautulli:8181"

# Container mapping (LXC ID:service)
CONTAINERS="109:qbittorrent 110:sabnzbd 111:radarr 112:sonarr 113:lidarr 114:bazarr 115:flaresolverr 116:prowlarr 117:overseerr 121:tautulli"

# Helper functions for bash 3.2 compatibility
get_service_port() {
    local service="$1"
    for pair in $SERVICES; do
        local svc="${pair%:*}"
        local port="${pair#*:}"
        if [ "$svc" = "$service" ]; then
            echo "$port"
            return
        fi
    done
}

get_container_service() {
    local lxc_id="$1"
    for pair in $CONTAINERS; do
        local id="${pair%:*}"
        local service="${pair#*:}"
        if [ "$id" = "$lxc_id" ]; then
            echo "$service"
            return
        fi
    done
}

get_service_lxc_id() {
    local service="$1"
    for pair in $CONTAINERS; do
        local id="${pair%:*}"
        local svc="${pair#*:}"
        if [ "$svc" = "$service" ]; then
            echo "$id"
            return
        fi
    done
}

# Migration order (dependency-based)
MIGRATION_ORDER=(
    "flaresolverr"
    "prowlarr"
    "qbittorrent"
    "sabnzbd"
    "radarr"
    "sonarr"
    "lidarr"
    "bazarr"
    "overseerr"
    "tautulli"
)

# Logging function
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Error handling
error() {
    log "ERROR: $1"
    exit 1
}

# Check if running in dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    if is_dry_run; then
        log "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log "Executing: $cmd"
        eval "$cmd"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check required commands
    for cmd in ssh rsync docker; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command not found: $cmd"
        fi
    done

    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "echo 'Connected'" >/dev/null 2>&1; then
        error "Cannot connect to Proxmox host: $PROXMOX_HOST"
    fi

    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "echo 'Connected'" >/dev/null 2>&1; then
        error "Cannot connect to Flatcar host: $FLATCAR_HOST"
    fi

    log "✓ Prerequisites check passed"
}

# Check port availability
check_port_availability() {
    log "Checking port availability on Flatcar host..."

    local unavailable_ports=()

    for pair in $SERVICES; do
        local service="${pair%:*}"
        local port="${pair#*:}"
        if ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "netstat -tlnp | grep -q ':$port '" 2>/dev/null; then
            unavailable_ports+=("$port")
            log "✗ Port $port is in use (needed for $service)"
        else
            log "✓ Port $port is available (for $service)"
        fi
    done

    if [ ${#unavailable_ports[@]} -gt 0 ]; then
        error "Ports in use: ${unavailable_ports[*]}. Please free these ports before migration."
    fi

    log "✓ All required ports are available"
}

# Create LXC snapshots
create_snapshots() {
    log "Creating LXC container snapshots..."

    local timestamp=$(date +%Y%m%d_%H%M%S)

    for pair in $CONTAINERS; do
        local lxc_id="${pair%:*}"
        local snapshot_name="pre-migration-$timestamp"
        local cmd="pct snapshot $lxc_id $snapshot_name"

        if ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "$cmd" 2>/dev/null; then
            log "✓ Created snapshot for LXC $lxc_id: $snapshot_name"
        else
            log "✗ Failed to create snapshot for LXC $lxc_id"
        fi
    done

    log "✓ Snapshot creation completed"
}

# Prepare Flatcar environment
prepare_flatcar_environment() {
    log "Preparing Flatcar environment..."

    # Create directory structure
    local dirs=(
        "/srv/docker/media-stack"
        "/srv/docker/media-stack/config"
    )

    for pair in $SERVICES; do
        local service="${pair%:*}"
        dirs+=("/srv/docker/media-stack/config/$service")
    done

    for dir in "${dirs[@]}"; do
        execute "ssh -o StrictHostKeyChecking=no '$FLATCAR_USER@$FLATCAR_HOST' 'sudo mkdir -p $dir'"
        execute "ssh -o StrictHostKeyChecking=no '$FLATCAR_USER@$FLATCAR_HOST' 'sudo chown -R 1000:1000 $dir'"
    done

    # Verify media directories exist
    local media_dirs=("/mnt/media" "/mnt/media/downloads" "/mnt/media/movies" "/mnt/media/tv" "/mnt/media/music")

    for dir in "${media_dirs[@]}"; do
        if ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "[ ! -d '$dir' ]" 2>/dev/null; then
            log "⚠ Warning: Media directory does not exist: $dir"
        else
            execute "ssh -o StrictHostKeyChecking=no '$FLATCAR_USER@$FLATCAR_HOST' 'sudo chown -R 1000:1000 $dir'"
            log "✓ Verified media directory: $dir"
        fi
    done

    log "✓ Flatcar environment prepared"
}

# Get LXC container data path
get_lxc_data_path() {
    local lxc_id="$1"
    local data_path

    data_path=$(ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" \
        "pct config $lxc_id | grep 'rootfs:' | cut -d'=' -f2 | cut -d',' -f1" 2>/dev/null)

    if [[ -n "$data_path" ]]; then
        echo "/var/lib/lxc/$lxc_id/rootfs"
    else
        echo "/var/lib/lxc/$lxc_id/rootfs"
    fi
}

# Migrate single container
migrate_container() {
    local service="$1"
    local lxc_id=""

    # Find LXC ID for this service
    lxc_id=$(get_service_lxc_id "$service")

    if [[ -z "$lxc_id" ]]; then
        error "Cannot find LXC ID for service: $service"
    fi

    log "Migrating $service (LXC $lxc_id)..."

    # Stop LXC container (unless --keep-lxc is specified)
    if [[ "$KEEP_LXC_RUNNING" == "true" ]]; then
        log "Keeping LXC container $lxc_id running (--keep-lxc mode)"
    else
        log "Stopping LXC container $lxc_id..."
        execute "ssh -o StrictHostKeyChecking=no '$PROXMOX_USER@$PROXMOX_HOST' 'pct stop $lxc_id'"
    fi

    # Get LXC data path
    local lxc_data_path=$(get_lxc_data_path "$lxc_id")
    log "LXC data path: $lxc_data_path"

    # Sync configuration data
    log "Syncing configuration data for $service..."
    local source_config_paths=(
        "$lxc_data_path/config"
        "$lxc_data_path/etc/$service"
        "$lxc_data_path/var/lib/$service"
        "$lxc_data_path/opt/$service"
        "$lxc_data_path/home"
    )

    for source_path in "${source_config_paths[@]}"; do
        if ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "[ -d '$source_path' ]" 2>/dev/null; then
            log "Syncing $source_path to Flatcar..."
            execute "rsync -avz --progress --delete \
                -e 'ssh -o StrictHostKeyChecking=no' \
                '$PROXMOX_USER@$PROXMOX_HOST:$source_path/' \
                '$FLATCAR_USER@$FLATCAR_HOST:/srv/docker/media-stack/config/$service/'"
        fi
    done

    # Start Docker container
    log "Starting Docker container for $service..."
    execute "ssh -o StrictHostKeyChecking=no '$FLATCAR_USER@$FLATCAR_HOST' \
        'cd /srv/docker/media-stack && /opt/bin/docker-compose -f docker-compose.yml --env-file .env.simple up -d $service'"

    # Wait for container to be healthy
    log "Waiting for $service to become healthy..."
    local port=$(get_service_port "$service")
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "curl -s -f http://localhost:$port >/dev/null 2>&1" 2>/dev/null; then
            log "✓ $service is healthy and responding on port $port"
            break
        fi

        log "Waiting for $service to respond (attempt $attempt/$max_attempts)..."
        sleep 10
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt $max_attempts ]; then
        log "⚠ Warning: $service did not respond after $max_attempts attempts"
    fi

    log "✓ Migration completed for $service"
}

# Main migration process
run_migration() {
    log "Starting simplified LXC to Docker migration..."
    log "Target: Single IP architecture (${FLATCAR_HOST})"
    log "Dry run mode: $DRY_RUN"

    check_prerequisites
    check_port_availability

    if ! is_dry_run; then
        create_snapshots
        prepare_flatcar_environment
    fi

    # Migrate containers in dependency order
    for service in "${MIGRATION_ORDER[@]}"; do
        migrate_container "$service"
    done

    log "✓ Migration completed successfully!"
    log "All services are now available at $FLATCAR_HOST with their respective ports"
    log "Run ./scripts/validate-simple.sh to verify the migration"
}

# Prepare mode (snapshots and environment setup only)
run_prepare() {
    log "Running prepare mode..."

    check_prerequisites
    check_port_availability
    create_snapshots
    prepare_flatcar_environment

    log "✓ Preparation completed. Run without --prepare to start migration."
}

# Help function
show_help() {
    cat << EOF
Simplified LXC to Docker Migration Script

Usage: $0 [OPTIONS]

OPTIONS:
    --prepare       Run preparation phase only (snapshots, environment setup)
    --dry-run       Show what would be done without executing
    --keep-lxc      Keep LXC containers running (don't stop them during migration)
    --help          Show this help message

ENVIRONMENT VARIABLES:
    PROXMOX_HOST       Proxmox server IP (default: 192.168.100.38)
    PROXMOX_USER       Proxmox username (default: root)
    PROXMOX_PASSWORD   Proxmox password (required)
    FLATCAR_HOST       Flatcar server IP (default: 192.168.100.100)
    FLATCAR_USER       Flatcar username (default: core)
    DRY_RUN            Set to 'true' for dry run mode
    KEEP_LXC_RUNNING   Set to 'true' to keep LXC containers running
    LOG_FILE           Custom log file path

EXAMPLES:
    # Prepare environment and create snapshots
    ./migrate-simple.sh --prepare

    # Test migration (dry run)
    DRY_RUN=true ./migrate-simple.sh

    # Run migration without stopping LXC containers (recommended for safe testing)
    ./migrate-simple.sh --keep-lxc

    # Run actual migration (stops LXC containers)
    PROXMOX_PASSWORD=yourpass ./migrate-simple.sh

    # Custom configuration
    PROXMOX_HOST=192.168.1.100 FLATCAR_HOST=192.168.1.200 ./migrate-simple.sh

EOF
}

# Main execution
main() {
    # Parse command line arguments
    case "${1:-}" in
        --prepare)
            run_prepare
            ;;
        --dry-run)
            DRY_RUN=true
            run_migration
            ;;
        --keep-lxc)
            KEEP_LXC_RUNNING=true
            run_migration
            ;;
        --help)
            show_help
            ;;
        "")
            run_migration
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi