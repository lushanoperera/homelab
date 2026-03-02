#!/bin/bash
LOG_FILE="/var/log/zimaboard-monitor.log"
ALERT_TEMP=75
CRITICAL_TEMP=85

# Crea directory di log se non esiste
mkdir -p $(dirname $LOG_FILE)

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

get_cpu_temp() {
  # Prova diversi metodi per ottenere temperatura
  if command -v sensors >/dev/null 2>&1; then
    local temp=$(sensors | grep -E 'Core 0|Package id 0' | head -1 | grep -o '[0-9.]*°C' | grep -o '[0-9.]*')
    if [ ! -z "$temp" ]; then
      echo $temp
      return
    fi
  fi
  
  # Prova i file di thermal zone
  for zone in /sys/class/thermal/thermal_zone*/temp; do
    if [ -f "$zone" ]; then
      local temp=$(cat $zone 2>/dev/null | awk '{printf "%.1f", $1/1000}')
      echo $temp
      return
    fi
  done
  
  # Fallback
  echo "50.0"  # valore di fallback sicuro
}

monitor_performance() {
  log "=== Performance Report ==="
  
  # CPU
  log "CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
  
  # Memoria
  log "Memory Usage: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
  
  # Temperatura
  local temp=$(get_cpu_temp)
  log "CPU Temperature: ${temp}°C"
  
  # Throttling check
  if command -v bc >/dev/null 2>&1; then
    if [ $(echo "$temp >= $ALERT_TEMP" | bc -l) -eq 1 ]; then
      log "WARNING: CPU temperatura elevata (${temp}°C)"
      if [ $(echo "$temp >= $CRITICAL_TEMP" | bc -l) -eq 1 ]; then
        log "CRITICAL: Temperatura CPU critica (${temp}°C) - attivazione throttling"
        for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          echo "powersave" > $gov 2>/dev/null || true
        done
      fi
    else
      for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "schedutil" > $gov 2>/dev/null || echo "ondemand" > $gov 2>/dev/null || true
      done
    fi
  fi
}

# Esegui il monitoraggio
monitor_performance

# Pulizia log vecchi (mantiene ultimi 7 giorni)
find /var/log -name "zimaboard-monitor.log*" -mtime +7 -delete 2>/dev/null || true
