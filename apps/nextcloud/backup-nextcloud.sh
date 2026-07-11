#!/bin/bash
# Nextcloud Restic backup script
# Deployed to: /opt/bin/backup-nextcloud.sh on Flatcar VM 100
LOCK_FILE="/tmp/nextcloud-backup.lock"
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE")
    if ps -p "$pid" > /dev/null; then
        echo "Backup already running with PID $pid"
        exit 1
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT
# Load Restic credentials
source /srv/docker/nextcloud/.restic-env
EMAIL="lushano.perera@gmail.com"
COMPOSE_DIR="/srv/docker/nextcloud"
LOG_DIR="/var/log/nextcloud"
LOG_FILE="$LOG_DIR/backup.log"
ERROR_LOG="$LOG_DIR/error.log"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
# Crea directory per i log se non esiste
mkdir -p "$LOG_DIR"
# Funzione per il logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"  # Output anche su console
}
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$ERROR_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"  # Output anche su console
}
# Funzione per inviare email solo in caso di errore
send_error_email() {
    local subject="$1"
    local body="$2"
    # Temporaneamente loggiamo invece di inviare email (per evitare limiti quotidiani Gmail)
    log_message "Email (non inviata): $subject"
    # echo "$body" | msmtp -a default "$EMAIL" -t << MAIL
    # From: Backup Nextcloud <$EMAIL>
    # To: $EMAIL
    # Subject: $subject
    # $body
    # MAIL
}

# Funzione per sbloccare il repository
unlock_repository() {
    log_message "Tentativo di sblocco repository"
    UNLOCK_OUTPUT=$(restic unlock --no-cache 2>&1)
    if [[ $? -eq 0 ]]; then
        log_message "Sblocco repository completato con successo: $UNLOCK_OUTPUT"
        return 0
    else
        log_error "Impossibile sbloccare il repository: $UNLOCK_OUTPUT"
        return 1
    fi
}

# Verifica blocchi repository
log_message "Verifica blocchi repository"
LOCKS_OUTPUT=$(restic list locks --no-cache 2>&1)
if [[ "$LOCKS_OUTPUT" != "no locks found" ]] && [[ "$LOCKS_OUTPUT" != *"no locks found"* ]]; then
    unlock_repository || {
        send_error_email "Backup Nextcloud - FALLITO" "Impossibile sbloccare il repository. Potrebbero esserci operazioni in corso."
        exit 1
    }
fi

# Verifica che il repository esista e sia accessibile
if ! restic snapshots --no-cache &>/dev/null; then
    log_error "Impossibile accedere al repository. Verifica la connessione e le credenziali."
    send_error_email "Backup Nextcloud - FALLITO" "Impossibile accedere al repository. Controlla la connessione e le credenziali."
    exit 1
fi

# Verifica spazio disponibile nel repository (se possibile)
if command -v aws &>/dev/null; then
    S3_USAGE=$(aws s3 ls $RESTIC_REPOSITORY --recursive --summarize --human-readable 2>/dev/null | grep "Total Size" | awk '{print $3, $4}')
    if [ ! -z "$S3_USAGE" ]; then
        log_message "Spazio utilizzato nel repository: $S3_USAGE"
    fi
fi

# Funzione per il backup di una directory
do_backup() {
    local path="$1"
    local tag="$2"
    local result=0

    log_message "Avvio backup di: $path con tag $tag"

    timeout 6h restic backup \
        --verbose \
        --no-cache \
        --tag nextcloud \
        --tag "$tag" \
        --tag "$(date +%Y-%m)" \
        "$path" >> "$LOG_FILE" 2>> "$ERROR_LOG"

    result=$?

    if [ $result -eq 0 ]; then
        log_message "Backup di $path completato con successo"
        return 0
    else
        log_error "Backup di $path fallito"
        return 1
    fi
}

# Funzione per la verifica dell'integrità
check_integrity() {
    local check_type="$1"
    local check_result
    local check_output

    # Sblocca il repository prima della verifica
    unlock_repository

    log_message "Avvio verifica integrità: $check_type"
    if [ "$check_type" = "full" ]; then
        check_output=$(restic check --no-cache --read-data 2>&1)
        check_result=$?
    else
        check_output=$(restic check --no-cache 2>&1)
        check_result=$?
    fi
    if [ $check_result -eq 0 ]; then
        log_message "Verifica integrità completata con successo: $check_type"
    else
        log_error "Verifica integrità fallita: $check_type. Output: $check_output"
        send_error_email "Verifica Integrità Nextcloud - FALLITA" "Verifica $check_type fallita\n\n$check_output"
    fi
    return $check_result
}

# Inizio backup
log_message "Backup iniziato"

# Enable maintenance mode
if ! docker exec -u www-data nextcloud-app php occ maintenance:mode --on; then
    log_error "Impossibile attivare maintenance mode"
    send_error_email "Backup Nextcloud - FALLITO" "Impossibile attivare maintenance mode"
    exit 1
fi

# Esegui backup a blocchi
BACKUP_SUCCESS=true
PRUNE_FAILED=false

# Identifica le principali directory da salvare
NCDATA_DIR="/mnt/ncdata"

# Backup della directory principale senza i dati (config, apps, etc.)
if ! do_backup "$NCDATA_DIR" "config"; then
    BACKUP_SUCCESS=false
    log_error "Backup della configurazione Nextcloud fallito"
