#!/bin/bash

# Script chiamato da upsmon per lo spegnimento finale
LOG_FILE="/var/log/ups-events.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sistema in spegnimento per comando UPS" >> "$LOG_FILE"

# Spegnimento del sistema
/sbin/shutdown -h now
