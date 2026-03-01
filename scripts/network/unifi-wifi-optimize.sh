#!/usr/bin/env bash
#
# unifi-wifi-optimize.sh — Apply WiFi channel & power optimization to UniFi APs
#
# Implements the WiFi optimization plan (2026-03-01):
#   1. Fix 5 GHz co-channel: Salotto → ch 36, Camera → ch 149
#   2. Set 5 GHz TX power: both → medium
#   3. Set 2.4 GHz TX power: both → medium
#   4. (Optional) Enable minimum RSSI at -75 dBm
#
# Usage:
#   ./unifi-wifi-optimize.sh                    # Dry-run — show planned changes
#   ./unifi-wifi-optimize.sh --apply            # Apply changes to APs
#   ./unifi-wifi-optimize.sh --apply --min-rssi # Apply changes + minimum RSSI
#   ./unifi-wifi-optimize.sh --rollback         # Revert to auto channels/power
#
# Credentials: same .env as unifi-inventory.sh (UNIFI_HOST, UNIFI_USER, UNIFI_PASS)
#
# Requirements: curl, jq

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration: The optimization plan
# ---------------------------------------------------------------------------
# Maps AP name substring → target radio settings
# radio_table entries: radio (ng=2.4, na=5, 6e=6GHz), channel, tx_power_mode
#
# Channel plan rationale:
#   Salotto 5GHz → ch 36 (UNII-1, non-DFS, pinned)
#   Camera  5GHz → auto (managed by Radio AI, which picks DFS channels)
#     Note: ch 149 (UNII-3) unavailable — EU/IT firmware regulatory table
#     Note: Manual DFS channels (52,60,64,100,116,128) all failed CAC
#     Note: Radio AI's optimizer successfully assigns DFS channels
#   Both 2.4GHz  → keep existing channels (1 and 11 are already optimal)
#   Both 6GHz    → no changes (37 and 85 are fine, abundant spectrum)

# AP plan entries: "name_pattern:5g_channel" (use "auto" for Radio AI managed)
PLAN_ENTRIES=(
    "Salotto:36"
    "Camera:auto"
)
TARGET_5G_TX_POWER_MODE="medium"
TARGET_24G_TX_POWER_MODE="medium"
MIN_RSSI_VALUE=-75

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIFI_HOST="${UNIFI_HOST:-}"
UNIFI_USER="${UNIFI_USER:-}"
UNIFI_PASS="${UNIFI_PASS:-}"
ENV_FILE="${SCRIPT_DIR}/.env"
COOKIE_JAR=""
CSRF_TOKEN=""
SITE="default"

MODE="dry-run"      # dry-run | apply | rollback
ENABLE_MIN_RSSI=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
chg()  { printf '\033[1;33m[CHG]\033[0m  %s\n' "$*"; }
skip() { printf '\033[0;37m[SKIP]\033[0m %s\n' "$*"; }

usage() {
    cat <<'EOF'
Usage: unifi-wifi-optimize.sh [OPTIONS]

Modes:
  (default)     Dry-run — show what would change without applying
  --apply       Apply the optimization plan to the APs
  --rollback    Revert channels to auto and TX power to auto

Options:
  --min-rssi    Also set minimum RSSI to -75 dBm (with --apply only)
  --site SITE   UniFi site name (default: "default")
  -h, --help    Show this help

Credentials:
  Same .env file as unifi-inventory.sh (UNIFI_HOST, UNIFI_USER, UNIFI_PASS)
EOF
    exit 0
}

