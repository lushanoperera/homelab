#!/bin/bash

# Imposta log file
LOG_FILE="/var/log/immich-mounts.log"
echo "$(date): Avvio script di mount per Immich" >> $LOG_FILE

# Verifica che i mount NFS siano pronti
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
fi

# Aspetta che i mount siano stabili
sleep 3

# Trova il rootfs del container 
ROOTFS=$(grep -Po '(?<=rootfs: ).*' /etc/pve/lxc/103.conf | cut -d',' -f1)
ROOTFS="/var/lib/lxc/103/rootfs"

echo "$(date): Rootfs del container: $ROOTFS" >> $LOG_FILE

# Crea i mountpoint nel container se non esistono
mkdir -p ${ROOTFS}/mnt/upload
mkdir -p ${ROOTFS}/mnt/database

# Cambia i permessi per allinearli con gli UID/GID del container
chown 100000:100000 ${ROOTFS}/mnt/upload
chown 100000:100000 ${ROOTFS}/mnt/database

# Esegui il bind mount
if ! mountpoint -q ${ROOTFS}/mnt/upload; then
    mount --bind /mnt/nfs_shared/immich/library ${ROOTFS}/mnt/upload
    echo "$(date): Bind mount di library completato" >> $LOG_FILE
fi

if ! mountpoint -q ${ROOTFS}/mnt/database; then
    mount --bind /mnt/nfs_shared/immich/database ${ROOTFS}/mnt/database
    echo "$(date): Bind mount di database completato" >> $LOG_FILE
fi

echo "$(date): Script completato con successo" >> $LOG_FILE
