#!/bin/bash
# media-cleanup.sh - Safe duplicate removal with *arr and Plex sync
# Deploy to Flatcar VM at /opt/bin/media-cleanup.sh
#
# Usage: ./media-cleanup.sh [--dry-run] [--auto] [--interactive]
#
# Modes:
#   --dry-run      Show what would be deleted (default)
#   --auto         Auto-delete obvious duplicates (CD splits, CAM rips)
#   --interactive  Prompt for each duplicate set
#
# Safety features:
#   - Files moved to trash (not permanently deleted)
#   - 7-day retention before permanent deletion
#   - *arr DB entries removed before files
#   - Plex notified after changes
#   - Full audit log for recovery
#
# Requires:
#   - .env file with API keys (RADARR_API_KEY, SONARR_API_KEY, PLEX_TOKEN)
#   - jq installed
#   - Access to /mnt/media (NFS mount)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-/srv/docker/media-stack/.env}"
MEDIA_ROOT="${MEDIA_ROOT:-/mnt/media}"
TRASH_DIR="${TRASH_DIR:-$MEDIA_ROOT/.trash}"
TRASH_RETENTION_DAYS=7
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/media-cleanup}"
LOG_PREFIX="[media-cleanup]"
AUTO_DELETE_THRESHOLD=50  # Minimum score difference for auto-delete

# Mode flags
DRY_RUN=true
AUTO_MODE=false
INTERACTIVE_MODE=false

# Video extensions
VIDEO_EXTENSIONS="mkv|mp4|avi|m4v|wmv|mov|ts|m2ts"
MIN_VIDEO_SIZE=$((1024 * 1024))  # 1MB minimum

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --auto)
            DRY_RUN=false
            AUTO_MODE=true
            shift
            ;;
        --interactive)
            DRY_RUN=false
            INTERACTIVE_MODE=true
            shift
            ;;
        --env)
            ENV_FILE="$2"
            shift 2
            ;;
        --media-root)
            MEDIA_ROOT="$2"
            shift 2
            ;;
        --trash-dir)
            TRASH_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Modes (mutually exclusive):"
            echo "  --dry-run        Show what would be deleted (default)"
            echo "  --auto           Auto-delete obvious duplicates"
            echo "  --interactive    Prompt for each duplicate set"
            echo ""
            echo "Options:"
            echo "  --env PATH       Path to .env file"
            echo "  --media-root PATH   Media root path (default: /mnt/media)"
            echo "  --trash-dir PATH    Trash directory (default: /mnt/media/.trash)"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run              # Preview deletions"
            echo "  $0 --auto                 # Auto-delete safe duplicates"
            echo "  $0 --interactive          # Manual review each set"
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

# Source quality functions
QUALITY_SCRIPT="${SCRIPT_DIR}/media-quality.sh"
if [[ -f "$QUALITY_SCRIPT" ]]; then
    # shellcheck disable=SC1090
    source "$QUALITY_SCRIPT"
elif [[ -f "/opt/bin/media-quality.sh" ]]; then
    # shellcheck disable=SC1091
    source "/opt/bin/media-quality.sh"
else
    echo "ERROR: media-quality.sh not found"
    exit 1
fi

# API URLs
SONARR_URL="${SONARR_URL:-http://localhost:8989}"
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
PLEX_URL="${PLEX_URL:-http://192.168.100.38:32400}"

# Verify API keys
[[ -z "${RADARR_API_KEY:-}" ]] && { echo "ERROR: RADARR_API_KEY not set"; exit 1; }
[[ -z "${SONARR_API_KEY:-}" ]] && { echo "ERROR: SONARR_API_KEY not set"; exit 1; }

# Create directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TRASH_DIR"

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1" >&2
}

log_info() { log "INFO: $1"; }
log_warn() { log "WARN: $1"; }
log_error() { log "ERROR: $1"; }

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    local gb=$((1073741824))
    local mb=$((1048576))
    if [[ $bytes -ge $gb ]]; then
        local whole=$((bytes / gb))
        local frac=$(((bytes % gb) * 10 / gb))
        echo "${whole}.${frac}GB"
    elif [[ $bytes -ge $mb ]]; then
        local whole=$((bytes / mb))
        local frac=$(((bytes % mb) * 10 / mb))
        echo "${whole}.${frac}MB"
    else
        echo "${bytes}B"
    fi
}

# ============================================================================
# API Functions
# ============================================================================

