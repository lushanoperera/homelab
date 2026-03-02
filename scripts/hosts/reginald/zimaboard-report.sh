#!/bin/bash
echo "=== REPORT OTTIMIZZAZIONI ZIMABOARD ==="
echo "Data: $(date)"
echo 

echo "= CPU ="
echo "Governor: $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | head -1)"
echo "Frequenza: $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | head -1) kHz"
if command -v sensors >/dev/null 2>&1; then
  echo "Temperatura: $(sensors | grep -E 'Core 0|Package id 0' | head -1)"
fi
echo 

echo "= MEMORIA ="
free -h
if command -v zramctl >/dev/null 2>&1; then
  echo "zRAM:"
  zramctl
fi
echo 

echo "= STORAGE ="
for disk in $(ls /sys/block/ | grep -E 'sd|nvme|mmcblk'); do
  echo "$disk:"
  echo "  Scheduler: $(cat /sys/block/$disk/queue/scheduler 2>/dev/null)"
  echo "  ReadAhead: $(cat /sys/block/$disk/queue/read_ahead_kb 2>/dev/null) KB"
done
echo 

echo "= RETE ="
echo "Buffer TCP:"
sysctl net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem

echo "= SERVIZI ="
echo "Monitor termico: $(systemctl is-enabled zimaboard-monitor.service 2>/dev/null || echo "avviato via cron")"
echo "Ottimizzazioni boot: $(systemctl is-enabled zimaboard-optimize.service)"
echo 

echo "= FILE DI CONFIGURAZIONE ="
echo "Ottimizzazioni sysctl:"
ls -la /etc/sysctl.d/99-zimaboard*

echo "Script di ottimizzazione:"
ls -la /usr/local/bin/zimaboard*
