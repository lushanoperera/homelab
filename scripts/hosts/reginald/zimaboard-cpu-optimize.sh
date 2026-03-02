#!/bin/bash

# Imposta il governor schedutil per tutti i core (o ondemand se schedutil non è disponibile)
echo "Impostazione governor ottimale per tutti i core..."
GOVERNORS=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)

if echo "$GOVERNORS" | grep -q "schedutil"; then
  TARGET_GOVERNOR="schedutil"
elif echo "$GOVERNORS" | grep -q "ondemand"; then
  TARGET_GOVERNOR="ondemand"
else
  TARGET_GOVERNOR="performance"
fi

echo "Utilizzo governor: $TARGET_GOVERNOR"

for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo "$TARGET_GOVERNOR" > $cpu
done

# Verifica l'impostazione
echo "Verifica configurazione governor:"
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Imposta la frequenza minima e massima
echo "Impostazione limiti di frequenza..."
# Ricava le frequenze minime e massime disponibili
MIN_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null || echo "800000")
MAX_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo "2200000")

for min in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do
  echo "$MIN_FREQ" > $min
done

for max in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
  echo "$MAX_FREQ" > $max
done

echo "Ottimizzazione CPU completata."