fi

# Backup della directory dei dati (divisa per utente)
if [ -d "$NCDATA_DIR/data" ]; then
    # Ottieni la lista delle directory utente
    USER_DIRS=$(find "$NCDATA_DIR/data" -mindepth 1 -maxdepth 1 -type d)

    if [ -z "$USER_DIRS" ]; then
        # Nessun utente trovato, fai backup dell'intera directory data
        if ! do_backup "$NCDATA_DIR/data" "all_users"; then
            BACKUP_SUCCESS=false
            log_error "Backup dei dati utente fallito"
        fi
    else
        # Backup di ogni utente separatamente
        for user_dir in $USER_DIRS; do
            user=$(basename "$user_dir")
            if ! do_backup "$user_dir" "user_$user"; then
                BACKUP_SUCCESS=false
                log_error "Backup dell'utente $user fallito"
            fi
        done
    fi
else
    log_message "Directory data non trovata, backup della struttura principale"
    # Se non c'è una struttura utente, fai backup dell'intera directory
    if ! do_backup "$NCDATA_DIR" "all_data"; then
        BACKUP_SUCCESS=false
        log_error "Backup dei dati Nextcloud fallito"
    fi
fi

# Backup di appdata_* separatamente (database e configurazioni)
APPDATA_DIRS=$(find "$NCDATA_DIR" -maxdepth 1 -type d -name "appdata_*")
for app_dir in $APPDATA_DIRS; do
    app_name=$(basename "$app_dir")
    if ! do_backup "$app_dir" "$app_name"; then
        BACKUP_SUCCESS=false
        log_error "Backup di $app_name fallito"
    fi
done

# Determina lo stato finale del backup
if $BACKUP_SUCCESS; then
    STATUS="successo"
    log_message "Tutti i backup completati con successo"

    # Prima di procedere, assicurati che il repository sia sbloccato
    unlock_repository

    # Esegui la pulizia dei backup vecchi
    # (timeout 15m troncava il prune a metà — repo grande + --no-cache; visto 2026-07-11)
    log_message "Avvio pulizia backup vecchi"
    timeout 60m restic forget \
        --no-cache \
        --keep-daily 7 \
        --prune >> "$LOG_FILE" 2>> "$ERROR_LOG"

    FORGET_RESULT=$?

    # Se il primo tentativo ha successo, prova con la policy completa
    if [ $FORGET_RESULT -eq 0 ]; then
        log_message "Prima fase di pulizia completata, proseguo con policy completa"
        unlock_repository

        timeout 90m restic forget \
            --no-cache \
            --keep-hourly 24 \
            --keep-daily 7 \
            --keep-weekly 4 \
            --keep-monthly 6 \
            --prune >> "$LOG_FILE" 2>> "$ERROR_LOG"

        FORGET_RESULT=$?
    fi

    # Se ancora fallisce, registra l'errore
    if [ $FORGET_RESULT -ne 0 ]; then
        PRUNE_FAILED=true
        unlock_repository

        PRUNE_ERROR=$(restic forget --no-cache --dry-run --keep-daily 7 2>&1)
        log_error "Pulizia backup fallita. Output dry-run: $PRUNE_ERROR"
        send_error_email "Backup Nextcloud - Pulizia Fallita" "La pulizia dei backup vecchi è fallita. Output: $PRUNE_ERROR"
        log_message "Scheduling pulizia manuale necessaria"

        cat > /tmp/cleanup-snapshots.sh << 'CLEANUP'
#!/bin/bash
source /srv/docker/nextcloud/.restic-env

# Sblocca repository
restic unlock

# Esegui pulizia con timeout esteso
timeout 120m restic forget \
    --no-cache \
    --keep-daily 7 \
    --prune

echo "Pulizia completata. Verifica lo stato con 'restic snapshots'"
CLEANUP
        chmod +x /tmp/cleanup-snapshots.sh
        log_message "Manual cleanup script created at /tmp/cleanup-snapshots.sh"
    fi
else
    STATUS="fallito"
    log_error "Almeno uno dei backup è fallito"
    send_error_email "Backup Nextcloud - FALLITO" "Almeno uno dei componenti del backup è fallito. Controlla i log in $ERROR_LOG"
fi

# Disable maintenance mode
if ! docker exec -u www-data nextcloud-app php occ maintenance:mode --off; then
    log_error "Impossibile disattivare maintenance mode"
    send_error_email "Backup Nextcloud - ERRORE" "Impossibile disattivare maintenance mode"
fi

# Log completamento
log_message "Backup completato con stato: $STATUS"

# Verifica integrità base dopo ogni backup riuscito
if [ "$STATUS" = "successo" ]; then
    check_integrity "basic"
fi

# Verifica approfondita ogni domenica
if [ "$STATUS" = "successo" ] && [ "$(date +%u)" = "7" ]; then
    log_message "Avvio verifica approfondita settimanale"
    check_integrity "full"
fi

# Propaga il fallimento a systemd (altrimenti l'unit risulta verde anche su backup fallito)
if [ "$STATUS" != "successo" ]; then
    exit 1
fi

# Prune fallito con backup OK: exit 1 comunque, altrimenti la retention non applicata resta invisibile
if $PRUNE_FAILED; then
    exit 1
fi