# Generic API call with method support
radarr_api() {
    local method="${1:-GET}"
    local endpoint="$2"
    local data="${3:-}"

    if [[ "$method" == "GET" ]]; then
        curl -sf -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
    elif [[ "$method" == "DELETE" ]]; then
        curl -sf -X DELETE -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
    elif [[ "$method" == "POST" ]]; then
        curl -sf -X POST -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$RADARR_URL/api/v3$endpoint"
    fi
}

sonarr_api() {
    local method="${1:-GET}"
    local endpoint="$2"
    local data="${3:-}"

    if [[ "$method" == "GET" ]]; then
        curl -sf -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3$endpoint"
    elif [[ "$method" == "DELETE" ]]; then
        curl -sf -X DELETE -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3$endpoint"
    elif [[ "$method" == "POST" ]]; then
        curl -sf -X POST -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$SONARR_URL/api/v3$endpoint"
    fi
}

plex_api() {
    local method="${1:-GET}"
    local endpoint="$2"

    if [[ -z "${PLEX_TOKEN:-}" ]]; then
        log_warn "PLEX_TOKEN not set, skipping Plex API call"
        return 1
    fi

    if [[ "$method" == "GET" ]]; then
        curl -sf -H "X-Plex-Token: $PLEX_TOKEN" -H "Accept: application/json" "$PLEX_URL$endpoint"
    elif [[ "$method" == "POST" ]]; then
        curl -sf -X POST -H "X-Plex-Token: $PLEX_TOKEN" "$PLEX_URL$endpoint"
    fi
}

# Get Radarr movie file ID by path
# Returns: file_id or empty if not found
get_radarr_file_id() {
    local path="$1"  # Full path like /movies/Title (Year)/file.mkv

    # Get all movie files and find the one matching our path
    radarr_api GET "/moviefile" | jq -r --arg p "$path" \
        '.[] | select(.path == $p) | .id' 2>/dev/null || echo ""
}

# Get Radarr movie ID by folder path
get_radarr_movie_id() {
    local folder_path="$1"  # Container path like /movies/Title (Year)

    radarr_api GET "/movie" | jq -r --arg p "$folder_path" \
        '.[] | select(.path == $p) | .id' 2>/dev/null || echo ""
}

# Delete file from Radarr (removes DB entry, not the file itself)
delete_radarr_file() {
    local file_id="$1"
    radarr_api DELETE "/moviefile/$file_id" 2>/dev/null
}

# Refresh Radarr movie after deletion
refresh_radarr_movie() {
    local movie_id="$1"
    radarr_api POST "/command" "{\"name\":\"RefreshMovie\",\"movieIds\":[$movie_id]}" >/dev/null 2>&1
}

# Get Sonarr episode file ID by path
get_sonarr_file_id() {
    local path="$1"

    sonarr_api GET "/episodefile" | jq -r --arg p "$path" \
        '.[] | select(.path == $p) | .id' 2>/dev/null || echo ""
}

# Get Sonarr series ID by folder path
get_sonarr_series_id() {
    local folder_path="$1"

    sonarr_api GET "/series" | jq -r --arg p "$folder_path" \
        '.[] | select(.path == $p) | .id' 2>/dev/null || echo ""
}

# Delete file from Sonarr
delete_sonarr_file() {
    local file_id="$1"
    sonarr_api DELETE "/episodefile/$file_id" 2>/dev/null
}

# Refresh Sonarr series after deletion
refresh_sonarr_series() {
    local series_id="$1"
    sonarr_api POST "/command" "{\"name\":\"RefreshSeries\",\"seriesId\":$series_id}" >/dev/null 2>&1
}

# Get Plex library section IDs
get_plex_sections() {
    plex_api GET "/library/sections" 2>/dev/null | \
        jq -r '.MediaContainer.Directory[] | "\(.key)|\(.type)|\(.title)"' 2>/dev/null || echo ""
}

# Trigger Plex library scan
plex_scan_library() {
    local section_id="$1"
    local path="${2:-}"

    if [[ -n "$path" ]]; then
        # Partial scan (faster) - URL encode the path
        local encoded_path
        encoded_path=$(printf '%s' "$path" | jq -sRr @uri)
        plex_api POST "/library/sections/$section_id/refresh?path=$encoded_path" 2>/dev/null
    else
        # Full section scan
        plex_api POST "/library/sections/$section_id/refresh" 2>/dev/null
    fi
}

# ============================================================================
# Trash System
# ============================================================================

