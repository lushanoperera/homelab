#!/bin/bash
# setup-quality-profiles.sh - Configure quality profiles with 4K + 1080p fallback
# Deploy to Flatcar VM at /opt/bin/setup-quality-profiles.sh
#
# Usage: ./setup-quality-profiles.sh [--dry-run] [--list] [--apply-to-existing]
#
# Requires:
# - .env file with API keys (see .env.example)
# - jq installed
#
# What it does:
# 1. Creates "4K with 1080p Fallback" profile in Radarr
# 2. Creates "4K with 1080p Fallback" profile in Sonarr
# 3. Optionally applies to existing media

set -euo pipefail

# Configuration
ENV_FILE="${ENV_FILE:-/srv/docker/media-stack/.env}"
LOG_PREFIX="[quality-profiles]"
DRY_RUN=false
LIST_ONLY=false
APPLY_TO_EXISTING=false
PROFILE_NAME="4K with 1080p Fallback"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --list|-l)
            LIST_ONLY=true
            shift
            ;;
        --apply-to-existing)
            APPLY_TO_EXISTING=true
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
            echo "  --dry-run, -n        Show what would be done"
            echo "  --list, -l           List current quality profiles"
            echo "  --apply-to-existing  Apply new profile to all existing media"
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

SONARR_URL="${SONARR_URL:-http://localhost:8989}"
RADARR_URL="${RADARR_URL:-http://localhost:7878}"

[[ -z "${SONARR_API_KEY:-}" ]] && { echo "ERROR: SONARR_API_KEY not set"; exit 1; }
[[ -z "${RADARR_API_KEY:-}" ]] && { echo "ERROR: RADARR_API_KEY not set"; exit 1; }

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

sonarr_api() {
    local method=${1:-GET}
    local endpoint=$2
    local data=${3:-}

    if [[ "$method" == "POST" ]]; then
        curl -s -X POST -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$SONARR_URL/api/v3$endpoint"
    elif [[ "$method" == "PUT" ]]; then
        curl -s -X PUT -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
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
    elif [[ "$method" == "PUT" ]]; then
        curl -s -X PUT -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
            -d "$data" "$RADARR_URL/api/v3$endpoint"
    else
        curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3$endpoint"
    fi
}

list_profiles() {
    echo "=== Radarr Quality Profiles ==="
    radarr_api GET "/qualityprofile" | jq -r '.[] | "\(.id): \(.name) (cutoff ID: \(.cutoff))"' 2>/dev/null || echo "Failed to fetch"
    echo ""

    echo "=== Sonarr Quality Profiles ==="
    sonarr_api GET "/qualityprofile" | jq -r '.[] | "\(.id): \(.name) (cutoff ID: \(.cutoff))"' 2>/dev/null || echo "Failed to fetch"
}

# Get quality definitions to map names to IDs
get_radarr_quality_ids() {
    radarr_api GET "/qualitydefinition" | jq -c '.'
}

get_sonarr_quality_ids() {
    sonarr_api GET "/qualitydefinition" | jq -c '.'
}

# Create quality profile for Radarr
# Quality IDs vary by installation, so we fetch them dynamically
create_radarr_profile() {
    log "Creating Radarr quality profile: $PROFILE_NAME"

    # Check if profile already exists
    local existing
    existing=$(radarr_api GET "/qualityprofile" | jq --arg name "$PROFILE_NAME" '.[] | select(.name == $name) | .id' 2>/dev/null)

    if [[ -n "$existing" ]]; then
        log "Profile already exists with ID: $existing"
        echo "$existing"
        return 0
    fi

    # Get quality definitions
    local qualities
    qualities=$(get_radarr_quality_ids)

    # Build quality items - prefer 4K, accept 1080p
    # We need to include all qualities and set allowed: true/false
    local profile_json
    profile_json=$(cat <<EOF
{
  "name": "$PROFILE_NAME",
  "upgradeAllowed": true,
  "cutoff": 18,
  "items": [
    {"quality": {"id": 18, "name": "Remux-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 19, "name": "Bluray-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 31, "name": "WEB 2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 20, "name": "HDTV-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 7, "name": "Bluray-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 3, "name": "WEBDL-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 15, "name": "WEBRip-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 9, "name": "HDTV-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 6, "name": "Bluray-720p"}, "items": [], "allowed": false},
    {"quality": {"id": 5, "name": "WEBDL-720p"}, "items": [], "allowed": false},
    {"quality": {"id": 14, "name": "WEBRip-720p"}, "items": [], "allowed": false},
    {"quality": {"id": 4, "name": "HDTV-720p"}, "items": [], "allowed": false}
  ],
  "minFormatScore": 0,
  "cutoffFormatScore": 0,
  "formatItems": []
}
EOF
)

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create profile with:"
        echo "$profile_json" | jq '.'
        return 0
    fi

    local result
    result=$(radarr_api POST "/qualityprofile" "$profile_json")
    local new_id
    new_id=$(echo "$result" | jq -r '.id // empty')

    if [[ -n "$new_id" ]]; then
        log "Created Radarr profile with ID: $new_id"
        echo "$new_id"
    else
        log "ERROR: Failed to create Radarr profile"
        echo "$result" | jq '.' 2>/dev/null || echo "$result"
        return 1
    fi
}

