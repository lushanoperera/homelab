#!/bin/bash
# media-audit.sh - Cross-check Plex, Radarr, Sonarr, and filesystem for duplicates/orphans
# Deploy to Flatcar VM at /opt/bin/media-audit.sh
#
# Usage: ./media-audit.sh [--dry-run] [--no-plex] [--output-dir /path]
#
# Requires:
# - .env file with API keys
# - jq installed
# - Access to /mnt/media (NFS mount)
#
# Reports generated:
# - orphaned_movies.txt: Movies on disk but not in Radarr
# - orphaned_tv.txt: TV shows on disk but not in Sonarr
# - duplicates.txt: Folders with multiple video versions
# - plex_sync.txt: Plex vs *arr sync status (if --no-plex not set)
# - summary.json: Overall counts and recommendations

set -euo pipefail

# Configuration
ENV_FILE="${ENV_FILE:-/srv/docker/media-stack/.env}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/media-audit}"
LOG_PREFIX="[media-audit]"
INCLUDE_PLEX=true
MEDIA_ROOT="${MEDIA_ROOT:-/mnt/media}"
VIDEO_EXTENSIONS="mkv|mp4|avi|m4v|wmv|mov|ts|m2ts"
# Folders to exclude from scan (QNAP system folders, Plex folders, etc.)
EXCLUDE_FOLDERS=(".@__thumb" "@eaDir" "@Recycle" "Plex Versions" ".plexmatch")
# Minimum file size to consider as video (1MB) - filters out thumbnails
MIN_VIDEO_SIZE=$((1024 * 1024))

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-plex)
            INCLUDE_PLEX=false
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --env)
            ENV_FILE="$2"
            shift 2
            ;;
        --media-root)
            MEDIA_ROOT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-plex            Skip Plex integration"
            echo "  --output-dir PATH    Output directory (default: /tmp/media-audit)"
            echo "  --env PATH           Path to .env file"
            echo "  --media-root PATH    Media root path (default: /mnt/media)"
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

SONARR_URL="${SONARR_URL:-http://localhost:8989}"
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
PLEX_URL="${PLEX_URL:-http://192.168.100.38:32400}"

[[ -z "${SONARR_API_KEY:-}" ]] && { echo "ERROR: SONARR_API_KEY not set"; exit 1; }
[[ -z "${RADARR_API_KEY:-}" ]] && { echo "ERROR: RADARR_API_KEY not set"; exit 1; }

# Create output directory
mkdir -p "$OUTPUT_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1" >&2
}

log_info() { log "INFO: $1"; }
log_warn() { log "WARN: $1"; }
log_error() { log "ERROR: $1"; }

# API helpers
sonarr_api() {
    local endpoint=$1
    curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3$endpoint"
}

radarr_api() {
    local endpoint=$1
    curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
}

plex_api() {
    local endpoint=$1
    local token=${PLEX_TOKEN:-}
    if [[ -z "$token" ]]; then
        log_warn "PLEX_TOKEN not set, skipping Plex API call"
        echo "{}"
        return
    fi
    curl -s -H "X-Plex-Token: $token" -H "Accept: application/json" "$PLEX_URL$endpoint"
}

# Get Plex token from Plex preferences (if running on Proxmox host or LXC)
get_plex_token() {
    if [[ -n "${PLEX_TOKEN:-}" ]]; then
        echo "$PLEX_TOKEN"
        return
    fi

    # Try to get token from Plex LXC via SSH
    local token
    token=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@192.168.100.38 \
        'pct exec 105 -- grep -oP "PlexOnlineToken=\"\K[^\"]*" "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"' 2>/dev/null || echo "")

    if [[ -n "$token" ]]; then
        echo "$token"
    else
        log_warn "Could not retrieve Plex token"
        echo ""
    fi
}

# Get all movies from Radarr (returns: path|title|tmdbId|hasFile)
get_radarr_movies() {
    log_info "Fetching movies from Radarr..."
    radarr_api "/movie" | jq -r '.[] | "\(.path)|\(.title)|\(.tmdbId)|\(.hasFile)"'
}

