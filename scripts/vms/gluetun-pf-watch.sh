#!/bin/bash
# gluetun-pf-watch.sh - Detect dead ProtonVPN port-forward and remediate
# Deploy to Flatcar VM at /opt/bin/gluetun-pf-watch.sh
#
# Runs on a 5 min timer. Queries gluetun control server /v1/portforward.
# If port=0 for FAIL_THRESHOLD consecutive runs (default 2 = ~10 min outage),
# restarts gluetun + media stack dependents. COOLDOWN_SEC prevents tight loops.
#
# Background: ProtonVPN NAT-PMP can fail with "recvfrom: connection refused" on
# UDP 5351; gluetun then loops without re-acquiring. No native healthcheck
# signal for this state. See .claude/rules/flatcar-lessons.md.

set -euo pipefail

STATE_FILE="/tmp/gluetun-pf-watch.state"
COOLDOWN_FILE="/tmp/gluetun-pf-watch.cooldown"
FAIL_THRESHOLD=2
COOLDOWN_SEC=1800
GLUETUN_CTRL="${GLUETUN_CTRL:-http://localhost:8001/v1/portforward}"
COMPOSE_DIR="/srv/docker/media-stack"
COMPOSE="/opt/bin/docker-compose"
DEPS=(gluetun qbittorrent prowlarr sabnzbd)

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [gluetun-pf-watch] $1"; }

get_port() {
    curl -sf --max-time 5 "$GLUETUN_CTRL" 2>/dev/null \
        | grep -oE '"port":[0-9]+' \
        | head -1 \
        | cut -d: -f2
}

read_state() { [[ -f $STATE_FILE ]] && cat "$STATE_FILE" || echo 0; }
write_state() { echo "$1" > "$STATE_FILE"; }

in_cooldown() {
    [[ -f $COOLDOWN_FILE ]] || return 1
    local last_remediation now elapsed
    last_remediation=$(cat "$COOLDOWN_FILE")
    now=$(date +%s)
    elapsed=$(( now - last_remediation ))
    (( elapsed < COOLDOWN_SEC ))
}

remediate() {
    log "ERROR: forwarded port has been 0 for $FAIL_THRESHOLD consecutive checks — restarting stack"
    cd "$COMPOSE_DIR"
    "$COMPOSE" restart "${DEPS[@]}" 2>&1 | sed "s/^/$(date '+%Y-%m-%d %H:%M:%S') [gluetun-pf-watch] /"
    date +%s > "$COOLDOWN_FILE"
    write_state 0
    log "Remediation complete; entering ${COOLDOWN_SEC}s cooldown"
}

main() {
    local port fails
    port=$(get_port || true)
    fails=$(read_state)

    if [[ -z $port || $port == "0" ]]; then
        fails=$(( fails + 1 ))
        write_state "$fails"
        log "WARN: forwarded port is ${port:-<unreachable>} (consecutive failures: $fails/$FAIL_THRESHOLD)"

        if (( fails >= FAIL_THRESHOLD )); then
            if in_cooldown; then
                log "WARN: remediation suppressed by cooldown"
                return 0
            fi
            remediate
        fi
        return 0
    fi

    if (( fails > 0 )); then
        log "Recovered: forwarded port is $port (after $fails failures)"
    fi
    write_state 0
}

main "$@"
