#!/bin/bash
while true; do
    clear
    echo "GPU Frequency Monitor - $(date '+%H:%M:%S')"
    echo "========================================="
    echo ""
    grep -E "Current|Actual|Min|Max" /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info
    echo ""
    echo "VF Status:"
    echo "  VFs Created: $(cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs)"
    echo "  Total GPUs: $(lspci | grep -c 'VGA.*Intel')"
    echo ""
    echo "Containers:"
    pct list | grep -E '101|103|105' | awk '{printf "  %s: %s\n", $1, $2}'
    echo ""
    echo "Press Ctrl+C to exit"
    sleep 1
done