# Get all series from Sonarr (returns: path|title|tvdbId)
get_sonarr_series() {
    log_info "Fetching series from Sonarr..."
    sonarr_api "/series" | jq -r '.[] | "\(.path)|\(.title)|\(.tvdbId)"'
}

# Check if a folder should be excluded from scanning
is_excluded_folder() {
    local folder=$1
    for excluded in "${EXCLUDE_FOLDERS[@]}"; do
        [[ "$folder" == "$excluded" ]] && return 0
    done
    # Also exclude folders starting with . or @
    [[ "$folder" == .* || "$folder" == @* ]] && return 0
    return 1
}

# Get filesystem movie folders (excluding system folders)
get_filesystem_movies() {
    log_info "Scanning filesystem for movies..."
    if [[ -d "$MEDIA_ROOT/movies" ]]; then
        find "$MEDIA_ROOT/movies" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | \
            while IFS= read -r folder; do
                is_excluded_folder "$folder" || echo "$folder"
            done | sort
    else
        log_warn "Movies directory not found: $MEDIA_ROOT/movies"
    fi
}

# Get filesystem TV folders (excluding system folders)
get_filesystem_tv() {
    log_info "Scanning filesystem for TV shows..."
    if [[ -d "$MEDIA_ROOT/tv" ]]; then
        find "$MEDIA_ROOT/tv" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | \
            while IFS= read -r folder; do
                is_excluded_folder "$folder" || echo "$folder"
            done | sort
    else
        log_warn "TV directory not found: $MEDIA_ROOT/tv"
    fi
}

# Count video files in a folder (only files >= MIN_VIDEO_SIZE)
count_video_files() {
    local folder=$1
    find "$folder" -type f -regextype posix-extended -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c 2>/dev/null | wc -l
}

# Get video file details in a folder (only files >= MIN_VIDEO_SIZE)
get_video_files() {
    local folder=$1
    find "$folder" -type f -regextype posix-extended -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c -printf '%f|%s\n' 2>/dev/null
}

# Format bytes to human readable (pure bash, no bc dependency)
format_bytes() {
    local bytes=$1
    local tb=$((1099511627776))
    local gb=$((1073741824))
    local mb=$((1048576))
    local kb=$((1024))

    if [[ $bytes -ge $tb ]]; then
        local whole=$((bytes / tb))
        local frac=$(((bytes % tb) * 10 / tb))
        echo "${whole}.${frac}TB"
    elif [[ $bytes -ge $gb ]]; then
        local whole=$((bytes / gb))
        local frac=$(((bytes % gb) * 10 / gb))
        echo "${whole}.${frac}GB"
    elif [[ $bytes -ge $mb ]]; then
        local whole=$((bytes / mb))
        local frac=$(((bytes % mb) * 10 / mb))
        echo "${whole}.${frac}MB"
    elif [[ $bytes -ge $kb ]]; then
        local whole=$((bytes / kb))
        echo "${whole}KB"
    else
        echo "${bytes}B"
    fi
}

