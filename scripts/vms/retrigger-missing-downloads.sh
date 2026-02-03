#!/bin/bash
# retrigger-missing-downloads.sh - Find stuck Overseerr requests and retrigger searches
# Deploy to Flatcar VM at /opt/bin/retrigger-missing-downloads.sh
#
# Usage: ./retrigger-missing-downloads.sh [--dry-run]
#
# Requires:
# - .env file with API keys (see .env.example)
# - jq installed (available in Flatcar)
# - All services running (Overseerr, Sonarr, Radarr, qBittorrent)
#
# What it does:
# 1. Gets pending/processing requests from Overseerr
# 2. Checks if content exists in Sonarr/Radarr
# 3. Checks if content is currently downloading in qBittorrent
# 4. For items NOT downloaded AND NOT in queue → triggers search

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-/srv/docker/media-stack/.env}"
LOG_PREFIX="[retrigger]"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --env)
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--env /path/to/.env]"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n    Show what would be retriggered without doing it"
            echo "  --env PATH       Path to .env file (default: /srv/docker/media-stack/.env)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: Environment file not found: $ENV_FILE"
    echo "Create it from .env.example with your API keys"
    exit 1
fi

# Defaults
OVERSEERR_URL="${OVERSEERR_URL:-http://localhost:5055}"
SONARR_URL="${SONARR_URL:-http://localhost:8989}"
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
QBITTORRENT_URL="${QBITTORRENT_URL:-http://localhost:8080}"

# Validate required keys
[[ -z "${OVERSEERR_API_KEY:-}" ]] && { echo "ERROR: OVERSEERR_API_KEY not set"; exit 1; }
[[ -z "${SONARR_API_KEY:-}" ]] && { echo "ERROR: SONARR_API_KEY not set"; exit 1; }
[[ -z "${RADARR_API_KEY:-}" ]] && { echo "ERROR: RADARR_API_KEY not set"; exit 1; }

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

log_info() {
    log "INFO: $1"
}

log_action() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: $1"
    else
        log "ACTION: $1"
    fi
}

die() {
    log "ERROR: $1"
    exit 1
}

# API helpers
overseerr_api() {
    local endpoint=$1
    curl -s -H "X-Api-Key: $OVERSEERR_API_KEY" "$OVERSEERR_URL/api/v1$endpoint"
}

sonarr_api() {
    local method=${1:-GET}
    local endpoint=$2
    local data=${3:-}

    if [[ "$method" == "POST" ]]; then
        curl -s -X POST -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$SONARR_URL/api/v3$endpoint"
    else
        curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3$endpoint"
    fi
}

radarr_api() {
    local method=${1:-GET}
    local endpoint=$2
    local data=${3:-}

    if [[ "$method" == "POST" ]]; then
        curl -s -X POST -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$RADARR_URL/api/v3$endpoint"
    else
        curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
    fi
}

# qBittorrent runs on gluetun network, so we exec into gluetun
qbt_api() {
    local endpoint=$1
    docker exec gluetun wget -qO- "$QBITTORRENT_URL/api/v2$endpoint" 2>/dev/null || echo "[]"
}

# Get all active torrents from qBittorrent
get_active_torrents() {
    qbt_api "/torrents/info?filter=all" | jq -r '.[].name // empty' 2>/dev/null || echo ""
}

# Check if a title is in the torrent queue (fuzzy match)
is_in_queue() {
    local title="$1"
    local queue="$2"

    # Normalize title for matching (lowercase, remove special chars)
    local normalized
    normalized=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

    # Check if any torrent name contains the normalized title
    echo "$queue" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9\n]//g' | grep -q "$normalized" 2>/dev/null
}

# Process movie requests - uses Radarr ID directly from Overseerr's externalServiceId
process_movie() {
    local radarr_id=$1
    local queue=$2

    # Get movie details from Radarr
    local movie
    movie=$(radarr_api GET "/movie/$radarr_id" 2>/dev/null)

    if [[ -z "$movie" || "$movie" == "null" || "$movie" == *"NotFound"* ]]; then
        log_info "Movie ID $radarr_id not found in Radarr"
        return 0
    fi

    local title has_file monitored
    title=$(echo "$movie" | jq -r '.title // "Unknown"')
    has_file=$(echo "$movie" | jq -r '.hasFile')
    monitored=$(echo "$movie" | jq -r '.monitored')

    # Skip if already has file
    if [[ "$has_file" == "true" ]]; then
        log_info "Movie already downloaded: $title"
        return 0
    fi

    # Skip if not monitored
    if [[ "$monitored" != "true" ]]; then
        log_info "Movie not monitored: $title"
        return 0
    fi

    # Check if in torrent queue
    if is_in_queue "$title" "$queue"; then
        log_info "Movie in download queue: $title"
        return 0
    fi

    # Retrigger search
    log_action "Triggering search for movie: $title (Radarr ID: $radarr_id)"
    echo "RETRIGGER:movie:$radarr_id:$title"

    if [[ "$DRY_RUN" != "true" ]]; then
        radarr_api POST "/command" "{\"name\":\"MoviesSearch\",\"movieIds\":[$radarr_id]}" > /dev/null
    fi
}

