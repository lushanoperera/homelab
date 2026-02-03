#!/bin/bash
# media-audit-functions.sh - Reusable functions for querying media services
# Source this file in other scripts: source /opt/bin/media-audit-functions.sh
#
# Requires: ENV_FILE or individual API key environment variables

# Default configuration
: "${SONARR_URL:=http://localhost:8989}"
: "${RADARR_URL:=http://localhost:7878}"
: "${PLEX_URL:=http://192.168.100.38:32400}"
: "${OVERSEERR_URL:=http://localhost:5055}"
: "${MEDIA_ROOT:=/mnt/media}"

# Video file extensions (pipe-separated for regex)
VIDEO_EXTENSIONS="mkv|mp4|avi|m4v|wmv|mov|ts|m2ts"

# Load environment file if specified
load_env() {
    local env_file="${1:-/srv/docker/media-stack/.env}"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
        return 0
    fi
    return 1
}

# Sonarr API helper
# Usage: sonarr_api "/series" or sonarr_api "/series/1"
sonarr_api() {
    local endpoint=$1
    [[ -z "${SONARR_API_KEY:-}" ]] && { echo "ERROR: SONARR_API_KEY not set" >&2; return 1; }
    curl -sf -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3$endpoint"
}

# Radarr API helper
# Usage: radarr_api "/movie" or radarr_api "/movie/1"
radarr_api() {
    local endpoint=$1
    [[ -z "${RADARR_API_KEY:-}" ]] && { echo "ERROR: RADARR_API_KEY not set" >&2; return 1; }
    curl -sf -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
}

# Plex API helper
# Usage: plex_api "/library/sections"
plex_api() {
    local endpoint=$1
    [[ -z "${PLEX_TOKEN:-}" ]] && { echo "ERROR: PLEX_TOKEN not set" >&2; return 1; }
    curl -sf -H "X-Plex-Token: $PLEX_TOKEN" -H "Accept: application/json" "$PLEX_URL$endpoint"
}

# Overseerr API helper
# Usage: overseerr_api "/request"
overseerr_api() {
    local endpoint=$1
    [[ -z "${OVERSEERR_API_KEY:-}" ]] && { echo "ERROR: OVERSEERR_API_KEY not set" >&2; return 1; }
    curl -sf -H "X-Api-Key: $OVERSEERR_API_KEY" "$OVERSEERR_URL/api/v1$endpoint"
}

# Get Plex token from Plex LXC on Proxmox
# Usage: token=$(get_plex_token_from_lxc)
get_plex_token_from_lxc() {
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@192.168.100.38 \
        'pct exec 105 -- grep -oP "PlexOnlineToken=\"\K[^\"]*" "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"' 2>/dev/null || echo ""
}

# Get all Radarr movies as JSON array
# Returns: [{id, title, path, tmdbId, hasFile, movieFile}, ...]
get_radarr_movies_json() {
    radarr_api "/movie"
}

# Get all Radarr movies as pipe-separated lines
# Returns: path|title|tmdbId|hasFile
get_radarr_movies() {
    radarr_api "/movie" | jq -r '.[] | "\(.path)|\(.title)|\(.tmdbId)|\(.hasFile)"'
}

# Get single Radarr movie by ID
# Usage: get_radarr_movie 123
get_radarr_movie() {
    local id=$1
    radarr_api "/movie/$id"
}

# Get all Sonarr series as JSON array
# Returns: [{id, title, path, tvdbId, statistics}, ...]
get_sonarr_series_json() {
    sonarr_api "/series"
}

# Get all Sonarr series as pipe-separated lines
# Returns: path|title|tvdbId
get_sonarr_series() {
    sonarr_api "/series" | jq -r '.[] | "\(.path)|\(.title)|\(.tvdbId)"'
}

# Get single Sonarr series by ID
# Usage: get_sonarr_series_by_id 123
get_sonarr_series_by_id() {
    local id=$1
    sonarr_api "/series/$id"
}

# Get Sonarr missing episodes
# Usage: get_sonarr_missing [page_size]
get_sonarr_missing() {
    local page_size=${1:-1000}
    sonarr_api "/wanted/missing?pageSize=$page_size"
}

# Get Plex library sections
# Returns: key|type|title
get_plex_libraries() {
    plex_api "/library/sections" | jq -r '.MediaContainer.Directory[] | "\(.key)|\(.type)|\(.title)"' 2>/dev/null
}

# Get Plex library items
# Usage: get_plex_library_items 1
get_plex_library_items() {
    local section_id=$1
    plex_api "/library/sections/$section_id/all"
}

# Get Plex library item count
# Usage: get_plex_library_count 1
get_plex_library_count() {
    local section_id=$1
    plex_api "/library/sections/$section_id/all" | jq '.MediaContainer.size // 0' 2>/dev/null
}

# Scan filesystem for movie folders
# Returns: folder names (one per line)
get_filesystem_movies() {
    local root="${1:-$MEDIA_ROOT}"
    [[ -d "$root/movies" ]] && find "$root/movies" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Scan filesystem for TV folders
# Returns: folder names (one per line)
get_filesystem_tv() {
    local root="${1:-$MEDIA_ROOT}"
    [[ -d "$root/tv" ]] && find "$root/tv" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Count video files in a folder
# Usage: count=$(count_video_files "/path/to/folder")
count_video_files() {
    local folder=$1
    find "$folder" -type f -regextype posix-extended -regex ".*\.($VIDEO_EXTENSIONS)$" 2>/dev/null | wc -l
}

# Get video files with sizes
# Returns: filename|size_bytes
get_video_files() {
    local folder=$1
    find "$folder" -type f -regextype posix-extended -regex ".*\.($VIDEO_EXTENSIONS)$" -printf '%f|%s\n' 2>/dev/null
}

# Format bytes to human readable (pure bash, no bc dependency)
# Usage: human=$(format_bytes 1073741824) # Returns "1.0GB"
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

# Normalize title for fuzzy matching
# Removes special characters, converts to lowercase
# Usage: normalized=$(normalize_title "The Dark Knight (2008)")
normalize_title() {
    local title=$1
    echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g'
}

# Check if a title matches in a list (fuzzy)
# Usage: if fuzzy_match "The Matrix" "$list"; then ...
fuzzy_match() {
    local title=$1
    local list=$2
    local normalized
    normalized=$(normalize_title "$title")
    echo "$list" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9\n]//g' | grep -q "$normalized" 2>/dev/null
}

# Compare two titles for similarity
# Returns 0 if similar enough, 1 otherwise
titles_match() {
    local title1=$1
    local title2=$2
    local norm1 norm2
    norm1=$(normalize_title "$title1")
    norm2=$(normalize_title "$title2")
    [[ "$norm1" == "$norm2" ]]
}
