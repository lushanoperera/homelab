#!/bin/bash

# Configurazione
MAX_TEMP=80  # Temperatura massima in gradi Celsius
WARN_TEMP=70 # Temperatura di warning
CHECK_INTERVAL=60  # Intervallo di controllo in secondi
LOG_FILE="/var/log/temp-monitor.log"
MAIL_TO="lushano.perera@gmail.com"

# Funzione per inviare notifiche
send_alert() {
    local temp=$1
    local severity=$2
    local message="[ZimaBoard ${severity}] Temperatura CPU: ${temp}°C"
    
    # Log su file
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> $LOG_FILE
    
    # Log di sistema
    logger -t temp-monitor "$message"
    
    # Email
    echo "$message" | mail -s "ZimaBoard Temperature Alert" $MAIL_TO
}

# Funzione per ottenere la temperatura corrente
get_cpu_temp() {
    # Prova prima con sensors
    local temp=$(sensors | grep 'Core 0' | awk '{print $3}' | grep -o '[0-9.]*')
    
    # Se sensors fallisce, prova con il file di sistema
    if [ -z "$temp" ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp=$(echo "scale=1; $temp/1000" | bc)
    fi
    
    echo $temp
}

# Script principale
while true; do
    TEMP=$(get_cpu_temp)
    FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    FREQ_MHZ=$(echo "scale=2; $FREQ/1000" | bc)
    
    # Registra sempre nel log
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Temp: ${TEMP}°C, Freq: ${FREQ_MHZ}MHz" >> $LOG_FILE
    
    # Controllo temperatura
    if (( $(echo "$TEMP >= $MAX_TEMP" | bc -l) )); then
        send_alert $TEMP "CRITICAL"
        # Forza throttling
        echo "powersave" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    elif (( $(echo "$TEMP >= $WARN_TEMP" | bc -l) )); then
        send_alert $TEMP "WARNING"
    fi
    
    # Se la temperatura torna normale, ripristina governor
    if (( $(echo "$TEMP < $WARN_TEMP" | bc -l) )); then
        echo "schedutil" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    fi
    
    # Pulizia log vecchi (mantiene ultimi 7 giorni)
    find /var/log -name "temp-monitor.log*" -mtime +7 -delete
    
    sleep $CHECK_INTERVAL
done
