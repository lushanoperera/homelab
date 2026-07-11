#!/bin/bash

# Immich Restic backup script
# Deployed to: /opt/bin/backup-immich.sh on Flatcar VM 100
LOCK_FILE="/tmp/immich-backup.lock"
EMAIL="lushano.perera@gmail.com"
COMPOSE_DIR="/srv/docker/immich"
LOG_DIR="/var/log/immich"
LOG_FILE="$LOG_DIR/backup.log"
ERROR_LOG="$LOG_DIR/error.log"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Crea directory per i log se non esiste
mkdir -p "$LOG_DIR"

# -------------------
# Funzioni di utility
# -------------------
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"  # Output anche su console
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$ERROR_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"  # Output anche su console
}

send_email() {
    local subject="$1"
    local body="$2"
    # Temporaneamente loggiamo invece di inviare email (per evitare limiti quotidiani Gmail)
    log_message "Email (non inviata): $subject"
    # echo "$body" | msmtp -a default "$EMAIL" -t << MAIL
    # From: Backup Immich <$EMAIL>
    # To: $EMAIL
    # Subject: $subject
    #
    # $body
    # MAIL
}

backup_database() {
    log_message "Avvio backup database via pg_dump"

    # Directory temporanea per i backup SQL
    TEMP_BACKUP_DIR="/tmp/immich_backup_tmp"
    mkdir -p "$TEMP_BACKUP_DIR"

    # Esegui pg_dump tramite container postgres
    docker exec immich_postgres pg_dump -U postgres immich > "$TEMP_BACKUP_DIR/immich_db.sql"
    local pg_result=$?

    if [ $pg_result -eq 0 ]; then
        log_message "Database SQL creato con successo, dimensione: $(du -h "$TEMP_BACKUP_DIR/immich_db.sql" | cut -f1)"
        return 0
    else
        log_error "Errore durante l'esecuzione di pg_dump"
        rm -rf "$TEMP_BACKUP_DIR"
        return 1
    fi
}

backup_database_restic() {
    TEMP_BACKUP_DIR="/tmp/immich_backup_tmp"

    if [ -f "$TEMP_BACKUP_DIR/immich_db.sql" ]; then
        # Backup del file SQL con restic
        timeout 6h restic backup \
            --verbose \
            --pack-size 16 \
            --no-cache \
            --tag immich \
            --tag "database" \
            --tag "$(date +%Y-%m)" \
            "$TEMP_BACKUP_DIR" >> "$LOG_FILE" 2>> "$ERROR_LOG"
        local restic_result=$?

        # Pulizia file temporaneo
        if [ $restic_result -eq 0 ]; then
            log_message "Backup database completato con successo"
            rm -rf "$TEMP_BACKUP_DIR"
            return 0
        else
            log_error "Backup database SQL fallito"
            rm -rf "$TEMP_BACKUP_DIR"
            return 1
        fi
    else
        log_error "File SQL non trovato per backup"
        return 1
    fi
}

do_backup() {
    local path="$1"
    local name="$2"
    local result=0

    log_message "Avvio backup $name da: $path"
    # Modifichiamo le opzioni di backup per ridurre i problemi
    timeout 6h restic backup \
        --verbose \
        --pack-size 16 \
        --no-cache \
        --tag immich \
        --tag "$name" \
        --tag "$(date +%Y-%m)" \
        "$path" >> "$LOG_FILE" 2>> "$ERROR_LOG"
    result=$?

    if [ $result -eq 0 ]; then
        log_message "Backup $name completato con successo"
        return 0
    else
        log_error "Backup $name fallito"
        return 1
    fi
}

check_integrity() {
    local check_type="$1"
    local check_result
    local check_output
    log_message "Avvio verifica integrità: $check_type"

    if [ "$check_type" = "full" ]; then
        check_output=$(restic check --read-data 2>&1)
        check_result=$?
    else
        check_output=$(restic check 2>&1)
        check_result=$?
    fi

    if [ $check_result -eq 0 ]; then
        log_message "Verifica integrità completata con successo: $check_type"
    else
        log_error "Verifica integrità fallita: $check_type"
        send_email "Verifica Integrità Immich - FALLITA" "Verifica $check_type fallita\n\n$check_output"
    fi
    return $check_result
}

