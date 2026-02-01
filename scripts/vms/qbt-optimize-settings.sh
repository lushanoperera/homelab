#!/bin/bash
# qbt-optimize-settings.sh - Apply optimized qBittorrent settings via API
# Deploy to Flatcar VM at /opt/bin/qbt-optimize-settings.sh
#
# Usage: ./qbt-optimize-settings.sh [--verify-only]
#
# Settings optimized for:
# - VM: 2 cores, 4GB RAM
# - Network: VPN (~100-300 Mbps realistic throughput)
# - Storage: NFS mount (adds latency, benefits from caching)
#
# Requires:
# - gluetun container running
# - qBittorrent WebUI running (shares gluetun network)
# - LocalHostAuth=false in qBittorrent config (for auth bypass)

set -euo pipefail

LOG_PREFIX="[qbt-optimize]"
VERIFY_ONLY=${1:-}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

die() {
    log "ERROR: $1"
    exit 1
}

# Run wget inside gluetun container (same network as qBittorrent)
gluetun_wget() {
    local url=$1
    local post_data=${2:-}
    if [[ -n "$post_data" ]]; then
        docker exec gluetun wget -qO- --post-data="$post_data" "$url" 2>/dev/null
    else
        docker exec gluetun wget -qO- "$url" 2>/dev/null
    fi
}

# Login to qBittorrent
qbt_login() {
    local response
    response=$(gluetun_wget "http://localhost:8080/api/v2/auth/login" "username=admin&password=") || return 1
    [[ "$response" == "Ok." ]]
}

# Get current preferences
get_preferences() {
    gluetun_wget "http://localhost:8080/api/v2/app/preferences"
}

# Set preferences via JSON
set_preferences() {
    local json=$1
    gluetun_wget "http://localhost:8080/api/v2/app/setPreferences" "json=$json" >/dev/null 2>&1
}

# Extract value from JSON (basic grep, no jq in gluetun)
json_value() {
    local json=$1
    local key=$2
    echo "$json" | grep -oP "\"${key}\":\s*\K[^,}]+" | tr -d '"' || echo "N/A"
}

# Build optimized settings JSON
build_settings_json() {
    cat <<'EOF'
{
    "max_connec": 200,
    "max_connec_per_torrent": 50,
    "max_uploads": 100,
    "max_uploads_per_torrent": 4,
    "disk_cache": 256,
    "disk_cache_ttl": 60,
    "async_io_threads": 4,
    "dht": true,
    "pex": true,
    "lsd": false,
    "max_active_downloads": 3,
    "max_active_uploads": 5,
    "max_active_torrents": 5,
    "dont_count_slow_torrents": true,
    "slow_torrent_dl_rate_threshold": 50,
    "slow_torrent_ul_rate_threshold": 10,
    "coalesce_reads_and_writes": true,
    "enable_utp": true,
    "encryption": 1,
    "announce_to_all_trackers": true,
    "announce_to_all_tiers": true
}
EOF
}

# Display settings comparison
show_comparison() {
    local current=$1
    local setting=$2
    local optimal=$3
    local current_val
    current_val=$(json_value "$current" "$setting")

    if [[ "$current_val" == "$optimal" ]]; then
        printf "  %-30s %s (OK)\n" "$setting:" "$current_val"
    else
        printf "  %-30s %s -> %s\n" "$setting:" "$current_val" "$optimal"
    fi
}

verify_settings() {
    local prefs
    prefs=$(get_preferences) || die "Failed to get preferences"

    log "Current vs Optimal Settings:"
    echo "────────────────────────────────────────────────────"
    echo "Connections:"
    show_comparison "$prefs" "max_connec" "200"
    show_comparison "$prefs" "max_connec_per_torrent" "50"
    show_comparison "$prefs" "max_uploads" "100"
    show_comparison "$prefs" "max_uploads_per_torrent" "4"

    echo "Cache & I/O:"
    show_comparison "$prefs" "disk_cache" "256"
    show_comparison "$prefs" "async_io_threads" "4"
    show_comparison "$prefs" "coalesce_reads_and_writes" "true"

    echo "Discovery:"
    show_comparison "$prefs" "dht" "true"
    show_comparison "$prefs" "pex" "true"
    show_comparison "$prefs" "lsd" "false"

    echo "Queue:"
    show_comparison "$prefs" "max_active_downloads" "3"
    show_comparison "$prefs" "max_active_uploads" "5"
    show_comparison "$prefs" "max_active_torrents" "5"

    echo "Advanced:"
    show_comparison "$prefs" "enable_utp" "true"
    show_comparison "$prefs" "encryption" "1"
    echo "────────────────────────────────────────────────────"
}

apply_settings() {
    local settings_json
    settings_json=$(build_settings_json)

    # Compact JSON for wget (remove newlines/spaces)
    local compact_json
    compact_json=$(echo "$settings_json" | tr -d '\n' | tr -s ' ')

    log "Applying optimized settings..."
    if set_preferences "$compact_json"; then
        log "Settings applied successfully"
        return 0
    else
        die "Failed to apply settings"
    fi
}

main() {
    log "qBittorrent Settings Optimizer"
    log "=============================="

    # Check container is running
    if ! docker ps --format '{{.Names}}' | grep -q '^gluetun$'; then
        die "gluetun container not running"
    fi

    # Login
    log "Authenticating with qBittorrent..."
    qbt_login || die "Failed to login (ensure LocalHostAuth=false)"

    if [[ "$VERIFY_ONLY" == "--verify-only" ]]; then
        verify_settings
        exit 0
    fi

    # Show before state
    log "Current settings:"
    verify_settings

    # Apply settings
    apply_settings

    # Wait for settings to persist
    sleep 2

    # Verify after
    log ""
    log "Verifying applied settings:"
    verify_settings

    log ""
    log "Done! Settings optimized for:"
    log "  - 2 CPU cores, 4GB RAM"
    log "  - VPN throughput (~200 Mbps)"
    log "  - NFS storage (256MB cache, 4 I/O threads)"
}

main "$@"
