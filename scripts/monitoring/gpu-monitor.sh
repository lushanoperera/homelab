#!/bin/bash
# GPU SR-IOV Monitoring Script for MS-01
# Monitors physical GPU and all Virtual Functions

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to get GPU frequency
get_gpu_freq() {
    local pci_addr=$1
    local freq_file="/sys/kernel/debug/dri/${pci_addr}/i915_frequency_info"

    if [ -f "$freq_file" ]; then
        local current=$(grep "Current freq:" "$freq_file" | awk '{print $3}')
        local actual=$(grep "Actual freq:" "$freq_file" | awk '{print $3}')
        echo "${current}/${actual}"
    else
        echo "N/A"
    fi
}

# Function to check if GPU is busy
get_gpu_activity() {
    local pci_addr=$1
    local engine_file="/sys/kernel/debug/dri/${pci_addr}/i915_engine_info"

    if [ -f "$engine_file" ]; then
        # Check if any engine is awake
        local awake=$(grep -c "Awake? 1" "$engine_file" 2>/dev/null || echo "0")
        if [ "$awake" -gt 0 ]; then
            echo -e "${GREEN}ACTIVE${NC}"
        else
            echo -e "${BLUE}IDLE${NC}"
        fi
    else
        echo "N/A"
    fi
}

# Function to get engine runtime
get_engine_runtime() {
    local pci_addr=$1
    local engine_file="/sys/kernel/debug/dri/${pci_addr}/i915_engine_info"

    if [ -f "$engine_file" ]; then
        # Sum up all engine runtimes
        local total_runtime=$(grep "Runtime:" "$engine_file" | awk '{sum += $2} END {print sum}')
        echo "${total_runtime:-0}ms"
    else
        echo "N/A"
    fi
}

# Function to get container name for a VF
get_container_name() {
    local render_device=$1

    # Map render devices to containers
    case $render_device in
        129) echo "CT 101 (Nextcloud)" ;;
        130) echo "CT 103 (Immich)" ;;
        131) echo "CT 105 (Plex)" ;;
        132) echo "Available (VF 3)" ;;
        133) echo "Available (VF 4)" ;;
        134) echo "Available (VF 5)" ;;
        135) echo "Available (VF 6)" ;;
        *) echo "Unknown" ;;
    esac
}

# Clear screen
clear

echo -e "${BOLD}╔════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          MS-01 Intel iGPU SR-IOV Monitoring Dashboard                 ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (for debugfs access)${NC}"
    exit 1
fi

# Get overall GPU info
echo -e "${BOLD}${BLUE}═══ Overall GPU Status ═══${NC}"
echo ""

VF_COUNT=$(cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs 2>/dev/null || echo "0")
TOTAL_GPUS=$(lspci | grep -c "VGA.*Intel" || echo "0")

echo -e "Virtual Functions: ${GREEN}${VF_COUNT}${NC}"
echo -e "Total GPU Devices: ${GREEN}${TOTAL_GPUS}${NC} (1 physical + ${VF_COUNT} VFs)"
echo ""

# Physical GPU info
echo -e "${BOLD}${YELLOW}═══ Physical GPU (00:02.0) ═══${NC}"
FREQ=$(get_gpu_freq "0000:00:02.0")
ACTIVITY=$(get_gpu_activity "0000:00:02.0")
RUNTIME=$(get_engine_runtime "0000:00:02.0")

echo -e "PCI Address:    00:02.0"
echo -e "Card Device:    card0"
echo -e "Render Device:  renderD128"
echo -e "Frequency:      ${FREQ} MHz (Current/Actual)"
echo -e "Status:         ${ACTIVITY}"
echo -e "Engine Runtime: ${RUNTIME}"
echo ""

# Virtual Functions
echo -e "${BOLD}${YELLOW}═══ Virtual Functions ═══${NC}"
echo ""

