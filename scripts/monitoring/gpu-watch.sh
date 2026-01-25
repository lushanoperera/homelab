#!/bin/bash
# Simple GPU frequency and activity watcher
# Usage: ./gpu-watch.sh [interval_seconds]

INTERVAL=${1:-1}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

watch_gpu() {
    while true; do
        clear
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║       GPU Frequency & Activity Monitor (SR-IOV)          ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo ""
        echo "Time: $(date '+%H:%M:%S')"
        echo ""

        # Physical GPU
        echo "Physical GPU (00:02.0):"
        if [ -f "/sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info" ]; then
            grep -E "Current|Actual" /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info | \
                sed 's/^/  /'
        fi
        echo ""

        # VF 0 (Nextcloud)
        echo "VF 0 - Container 101 (Nextcloud) - renderD129:"
        if [ -d "/sys/kernel/debug/dri/0000:00:02.1" ]; then
            echo "  Status: Available"
        fi
        echo ""

        # VF 1 (Immich)
        echo "VF 1 - Container 103 (Immich) - renderD130:"
        if [ -d "/sys/kernel/debug/dri/0000:00:02.2" ]; then
            echo "  Status: Available"
        fi
        echo ""

        # VF 2 (Plex)
        echo "VF 2 - Container 105 (Plex) - renderD131:"
        if [ -d "/sys/kernel/debug/dri/0000:00:02.3" ]; then
            echo "  Status: Available"
        fi
        echo ""

        echo "───────────────────────────────────────────────────────────"
        echo "Press Ctrl+C to exit | Refresh: ${INTERVAL}s"

        sleep $INTERVAL
    done
}

# Check if root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Must run as root"
    exit 1
fi

watch_gpu
