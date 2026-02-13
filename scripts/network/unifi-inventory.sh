#!/usr/bin/env bash
#
# unifi-inventory.sh — Query UniFi Fiber Gateway API for network discovery
#
# Authenticates to a UniFi OS gateway's local REST API and retrieves
# clients, devices, networks, health, and other inventory data.
#
# Usage:
#   ./unifi-inventory.sh [--json] [--clients] [--devices] [--networks] [--health] [--all]
#
# Credentials (in order of precedence):
#   1. Environment variables: UNIFI_HOST, UNIFI_USER, UNIFI_PASS
#   2. .env file alongside this script (see .env.example)
#
# Requirements: curl, jq

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIFI_HOST="${UNIFI_HOST:-}"
UNIFI_USER="${UNIFI_USER:-}"
UNIFI_PASS="${UNIFI_PASS:-}"
ENV_FILE="${SCRIPT_DIR}/.env"
COOKIE_JAR=""
OUTPUT_JSON=false
SITE="default"

# What to fetch — empty means --all
FETCH_CLIENTS=false
FETCH_DEVICES=false
FETCH_NETWORKS=false
FETCH_HEALTH=false
FETCH_ALL=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
Usage: unifi-inventory.sh [OPTIONS]

Options:
  --clients    Show active clients
  --devices    Show UniFi devices
  --networks   Show network/VLAN configuration
  --health     Show site health summary
  --all        Show everything (default if no section flags)
  --json       Output raw JSON instead of tables
  --site SITE  UniFi site name (default: "default")
  -h, --help   Show this help

Credentials:
  Set UNIFI_HOST, UNIFI_USER, UNIFI_PASS env vars, or copy
  .env.example to .env alongside this script and fill in values.
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
# Credential loading
# ---------------------------------------------------------------------------
load_credentials() {
    # Already set via env?
    if [[ -n "$UNIFI_HOST" && -n "$UNIFI_USER" && -n "$UNIFI_PASS" ]]; then
        return
    fi

    # Source .env file next to this script
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck source=/dev/null
        set -a
        source "$ENV_FILE"
        set +a
    fi

    if [[ -z "$UNIFI_HOST" ]]; then die "UNIFI_HOST not set. Export it or add to ${ENV_FILE} (see .env.example)"; fi
    if [[ -z "$UNIFI_USER" ]]; then die "UNIFI_USER not set. Export it or add to ${ENV_FILE} (see .env.example)"; fi
    if [[ -z "$UNIFI_PASS" ]]; then die "UNIFI_PASS not set. Export it or add to ${ENV_FILE} (see .env.example)"; fi
}

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------
api_login() {
    COOKIE_JAR=$(mktemp /tmp/unifi-cookies.XXXXXX)

    # Fetch initial CSRF token (required by newer UniFi OS firmware)
    curl -sSk -c "$COOKIE_JAR" -o /dev/null "https://${UNIFI_HOST}/"

    local csrf_token=""
    if [[ -f "$COOKIE_JAR" ]]; then
        csrf_token=$(grep -i 'csrf_token\|TOKEN' "$COOKIE_JAR" | awk '{print $NF}' || true)
    fi

    local http_code response
    response=$(mktemp /tmp/unifi-response.XXXXXX)
    http_code=$(curl -sSk -w '%{http_code}' -o "$response" \
        -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
        -H 'Content-Type: application/json' \
        ${csrf_token:+-H "X-CSRF-Token: $csrf_token"} \
        -d "{\"username\":\"$UNIFI_USER\",\"password\":\"$UNIFI_PASS\"}" \
        "https://${UNIFI_HOST}/api/auth/login")

    if [[ "$http_code" != "200" ]]; then
        local body
        body=$(cat "$response" 2>/dev/null || true)
        rm -f "$response"
        die "Login failed (HTTP $http_code). ${body:+Response: $body}"
    fi
    rm -f "$response"
    info "Authenticated to $UNIFI_HOST"
}

api_get() {
    local endpoint="$1"
    curl -sSk -b "$COOKIE_JAR" \
        "https://${UNIFI_HOST}/proxy/network/api/s/${SITE}/${endpoint}"
}

