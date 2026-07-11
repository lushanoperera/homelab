#!/bin/bash
# check-cluster-drift.sh — compare SOA serial across Technitium cluster nodes
# and pull QPS stats from primary. Writes JSON status for the Homepage widget
# to consume. Exits 0 when all serials match, 1 otherwise.
#
# Deploy to /opt/bin/check-cluster-drift.sh on Flatcar. Driven by
# systemd timer dns-drift-check.timer (every 5 min).
#
# Env (loaded from /etc/dns-drift.env on the host):
#   TECHNITIUM_ADMIN_PASSWORD  required — for primary stats API
#   TECHNITIUM_ADMIN_USER      default: admin
#   PRIMARY                    default: 192.168.100.120
#   ZONE                       default: home.disconnesso.com
#   OUT_FILE                   default: /srv/docker/homepage/data/dns-cluster.json

set -euo pipefail

ENV_FILE="${DNS_DRIFT_ENV:-/etc/dns-drift.env}"
# shellcheck disable=SC1090
[[ -r $ENV_FILE ]] && source "$ENV_FILE"

PRIMARY="${PRIMARY:-192.168.100.120}"
SECONDARIES=("${SECONDARIES_OVERRIDE:-192.168.100.100 192.168.100.254}")
ZONE="${ZONE:-home.disconnesso.com}"
OUT_FILE="${OUT_FILE:-/srv/docker/homepage/data/dns-cluster.json}"
USER="${TECHNITIUM_ADMIN_USER:-admin}"
PASS="${TECHNITIUM_ADMIN_PASSWORD:-}"
TAG="dns-drift"

log() { logger -t "$TAG" "$1"; echo "$(date '+%Y-%m-%d %H:%M:%S') [$TAG] $1"; }

mkdir -p "$(dirname "$OUT_FILE")"

# --- collect SOA serial per node --------------------------------------------
get_serial() {
    local node="$1"
    dig +short +time=3 +tries=1 @"$node" SOA "$ZONE" 2>/dev/null \
        | awk '{print $3}' | head -1
}

primary_serial=$(get_serial "$PRIMARY" || echo "")
declare -A serials
serials["$PRIMARY"]="$primary_serial"

# shellcheck disable=SC2206
nodes=($PRIMARY ${SECONDARIES[@]})
drift="false"
unreachable="false"
for n in "${SECONDARIES[@]}"; do
    s=$(get_serial "$n" || echo "")
    serials["$n"]="$s"
    if [[ -z $s ]]; then
        unreachable="true"
    elif [[ -n $primary_serial && $s != "$primary_serial" ]]; then
        drift="true"
    fi
done

# --- primary QPS / blocked stats --------------------------------------------
qps="null"; blocked="null"; total="null"
if [[ -n $PASS ]]; then
    token=$(curl -sSk --max-time 5 -G "https://${PRIMARY}:5380/api/user/login" \
        --data-urlencode "user=$USER" \
        --data-urlencode "pass=$PASS" \
        --data-urlencode "includeInfo=false" \
      | grep -oE '"token":"[^"]+"' | head -1 | cut -d'"' -f4 || true)
    if [[ -n $token ]]; then
        stats=$(curl -sSk --max-time 5 -G "https://${PRIMARY}:5380/api/dashboard/stats/get" \
            --data-urlencode "token=$token" \
            --data-urlencode "type=lastHour" || true)
        # Field names per Technitium dashboard: stats.totalQueries, blocked.
        total=$(echo "$stats" | grep -oE '"totalQueries":[0-9]+' | head -1 | cut -d: -f2 || echo "null")
        blocked=$(echo "$stats" | grep -oE '"totalBlocked":[0-9]+' | head -1 | cut -d: -f2 || echo "null")
        # qps over last hour (queries / 3600), bash arithmetic safe-ish
        if [[ $total =~ ^[0-9]+$ ]]; then
            qps=$(awk -v t="$total" 'BEGIN{ printf "%.2f", t/3600 }')
        fi
    fi
fi

# --- compose status ---------------------------------------------------------
if [[ $unreachable == "true" ]]; then
    status="unreachable"
elif [[ $drift == "true" ]]; then
    status="drift"
else
    status="healthy"
fi

# --- write JSON (atomic) ----------------------------------------------------
tmp=$(mktemp)
{
    printf '{\n'
    printf '  "status": "%s",\n' "$status"
    printf '  "zone": "%s",\n' "$ZONE"
    printf '  "primary": "%s",\n' "$PRIMARY"
    printf '  "primary_serial": "%s",\n' "${primary_serial:-unknown}"
    printf '  "qps_1h": %s,\n' "${qps:-null}"
    printf '  "queries_1h": %s,\n' "${total:-null}"
    printf '  "blocked_1h": %s,\n' "${blocked:-null}"
    printf '  "checked_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "nodes": {\n'
    first=1
    for n in "${nodes[@]}"; do
        [[ $first -eq 1 ]] || printf ',\n'
        printf '    "%s": "%s"' "$n" "${serials[$n]:-unreachable}"
        first=0
    done
    printf '\n  }\n'
    printf '}\n'
} > "$tmp"
mv "$tmp" "$OUT_FILE"
chmod 0644 "$OUT_FILE"

log "status=$status primary_serial=${primary_serial:-?} qps=$qps blocked=$blocked"

[[ $status == "healthy" ]] && exit 0 || exit 1
