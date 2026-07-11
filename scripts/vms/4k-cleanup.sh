#!/bin/bash
# 4k-cleanup.sh - One-shot 4K movie cleanup: delete, downgrade to 1080p, keep select titles
# Deploy to Flatcar VM at /opt/bin/4k-cleanup.sh
#
# Usage: ./4k-cleanup.sh [--dry-run] [--deletions-only] [--downgrades-only]
#
# Actions:
#   1. DELETE 6 movies entirely (addImportExclusion to prevent re-adding)
#   2. DOWNGRADE 41 movies: switch to HD-1080p profile, delete 4K file, trigger search
#   3. KEEP 13 select movies as-is (no action)
#
# Requires:
#   - .env file with RADARR_API_KEY
#   - jq installed
#   - Run on Flatcar VM 100 (localhost access to Radarr)

set -euo pipefail

# Configuration
ENV_FILE="${ENV_FILE:-/srv/docker/media-stack/.env}"
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
LOG_PREFIX="[4k-cleanup]"
BATCH_SIZE=5
BATCH_DELAY=10  # seconds between batches

# Mode flags
DRY_RUN=false
DELETIONS_ONLY=false
DOWNGRADES_ONLY=false

# Quality profile IDs
PROFILE_HD=4       # HD-1080p (existing)

# Movies to DELETE entirely (Radarr IDs)
DELETE_IDS=(258 36 269 267 259 255)
declare -A DELETE_TITLES=(
    [258]="Conclave (2024)"
    [36]="Dungeons & Dragons: Honor Among Thieves (2023)"
    [269]="F1 (2025)"
    [267]="Lilo & Stitch (2025)"
    [259]="Sinners (2025)"
    [255]="Thunderbolts* (2025)"
)

# Movies to DOWNGRADE to 1080p (Radarr IDs)
DOWNGRADE_IDS=(274 2 230 260 330 328 318 324 320 322 321 317 319 240 285 263 109 112 132 136 329 181 337 190 232 277 249 275 325 327 326 243 247 242 165 250 256 226 235 261 237)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --deletions-only)
            DELETIONS_ONLY=true
            shift
            ;;
        --downgrades-only)
            DOWNGRADES_ONLY=true
            shift
            ;;
        --env)
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n        Show what would be done (no changes)"
            echo "  --deletions-only     Only process deletions"
            echo "  --downgrades-only    Only process downgrades"
            echo "  --env PATH           Path to .env file"
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
    exit 1
fi

[[ -z "${RADARR_API_KEY:-}" ]] && { echo "ERROR: RADARR_API_KEY not set"; exit 1; }

# Logging
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"; }

print_color() {
    local color=$1 message=$2
    echo -e "${color}${message}${NC}"
}

# Radarr API helper
radarr_api() {
    local method=${1:-GET}
    local endpoint=$2
    local data=${3:-}

    case "$method" in
        GET)
            curl -sf -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
            ;;
        DELETE)
            curl -sf -X DELETE -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
            ;;
        PUT|POST)
            curl -sf -X "$method" -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
                -d "$data" "$RADARR_URL/api/v3$endpoint"
            ;;
    esac
}

# Verify Radarr is reachable
verify_radarr() {
    if ! radarr_api GET "/system/status" >/dev/null 2>&1; then
        echo "ERROR: Cannot reach Radarr at $RADARR_URL"
        exit 1
    fi
    log "Radarr is reachable"
}

# Get movie details by ID
get_movie() {
    radarr_api GET "/movie/$1"
}

# ============================================================================
# Phase 1: DELETE movies
# ============================================================================