# Find orphaned movies (on disk but not in Radarr)
find_orphaned_movies() {
    log_info "Finding orphaned movies..."

    local radarr_paths
    radarr_paths=$(get_radarr_movies | cut -d'|' -f1 | while IFS= read -r path; do basename "$path"; done | sort)

    local fs_movies
    fs_movies=$(get_filesystem_movies)

    local orphaned=()
    while IFS= read -r folder; do
        [[ -z "$folder" ]] && continue
        if ! echo "$radarr_paths" | grep -qxF "$folder"; then
            orphaned+=("$folder")
        fi
    done <<< "$fs_movies"

    if [[ ${#orphaned[@]} -gt 0 ]]; then
        printf '%s\n' "${orphaned[@]}" > "$OUTPUT_DIR/orphaned_movies.txt"
        echo "${#orphaned[@]}"
    else
        echo "0"
    fi
}

# Find orphaned TV shows (on disk but not in Sonarr)
find_orphaned_tv() {
    log_info "Finding orphaned TV shows..."

    local sonarr_paths
    sonarr_paths=$(get_sonarr_series | cut -d'|' -f1 | while IFS= read -r path; do basename "$path"; done | sort)

    local fs_tv
    fs_tv=$(get_filesystem_tv)

    local orphaned=()
    while IFS= read -r folder; do
        [[ -z "$folder" ]] && continue
        if ! echo "$sonarr_paths" | grep -qxF "$folder"; then
            orphaned+=("$folder")
        fi
    done <<< "$fs_tv"

    if [[ ${#orphaned[@]} -gt 0 ]]; then
        printf '%s\n' "${orphaned[@]}" > "$OUTPUT_DIR/orphaned_tv.txt"
        echo "${#orphaned[@]}"
    else
        echo "0"
    fi
}

# Find duplicate versions (multiple video files in same folder)
find_duplicates() {
    log_info "Finding duplicate versions..."

    local duplicates_file="$OUTPUT_DIR/duplicates.txt"
    : > "$duplicates_file"

    local dup_count=0
    local total_dup_size=0

    # Check movies
    if [[ -d "$MEDIA_ROOT/movies" ]]; then
        while IFS= read -r folder; do
            [[ -z "$folder" ]] && continue
            local full_path="$MEDIA_ROOT/movies/$folder"
            local video_count
            video_count=$(count_video_files "$full_path")

            if [[ $video_count -gt 1 ]]; then
                ((dup_count++))
                echo "=== $folder ($video_count files) ===" >> "$duplicates_file"

                local folder_size=0
                while IFS='|' read -r filename size; do
                    [[ -z "$filename" ]] && continue
                    local human_size
                    human_size=$(format_bytes "$size")
                    echo "  - $filename ($human_size)" >> "$duplicates_file"
                    folder_size=$((folder_size + size))
                done < <(get_video_files "$full_path")

                local human_total
                human_total=$(format_bytes "$folder_size")
                echo "  Total: $human_total" >> "$duplicates_file"
                echo "" >> "$duplicates_file"

                total_dup_size=$((total_dup_size + folder_size))
            fi
        done < <(get_filesystem_movies)
    fi

    # Check TV shows (duplicates within season folders)
    if [[ -d "$MEDIA_ROOT/tv" ]]; then
        while IFS= read -r show; do
            [[ -z "$show" ]] && continue
            local show_path="$MEDIA_ROOT/tv/$show"

            # Check each season folder
            while IFS= read -r season; do
                [[ -z "$season" ]] && continue
                local season_path="$show_path/$season"
                [[ ! -d "$season_path" ]] && continue

                # Group files by episode number to find duplicates (only files >= MIN_VIDEO_SIZE)
                local episode_counts
                episode_counts=$(find "$season_path" -type f -regextype posix-extended \
                    -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c -printf '%f\n' 2>/dev/null | \
                    grep -oP 'S\d+E\d+|s\d+e\d+|\d+x\d+' | tr '[:lower:]' '[:upper:]' | sort | uniq -c | sort -rn)

                while read -r count ep; do
                    [[ -z "$ep" ]] && continue
                    if [[ $count -gt 1 ]]; then
                        ((dup_count++))
                        echo "=== $show/$season - $ep ($count versions) ===" >> "$duplicates_file"
                        find "$season_path" -type f -regextype posix-extended \
                            -regex ".*\.($VIDEO_EXTENSIONS)$" -size +${MIN_VIDEO_SIZE}c \
                            \( -name "*$ep*" -o -name "*$(echo "$ep" | tr '[:upper:]' '[:lower:]')*" \) \
                            -printf '  - %f (%s bytes)\n' 2>/dev/null >> "$duplicates_file" || true
                        echo "" >> "$duplicates_file"
                    fi
                done <<< "$episode_counts"
            done < <(find "$show_path" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null)
        done < <(get_filesystem_tv)
    fi

    echo "$dup_count|$total_dup_size"
}

# Get Plex library sections
get_plex_libraries() {
    if [[ "$INCLUDE_PLEX" != "true" ]]; then
        return
    fi

    log_info "Fetching Plex libraries..."
    plex_api "/library/sections" | jq -r '.MediaContainer.Directory[] | "\(.key)|\(.type)|\(.title)"' 2>/dev/null || echo ""
}

# Get Plex library items count
get_plex_library_count() {
    local section_id=$1
    plex_api "/library/sections/$section_id/all" | jq '.MediaContainer.size // 0' 2>/dev/null || echo "0"
}

# Cross-check Plex with *arr apps
check_plex_sync() {
    if [[ "$INCLUDE_PLEX" != "true" ]]; then
        return
    fi

    log_info "Checking Plex sync status..."

    local plex_sync_file="$OUTPUT_DIR/plex_sync.txt"
    : > "$plex_sync_file"

    local plex_token
    plex_token=$(get_plex_token)

    if [[ -z "$plex_token" ]]; then
        echo "Plex token not available - skipping sync check" > "$plex_sync_file"
        return
    fi

    export PLEX_TOKEN="$plex_token"

    local libraries
    libraries=$(get_plex_libraries)

    if [[ -z "$libraries" ]]; then
        echo "Could not fetch Plex libraries" > "$plex_sync_file"
        return
    fi

    echo "=== Plex Library Sync Status ===" >> "$plex_sync_file"
    echo "" >> "$plex_sync_file"

    local radarr_count sonarr_count
    radarr_count=$(radarr_api "/movie" | jq 'length')
    sonarr_count=$(sonarr_api "/series" | jq 'length')

    while IFS='|' read -r key type title; do
        [[ -z "$key" ]] && continue

        local plex_count
        plex_count=$(get_plex_library_count "$key")

        echo "Library: $title (Type: $type)" >> "$plex_sync_file"
        echo "  Plex items: $plex_count" >> "$plex_sync_file"

        if [[ "$type" == "movie" ]]; then
            echo "  Radarr movies: $radarr_count" >> "$plex_sync_file"
            local diff=$((plex_count - radarr_count))
            if [[ $diff -ne 0 ]]; then
                echo "  Difference: $diff (Plex ${diff:0:1} Radarr)" >> "$plex_sync_file"
            else
                echo "  Status: In sync" >> "$plex_sync_file"
            fi
        elif [[ "$type" == "show" ]]; then
            echo "  Sonarr series: $sonarr_count" >> "$plex_sync_file"
            local diff=$((plex_count - sonarr_count))
            if [[ $diff -ne 0 ]]; then
                echo "  Difference: $diff" >> "$plex_sync_file"
            else
                echo "  Status: In sync" >> "$plex_sync_file"
            fi
        fi
        echo "" >> "$plex_sync_file"
    done <<< "$libraries"
}

# Calculate storage usage
calculate_storage() {
    log_info "Calculating storage usage..."

    local movies_size=0
    local tv_size=0

    if [[ -d "$MEDIA_ROOT/movies" ]]; then
        movies_size=$(du -sb "$MEDIA_ROOT/movies" 2>/dev/null | cut -f1 || echo "0")
    fi

    if [[ -d "$MEDIA_ROOT/tv" ]]; then
        tv_size=$(du -sb "$MEDIA_ROOT/tv" 2>/dev/null | cut -f1 || echo "0")
    fi

    echo "$movies_size|$tv_size"
}

# Generate summary report
generate_summary() {
    local orphaned_movies=$1
    local orphaned_tv=$2
    local dup_info=$3
    local storage_info=$4

    local dup_count dup_size
    dup_count=$(echo "$dup_info" | cut -d'|' -f1)
    dup_size=$(echo "$dup_info" | cut -d'|' -f2)

    local movies_size tv_size
    movies_size=$(echo "$storage_info" | cut -d'|' -f1)
    tv_size=$(echo "$storage_info" | cut -d'|' -f2)

    local radarr_count sonarr_count fs_movies_count fs_tv_count
    radarr_count=$(radarr_api "/movie" | jq 'length')
    sonarr_count=$(sonarr_api "/series" | jq 'length')
    fs_movies_count=$(get_filesystem_movies | wc -l)
    fs_tv_count=$(get_filesystem_tv | wc -l)

    # Generate JSON summary
    cat > "$OUTPUT_DIR/summary.json" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "movies": {
    "radarr_count": $radarr_count,
    "filesystem_count": $fs_movies_count,
    "orphaned_count": $orphaned_movies,
    "size_bytes": $movies_size,
    "size_human": "$(format_bytes "$movies_size")"
  },
  "tv": {
    "sonarr_count": $sonarr_count,
    "filesystem_count": $fs_tv_count,
    "orphaned_count": $orphaned_tv,
    "size_bytes": $tv_size,
    "size_human": "$(format_bytes "$tv_size")"
  },
  "duplicates": {
    "count": $dup_count,
    "total_size_bytes": ${dup_size:-0},
    "total_size_human": "$(format_bytes "${dup_size:-0}")"
  },
  "recommendations": [
    $(if [[ $orphaned_movies -gt 0 ]]; then printf '"Add %d orphaned movies to Radarr or delete",' "$orphaned_movies"; fi)
    $(if [[ $orphaned_tv -gt 0 ]]; then printf '"Add %d orphaned TV shows to Sonarr or delete",' "$orphaned_tv"; fi)
    $(if [[ $dup_count -gt 0 ]]; then printf '"Review %d folders with duplicate versions",' "$dup_count"; fi)
    "Run Plex library scan if items are out of sync"
  ]
}
EOF

    # Print human-readable summary
    echo ""
    echo "=============================================="
    echo "          MEDIA AUDIT REPORT"
    echo "=============================================="
    echo ""
    echo "Movies:"
    echo "  Radarr tracked:    $radarr_count"
    echo "  On filesystem:     $fs_movies_count"
    echo "  Orphaned:          $orphaned_movies"
    echo "  Total size:        $(format_bytes "$movies_size")"
    echo ""
    echo "TV Shows:"
    echo "  Sonarr tracked:    $sonarr_count"
    echo "  On filesystem:     $fs_tv_count"
    echo "  Orphaned:          $orphaned_tv"
    echo "  Total size:        $(format_bytes "$tv_size")"
    echo ""
    echo "Duplicates:"
    echo "  Folders with duplicates: $dup_count"
    echo "  Duplicate storage:       $(format_bytes "${dup_size:-0}")"
    echo ""
    echo "=============================================="
    echo "RECOMMENDATIONS"
    echo "=============================================="

    if [[ $orphaned_movies -gt 0 ]]; then
        echo "- Add $orphaned_movies orphaned movies to Radarr or delete"
        echo "  See: $OUTPUT_DIR/orphaned_movies.txt"
    fi

    if [[ $orphaned_tv -gt 0 ]]; then
        echo "- Add $orphaned_tv orphaned TV shows to Sonarr or delete"
        echo "  See: $OUTPUT_DIR/orphaned_tv.txt"
    fi

    if [[ $dup_count -gt 0 ]]; then
        echo "- Review $dup_count folders with duplicate versions"
        echo "  See: $OUTPUT_DIR/duplicates.txt"
        echo "  Potential space savings: $(format_bytes "${dup_size:-0}")"
    fi

    echo ""
    echo "Reports saved to: $OUTPUT_DIR/"
    echo "=============================================="
}

main() {
    log_info "Starting media audit..."
    log_info "Media root: $MEDIA_ROOT"
    log_info "Output directory: $OUTPUT_DIR"

    # Verify media mount
    if [[ ! -d "$MEDIA_ROOT" ]]; then
        log_error "Media root not accessible: $MEDIA_ROOT"
        exit 1
    fi

    # Run audits
    local orphaned_movies orphaned_tv dup_info storage_info

    orphaned_movies=$(find_orphaned_movies)
    orphaned_tv=$(find_orphaned_tv)
    dup_info=$(find_duplicates)
    storage_info=$(calculate_storage)

    # Check Plex sync
    check_plex_sync

    # Generate summary
    generate_summary "$orphaned_movies" "$orphaned_tv" "$dup_info" "$storage_info"

    log_info "Audit complete!"
}

main "$@"
