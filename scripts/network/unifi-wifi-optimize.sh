#!/usr/bin/env bash
#
# unifi-wifi-optimize.sh — Apply WiFi channel, power & band steering optimization
#
# Implements the WiFi optimization plan (2026-03-26):
#   1. Fix 5GHz co-channel: Salotto → ch 36 (UNII-1), Camera → ch 100 (DFS UNII-2e)
#   2. Fix 6GHz co-channel: Salotto → ch 37/160, Camera → ch 69/160 (separate blocks)
#   3. Band steering: 2.4GHz TX power → low (shrink cell, push clients to 5/6GHz)
#   4. Min RSSI on 2.4GHz only (-75 dBm) — kicks weak 2.4GHz clients to higher bands
#   5. Radio AI exclusion for DFS-pinned APs (prevents Radio AI overriding manual channels)
#
# Usage:
#   ./unifi-wifi-optimize.sh                       # Dry-run — show planned changes
#   ./unifi-wifi-optimize.sh --apply               # Apply changes (min RSSI enabled by default)
#   ./unifi-wifi-optimize.sh --apply --no-min-rssi # Apply without min RSSI
#   ./unifi-wifi-optimize.sh --rollback            # Revert to auto channels/power/Radio AI
#
# Credentials: same .env as unifi-inventory.sh (UNIFI_HOST, UNIFI_USER, UNIFI_PASS)
#
# Requirements: curl, jq

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration: The optimization plan (parallel arrays for bash 3.2 compat)
# ---------------------------------------------------------------------------
# Channel plan rationale:
#   Salotto 5GHz → ch 36 (UNII-1, non-DFS, pinned)
#   Camera  5GHz → ch 100 (UNII-2e DFS, pinned — excluded from Radio AI)
#   Salotto 6GHz → ch 37/160MHz (block 1-61)
#   Camera  6GHz → ch 69/160MHz (block 65-125, no overlap with Salotto)
#   Both 2.4GHz  → keep existing channels (1 and 11), TX power → low for band steering
#
# Italy regulatory: UNII-3 (ch 149+) unavailable. Only UNII-1 (36-48) and UNII-2/2e (52-140).

PLAN_NAMES=("Salotto" "Camera")
PLAN_5G_CH=(36 100)
PLAN_6G_CH=(37 69)
PLAN_5G_TX=("medium" "medium")
PLAN_24G_TX=("low" "low")
PLAN_6G_TX=("high" "high")
PLAN_6G_HT=(160 160)
PLAN_EXCLUDE_RADIO_AI=(false true)

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
ENABLE_MIN_RSSI=true

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
chg()  { printf '\033[1;33m[CHG]\033[0m  %s\n' "$*"; }
skip() { printf '\033[0;37m[SKIP]\033[0m %s\n' "$*"; }
dfs()  { printf '\033[1;35m[DFS]\033[0m  %s\n' "$*"; }

