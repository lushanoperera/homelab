#!/usr/bin/env bash
#
# test-5ghz-channel.sh — Test a 5GHz channel on Camera AP via UniFi API
#
# Usage: ./test-5ghz-channel.sh <channel> [ht_width]
#   channel: 5GHz channel number (e.g., 52, 60, 100)
#   ht_width: channel width (default: 80)
#
# Returns exit 0 if channel adopted, exit 1 if fell back

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
SITE="default"
TARGET_AP_PATTERN="Camera"
WAIT_SECONDS="${3:-100}"

die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 2; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }

CHANNEL="${1:?Usage: $0 <channel> [ht_width]}"
HT="${2:-80}"

# Load credentials
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi
[[ -n "${UNIFI_HOST:-}" ]] || die "UNIFI_HOST not set"
[[ -n "${UNIFI_USER:-}" ]] || die "UNIFI_USER not set"
[[ -n "${UNIFI_PASS:-}" ]] || die "UNIFI_PASS not set"

# Login
COOKIE_JAR=$(mktemp "${TMPDIR:-/tmp}"/unifi-cookies.XXXXXX)
trap 'rm -f "$COOKIE_JAR"' EXIT
curl -sSk -c "$COOKIE_JAR" -o /dev/null "https://${UNIFI_HOST}/"
curl -sSk -o /dev/null -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$UNIFI_USER\",\"password\":\"$UNIFI_PASS\"}" \
    "https://${UNIFI_HOST}/api/auth/login"

# Extract CSRF
CSRF_TOKEN=""
jwt_token=$(grep 'TOKEN' "$COOKIE_JAR" | awk '{print $NF}' || true)
if [[ -n "$jwt_token" ]]; then
    jwt_payload=$(echo "$jwt_token" | cut -d. -f2)
    pad=$(( 4 - ${#jwt_payload} % 4 ))
    if (( pad < 4 )); then
        jwt_payload="${jwt_payload}$(printf '=%.0s' $(seq 1 "$pad"))"
    fi
    CSRF_TOKEN=$(echo "$jwt_payload" | base64 -d 2>/dev/null | jq -r '.csrfToken // empty')
fi

api_get() {
    curl -sSk -b "$COOKIE_JAR" \
        "https://${UNIFI_HOST}/proxy/network/api/s/${SITE}/$1"
}

api_put() {
    curl -sSk -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
        -X PUT -H 'Content-Type: application/json' \
        ${CSRF_TOKEN:+-H "X-CSRF-Token: $CSRF_TOKEN"} \
        -d "$2" \
        "https://${UNIFI_HOST}/proxy/network/api/s/${SITE}/$1"
}

# Find Camera AP
AP_DATA=$(api_get "stat/device" | jq --arg pat "$TARGET_AP_PATTERN" '.data[] | select(.type == "uap" and (.name | test($pat)))')
AP_ID=$(echo "$AP_DATA" | jq -r '._id')
AP_NAME=$(echo "$AP_DATA" | jq -r '.name')
CURRENT_RADIOS=$(echo "$AP_DATA" | jq '.radio_table')

info "AP: $AP_NAME ($AP_ID)"
info "Setting 5GHz to ch $CHANNEL / ${HT}MHz..."

# Update radio_table: set na channel and ht
NEW_RADIOS=$(echo "$CURRENT_RADIOS" | jq --argjson ch "$CHANNEL" --argjson ht "$HT" '
    map(if .radio == "na" then .channel = $ch | .ht = $ht | del(.tx_power) else . end)')

BODY=$(jq -n --argjson rt "$NEW_RADIOS" '{"radio_table": $rt}')
RESULT=$(api_put "rest/device/$AP_ID" "$BODY")
STATUS=$(echo "$RESULT" | jq -r '.meta.rc // "error"')

if [[ "$STATUS" != "ok" ]]; then
    MSG=$(echo "$RESULT" | jq -r '.meta.msg // "unknown"')
    die "API error: $MSG"
fi

info "Config applied. Waiting ${WAIT_SECONDS}s for DFS CAC scan..."

# Wait for CAC
sleep "$WAIT_SECONDS"

# Re-login (session may have expired during wait)
curl -sSk -c "$COOKIE_JAR" -o /dev/null "https://${UNIFI_HOST}/"
curl -sSk -o /dev/null -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$UNIFI_USER\",\"password\":\"$UNIFI_PASS\"}" \
    "https://${UNIFI_HOST}/api/auth/login" 2>/dev/null || true

# Check actual channel
ACTUAL=$(api_get "stat/device" | jq --arg pat "$TARGET_AP_PATTERN" '
    .data[] | select(.type == "uap" and (.name | test($pat))) |
    .radio_table_stats[] | select(.name == "wifi1") | .channel')

info "Configured: ch $CHANNEL | Actual: ch $ACTUAL"

if [[ "$ACTUAL" == "$CHANNEL" ]]; then
    printf '\033[1;32m[SUCCESS]\033[0m Channel %s adopted!\n' "$CHANNEL"
    exit 0
else
    printf '\033[1;31m[FAILED]\033[0m Channel %s not adopted (actual: %s) — DFS CAC likely failed\n' "$CHANNEL" "$ACTUAL"
    exit 1
fi
