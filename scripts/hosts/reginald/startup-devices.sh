#!/bin/bash

LOG_FILE="/var/log/ups-events.log"
MS01_MAC="58:47:ca:7c:06:a2"
QNAP_MAC="00:08:9b:fa:6d:8d"
MANAGE_MS01=true
MANAGE_QNAP=false

log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Attendi 2 minuti dal ripristino della corrente
log_event "Attesa 2 minuti prima della riaccensione dispositivi"
sleep 120

# ZimaBoard dovrebbe essere già accesa (auto-power-on)

# Riaccendi MS-01 e QNAP contemporaneamente dopo 5 minuti
log_event "Attesa altri 3 minuti prima di riaccendere gli altri dispositivi"
sleep 180

if [ "$MANAGE_MS01" = true ]; then
    log_event "Riaccensione MS-01 tramite Wake-on-LAN"
    etherwake -i $(ip route | grep default | awk '{print $5}') "$MS01_MAC"
fi

if [ "$MANAGE_QNAP" = true ]; then
    log_event "Riaccensione QNAP tramite Wake-on-LAN"
    etherwake -i $(ip route | grep default | awk '{print $5}') "$QNAP_MAC"
fi

log_event "Procedura di riaccensione completata"
