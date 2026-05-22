#!/bin/bash
# technitium-config-backup.sh — restic backup of Technitium config dir + prune.
# Deploy to /opt/bin/technitium-config-backup.sh on Flatcar and Reginald.
# QNAP: registered via Container Station scheduled task; same script body.
#
# Env file: /etc/restic/technitium.env (mirror of apps/technitium/restic-env.example).
# Retention: keep-daily 7, keep-weekly 4, keep-monthly 6.

set -euo pipefail

ENV_FILE="${TECHNITIUM_RESTIC_ENV:-/etc/restic/technitium.env}"
LOG_TAG="technitium-backup"

log() { logger -t "$LOG_TAG" "$1"; echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $1"; }

if [[ ! -r $ENV_FILE ]]; then
    log "ERROR: env file not readable: $ENV_FILE"
    exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${TECHNITIUM_CONFIG_DIR:?TECHNITIUM_CONFIG_DIR not set}"
: "${TECHNITIUM_NODE:?TECHNITIUM_NODE not set}"
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY not set}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD not set}"

if [[ ! -d $TECHNITIUM_CONFIG_DIR ]]; then
    log "ERROR: config dir missing: $TECHNITIUM_CONFIG_DIR"
    exit 1
fi

# Init repo if first run (idempotent — restic init returns 0 if already initialized via --quiet trick).
if ! restic snapshots --no-lock --json >/dev/null 2>&1; then
    log "Initializing restic repo at $RESTIC_REPOSITORY"
    restic init || true
fi

log "Backing up $TECHNITIUM_CONFIG_DIR (node=$TECHNITIUM_NODE)"
restic backup \
    --host "technitium-${TECHNITIUM_NODE}" \
    --tag technitium \
    --tag "node=${TECHNITIUM_NODE}" \
    "$TECHNITIUM_CONFIG_DIR"

log "Pruning per retention policy"
restic forget \
    --host "technitium-${TECHNITIUM_NODE}" \
    --tag technitium \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune

log "Done"