# Process TV series requests - uses Sonarr ID directly from Overseerr's externalServiceId
process_series() {
    local sonarr_id=$1
    local queue=$2

    # Get series details from Sonarr
    local series
    series=$(sonarr_api GET "/series/$sonarr_id" 2>/dev/null)

    if [[ -z "$series" || "$series" == "null" || "$series" == *"NotFound"* ]]; then
        log_info "Series ID $sonarr_id not found in Sonarr"
        return 0
    fi

    local title monitored episode_count episode_file_count
    title=$(echo "$series" | jq -r '.title // "Unknown"')
    monitored=$(echo "$series" | jq -r '.monitored')
    episode_count=$(echo "$series" | jq -r '.statistics.episodeCount // 0')
    episode_file_count=$(echo "$series" | jq -r '.statistics.episodeFileCount // 0')

    # Skip if not monitored
    if [[ "$monitored" != "true" ]]; then
        log_info "Series not monitored: $title"
        return 0
    fi

    # Skip if all episodes downloaded
    if [[ "$episode_count" -gt 0 && "$episode_count" == "$episode_file_count" ]]; then
        log_info "Series fully downloaded: $title ($episode_file_count/$episode_count)"
        return 0
    fi

    # Check if in torrent queue
    if is_in_queue "$title" "$queue"; then
        log_info "Series in download queue: $title"
        return 0
    fi

    # Check for missing episodes
    local missing
    missing=$(sonarr_api GET "/wanted/missing?pageSize=1000" | jq --arg id "$sonarr_id" '[.records[] | select(.seriesId == ($id | tonumber))] | length' 2>/dev/null || echo "0")

    if [[ "$missing" == "0" ]]; then
        log_info "No missing episodes for: $title"
        return 0
    fi

    # Retrigger search
    log_action "Triggering search for series: $title (Sonarr ID: $sonarr_id, $missing missing episodes)"
    echo "RETRIGGER:tv:$sonarr_id:$title"

    if [[ "$DRY_RUN" != "true" ]]; then
        sonarr_api POST "/command" "{\"name\":\"SeriesSearch\",\"seriesId\":$sonarr_id}" > /dev/null
    fi
}

main() {
    log_info "Starting retrigger scan..."
    [[ "$DRY_RUN" == "true" ]] && log_info "DRY RUN MODE - no changes will be made"

    # Get active torrent queue
    log_info "Fetching qBittorrent queue..."
    local queue
    queue=$(get_active_torrents)
    local queue_count
    queue_count=$(echo "$queue" | grep -c . 2>/dev/null || echo "0")
    log_info "Found $queue_count active torrents"

    # Get all Overseerr requests
    log_info "Fetching Overseerr requests..."
    local requests
    requests=$(overseerr_api "/request?take=500&skip=0&filter=all")

    if [[ -z "$requests" ]]; then
        die "Failed to fetch Overseerr requests"
    fi

    local total
    total=$(echo "$requests" | jq '.pageInfo.results // 0')
    log_info "Processing $total Overseerr requests..."

    # Extract approved but not available requests
    # Status codes: 1=PENDING, 2=APPROVED, 3=DECLINED
    # Media status: 1=UNKNOWN, 2=PENDING, 3=PROCESSING, 4=PARTIALLY_AVAILABLE, 5=AVAILABLE
    # externalServiceId = Radarr/Sonarr internal ID
    local pending_requests
    pending_requests=$(echo "$requests" | jq -c '.results[] | select(.status == 2) | select(.media.status < 5) | {type, externalId: .media.externalServiceId}' 2>/dev/null)

    local movies_checked=0
    local series_checked=0
    local movies_retriggered=0
    local series_retriggered=0

    # Use a temp file to capture output from subprocesses
    local output_file
    output_file=$(mktemp)

    # Process each request
    echo "$pending_requests" | while read -r request; do
        [[ -z "$request" ]] && continue

        local media_type external_id
        media_type=$(echo "$request" | jq -r '.type')
        external_id=$(echo "$request" | jq -r '.externalId')

        # Skip if no external ID (not yet added to Radarr/Sonarr)
        [[ -z "$external_id" || "$external_id" == "null" ]] && continue

        if [[ "$media_type" == "movie" ]]; then
            process_movie "$external_id" "$queue"
        elif [[ "$media_type" == "tv" ]]; then
            process_series "$external_id" "$queue"
        fi
    done > "$output_file"

    # Parse results from output
    movies_checked=$(grep -c "^RETRIGGER:movie:" "$output_file" 2>/dev/null || echo "0")
    series_checked=$(grep -c "^RETRIGGER:tv:" "$output_file" 2>/dev/null || echo "0")
    movies_retriggered=$movies_checked
    series_retriggered=$series_checked

    # Show what was retriggered
    if [[ -s "$output_file" ]]; then
        echo ""
        log_info "=== Retriggered Items ==="
        grep "^RETRIGGER:" "$output_file" | while IFS=: read -r _ type id title; do
            log_info "  $type: $title (ID: $id)"
        done
    fi

    rm -f "$output_file"

    # Summary
    echo ""
    log_info "=== Summary ==="
    log_info "Movies retriggered: $movies_retriggered"
    log_info "Series retriggered: $series_retriggered"
    log_info "Total: $((movies_retriggered + series_retriggered))"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "(Dry run - no actual searches triggered)"
    fi
}

main "$@"