usage() {
    cat <<'EOF'
Usage: unifi-wifi-optimize.sh [OPTIONS]

Modes:
  (default)     Dry-run — show what would change without applying
  --apply       Apply the optimization plan to the APs
  --rollback    Revert channels to auto, TX power to auto, Radio AI exclusions removed

Options:
  --no-min-rssi Skip minimum RSSI setting (with --apply only)
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

api_get_setting() {
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
# Plan lookup helpers
# ---------------------------------------------------------------------------
# Returns the plan index (0-based) for an AP name, or -1 if not found
get_plan_index() {
    local ap_name="$1"
    local i
    for i in "${!PLAN_NAMES[@]}"; do
        if [[ "$ap_name" == *"${PLAN_NAMES[$i]}"* ]]; then
            echo "$i"
            return
        fi
    done
    echo "-1"
}

# Check if a 5GHz channel is in the DFS range (52-140)
is_dfs_channel() {
    local ch="$1"
    if [[ "$ch" == "auto" ]]; then
        return 1
    fi
    (( ch >= 52 && ch <= 140 ))
}

# ---------------------------------------------------------------------------
# Radio AI exclusion management
# ---------------------------------------------------------------------------
# Add or remove an AP MAC from the Radio AI exclude_devices list
update_radio_ai_exclusion() {
    local ap_mac="$1"
    local action="$2"  # "add" or "remove"

    # Fetch current Radio AI settings
    local radio_ai_data
    radio_ai_data=$(api_get_setting "rest/setting/radio_ai")

    local setting_id current_excludes
    setting_id=$(echo "$radio_ai_data" | jq -r '.data[0]._id // empty')
    current_excludes=$(echo "$radio_ai_data" | jq '.data[0].exclude_devices // []')

    if [[ -z "$setting_id" ]]; then
        warn "Could not find Radio AI settings — skipping exclusion update"
        return 1
    fi

    local new_excludes
    if [[ "$action" == "add" ]]; then
        # Add MAC if not already present
        local already_excluded
        already_excluded=$(echo "$current_excludes" | jq --arg mac "$ap_mac" '[.[] | select(. == $mac)] | length')
        if (( already_excluded > 0 )); then
            skip "  $ap_mac already excluded from Radio AI"
            return 0
        fi
        new_excludes=$(echo "$current_excludes" | jq --arg mac "$ap_mac" '. + [$mac]')
    elif [[ "$action" == "remove" ]]; then
        new_excludes=$(echo "$current_excludes" | jq --arg mac "$ap_mac" '[.[] | select(. != $mac)]')
    else
        die "update_radio_ai_exclusion: unknown action '$action'"
    fi

    local body
    body=$(jq -n --argjson excludes "$new_excludes" '{"exclude_devices": $excludes}')

    local result
    result=$(api_put "rest/setting/radio_ai/$setting_id" "$body")

    local ok_status
    ok_status=$(echo "$result" | jq -r '.meta.rc // "error"')
    if [[ "$ok_status" == "ok" ]]; then
        if [[ "$action" == "add" ]]; then
            ok "  Excluded $ap_mac from Radio AI"
        else
            ok "  Removed $ap_mac from Radio AI exclusion"
        fi
        return 0
    else
        local msg
        msg=$(echo "$result" | jq -r '.meta.msg // "unknown error"')
        warn "  Radio AI update failed: $msg"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Build target radio_table for an AP
# ---------------------------------------------------------------------------
build_target_radio_table() {
    local current_radios="$1"
    local plan_idx="$2"

    local target_5g_ch="${PLAN_5G_CH[$plan_idx]}"
    local target_5g_tx="${PLAN_5G_TX[$plan_idx]}"
    local target_24g_tx="${PLAN_24G_TX[$plan_idx]}"
    local target_6g_ch="${PLAN_6G_CH[$plan_idx]}"
    local target_6g_tx="${PLAN_6G_TX[$plan_idx]}"
    local target_6g_ht="${PLAN_6G_HT[$plan_idx]}"

    local result="$current_radios"

    # 5 GHz (na): set channel and TX power
    if [[ "$MODE" == "rollback" ]]; then
        result=$(echo "$result" | jq --arg radio "na" '
            map(if .radio == $radio then
                .channel = "auto" | .tx_power_mode = "auto" | del(.tx_power)
            else . end)')
    else
        result=$(echo "$result" | jq --arg radio "na" --argjson ch "$target_5g_ch" --arg txmode "$target_5g_tx" '
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
        result=$(echo "$result" | jq --arg radio "ng" --arg txmode "$target_24g_tx" '
            map(if .radio == $radio then
                .tx_power_mode = $txmode | del(.tx_power)
            else . end)')
    fi

    # 6 GHz (6e): set channel, TX power, and channel width
    if [[ "$MODE" == "rollback" ]]; then
        result=$(echo "$result" | jq --arg radio "6e" '
            map(if .radio == $radio then
                .channel = "auto" | .tx_power_mode = "auto" | del(.tx_power)
            else . end)')
    else
        result=$(echo "$result" | jq --arg radio "6e" --argjson ch "$target_6g_ch" --arg txmode "$target_6g_tx" --argjson ht "$target_6g_ht" '
            map(if .radio == $radio then
                .channel = $ch | .tx_power_mode = $txmode | .ht = $ht | del(.tx_power)
            else . end)')
    fi

    # Minimum RSSI — 2.4GHz only (band steering: kick weak 2.4GHz clients to 5/6GHz)
    if $ENABLE_MIN_RSSI && [[ "$MODE" != "rollback" ]]; then
        result=$(echo "$result" | jq --argjson rssi "$MIN_RSSI_VALUE" '
            map(if .radio == "ng" then
                .min_rssi_enabled = true | .min_rssi = $rssi
            else . end)')
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

        local cur_ch cur_txmode cur_rssi_en cur_rssi cur_ht
        cur_ch=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .channel // "auto"')
        cur_txmode=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .tx_power_mode // "auto"')
        cur_rssi_en=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi_enabled // false')
        cur_rssi=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi // "N/A"')
        cur_ht=$(echo "$current" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .ht // "auto"')

        local tgt_ch tgt_txmode tgt_rssi_en tgt_rssi tgt_ht
        tgt_ch=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .channel // "auto"')
        tgt_txmode=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .tx_power_mode // "auto"')
        tgt_rssi_en=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi_enabled // false')
        tgt_rssi=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .min_rssi // "N/A"')
        tgt_ht=$(echo "$target" | jq -r --arg r "$radio_code" '.[] | select(.radio == $r) | .ht // "auto"')

        # Skip if no data for this band
        if [[ -z "$cur_ch" && -z "$tgt_ch" ]]; then
            continue
        fi

        local has_changes=false

        if [[ "$cur_ch" != "$tgt_ch" ]]; then
            chg "  $band channel: $cur_ch → $tgt_ch"
            has_changes=true
        fi
        if [[ "$cur_ht" != "$tgt_ht" ]]; then
            chg "  $band width: ${cur_ht}MHz → ${tgt_ht}MHz"
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
            --apply)       MODE="apply" ;;
            --rollback)    MODE="rollback" ;;
            --no-min-rssi) ENABLE_MIN_RSSI=false ;;
            --min-rssi)    ENABLE_MIN_RSSI=true ;;
            --site)        SITE="${2:?--site requires a value}"; shift ;;
            -h|--help)     usage ;;
            *)             die "Unknown option: $1" ;;
        esac
        shift
    done

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
    local has_dfs=false

    # Process each AP
    for i in $(seq 0 $((ap_count - 1))); do
        local ap_name ap_id ap_mac current_radios
        ap_name=$(echo "$ap_data" | jq -r ".[$i].name // .[$i].hostname // \"unknown\"")
        ap_id=$(echo "$ap_data" | jq -r ".[$i]._id")
        ap_mac=$(echo "$ap_data" | jq -r ".[$i].mac // empty")
        current_radios=$(echo "$ap_data" | jq ".[$i].radio_table")

        local plan_idx
        plan_idx=$(get_plan_index "$ap_name")

        if [[ "$plan_idx" == "-1" ]]; then
            echo ""
            printf '\033[1m%s\033[0m\n' "$ap_name"
            skip "  Not in optimization plan — skipping"
            continue
        fi

        # Build target radio_table
        local target_radios
        target_radios=$(build_target_radio_table "$current_radios" "$plan_idx")

        # Show diff
        show_radio_diff "$ap_name" "$current_radios" "$target_radios"

        # Show Radio AI exclusion change
        if [[ "${PLAN_EXCLUDE_RADIO_AI[$plan_idx]}" == "true" && "$MODE" != "rollback" ]]; then
            chg "  Radio AI: exclude this AP (pin DFS channel)"
        elif [[ "$MODE" == "rollback" && -n "$ap_mac" ]]; then
            chg "  Radio AI: remove exclusion (return to managed)"
        fi

        # Check if we're assigning a DFS channel
        if [[ "$MODE" != "rollback" ]] && is_dfs_channel "${PLAN_5G_CH[$plan_idx]}"; then
            has_dfs=true
        fi

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
                ok "  $ap_name radio_table updated successfully"
                changes_applied=$((changes_applied + 1))
            else
                local msg
                msg=$(echo "$result" | jq -r '.meta.msg // "unknown error"')
                printf '\033[1;31m[FAIL]\033[0m  %s — API error: %s\n' "$ap_name" "$msg"
                warn "  Full response: $result"
            fi

            # Handle Radio AI exclusion
            if [[ -n "$ap_mac" ]]; then
                if [[ "${PLAN_EXCLUDE_RADIO_AI[$plan_idx]}" == "true" && "$MODE" == "apply" ]]; then
                    info "  Updating Radio AI exclusion for $ap_name..."
                    update_radio_ai_exclusion "$ap_mac" "add" || true
                elif [[ "$MODE" == "rollback" ]]; then
                    info "  Removing Radio AI exclusion for $ap_name..."
                    update_radio_ai_exclusion "$ap_mac" "remove" || true
                fi
            fi
        fi
    done

    # Summary
    echo ""
    case "$MODE" in
        dry-run)
            info "Dry run complete. Use --apply to execute changes."
            if $has_dfs; then
                echo ""
                dfs "Plan includes DFS channel (52-140). After applying:"
                dfs "  - AP performs 60s CAC radar scan before transmitting"
                dfs "  - Verify channel assignment after ~90s with:"
                dfs "    ./scripts/network/unifi-inventory.sh --wifi"
            fi
            ;;
        apply|rollback)
            if (( changes_applied > 0 )); then
                ok "$changes_applied AP(s) updated."
                if $has_dfs && [[ "$MODE" == "apply" ]]; then
                    echo ""
                    dfs "DFS channel assigned — 60s CAC radar scan in progress."
                    dfs "Wait ~90s, then verify:"
                else
                    info "Wait 30-60s for APs to provision, then verify:"
                fi
                info "  ./scripts/network/unifi-inventory.sh --wifi"
            else
                warn "No changes were applied."
            fi
            ;;
    esac

    api_logout
}

main "$@"
