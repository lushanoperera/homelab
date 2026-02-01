#!/bin/bash
# qbt-port-sync.sh - Sync gluetun forwarded port to qBittorrent
# Deploy to Flatcar VM at /opt/bin/qbt-port-sync.sh
#
# Usage: ./qbt-port-sync.sh
#
# Requires:
# - gluetun container running with port forwarding enabled
# - qBittorrent WebUI running (shares gluetun network)
# - LocalHostAuth=false in qBittorrent config (for auth bypass)
#
# Note: API calls run inside gluetun container since qBittorrent
# uses network_mode: service:gluetun

set -euo pipefail

# Configuration
STATE_FILE="/tmp/qbt-port-sync.state"
LOG_PREFIX="[qbt-port-sync]"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

die() {
    log "ERROR: $1"
    exit 1
}

# Get forwarded port from gluetun (file-based, most reliable)
get_forwarded_port() {
    docker exec gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null | tr -d '[:space:]'
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

# Get current qBittorrent listening port
get_qbt_port() {
    local response
    response=$(gluetun_wget "http://localhost:8080/api/v2/app/preferences") || return 1
    # Parse JSON with basic tools (no jq in gluetun)
    echo "$response" | grep -oP '"listen_port":\s*\K\d+' || return 1
}

# Login to qBittorrent (localhost auth bypass - no password needed)
qbt_login() {
    local response
    response=$(gluetun_wget "http://localhost:8080/api/v2/auth/login" "username=admin&password=") || return 1
    if [[ "$response" == "Ok." ]]; then
        echo "ok"
        return 0
    fi
    return 1
}

# Set qBittorrent listening port
set_qbt_port() {
    local port=$1
    gluetun_wget "http://localhost:8080/api/v2/app/setPreferences" "json={\"listen_port\":${port}}" >/dev/null 2>&1
}

# Read last known port from state file
get_last_port() {
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" 2>/dev/null || echo ""
}

# Save current port to state file
save_port() {
    echo "$1" > "$STATE_FILE"
}

main() {
    # Get forwarded port from gluetun
    local forwarded_port
    forwarded_port=$(get_forwarded_port) || die "Failed to get forwarded port from gluetun"

    if [[ -z "$forwarded_port" || "$forwarded_port" == "0" ]]; then
        die "No valid forwarded port (got: '$forwarded_port')"
    fi

    # Check if port changed since last run
    local last_port
    last_port=$(get_last_port)

    if [[ "$forwarded_port" == "$last_port" ]]; then
        log "Port unchanged ($forwarded_port), skipping"
        exit 0
    fi

    log "Forwarded port: $forwarded_port (was: ${last_port:-unknown})"

    # Login to qBittorrent (verifies connectivity)
    qbt_login || die "Failed to connect to qBittorrent (ensure LocalHostAuth=false)"

    # Get current qBittorrent port
    local current_port
    current_port=$(get_qbt_port) || die "Failed to get current qBittorrent port"

    if [[ "$current_port" == "$forwarded_port" ]]; then
        log "qBittorrent already using port $forwarded_port"
        save_port "$forwarded_port"
        exit 0
    fi

    log "Updating qBittorrent port from $current_port to $forwarded_port"

    # Set new port
    if set_qbt_port "$forwarded_port"; then
        log "Successfully updated qBittorrent to port $forwarded_port"
        save_port "$forwarded_port"
    else
        die "Failed to update qBittorrent port"
    fi
}

main "$@"
