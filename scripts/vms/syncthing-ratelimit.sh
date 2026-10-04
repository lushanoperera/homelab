#!/bin/bash
# Hub rate limit while the nwlab -> homelab PBS push runs (04:00 Europe/Rome) on the same tunnel.
# Inside 03:30-05:30 Europe/Rome: maxSendKbps/maxRecvKbps = LIMIT_KIBPS. Outside: 0 (unlimited).
# Run by syncthing-ratelimit.timer at 03:30, 05:30 and after boot; it reads the clock, so order
# and missed runs do not matter.
set -eu
LIMIT_KIBPS=1000
CFG=/srv/docker/syncthing/config/config.xml
key=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$CFG")
now=$(TZ=Europe/Rome date +%H%M)
limit=0
if [ "$now" -ge 0330 ] && [ "$now" -lt 0530 ]; then limit=$LIMIT_KIBPS; fi
curl -fsS -m 10 -X PATCH -H "X-API-Key: $key" http://127.0.0.1:8384/rest/config/options \
  -d "{\"maxSendKbps\":$limit,\"maxRecvKbps\":$limit}"
echo "syncthing rate limit: $limit KiB/s (Europe/Rome $now)"
