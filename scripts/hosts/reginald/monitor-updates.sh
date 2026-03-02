#!/bin/bash
LOG_FILE="/var/log/update-monitor.log"

# Verifica stato unattended-upgrades
systemctl status unattended-upgrades | tee -a $LOG_FILE

# Verifica ultimi aggiornamenti
echo "=== Ultimi Aggiornamenti ===" >> $LOG_FILE
grep "starting unattended upgrades" /var/log/unattended-upgrades/unattended-upgrades.log | tail -n 5 >> $LOG_FILE

# Verifica errori
echo "=== Errori Recenti ===" >> $LOG_FILE
grep -i error /var/log/unattended-upgrades/unattended-upgrades.log | tail -n 10 >> $LOG_FILE

# Verifica spazio disco
echo "=== Spazio Disco ===" >> $LOG_FILE
df -h /var/cache/apt/archives >> $LOG_FILE

# Verifica repository
echo "=== Stato Repository ===" >> $LOG_FILE
apt-get update 2>&1 | grep -E '^(Hit|Ign|Get)' >> $LOG_FILE

# Verifica pacchetti hold
echo "=== Pacchetti in Hold ===" >> $LOG_FILE
apt-mark showhold >> $LOG_FILE
