#!/bin/bash
DATE=\20250218
echo "=== ZFS Status Report \ ===" >> /var/log/zfs-monitor.log
echo "Pool Status:" >> /var/log/zfs-monitor.log
zpool status >> /var/log/zfs-monitor.log
echo "ARC Stats:" >> /var/log/zfs-monitor.log
arc_summary >> /var/log/zfs-monitor.log
echo "Dataset Space:" >> /var/log/zfs-monitor.log
zfs list >> /var/log/zfs-monitor.log