# Move file to trash instead of permanent delete
safe_delete() {
    local file="$1"
    local date_dir
    date_dir=$(date +%Y-%m-%d)
    local trash_path="$TRASH_DIR/$date_dir/$(basename "$file")"

    # Handle filename collisions
    local counter=1
    while [[ -e "$trash_path" ]]; do
        local base="${trash_path%.*}"
        local ext="${trash_path##*.}"
        trash_path="${base}_${counter}.${ext}"
        ((counter++)) || true
    done

    sudo mkdir -p "$(dirname "$trash_path")"
    sudo mv "$file" "$trash_path"

    # Log deletion for recovery
    echo "$(date -Iseconds)|$file|$trash_path" | sudo tee -a "$TRASH_DIR/deletion_log.txt" >/dev/null

    echo "$trash_path"
}

# Cleanup old trash (call from cron)
cleanup_trash() {
    log_info "Cleaning up trash older than $TRASH_RETENTION_DAYS days..."
    find "$TRASH_DIR" -type f -mtime +$TRASH_RETENTION_DAYS -delete 2>/dev/null || true
    find "$TRASH_DIR" -type d -empty -delete 2>/dev/null || true
}

# ============================================================================
# Duplicate Detection and Cleanup
# ============================================================================

# Get video files in a folder with details
# Returns: filename|size|full_path (one per line)
get_folder_videos() {
    local folder="$1"
    find "$folder" -maxdepth 2 -type f -regextype posix-extended \
        -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c \
        -printf '%f|%s|%p\n' 2>/dev/null | sort -t'|' -k2 -rn
}

# Process a single duplicate folder
# Returns: number of files deleted
process_duplicate_folder() {
    local folder="$1"
    local media_type="$2"  # "movie" or "tv"
    local deleted_count=0
    local deleted_size=0

    # Get all video files with details
    local files=()
    local sizes=()
    local paths=()
    local scores=()

    while IFS='|' read -r filename size full_path; do
        [[ -z "$filename" ]] && continue
        files+=("$filename")
        sizes+=("$size")
        paths+=("$full_path")
        scores+=("$(get_quality_score "$filename")")
    done < <(get_folder_videos "$folder")

    local file_count=${#files[@]}
    [[ $file_count -lt 2 ]] && return 0

    # Find best file (highest score, largest size as tiebreaker)
    local best_idx=0
    local best_score=${scores[0]}
    local best_size=${sizes[0]}

    for ((i=1; i<file_count; i++)); do
        if [[ ${scores[$i]} -gt $best_score ]] || \
           ([[ ${scores[$i]} -eq $best_score ]] && [[ ${sizes[$i]} -gt $best_size ]]); then
            best_idx=$i
            best_score=${scores[$i]}
            best_size=${sizes[$i]}
        fi
    done

    local folder_name
    folder_name=$(basename "$folder")

    echo "" >&2
    print_color "$BLUE" "=== $folder_name ===" >&2
    echo "Files: $file_count" >&2
    echo "" >&2

    # Show all files with quality info
    for ((i=0; i<file_count; i++)); do
        local tier
        tier=$(get_quality_tier "${scores[$i]}")
        local human_size
        human_size=$(format_bytes "${sizes[$i]}")

        if [[ $i -eq $best_idx ]]; then
            print_color "$GREEN" "  [KEEP] ${files[$i]}" >&2
            echo "         $human_size | Score: ${scores[$i]} | Tier: $tier" >&2
        else
            print_color "$RED" "  [DELETE] ${files[$i]}" >&2
            echo "           $human_size | Score: ${scores[$i]} | Tier: $tier" >&2
        fi
    done
    echo "" >&2

    # Determine action based on mode
    if [[ "$DRY_RUN" == "true" ]]; then
        # Just record what would be deleted
        for ((i=0; i<file_count; i++)); do
            [[ $i -eq $best_idx ]] && continue
            echo "${paths[$i]}|${sizes[$i]}|${scores[$i]}" >> "$OUTPUT_DIR/proposed_deletions.txt"
            deleted_size=$((deleted_size + sizes[$i]))
            ((deleted_count++)) || true
        done
        echo "Would delete $deleted_count file(s), freeing $(format_bytes $deleted_size)" >&2
        echo "$deleted_count"
        return 0
    fi

    # Process deletions
    for ((i=0; i<file_count; i++)); do
        [[ $i -eq $best_idx ]] && continue

        local should_delete=false
        local file_path="${paths[$i]}"
        local filename="${files[$i]}"

        if [[ "$AUTO_MODE" == "true" ]]; then
            # Check if safe to auto-delete
            if is_safe_auto_delete "$filename" "${files[$best_idx]}"; then
                should_delete=true
                log_info "Auto-deleting: $filename (safe quality difference)"
            else
                log_info "Skipping: $filename (quality too close, use --interactive)"
            fi
        elif [[ "$INTERACTIVE_MODE" == "true" ]]; then
            echo -n "Delete ${files[$i]}? [y/N/s(kip all)] " >&2
            read -r response
            case "$response" in
                y|Y) should_delete=true ;;
                s|S) return $deleted_count ;;
                *) continue ;;
            esac
        fi

        if [[ "$should_delete" == "true" ]]; then
            # Delete from *arr first
            if [[ "$media_type" == "movie" ]]; then
                # Convert filesystem path to container path
                local container_path="${file_path/$MEDIA_ROOT//}"
                container_path="/movies${container_path#/movies}"

                local file_id
                file_id=$(get_radarr_file_id "$container_path")
                if [[ -n "$file_id" ]]; then
                    log_info "Removing from Radarr DB: file_id=$file_id"
                    delete_radarr_file "$file_id" || log_warn "Failed to delete from Radarr"
                fi
            elif [[ "$media_type" == "tv" ]]; then
                local container_path="${file_path/$MEDIA_ROOT//}"
                container_path="/tv${container_path#/tv}"

                local file_id
                file_id=$(get_sonarr_file_id "$container_path")
                if [[ -n "$file_id" ]]; then
                    log_info "Removing from Sonarr DB: file_id=$file_id"
                    delete_sonarr_file "$file_id" || log_warn "Failed to delete from Sonarr"
                fi
            fi

            # Move to trash
            local trash_path
            trash_path=$(safe_delete "$file_path")
            log_info "Moved to trash: $trash_path"

            deleted_size=$((deleted_size + sizes[$i]))
            ((deleted_count++)) || true

            # Log to output
            echo "$(date -Iseconds)|DELETED|${file_path}|${trash_path}" >> "$OUTPUT_DIR/cleanup_log.txt"
        fi
    done

    if [[ $deleted_count -gt 0 ]]; then
        echo "Deleted $deleted_count file(s), freed $(format_bytes $deleted_size)" >&2

        # Trigger *arr refresh
        if [[ "$media_type" == "movie" ]]; then
            local container_folder="/movies/$(basename "$folder")"
            local movie_id
            movie_id=$(get_radarr_movie_id "$container_folder")
            if [[ -n "$movie_id" ]]; then
                log_info "Refreshing Radarr movie: $movie_id"
                refresh_radarr_movie "$movie_id" || true
            fi
        elif [[ "$media_type" == "tv" ]]; then
            local show_folder
            show_folder=$(dirname "$folder")
            local container_folder="/tv/$(basename "$show_folder")"
            local series_id
            series_id=$(get_sonarr_series_id "$container_folder")
            if [[ -n "$series_id" ]]; then
                log_info "Refreshing Sonarr series: $series_id"
                refresh_sonarr_series "$series_id" || true
            fi
        fi
    fi

    echo "$deleted_count"
}