api_logout() {
    local csrf_token=""
    if [[ -f "$COOKIE_JAR" ]]; then
        csrf_token=$(grep -i 'csrf_token\|TOKEN' "$COOKIE_JAR" | awk '{print $NF}' || true)
    fi
    curl -sSk -b "$COOKIE_JAR" \
        ${csrf_token:+-H "X-CSRF-Token: $csrf_token"} \
        -X POST "https://${UNIFI_HOST}/api/auth/logout" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
format_uptime() {
    local secs="${1:-0}"
    # Handle floating point from jq
    secs="${secs%%.*}"
    local days=$((secs / 86400))
    local hours=$(( (secs % 86400) / 3600 ))
    local mins=$(( (secs % 3600) / 60 ))
    if (( days > 0 )); then
        printf '%dd %dh' "$days" "$hours"
    elif (( hours > 0 )); then
        printf '%dh %dm' "$hours" "$mins"
    else
        printf '%dm' "$mins"
    fi
}

format_bytes() {
    local bytes="${1:-0}"
    if (( bytes >= 1073741824 )); then
        printf '%.1f GB' "$(echo "$bytes / 1073741824" | bc -l)"
    elif (( bytes >= 1048576 )); then
        printf '%.1f MB' "$(echo "$bytes / 1048576" | bc -l)"
    elif (( bytes >= 1024 )); then
        printf '%.1f KB' "$(echo "$bytes / 1024" | bc -l)"
    else
        printf '%d B' "$bytes"
    fi
}

separator() {
    printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"
}

# ---------------------------------------------------------------------------
# Section: System Info
# ---------------------------------------------------------------------------
print_sysinfo() {
    local data
    data=$(api_get "stat/sysinfo")
    if $OUTPUT_JSON; then
        echo "$data"
        return
    fi

    local version uptime_secs uptime_str
    version=$(echo "$data" | jq -r '.data[0].version // "unknown"')
    uptime_secs=$(echo "$data" | jq -r '.data[0].uptime // 0')
    uptime_str=$(format_uptime "$uptime_secs")

    separator "UniFi Gateway: $UNIFI_HOST"
    printf 'System: UniFi OS %s | Uptime: %s\n' "$version" "$uptime_str"
}

# ---------------------------------------------------------------------------
# Section: Health
# ---------------------------------------------------------------------------
print_health() {
    local data
    data=$(api_get "stat/health")
    if $OUTPUT_JSON; then
        echo "$data"
        return
    fi

    separator "Site Health"
    printf '%-14s %-10s %-10s %s\n' "Subsystem" "Status" "Clients" "Details"
    printf '%-14s %-10s %-10s %s\n' "---------" "------" "-------" "-------"

    echo "$data" | jq -r '.data[] |
        [
            .subsystem,
            .status,
            (.num_user // .num_sta // "-" | tostring),
            (
                if .subsystem == "wan" then
                    "▲ " + ((.tx_bytes_r // 0) / 1024 | floor | tostring) + " KB/s  ▼ " + ((.rx_bytes_r // 0) / 1024 | floor | tostring) + " KB/s"
                elif .subsystem == "wlan" then
                    (.num_ap // 0 | tostring) + " APs"
                elif .subsystem == "lan" then
                    (.num_sw // 0 | tostring) + " switches"
                else
                    "-"
                end
            )
        ] | @tsv' | while IFS=$'\t' read -r subsys status clients details; do
        printf '%-14s %-10s %-10s %s\n' "$subsys" "$status" "$clients" "$details"
    done
}

# ---------------------------------------------------------------------------
# Section: Active Clients
# ---------------------------------------------------------------------------
print_clients() {
    local data
    data=$(api_get "stat/sta")
    if $OUTPUT_JSON; then
        echo "$data"
        return
    fi

    local count
    count=$(echo "$data" | jq '.data | length')
    separator "Active Clients ($count)"

    printf '%-17s %-19s %-24s %-12s %-10s %s\n' \
        "IP" "MAC" "Hostname" "Network" "Uptime" "Traffic"
    printf '%-17s %-19s %-24s %-12s %-10s %s\n' \
        "--" "---" "--------" "-------" "------" "-------"

    echo "$data" | jq -r '.data | sort_by(.ip // "zzz") | .[] |
        [
            (.ip // "-"),
            (.mac // "-"),
            (.hostname // .name // .oui // "-"),
            (.network // "-"),
            (.uptime // 0 | tostring),
            ((.tx_bytes // 0) + (.rx_bytes // 0) | tostring)
        ] | @tsv' | while IFS=$'\t' read -r ip mac hostname network uptime_s total_bytes; do
        local up_str traffic_str
        up_str=$(format_uptime "$uptime_s")
        traffic_str=$(format_bytes "$total_bytes")
        printf '%-17s %-19s %-24s %-12s %-10s %s\n' \
            "$ip" "$mac" "${hostname:0:23}" "${network:0:11}" "$up_str" "$traffic_str"
    done
}

# ---------------------------------------------------------------------------
# Section: Networks / VLANs
# ---------------------------------------------------------------------------
print_networks() {
    local data
    data=$(api_get "rest/networkconf")
    if $OUTPUT_JSON; then
        echo "$data"
        return
    fi

    local count
    count=$(echo "$data" | jq '[.data[] | select(.purpose == "corporate" or .purpose == "guest" or .purpose == "vlan-only")] | length')
    separator "Networks ($count)"

    printf '%-16s %-22s %-8s %-8s %s\n' "Name" "Subnet" "VLAN" "DHCP" "DHCP Range"
    printf '%-16s %-22s %-8s %-8s %s\n' "----" "------" "----" "----" "----------"

    echo "$data" | jq -r '.data[]
        | select(.purpose == "corporate" or .purpose == "guest" or .purpose == "vlan-only")
        | [
            (.name // "-"),
            (.ip_subnet // "-"),
            (.vlan // "1" | tostring),
            (if .dhcpd_enabled then "on" else "off" end),
            (if .dhcpd_enabled then (.dhcpd_start // "?") + "-" + (.dhcpd_stop // "?") else "disabled" end)
          ] | @tsv' | while IFS=$'\t' read -r name subnet vlan dhcp range; do
        printf '%-16s %-22s %-8s %-8s %s\n' \
            "${name:0:15}" "${subnet:0:21}" "$vlan" "$dhcp" "$range"
    done
}

# ---------------------------------------------------------------------------
# Section: UniFi Devices
# ---------------------------------------------------------------------------
print_devices() {
    local data
    data=$(api_get "stat/device")
    if $OUTPUT_JSON; then
        echo "$data"
        return
    fi

    local count
    count=$(echo "$data" | jq '.data | length')
    separator "UniFi Devices ($count)"

    printf '%-20s %-14s %-17s %-10s %-10s %s\n' \
        "Name" "Model" "IP" "Status" "Uptime" "Version"
    printf '%-20s %-14s %-17s %-10s %-10s %s\n' \
        "----" "-----" "--" "------" "------" "-------"

    echo "$data" | jq -r '.data | sort_by(.type) | .[] |
        [
            (.name // .hostname // "-"),
            (.model // "-"),
            (.ip // "-"),
            (if .state == 1 then "online" elif .state == 0 then "offline" else "unknown" end),
            (.uptime // 0 | tostring),
            (.version // "-")
        ] | @tsv' | while IFS=$'\t' read -r name model ip status uptime_s version; do
        local up_str
        up_str=$(format_uptime "$uptime_s")
        printf '%-20s %-14s %-17s %-10s %-10s %s\n' \
            "${name:0:19}" "${model:0:13}" "$ip" "$status" "$up_str" "$version"
    done
}

# ---------------------------------------------------------------------------
# Section: Port Forwards
# ---------------------------------------------------------------------------
print_portforwards() {
    local data
    data=$(api_get "stat/portforward")
    if $OUTPUT_JSON; then
        echo "$data"
        return
    fi

    local count
    count=$(echo "$data" | jq '.data | length')
    if (( count == 0 )); then
        return
    fi

    separator "Port Forwards ($count)"
    printf '%-20s %-8s %-14s %-8s %s\n' "Name" "Proto" "Dest IP" "Dest" "Source"
    printf '%-20s %-8s %-14s %-8s %s\n' "----" "-----" "-------" "----" "------"

    echo "$data" | jq -r '.data[] |
        [
            (.name // "-"),
            (.proto // "-"),
            (.fwd // "-"),
            (.fwd_port // "-"),
            (.src // "any")
        ] | @tsv' | while IFS=$'\t' read -r name proto fwd fwd_port src; do
        printf '%-20s %-8s %-14s %-8s %s\n' \
            "${name:0:19}" "$proto" "$fwd" "$fwd_port" "$src"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Check dependencies
    command -v curl >/dev/null || die "curl is required"
    command -v jq >/dev/null   || die "jq is required"

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clients)  FETCH_CLIENTS=true ;;
            --devices)  FETCH_DEVICES=true ;;
            --networks) FETCH_NETWORKS=true ;;
            --health)   FETCH_HEALTH=true ;;
            --all)      FETCH_ALL=true ;;
            --json)     OUTPUT_JSON=true ;;
            --site)     SITE="${2:?--site requires a value}"; shift ;;
            -h|--help)  usage ;;
            *)          die "Unknown option: $1" ;;
        esac
        shift
    done

    # Default to --all if no section specified
    if ! $FETCH_CLIENTS && ! $FETCH_DEVICES && ! $FETCH_NETWORKS && ! $FETCH_HEALTH; then
        FETCH_ALL=true
    fi

    load_credentials
    api_login

    # Always show sysinfo header unless --json with a specific section
    if $FETCH_ALL || ! $OUTPUT_JSON; then
        print_sysinfo
    fi

    if $FETCH_ALL || $FETCH_HEALTH;   then print_health; fi
    if $FETCH_ALL || $FETCH_CLIENTS;  then print_clients; fi
    if $FETCH_ALL || $FETCH_NETWORKS; then print_networks; fi
    if $FETCH_ALL || $FETCH_DEVICES;  then print_devices; fi
    if $FETCH_ALL; then print_portforwards; fi

    api_logout
    echo ""
    info "Done."
}

main "$@"
