#!/bin/bash
LOG_FILE="/var/log/log-monitor.log"
EMAIL="lushano.perera@gmail.com"

# Verifica spazio utilizzato
log_usage=$(du -sh /var/log | cut -f1)
echo "Spazio utilizzato dai log: $log_usage" >> $LOG_FILE

# Verifica dataset ZFS
zfs list rpool/log >> $LOG_FILE

# Controlla log più grandi
echo "Top 10 file di log più grandi:" >> $LOG_FILE
find /var/log -type f -exec du -h {} + | sort -rh | head -n 10 >> $LOG_FILE

# Verifica rotazione
echo "Status rotazione log:" >> $LOG_FILE
logrotate -d /etc/logrotate.conf >> $LOG_FILE 2>&1

# Invia alert se spazio supera soglia
used_percent=$(zfs get -H -o value usedbydataset rpool/log)
if [ ${used_percent%.*} -gt 80 ]; then
    echo "ATTENZIONE: Spazio log superiore all'80%" | mail -s "Alert Log ZimaBoard" $EMAIL
fi
