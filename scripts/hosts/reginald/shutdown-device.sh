#!/bin/bash

DEVICE="$1"
MODE="${2:-normal}"  # normal o force
LOG_FILE="/var/log/ups-events.log"

log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

case "$DEVICE" in
    ms01)
        log_event "Spegnimento MS-01 (192.168.100.38)"
        if [ "$MODE" = "force" ]; then
            # Spegnimento forzato
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@192.168.100.38 "shutdown -h now" || \
            log_event "ERRORE: Impossibile spegnere MS-01"
        else
            # Spegnimento ordinato
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@192.168.100.38 "shutdown -h +1" || \
            log_event "ERRORE: Impossibile spegnere MS-01"
        fi
        ;;
        
    qnap)
        log_event "Spegnimento QNAP (192.168.100.254)"
        # Metodo SSH per QNAP
        ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no admin@192.168.100.254 "poweroff" || \
        log_event "ERRORE: Impossibile spegnere QNAP"
        ;;
        
    zimaboard)
        log_event "Spegnimento ZimaBoard (locale)"
        if [ "$MODE" = "force" ]; then
            shutdown -h now
        else
            shutdown -h +2
        fi
        ;;
        
    *)
        log_event "ERRORE: Dispositivo sconosciuto: $DEVICE"
        exit 1
        ;;
esac
