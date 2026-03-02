#!/bin/bash
echo "=== Temperature Monitor Status ==="
systemctl status temp-monitor
echo
echo "=== Latest Temperature Logs ==="
tail -n 10 /var/log/temp-monitor.log
echo
echo "=== Current CPU Status ==="
sensors
echo
echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo "Current Frequency: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
