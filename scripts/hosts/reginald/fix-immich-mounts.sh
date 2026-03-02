#!/bin/bash

# Imposta log file
LOG_FILE="/var/log/immich-mounts.log"
echo "$(date): Verifica mount per Immich" >> $LOG_FILE

# Funzione per verificare se il mount è correttamente visibile nel container
check_container_mount() {
    MOUNT_PATH="/var/lib/lxc/103/rootfs/mnt/$1"
    EXPECTED_FILES=$2
    
    # Conta i file nel mount
    FILE_COUNT=$(ls -la "$MOUNT_PATH" | wc -l)
    
    if [ "$FILE_COUNT" -ge "$EXPECTED_FILES" ]; then
        echo "$(date): Mount $1 OK ($FILE_COUNT file/dir trovati)" >> $LOG_FILE
        return 0
    else
        echo "$(date): Mount $1 non corretto (solo $FILE_COUNT file/dir trovati)" >> $LOG_FILE
        return 1
    fi
}

# Verifica che i mount NFS host siano pronti
if ! mountpoint -q /mnt/nfs_shared/immich/library || ! mountpoint -q /mnt/nfs_shared/immich/database; then
    echo "$(date): I mount NFS non sono pronti, rimonto..." >> $LOG_FILE
    
    # Rimonta se necessario
    if ! mountpoint -q /mnt/nfs_shared/immich/library; then
        mount -o rw,soft,timeo=30,retry=2,actimeo=120,noatime 192.168.200.4:/rpool/shared/immich/library /mnt/nfs_shared/immich/library
        echo "$(date): Rimontato library" >> $LOG_FILE
    fi
    
    if ! mountpoint -q /mnt/nfs_shared/immich/database; then
        mount -o rw,soft,timeo=30,retry=2,actimeo=120,noatime 192.168.200.4:/rpool/shared/immich/database /mnt/nfs_shared/immich/database
        echo "$(date): Rimontato database" >> $LOG_FILE
    fi
    
    sleep 5
fi

# Controlla lo stato del container
CONTAINER_RUNNING=$(pct status 103 | grep -c "status: running")

if [ "$CONTAINER_RUNNING" -eq 1 ]; then
    echo "$(date): Container 103 è in esecuzione, verifico mount" >> $LOG_FILE
    
    # Verifica i mount nel container (ci aspettiamo almeno 8 elementi in library e 20 in database)
    UPLOAD_OK=$(check_container_mount "upload" 8)
    DATABASE_OK=$(check_container_mount "database" 20)
    
    # Se i mount non sono corretti, riavvia il container
    if [ "$UPLOAD_OK" -ne 0 ] || [ "$DATABASE_OK" -ne 0 ]; then
        echo "$(date): Mount non corretti, riavvio container" >> $LOG_FILE
        pct reboot 103
        echo "$(date): Riavvio container avviato" >> $LOG_FILE
    fi
else
    echo "$(date): Container 103 non è in esecuzione, avvio" >> $LOG_FILE
    pct start 103
    echo "$(date): Avvio container iniziato" >> $LOG_FILE
fi

echo "$(date): Script completato" >> $LOG_FILE