# Find and process all duplicate folders
find_and_process_duplicates() {
    local total_deleted=0
    local total_freed=0
    local folders_processed=0

    # Initialize output files
    : > "$OUTPUT_DIR/proposed_deletions.txt"
    : > "$OUTPUT_DIR/cleanup_log.txt"

    echo ""
    print_color "$BLUE" "=============================================="
    print_color "$BLUE" "        MEDIA DUPLICATE CLEANUP"
    print_color "$BLUE" "=============================================="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        print_color "$YELLOW" "Mode: DRY RUN (no changes will be made)"
    elif [[ "$AUTO_MODE" == "true" ]]; then
        print_color "$GREEN" "Mode: AUTO (deleting obvious duplicates)"
    elif [[ "$INTERACTIVE_MODE" == "true" ]]; then
        print_color "$YELLOW" "Mode: INTERACTIVE (prompting for each)"
    fi
    echo ""

    # Process movies
    if [[ -d "$MEDIA_ROOT/movies" ]]; then
        print_color "$BLUE" "--- Scanning Movies ---"
        while IFS= read -r folder; do
            [[ -z "$folder" ]] && continue
            [[ "$folder" == .* || "$folder" == @* ]] && continue

            local full_path="$MEDIA_ROOT/movies/$folder"
            local video_count
            video_count=$(find "$full_path" -maxdepth 2 -type f -regextype posix-extended \
                -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c 2>/dev/null | wc -l)

            if [[ $video_count -gt 1 ]]; then
                local deleted
                deleted=$(process_duplicate_folder "$full_path" "movie")
                total_deleted=$((total_deleted + deleted))
                ((folders_processed++)) || true
            fi
        done < <(find "$MEDIA_ROOT/movies" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
    fi

    # Process TV (check for duplicate episodes within seasons)
    if [[ -d "$MEDIA_ROOT/tv" ]]; then
        print_color "$BLUE" "--- Scanning TV Shows ---"
        while IFS= read -r show; do
            [[ -z "$show" ]] && continue
            [[ "$show" == .* || "$show" == @* ]] && continue

            local show_path="$MEDIA_ROOT/tv/$show"

            # Check each season folder
            while IFS= read -r season; do
                [[ -z "$season" ]] && continue
                local season_path="$show_path/$season"
                [[ ! -d "$season_path" ]] && continue

                local video_count
                video_count=$(find "$season_path" -maxdepth 1 -type f -regextype posix-extended \
                    -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c 2>/dev/null | wc -l)

                # For TV, we need to group by episode and check for dups within each episode
                # This is more complex - for now, flag folders with many files
                if [[ $video_count -gt 1 ]]; then
                    # Group files by episode number
                    local episode_groups
                    episode_groups=$(find "$season_path" -maxdepth 1 -type f -regextype posix-extended \
                        -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c -printf '%f\n' 2>/dev/null | \
                        grep -oP 'S\d+E\d+|s\d+e\d+|\d+x\d+' | tr '[:lower:]' '[:upper:]' | sort | uniq -c | \
                        awk '$1 > 1 {print $2}')

                    # Process each episode with duplicates
                    while IFS= read -r ep; do
                        [[ -z "$ep" ]] && continue
                        # Create temp folder context for this episode's files
                        log_info "Found duplicate episode: $show/$season - $ep"
                        # TODO: Implement episode-level duplicate handling
                        ((folders_processed++)) || true
                    done <<< "$episode_groups"
                fi
            done < <(find "$show_path" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null)
        done < <(find "$MEDIA_ROOT/tv" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
    fi

    # Summary
    echo ""
    print_color "$BLUE" "=============================================="
    print_color "$BLUE" "                SUMMARY"
    print_color "$BLUE" "=============================================="
    echo ""
    echo "Folders processed: $folders_processed"

    if [[ "$DRY_RUN" == "true" ]]; then
        local proposed_count proposed_size
        proposed_count=$(wc -l < "$OUTPUT_DIR/proposed_deletions.txt" 2>/dev/null || echo 0)
        proposed_size=$(awk -F'|' '{sum += $2} END {print sum+0}' "$OUTPUT_DIR/proposed_deletions.txt" 2>/dev/null || echo 0)

        echo "Proposed deletions: $proposed_count files"
        echo "Potential space savings: $(format_bytes "$proposed_size")"
        echo ""
        echo "Review proposed deletions:"
        echo "  cat $OUTPUT_DIR/proposed_deletions.txt"
        echo ""
        echo "To execute cleanup:"
        echo "  $0 --auto          # Auto-delete safe duplicates"
        echo "  $0 --interactive   # Manual review each"
    else
        local deleted_count
        deleted_count=$(grep -c "DELETED" "$OUTPUT_DIR/cleanup_log.txt" 2>/dev/null || echo 0)
        echo "Files deleted: $deleted_count"
        echo "Trash location: $TRASH_DIR"
        echo ""

        # Trigger Plex scan if we deleted anything
        if [[ $deleted_count -gt 0 ]] && [[ -n "${PLEX_TOKEN:-}" ]]; then
            echo "Triggering Plex library scan..."
            local sections
            sections=$(get_plex_sections)
            while IFS='|' read -r key type title; do
                [[ -z "$key" ]] && continue
                if [[ "$type" == "movie" ]] || [[ "$type" == "show" ]]; then
                    log_info "Scanning Plex library: $title (section $key)"
                    plex_scan_library "$key" || log_warn "Failed to scan $title"
                fi
            done <<< "$sections"
        fi
    fi

    echo ""
    print_color "$BLUE" "=============================================="
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "Starting media cleanup..."
    log_info "Media root: $MEDIA_ROOT"
    log_info "Trash directory: $TRASH_DIR"

    # Verify media mount
    if [[ ! -d "$MEDIA_ROOT" ]]; then
        log_error "Media root not accessible: $MEDIA_ROOT"
        exit 1
    fi

    # Run cleanup
    find_and_process_duplicates

    log_info "Cleanup complete!"
}

main "$@"