process_deletions() {
    print_color "$RED" "=== PHASE 1: DELETING ${#DELETE_IDS[@]} movies ==="
    echo ""

    local deleted=0 failed=0

    for id in "${DELETE_IDS[@]}"; do
        local title="${DELETE_TITLES[$id]:-ID $id}"

        # Verify movie exists and get size
        local movie_json
        movie_json=$(get_movie "$id" 2>/dev/null) || {
            print_color "$YELLOW" "  SKIP: $title (ID $id) - not found in Radarr"
            ((failed++)) || true
            continue
        }

        local size_bytes actual_title has_file
        actual_title=$(echo "$movie_json" | jq -r '.title // "Unknown"')
        size_bytes=$(echo "$movie_json" | jq -r '.sizeOnDisk // 0')
        has_file=$(echo "$movie_json" | jq -r '.hasFile')
        local size_gb
        size_gb=$(echo "scale=1; $size_bytes / 1073741824" | bc 2>/dev/null || echo "?")

        if [[ "$DRY_RUN" == "true" ]]; then
            print_color "$YELLOW" "  [DRY RUN] Would delete: $actual_title (${size_gb} GB)"
        else
            log "Deleting: $actual_title (ID $id, ${size_gb} GB)"
            if radarr_api DELETE "/movie/${id}?deleteFiles=true&addImportExclusion=true" >/dev/null 2>&1; then
                print_color "$GREEN" "  DELETED: $actual_title (${size_gb} GB)"
                ((deleted++)) || true
            else
                print_color "$RED" "  FAILED: $actual_title (ID $id)"
                ((failed++)) || true
            fi
        fi
    done

    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run: would delete ${#DELETE_IDS[@]} movies"
    else
        log "Deleted: $deleted, Failed: $failed"
    fi
}

# ============================================================================
# Phase 2: DOWNGRADE movies to 1080p
# ============================================================================

process_downgrades() {
    local total=${#DOWNGRADE_IDS[@]}
    print_color "$BLUE" "=== PHASE 2: DOWNGRADING $total movies to 1080p ==="
    echo ""

    local downgraded=0 failed=0 batch_count=0

    for id in "${DOWNGRADE_IDS[@]}"; do
        # Get current movie data
        local movie_json
        movie_json=$(get_movie "$id" 2>/dev/null) || {
            print_color "$YELLOW" "  SKIP: ID $id - not found in Radarr"
            ((failed++)) || true
            continue
        }

        local actual_title current_profile has_file movie_file_id size_bytes
        actual_title=$(echo "$movie_json" | jq -r '.title // "Unknown"')
        current_profile=$(echo "$movie_json" | jq -r '.qualityProfileId')
        has_file=$(echo "$movie_json" | jq -r '.hasFile')
        movie_file_id=$(echo "$movie_json" | jq -r '.movieFile.id // empty')
        size_bytes=$(echo "$movie_json" | jq -r '.sizeOnDisk // 0')
        local size_gb
        size_gb=$(echo "scale=1; $size_bytes / 1073741824" | bc 2>/dev/null || echo "?")

        if [[ "$DRY_RUN" == "true" ]]; then
            print_color "$YELLOW" "  [DRY RUN] Would downgrade: $actual_title (${size_gb} GB, profile $current_profile → $PROFILE_HD)"
            continue
        fi

        log "Downgrading: $actual_title (ID $id, ${size_gb} GB)"

        # Step 1: Switch quality profile to HD-1080p
        # Update the movie with new profile ID (PUT requires full movie object)
        local updated_json
        updated_json=$(echo "$movie_json" | jq --argjson profile "$PROFILE_HD" '.qualityProfileId = $profile')
        if ! radarr_api PUT "/movie/$id" "$updated_json" >/dev/null 2>&1; then
            print_color "$RED" "  FAILED profile switch: $actual_title"
            ((failed++)) || true
            continue
        fi

        # Step 2: Delete existing 4K file if present
        if [[ "$has_file" == "true" ]] && [[ -n "$movie_file_id" ]]; then
            if radarr_api DELETE "/moviefile/$movie_file_id" >/dev/null 2>&1; then
                log "  Deleted 4K file (moviefile ID $movie_file_id)"
            else
                print_color "$YELLOW" "  WARN: Failed to delete 4K file for $actual_title"
            fi
        fi

        # Step 3: Trigger search for 1080p replacement
        if radarr_api POST "/command" "{\"name\":\"MoviesSearch\",\"movieIds\":[$id]}" >/dev/null 2>&1; then
            log "  Triggered 1080p search"
        else
            print_color "$YELLOW" "  WARN: Failed to trigger search for $actual_title"
        fi

        print_color "$GREEN" "  DOWNGRADED: $actual_title (profile → HD-1080p, search triggered)"
        ((downgraded++)) || true
        ((batch_count++)) || true

        # Batch delay to avoid hammering indexers
        if [[ $batch_count -ge $BATCH_SIZE ]]; then
            batch_count=0
            local remaining=$((total - downgraded - failed))
            if [[ $remaining -gt 0 ]]; then
                log "Batch complete. Waiting ${BATCH_DELAY}s before next batch ($remaining remaining)..."
                sleep "$BATCH_DELAY"
            fi
        fi
    done

    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run: would downgrade $total movies"
    else
        log "Downgraded: $downgraded, Failed: $failed"
    fi
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    echo ""
    print_color "$BLUE" "=============================================="
    print_color "$BLUE" "           4K CLEANUP SUMMARY"
    print_color "$BLUE" "=============================================="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        print_color "$YELLOW" "Mode: DRY RUN (no changes made)"
        echo ""
        echo "Planned actions:"
        [[ "$DOWNGRADES_ONLY" != "true" ]] && echo "  - Delete ${#DELETE_IDS[@]} movies (~244 GB)"
        [[ "$DELETIONS_ONLY" != "true" ]] && echo "  - Downgrade ${#DOWNGRADE_IDS[@]} movies to 1080p (~1.4 TB freed)"
        echo "  - Keep 13 movies in 4K (no action)"
        echo ""
        echo "Estimated total savings: ~1.7 TB"
        echo ""
        echo "To execute: $0"
        echo "  $0 --deletions-only    # Deletions first"
        echo "  $0 --downgrades-only   # Then downgrades"
    else
        echo "Cleanup complete."
        echo ""
        echo "Next steps:"
        echo "  1. Check Radarr UI for correct profile assignments"
        echo "  2. Monitor download queue for 1080p replacements"
        echo "  3. Verify disk space:"
        echo "     ssh root@192.168.100.4 'zfs list rpool/shared/media'"
    fi

    echo ""
    print_color "$BLUE" "=============================================="
}

# ============================================================================
# Main
# ============================================================================

main() {
    log "Starting 4K cleanup..."
    [[ "$DRY_RUN" == "true" ]] && print_color "$YELLOW" "=== DRY RUN MODE ==="

    verify_radarr

    if [[ "$DOWNGRADES_ONLY" != "true" ]]; then
        process_deletions
    fi

    if [[ "$DELETIONS_ONLY" != "true" ]]; then
        process_downgrades
    fi

    print_summary
    log "Done!"
}

main "$@"
