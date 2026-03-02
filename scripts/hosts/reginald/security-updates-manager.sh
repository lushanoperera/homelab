#!/bin/bash
.LOG_FILE="/var/log/security-updates.log"
MAIL_TO="lushano.perera@gmail.com"
LOCK_FILE="/var/run/security-updates.lock"

# Funzione di logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Verifica se è in esecuzione
if [ -f "$LOCK_FILE" ]; then
    log "Processo già in esecuzione. Uscita."
    exit 1
fi

# Crea lock file
touch $LOCK_FILE

# Funzione di cleanup
cleanup() {
    rm -f $LOCK_FILE
    log "Pulizia completata"
}
trap cleanup EXIT

# Backup pre-aggiornamento
log "Creazione snapshot ZFS pre-aggiornamento"
zfs snapshot rpool@pre-update-$(date +%Y%m%d)

# Verifica aggiornamenti di sicurezza disponibili
SECURITY_UPDATES=$(apt-get -s upgrade | grep -i security | wc -l)
if [ $SECURITY_UPDATES -gt 0 ]; then
    log "Trovati $SECURITY_UPDATES aggiornamenti di sicurezza"

    # Notifica via email
    echo "Trovati $SECURITY_UPDATES aggiornamenti di sicurezza" | \
    mail -s "ZimaBoard: Aggiornamenti di Sicurezza Disponibili" $MAIL_TO

    # Lista dettagliata degli aggiornamenti
    apt-get -s upgrade | grep -i security > /tmp/security-updates.txt

    # Esegui gli aggiornamenti
    log "Avvio aggiornamenti di sicurezza"
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" upgrade

    # Verifica stato aggiornamenti
    if [ $? -eq 0 ]; then
        log "Aggiornamenti completati con successo"

        # Cleanup
        apt-get clean
        apt-get autoremove -y

        # Notifica completamento
        echo "Aggiornamenti di sicurezza installati con successo" | \
        mail -s "ZimaBoard: Aggiornamenti Completati" $MAIL_TO
    else
        log "ERRORE durante gli aggiornamenti"

        # Ripristino snapshot in caso di errore
        log "Ripristino snapshot pre-aggiornamento"
        zfs rollback rpool@pre-update-$(date +%Y%m%d)

        # Notifica errore
        echo "Errore durante gli aggiornamenti. Sistema ripristinato." | \
        mail -s "ZimaBoard: ERRORE Aggiornamenti" $MAIL_TO
    fi
else
    log "Nessun aggiornamento di sicurezza disponibile"
fi

# Pulizia snapshot vecchi (mantiene ultimi 3 giorni)
log "Pulizia snapshot vecchi"
zfs list -t snapshot -o name | grep "pre-update" | while read snap; do
    SNAP_DATE=$(echo $snap | grep -o "[0-9]\{8\}")
    if [ $(( $(date +%s) - $(date -d "${SNAP_DATE}" +%s) )) -gt 259200 ]; then
        zfs destroy $snap
    fi
done
