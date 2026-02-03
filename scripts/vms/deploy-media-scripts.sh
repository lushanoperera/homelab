#!/bin/bash
# deploy-media-scripts.sh - Deploy media management scripts to Flatcar VM
#
# Usage: ./deploy-media-scripts.sh [host]
#
# Deploys:
#   - media-audit.sh
#   - media-audit-functions.sh
#   - media-quality.sh
#   - media-cleanup.sh
#   - media-trash-cleanup.service/timer (systemd units)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_HOST="${1:-core@192.168.100.100}"
TARGET_DIR="/opt/bin"

echo "Deploying media scripts to $TARGET_HOST:$TARGET_DIR"

# Scripts to deploy
SCRIPTS=(
    "media-audit.sh"
    "media-audit-functions.sh"
    "media-quality.sh"
    "media-cleanup.sh"
)

# Systemd units to deploy
SYSTEMD_UNITS=(
    "media-trash-cleanup.service"
    "media-trash-cleanup.timer"
)

# Check all scripts exist
for script in "${SCRIPTS[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        echo "ERROR: Script not found: $SCRIPT_DIR/$script"
        exit 1
    fi
done

# Create target directory (Flatcar has read-only /usr, but /opt/bin is writable)
ssh "$TARGET_HOST" "sudo mkdir -p $TARGET_DIR"

# Copy scripts
for script in "${SCRIPTS[@]}"; do
    echo "  Copying $script..."
    scp "$SCRIPT_DIR/$script" "$TARGET_HOST:/tmp/$script"
    ssh "$TARGET_HOST" "sudo mv /tmp/$script $TARGET_DIR/$script && sudo chmod +x $TARGET_DIR/$script"
done

# Deploy systemd units
echo ""
echo "Deploying systemd units..."
for unit in "${SYSTEMD_UNITS[@]}"; do
    unit_path="$REPO_ROOT/systemd/$unit"
    if [[ -f "$unit_path" ]]; then
        echo "  Copying $unit..."
        scp "$unit_path" "$TARGET_HOST:/tmp/$unit"
        ssh "$TARGET_HOST" "sudo mv /tmp/$unit /etc/systemd/system/$unit"
    else
        echo "  WARNING: Unit not found: $unit_path"
    fi
done

# Enable timer
echo ""
echo "Enabling trash cleanup timer..."
ssh "$TARGET_HOST" "sudo systemctl daemon-reload && sudo systemctl enable --now media-trash-cleanup.timer"

echo ""
echo "Deployment complete!"
echo ""
echo "Scripts deployed to $TARGET_DIR:"
for script in "${SCRIPTS[@]}"; do
    echo "  - $script"
done
echo ""
echo "Systemd units:"
ssh "$TARGET_HOST" "systemctl list-timers media-trash-cleanup.timer --no-pager" 2>/dev/null || true

echo ""
echo "Quick verification:"
ssh "$TARGET_HOST" "ls -la $TARGET_DIR/media-*.sh"