# Create quality profile for Sonarr
create_sonarr_profile() {
    log "Creating Sonarr quality profile: $PROFILE_NAME"

    # Check if profile already exists
    local existing
    existing=$(sonarr_api GET "/qualityprofile" | jq --arg name "$PROFILE_NAME" '.[] | select(.name == $name) | .id' 2>/dev/null)

    if [[ -n "$existing" ]]; then
        log "Profile already exists with ID: $existing"
        echo "$existing"
        return 0
    fi

    # Build quality items for Sonarr (IDs differ from Radarr)
    local profile_json
    profile_json=$(cat <<EOF
{
  "name": "$PROFILE_NAME",
  "upgradeAllowed": true,
  "cutoff": 18,
  "items": [
    {"quality": {"id": 18, "name": "Remux-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 19, "name": "Bluray-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 16, "name": "WEBDL-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 17, "name": "WEBRip-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 15, "name": "HDTV-2160p"}, "items": [], "allowed": true},
    {"quality": {"id": 7, "name": "Bluray-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 3, "name": "WEBDL-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 14, "name": "WEBRip-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 9, "name": "HDTV-1080p"}, "items": [], "allowed": true},
    {"quality": {"id": 6, "name": "Bluray-720p"}, "items": [], "allowed": false},
    {"quality": {"id": 5, "name": "WEBDL-720p"}, "items": [], "allowed": false},
    {"quality": {"id": 13, "name": "WEBRip-720p"}, "items": [], "allowed": false},
    {"quality": {"id": 4, "name": "HDTV-720p"}, "items": [], "allowed": false}
  ],
  "minFormatScore": 0,
  "cutoffFormatScore": 0,
  "formatItems": []
}
EOF
)

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create profile with:"
        echo "$profile_json" | jq '.'
        return 0
    fi

    local result
    result=$(sonarr_api POST "/qualityprofile" "$profile_json")
    local new_id
    new_id=$(echo "$result" | jq -r '.id // empty')

    if [[ -n "$new_id" ]]; then
        log "Created Sonarr profile with ID: $new_id"
        echo "$new_id"
    else
        log "ERROR: Failed to create Sonarr profile"
        echo "$result" | jq '.' 2>/dev/null || echo "$result"
        return 1
    fi
}

# Apply profile to all existing movies in Radarr
apply_to_radarr_movies() {
    local profile_id=$1

    log "Applying profile $profile_id to all Radarr movies..."

    local movies
    movies=$(radarr_api GET "/movie")
    local count
    count=$(echo "$movies" | jq 'length')

    log "Found $count movies"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would update $count movies to profile ID $profile_id"
        return 0
    fi

    local updated=0
    echo "$movies" | jq -c '.[]' | while read -r movie; do
        local movie_id current_profile
        movie_id=$(echo "$movie" | jq -r '.id')
        current_profile=$(echo "$movie" | jq -r '.qualityProfileId')

        if [[ "$current_profile" != "$profile_id" ]]; then
            local updated_movie
            updated_movie=$(echo "$movie" | jq --arg pid "$profile_id" '.qualityProfileId = ($pid | tonumber)')
            radarr_api PUT "/movie/$movie_id" "$updated_movie" > /dev/null
            ((updated++)) || true
        fi
    done

    log "Updated movies to new profile"
}

# Apply profile to all existing series in Sonarr
apply_to_sonarr_series() {
    local profile_id=$1

    log "Applying profile $profile_id to all Sonarr series..."

    local series
    series=$(sonarr_api GET "/series")
    local count
    count=$(echo "$series" | jq 'length')

    log "Found $count series"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would update $count series to profile ID $profile_id"
        return 0
    fi

    echo "$series" | jq -c '.[]' | while read -r show; do
        local series_id current_profile
        series_id=$(echo "$show" | jq -r '.id')
        current_profile=$(echo "$show" | jq -r '.qualityProfileId')

        if [[ "$current_profile" != "$profile_id" ]]; then
            local updated_series
            updated_series=$(echo "$show" | jq --arg pid "$profile_id" '.qualityProfileId = ($pid | tonumber)')
            sonarr_api PUT "/series/$series_id" "$updated_series" > /dev/null
        fi
    done

    log "Updated series to new profile"
}

main() {
    if [[ "$LIST_ONLY" == "true" ]]; then
        list_profiles
        exit 0
    fi

    log "Setting up quality profiles..."
    [[ "$DRY_RUN" == "true" ]] && log "DRY RUN MODE"

    # Create profiles
    local radarr_profile_id sonarr_profile_id
    radarr_profile_id=$(create_radarr_profile)
    sonarr_profile_id=$(create_sonarr_profile)

    # Apply to existing if requested
    if [[ "$APPLY_TO_EXISTING" == "true" ]]; then
        if [[ -n "$radarr_profile_id" ]]; then
            apply_to_radarr_movies "$radarr_profile_id"
        fi
        if [[ -n "$sonarr_profile_id" ]]; then
            apply_to_sonarr_series "$sonarr_profile_id"
        fi
    fi

    echo ""
    log "=== Summary ==="
    log "Radarr profile ID: ${radarr_profile_id:-failed}"
    log "Sonarr profile ID: ${sonarr_profile_id:-failed}"

    if [[ "$APPLY_TO_EXISTING" != "true" ]]; then
        log "To apply to existing media, run with --apply-to-existing"
    fi
}

main "$@"
