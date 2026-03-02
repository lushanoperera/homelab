#!/bin/bash
LOG_FILE="/var/log/zimaboard-boot-optimize.log"

# Funzione per logging
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Crea directory log
mkdir -p $(dirname $LOG_FILE)

log "Avvio ottimizzazioni Zimaboard..."

# 1. Ottimizzazioni CPU
log "Applicazione ottimizzazioni CPU..."
# Imposta governor ottimale
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
  gov_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
  if [ -f "$gov_path" ]; then
    avail_govs=$(cat $gov_path)
    if echo "$avail_govs" | grep -q "schedutil"; then
      opt_gov="schedutil"
    elif echo "$avail_govs" | grep -q "ondemand"; then
      opt_gov="ondemand"
    else
      opt_gov="performance"
    fi
    
    log "Impostazione governor CPU su $opt_gov"
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo "$opt_gov" > $gov 2>/dev/null
    done
  fi
fi

# 2. Ottimizzazioni I/O
log "Applicazione ottimizzazioni I/O..."
# Imposta scheduler disk
for disk in $(ls /sys/block/ | grep -E 'sd|nvme|mmcblk'); do
  if [ -f "/sys/block/$disk/queue/scheduler" ]; then
    if [ -f "/sys/block/$disk/queue/rotational" ] && [ "$(cat /sys/block/$disk/queue/rotational)" = "0" ]; then
      log "Impostazione scheduler mq-deadline per $disk (SSD/NVMe)"
      echo "mq-deadline" > /sys/block/$disk/queue/scheduler 2>/dev/null
    else
      log "Impostazione scheduler bfq per $disk (HDD)"
      echo "bfq" > /sys/block/$disk/queue/scheduler 2>/dev/null || echo "mq-deadline" > /sys/block/$disk/queue/scheduler 2>/dev/null
    fi
    
    # Imposta read_ahead
    if [ -f "/sys/block/$disk/queue/read_ahead_kb" ]; then
      log "Impostazione read_ahead per $disk"
      echo "2048" > /sys/block/$disk/queue/read_ahead_kb 2>/dev/null
    fi
  fi
done

# 3. Ottimizzazioni memoria
log "Applicazione ottimizzazioni memoria..."
# Verifica se ci sono sottosistemi ZFS da ottimizzare
if [ -f "/proc/spl/kstat/zfs/arcstats" ]; then
  log "Ottimizzazione ZFS ARC..."
  if [ -f "/proc/sys/vm/swappiness" ]; then
    echo "100" > /proc/sys/vm/swappiness
  fi
fi

log "Ottimizzazioni completate con successo."