cleanup() {
    if [[ -n "$COOKIE_JAR" && -f "$COOKIE_JAR" ]]; then
        rm -f "$COOKIE_JAR"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Credential loading (same as unifi-inventory.sh)
# ---------------------------------------------------------------------------
load_credentials() {
    if [[ -n "$UNIFI_HOST" && -n "$UNIFI_USER" && -n "$UNIFI_PASS" ]]; then
        return
    fi
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi
    if [[ -z "$UNIFI_HOST" ]]; then die "UNIFI_HOST not set"; fi
    if [[ -z "$UNIFI_USER" ]]; then die "UNIFI_USER not set"; fi
    if [[ -z "$UNIFI_PASS" ]]; then die "UNIFI_PASS not set"; fi
}

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------
api_login() {
    COOKIE_JAR=$(mktemp "${TMPDIR:-/tmp}"/unifi-cookies.XXXXXX)

    # Seed session cookie
    curl -sSk -c "$COOKIE_JAR" -o /dev/null "https://${UNIFI_HOST}/"

    local http_code response
    response=$(mktemp "${TMPDIR:-/tmp}"/unifi-response.XXXXXX)
    http_code=$(curl -sSk -w '%{http_code}' -o "$response" \
        -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$UNIFI_USER\",\"password\":\"$UNIFI_PASS\"}" \
        "https://${UNIFI_HOST}/api/auth/login")

    if [[ "$http_code" != "200" ]]; then
        local body
        body=$(cat "$response" 2>/dev/null || true)
        rm -f "$response"
        die "Login failed (HTTP $http_code). ${body:+Response: $body}"
    fi
    rm -f "$response"

    # Extract CSRF token from JWT payload (UniFi OS embeds it inside the TOKEN cookie)
    CSRF_TOKEN=""
    if [[ -f "$COOKIE_JAR" ]]; then
        local jwt_token
        jwt_token=$(grep 'TOKEN' "$COOKIE_JAR" | awk '{print $NF}' || true)
        if [[ -n "$jwt_token" ]]; then
            local jwt_payload
            jwt_payload=$(echo "$jwt_token" | cut -d. -f2)
            # Pad base64 if needed (base64url → standard base64)
            local pad=$(( 4 - ${#jwt_payload} % 4 ))
            if (( pad < 4 )); then
                jwt_payload="${jwt_payload}$(printf '=%.0s' $(seq 1 "$pad"))"
            fi
            CSRF_TOKEN=$(echo "$jwt_payload" | base64 -d 2>/dev/null | jq -r '.csrfToken // empty')
        fi
    fi
    if [[ -z "$CSRF_TOKEN" ]]; then
        warn "Could not extract CSRF token — write operations may fail"
    fi
    info "Authenticated to $UNIFI_HOST"
}

api_get() {
    local endpoint="$1"
    curl -sSk -b "$COOKIE_JAR" \
        "https://${UNIFI_HOST}/proxy/network/api/s/${SITE}/${endpoint}"
}

api_put() {
    local endpoint="$1"
    local body="$2"
    curl -sSk -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
        -X PUT \
        -H 'Content-Type: application/json' \
        ${CSRF_TOKEN:+-H "X-CSRF-Token: $CSRF_TOKEN"} \
        -d "$body" \
        "https://${UNIFI_HOST}/proxy/network/api/s/${SITE}/${endpoint}"
}

api_logout() {
    curl -sSk -b "$COOKIE_JAR" \
        ${CSRF_TOKEN:+-H "X-CSRF-Token: $CSRF_TOKEN"} \
        -X POST "https://${UNIFI_HOST}/api/auth/logout" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Match AP name to plan entry
# ---------------------------------------------------------------------------
# Returns the plan key (e.g., "Salotto" or "Camera") or empty string
match_ap_to_plan() {
    local ap_name="$1"
    for entry in "${PLAN_ENTRIES[@]}"; do
        local key="${entry%%:*}"
        if [[ "$ap_name" == *"$key"* ]]; then
            echo "$key"
            return
        fi
    done
    echo ""
}

# Look up 5 GHz target channel for a plan key
get_5g_channel() {
    local plan_key="$1"
    for entry in "${PLAN_ENTRIES[@]}"; do
        local key="${entry%%:*}"
        local ch="${entry##*:}"
        if [[ "$key" == "$plan_key" ]]; then
            echo "$ch"
            return
        fi
    done
    echo ""
}

# ---------------------------------------------------------------------------
# Build target radio_table for an AP
# ---------------------------------------------------------------------------
# Takes current radio_table JSON and returns modified version
build_target_radio_table() {
    local current_radios="$1"
    local plan_key="$2"

    local target_5g_channel
    target_5g_channel=$(get_5g_channel "$plan_key")

    # Start with the current radio_table and modify target fields
    local result="$current_radios"

    # 5 GHz (na): set channel and TX power
    if [[ "$MODE" == "rollback" ]]; then
        result=$(echo "$result" | jq --arg radio "na" '
            map(if .radio == $radio then
                .channel = "auto" | .tx_power_mode = "auto" | del(.tx_power)
            else . end)')
    elif [[ "$target_5g_channel" == "auto" ]]; then
        result=$(echo "$result" | jq --arg radio "na" --arg txmode "$TARGET_5G_TX_POWER_MODE" '
            map(if .radio == $radio then
                .channel = "auto" | .tx_power_mode = $txmode | del(.tx_power)
            else . end)')
    else
        result=$(echo "$result" | jq --arg radio "na" --argjson ch "$target_5g_channel" --arg txmode "$TARGET_5G_TX_POWER_MODE" '
            map(if .radio == $radio then
                .channel = $ch | .tx_power_mode = $txmode | del(.tx_power)
            else . end)')
    fi

    # 2.4 GHz (ng): set TX power only (keep existing channel — {1,11} is optimal)
    if [[ "$MODE" == "rollback" ]]; then
        result=$(echo "$result" | jq --arg radio "ng" '
            map(if .radio == $radio then
                .tx_power_mode = "auto" | del(.tx_power)
            else . end)')
    else
        result=$(echo "$result" | jq --arg radio "ng" --arg txmode "$TARGET_24G_TX_POWER_MODE" '
            map(if .radio == $radio then
                .tx_power_mode = $txmode | del(.tx_power)
            else . end)')
    fi

    # Minimum RSSI (optional, on all radios)
    if $ENABLE_MIN_RSSI && [[ "$MODE" == "apply" ]]; then
        result=$(echo "$result" | jq --argjson rssi "$MIN_RSSI_VALUE" '
            map(.min_rssi_enabled = true | .min_rssi = $rssi)')
    elif [[ "$MODE" == "rollback" ]]; then
        result=$(echo "$result" | jq '
            map(.min_rssi_enabled = false | del(.min_rssi))')
    fi

    echo "$result"
}

# ---------------------------------------------------------------------------
# Display radio diff
# ---------------------------------------------------------------------------
show_radio_diff() {
    local ap_name="$1"
    local current="$2"
    local target="$3"

    echo ""
    printf '\033[1m%s\033[0m\n' "$ap_name"

    # Compare each radio band
    for radio_code in ng na 6e; do
        local band
        case "$radio_code" in
            ng) band="2.4GHz" ;;
            na) band="5GHz"   ;;
            6e) band="6GHz"   ;;
        esac

        local cur_ch cur_txmode cur_rssi_en cur_rssi
        cur_ch=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .channel // "auto"')
        cur_txmode=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .tx_power_mode // "auto"')
        cur_rssi_en=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi_enabled // false')
        cur_rssi=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi // "N/A"')

        local tgt_ch tgt_txmode tgt_rssi_en tgt_rssi
        tgt_ch=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .channel // "auto"')
        tgt_txmode=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .tx_power_mode // "auto"')
        tgt_rssi_en=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi_enabled // false')
        tgt_rssi=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi // "N/A"')

        # Skip if no data for this band
        if [[ -z "$cur_ch" && -z "$tgt_ch" ]]; then
            continue
        fi

        local has_changes=false

        if [[ "$cur_ch" != "$tgt_ch" ]]; then
            chg "  $band channel: $cur_ch → $tgt_ch"
            has_changes=true
        fi
        if [[ "$cur_txmode" != "$tgt_txmode" ]]; then
            chg "  $band TX power: $cur_txmode → $tgt_txmode"
            has_changes=true
        fi
        if [[ "$cur_rssi_en" != "$tgt_rssi_en" ]]; then
            if [[ "$tgt_rssi_en" == "true" ]]; then
                chg "  $band min RSSI: disabled → ${tgt_rssi} dBm"
            else
                chg "  $band min RSSI: ${cur_rssi} dBm → disabled"
            fi
            has_changes=true
        fi

        if ! $has_changes; then
            skip "  $band — no changes"
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    command -v curl >/dev/null || die "curl is required"
    command -v jq >/dev/null   || die "jq is required"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply)    MODE="apply" ;;
            --rollback) MODE="rollback" ;;
            --min-rssi) ENABLE_MIN_RSSI=true ;;
            --site)     SITE="${2:?--site requires a value}"; shift ;;
            -h|--help)  usage ;;
            *)          die "Unknown option: $1" ;;
        esac
        shift
    done

    if $ENABLE_MIN_RSSI && [[ "$MODE" != "apply" ]]; then
        warn "--min-rssi only takes effect with --apply"
    fi

    load_credentials
    api_login

    # Fetch all APs
    local devices
    devices=$(api_get "stat/device")

    local ap_data
    ap_data=$(echo "$devices" | jq '[.data[] | select(.type == "uap")]')

    local ap_count
    ap_count=$(echo "$ap_data" | jq 'length')

    if (( ap_count == 0 )); then
        die "No access points found"
    fi

    info "Found $ap_count APs"

    case "$MODE" in
        dry-run)  printf '\n\033[1;36m=== Dry Run — Planned Changes ===\033[0m\n' ;;
        apply)    printf '\n\033[1;33m=== Applying WiFi Optimization ===\033[0m\n' ;;
        rollback) printf '\n\033[1;33m=== Rolling Back to Auto ===\033[0m\n' ;;
    esac

    local changes_applied=0

    # Process each AP
    for i in $(seq 0 $((ap_count - 1))); do
        local ap_name ap_id current_radios
        ap_name=$(echo "$ap_data" | jq -r ".[$i].name // .[$i].hostname // \"unknown\"")
        ap_id=$(echo "$ap_data" | jq -r ".[$i]._id")
        current_radios=$(echo "$ap_data" | jq ".[$i].radio_table")

        local plan_key
        plan_key=$(match_ap_to_plan "$ap_name")

        if [[ -z "$plan_key" ]]; then
            echo ""
            printf '\033[1m%s\033[0m\n' "$ap_name"
            skip "  Not in optimization plan — skipping"
            continue
        fi

        # Build target radio_table
        local target_radios
        target_radios=$(build_target_radio_table "$current_radios" "$plan_key")

        # Show diff
        show_radio_diff "$ap_name" "$current_radios" "$target_radios"

        # Apply if not dry-run
        if [[ "$MODE" != "dry-run" ]]; then
            local body
            body=$(jq -n --argjson rt "$target_radios" '{"radio_table": $rt}')

            info "  Updating $ap_name ($ap_id)..."
            local result
            result=$(api_put "rest/device/$ap_id" "$body")

            local ok_status
            ok_status=$(echo "$result" | jq -r '.meta.rc // "error"')
            if [[ "$ok_status" == "ok" ]]; then
                ok "  $ap_name updated successfully"
                changes_applied=$((changes_applied + 1))
            else
                local msg
                msg=$(echo "$result" | jq -r '.meta.msg // "unknown error"')
                printf '\033[1;31m[FAIL]\033[0m  %s — API error: %s\n' "$ap_name" "$msg"
                warn "  Full response: $result"
            fi
        fi
    done

    # Summary
    echo ""
    case "$MODE" in
        dry-run)
            info "Dry run complete. Use --apply to execute changes."
            ;;
        apply|rollback)
            if (( changes_applied > 0 )); then
                ok "$changes_applied AP(s) updated. Wait 30-60s for APs to provision, then verify:"
                info "  ./scripts/network/unifi-inventory.sh --wifi"
            else
                warn "No changes were applied."
            fi
            ;;
    esac

    api_logout
}

main "$@"