# VF 0 (Container 101 - Nextcloud)
if [ -d "/sys/kernel/debug/dri/0000:00:02.1" ]; then
    echo -e "${BOLD}VF 0 - $(get_container_name 129)${NC}"
    FREQ=$(get_gpu_freq "0000:00:02.1")
    ACTIVITY=$(get_gpu_activity "0000:00:02.1")
    RUNTIME=$(get_engine_runtime "0000:00:02.1")
    echo -e "  PCI:       00:02.1  │  Card: card1  │  Render: renderD129"
    echo -e "  Frequency: ${FREQ} MHz  │  Status: ${ACTIVITY}  │  Runtime: ${RUNTIME}"
    echo ""
fi

# VF 1 (Container 103 - Immich)
if [ -d "/sys/kernel/debug/dri/0000:00:02.2" ]; then
    echo -e "${BOLD}VF 1 - $(get_container_name 130)${NC}"
    FREQ=$(get_gpu_freq "0000:00:02.2")
    ACTIVITY=$(get_gpu_activity "0000:00:02.2")
    RUNTIME=$(get_engine_runtime "0000:00:02.2")
    echo -e "  PCI:       00:02.2  │  Card: card2  │  Render: renderD130"
    echo -e "  Frequency: ${FREQ} MHz  │  Status: ${ACTIVITY}  │  Runtime: ${RUNTIME}"
    echo ""
fi

# VF 2 (Container 105 - Plex)
if [ -d "/sys/kernel/debug/dri/0000:00:02.3" ]; then
    echo -e "${BOLD}VF 2 - $(get_container_name 131)${NC}"
    FREQ=$(get_gpu_freq "0000:00:02.3")
    ACTIVITY=$(get_gpu_activity "0000:00:02.3")
    RUNTIME=$(get_engine_runtime "0000:00:02.3")
    echo -e "  PCI:       00:02.3  │  Card: card3  │  Render: renderD131"
    echo -e "  Frequency: ${FREQ} MHz  │  Status: ${ACTIVITY}  │  Runtime: ${RUNTIME}"
    echo ""
fi

# VF 3 (Available)
if [ -d "/sys/kernel/debug/dri/0000:00:02.4" ]; then
    echo -e "${BOLD}VF 3 - $(get_container_name 132)${NC}"
    echo -e "  PCI:       00:02.4  │  Card: card4  │  Render: renderD132"
    echo -e "  Status:    ${BLUE}AVAILABLE${NC} (Not assigned)"
    echo ""
fi

# VF 4 (Available)
if [ -d "/sys/kernel/debug/dri/0000:00:02.5" ]; then
    echo -e "${BOLD}VF 4 - $(get_container_name 133)${NC}"
    echo -e "  PCI:       00:02.5  │  Card: card5  │  Render: renderD133"
    echo -e "  Status:    ${BLUE}AVAILABLE${NC} (Not assigned)"
    echo ""
fi

# VF 5 (Available)
if [ -d "/sys/kernel/debug/dri/0000:00:02.6" ]; then
    echo -e "${BOLD}VF 5 - $(get_container_name 134)${NC}"
    echo -e "  PCI:       00:02.6  │  Card: card6  │  Render: renderD134"
    echo -e "  Status:    ${BLUE}AVAILABLE${NC} (Not assigned)"
    echo ""
fi

# VF 6 (Available)
if [ -d "/sys/kernel/debug/dri/0000:00:02.7" ]; then
    echo -e "${BOLD}VF 6 - $(get_container_name 135)${NC}"
    echo -e "  PCI:       00:02.7  │  Card: card7  │  Render: renderD135"
    echo -e "  Status:    ${BLUE}AVAILABLE${NC} (Not assigned)"
    echo ""
fi

# Container status
echo -e "${BOLD}${YELLOW}═══ Container Status ═══${NC}"
echo ""
pct list | grep -E "VMID|101|103|105" | head -4

echo ""
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo -e "${YELLOW}Tip:${NC} Run with 'watch -n 1' for continuous monitoring:"
echo -e "      ${GREEN}watch -n 1 -c /path/to/gpu-monitor.sh${NC}"
echo ""