# -------------------
# Controllo lock file
# -------------------
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE")
    if ps -p "$pid" > /dev/null; then
        echo "Backup già in esecuzione con PID $pid"
        exit 1
    fi
fi

# Crea lock file e imposta rimozione automatica all'uscita
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; rm -rf /tmp/immich_backup_tmp' EXIT

source /srv/docker/immich/.restic-env

# Verifica variabili d'ambiente
log_message "Verifica configurazione:"
log_message "UPLOAD_LOCATION: $UPLOAD_LOCATION"
log_message "DB_DATA_LOCATION: $DB_DATA_LOCATION"
log_message "RESTIC_REPOSITORY: $RESTIC_REPOSITORY"

# Verifica directory
if [ ! -d "$UPLOAD_LOCATION" ]; then
    log_error "Directory upload non trovata: $UPLOAD_LOCATION"
    exit 1
fi

# -------------------
# Esecuzione backup
# -------------------
PRUNE_FAILED=false
log_message "Backup iniziato"

# Prima eseguiamo il backup del database mentre i container sono ancora attivi
if backup_database; then
    DB_DUMP_SUCCESS=true
else
    DB_DUMP_SUCCESS=false
fi

# Stop Immich containers
cd "$COMPOSE_DIR" || {
    log_error "Cannot access compose directory: $COMPOSE_DIR"
    exit 1
}

log_message "Stopping Immich containers"
/opt/bin/docker-compose down

# Esegui il backup con restic del dump del database
if $DB_DUMP_SUCCESS; then
    if backup_database_restic; then
        DB_SUCCESS=true
    else
        DB_SUCCESS=false
    fi
else
    DB_SUCCESS=false
fi

# Se il database è stato salvato con successo, backup degli upload
if $DB_SUCCESS; then
    log_message "Backup database completato"

    # Backup degli upload in chunk più piccoli
    UPLOAD_SUBDIRS=$(find "$UPLOAD_LOCATION" -maxdepth 1 -type d | grep -v "^$UPLOAD_LOCATION$")

    if [ -z "$UPLOAD_SUBDIRS" ]; then
        # Nessuna sottodirectory, backup diretto
        if do_backup "$UPLOAD_LOCATION" "upload"; then
            UPLOAD_SUCCESS=true
        else
            UPLOAD_SUCCESS=false
        fi
    else
        # Backup delle sottodirectory separatamente
        UPLOAD_SUCCESS=true
        for dir in $UPLOAD_SUBDIRS; do
            dir_name=$(basename "$dir")
            if ! do_backup "$dir" "upload_$dir_name"; then
                UPLOAD_SUCCESS=false
            fi
        done
    fi

    if $UPLOAD_SUCCESS; then
        log_message "Backup upload completato"
        STATUS="successo"

        # Pulizia backup vecchi
        log_message "Avvio pulizia backup vecchi"
        timeout 30m restic forget \
            --keep-daily 7 \
            --keep-weekly 4 \
            --keep-monthly 6 \
            --prune >> "$LOG_FILE" 2>> "$ERROR_LOG"
        FORGET_RESULT=$?

        if [ $FORGET_RESULT -ne 0 ]; then
            PRUNE_FAILED=true
            log_error "Pulizia backup fallita (exit $FORGET_RESULT)"
            send_email "Backup Immich - Pulizia Fallita" "restic forget/prune fallito con exit $FORGET_RESULT. Controlla $ERROR_LOG"
        fi

        # Statistiche backup
        STATS=$(restic stats latest)
        log_message "Statistiche backup:\n$STATS"
    else
        STATUS="fallito"
        log_error "Backup upload fallito"
    fi
else
    STATUS="fallito"
    log_error "Backup database fallito"
fi

# Se il backup è fallito, invia email
if [ "$STATUS" = "fallito" ]; then
    send_email "Backup Immich - FALLITO" "Il backup è fallito. Controlla i log in $ERROR_LOG"
fi

# Riavvio dei container
log_message "Riavvio container Immich"
/opt/bin/docker-compose up -d

# -------------------
# Verifiche finali
# -------------------
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

# Propaga il fallimento a systemd (finora usciva 0 anche su backup fallito — 4 mesi non rilevati)
if [ "$STATUS" != "successo" ]; then
    exit 1
fi

# Prune fallito con backup OK: exit 1 comunque, altrimenti la retention non applicata resta invisibile
if $PRUNE_FAILED; then
    exit 1
fi
