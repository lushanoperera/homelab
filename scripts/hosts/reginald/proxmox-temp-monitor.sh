#!/bin/bash

# Proxmox Temperature Monitoring Script
# Versione 1.0

# Configurazione
LOG_DIR="/var/log/proxmox-monitoring"
LOG_FILE="${LOG_DIR}/temperature.log"
ERROR_LOG="${LOG_DIR}/temperature-errors.log"
EMAIL_RECIPIENT="lushano.perera@gmail.com"
CRITICAL_TEMP=80  # Temperatura critica in Celsius
WARNING_TEMP=70   # Temperatura di warning in Celsius

# Creazione directory log
mkdir -p "$LOG_DIR"

# Funzione di logging
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Funzione di logging errori
log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" | tee -a "$LOG_FILE" >> "$ERROR_LOG"
}

# Funzione di invio email
send_alert() {
    local subject="$1"
    local message="$2"
    echo "$message" | mail -s "$subject" "$EMAIL_RECIPIENT"
}

# Funzione per ottenere la temperatura della CPU
get_cpu_temp() {
    local temp
    
    # Prova diversi metodi per ottenere la temperatura
    
    # Metodo 1: sensors
    temp=$(sensors | grep -E 'Core 0|Package id 0' | awk '{print $3}' | grep -o '[0-9.]*' | head -n1)
    
    # Metodo 2: sysfs thermal zone
    if [ -z "$temp" ] || [ "$(echo "$temp < 0" | bc)" -eq 1 ]; then
        temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | awk '{print $1/1000}' | head -n1)
    fi
    
    # Metodo 3: alternative thermal zone
    if [ -z "$temp" ] || [ "$(echo "$temp < 0" | bc)" -eq 1 ]; then
        temp=$(cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | awk '{print $1/1000}' | head -n1)
    fi
    
    # Se ancora non abbiamo una temperatura valida
    if [ -z "$temp" ] || [ "$(echo "$temp < 0" | bc)" -eq 1 ]; then
        log_error "Impossibile rilevare la temperatura della CPU"
        return 1
    fi
    
    echo "$temp"
}

# Funzione per ottenere lo stato della CPU
get_cpu_info() {
    local freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    local load=$(uptime | awk -F'[a-z]:' '{ print $2 }' | cut -d',' -f1)
    
    echo "Frequenza attuale: $((freq/1000)) MHz"
    echo "Governor attivo: $governor"
    echo "Carico medio: $load"
}

# Funzione principale di monitoraggio
monitor_temperature() {
    # Ottieni temperatura
    local temp=$(get_cpu_temp)
    
    # Verifica temperatura
    if [ $? -ne 0 ]; then
        log_error "Rilevazione temperatura fallita"
        return 1
    fi

    # Log temperatura e info CPU
    log_message "Temperatura corrente: ${temp}°C"
    log_message "$(get_cpu_info)"

    # Controlli temperatura
    if (( $(echo "$temp >= $CRITICAL_TEMP" | bc -l) )); then
        local critical_msg="TEMPERATURA CRITICA: ${temp}°C! Possibile throttling o surriscaldamento."
        log_error "$critical_msg"
        send_alert "Proxmox - TEMPERATURA CRITICA" "$critical_msg"
        
        # Azioni di mitigazione
        echo "performance" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    elif (( $(echo "$temp >= $WARNING_TEMP" | bc -l) )); then
        local warning_msg="Temperatura elevata: ${temp}°C. Controllare raffreddamento."
        log_message "$warning_msg"
        send_alert "Proxmox - TEMPERATURA ELEVATA" "$warning_msg"
        
        # Passa a governor powersave
        echo "powersave" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    fi
}

# Esecuzione periodica del monitoraggio
main() {
    log_message "Avvio monitoraggio temperatura Proxmox"
    
    # Ciclo di monitoraggio
    while true; do
        monitor_temperature
        
        # Pausa tra un controllo e l'altro
        sleep 300  # Controlla ogni 5 minuti
    done
}

# Gestione segnali di interruzione
trap 'log_message "Monitoraggio temperatura terminato"; exit 0' SIGINT SIGTERM

# Avvio script
main
