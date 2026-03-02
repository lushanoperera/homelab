#!/bin/bash

# Configurazione
LOG_FILE="/var/log/ups-events.log"
EMAIL="lushano.perera@gmail.com"
MS01_IP="192.168.100.38"
QNAP_IP="192.168.100.254"
QNAP_MAC="00:08:9b:fa:6d:8d"
MS01_MAC="58:47:ca:7c:06:a2"

# Configurazione flags per abilitare/disabilitare dispositivi
MANAGE_MS01=true
MANAGE_QNAP=false  # Disabilitato come richiesto

# Funzioni di utilità
log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    logger -t upssched "$1"
}

send_notification() {
    local subject="$1"
    local message="$2"
    echo "$message" | mail -s "$subject" "$EMAIL"
    log_event "Email sent: $subject"
}

# Gestione eventi
case $1 in
    shutdown-warning)
        log_event "🚨 BLACKOUT: 10 minuti trascorsi, avvio procedure di spegnimento"
        send_notification "UPS: Avvio Spegnimento Dispositivi" "Blackout prolungato rilevato. Avvio spegnimento ordinato dei dispositivi."
        
        # Spegni MS-01 per primo (se abilitato)
        if [ "$MANAGE_MS01" = true ]; then
            /usr/local/bin/shutdown-device.sh ms01 &
        fi
        
        # Spegni QNAP dopo 2 minuti (se abilitato)
        if [ "$MANAGE_QNAP" = true ]; then
            (sleep 120 && /usr/local/bin/shutdown-device.sh qnap) &
        fi
        
        # Spegni ZimaBoard dopo 5 minuti
        (sleep 300 && /usr/local/bin/shutdown-device.sh zimaboard) &
        ;;
        
    power-restored)
        log_event "✅ ALIMENTAZIONE RIPRISTINATA"
        send_notification "UPS: Alimentazione Ripristinata" "L'alimentazione è stata ripristinata. I dispositivi verranno riaccesi automaticamente."
        
        # Avvia procedura di riaccensione con delay
        /usr/local/bin/startup-devices.sh &
        ;;
        
    critical-shutdown)
        log_event "🔴 BATTERIA CRITICA: Spegnimento immediato"
        send_notification "UPS: EMERGENZA - Batteria Critica" "Batteria UPS critica. Spegnimento immediato di tutti i dispositivi."
        
        # Spegnimento immediato di tutti i dispositivi
        if [ "$MANAGE_MS01" = true ]; then
            /usr/local/bin/shutdown-device.sh ms01 force &
        fi
        if [ "$MANAGE_QNAP" = true ]; then
            /usr/local/bin/shutdown-device.sh qnap force &
        fi
        
        # Spegni ZimaBoard dopo 60 secondi
        (sleep 60 && /usr/local/bin/shutdown-device.sh zimaboard force) &
        ;;
        
    battery-replace-warning)
        log_event "🔋 Rilevata necessità di sostituzione batteria UPS"
        send_notification "UPS: Sostituzione Batteria Richiesta" "Il sistema UPS indica che è necessario sostituire la batteria."
        ;;
        
    *)
        log_event "Evento sconosciuto: $1"
        ;;
esac
