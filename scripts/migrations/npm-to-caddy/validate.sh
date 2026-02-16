#!/usr/bin/env bash
# Validate all proxy hosts against Caddy
# Usage: validate.sh [port]  (default: 443)
set -euo pipefail

PORT="${1:-443}"
DOMAIN="home.disconnesso.com"
PASS=0
FAIL=0
TOTAL=0

declare -A SERVICES=(
    # Media stack (localhost)
    [seerr]=5055
    [prowlarr]=9696
    [qbittorrent]=8080
    [sabnzbd]=7777
    [radarr]=7878
    [sonarr]=8989
    [lidarr]=8686
    [bazarr]=6767
    [tautulli]=8181
    # Apps
    [nextcloud]=11000
    [homeassistant]=8123
    [immich]=2283
    [vaultwarden]=8200
    [portainer]=9443
    [wireguard]=10086
    # Infrastructure
    [proxmox]=8006
    [reginald]=8006
    [pbs]=8007
    [qnap]=8080
    [technitium]=5380
)

echo "=== Caddy Proxy Validation (port ${PORT}) ==="
echo ""

for service in $(echo "${!SERVICES[@]}" | tr ' ' '\n' | sort); do
    TOTAL=$((TOTAL + 1))
    url="https://${service}.${DOMAIN}:${PORT}"
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "${url}" 2>/dev/null || echo "000")

    if [[ "${http_code}" =~ ^(200|301|302|303|307|308|401|403)$ ]]; then
        printf "  PASS  %-20s %s (HTTP %s)\n" "${service}" "${url}" "${http_code}"
        PASS=$((PASS + 1))
    else
        printf "  FAIL  %-20s %s (HTTP %s)\n" "${service}" "${url}" "${http_code}"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results: ${PASS}/${TOTAL} PASS, ${FAIL}/${TOTAL} FAIL ==="

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi
