#!/bin/bash
# setup-reverse-zone.sh — create 100.168.192.in-addr.arpa primary zone on
# Technitium QNAP primary, enable auto-PTR cluster-wide, seed static PTRs.
# Idempotent: re-running is safe (creates skipped if exist, adds dedup'd).
#
# Env:
#   TECHNITIUM_HOST           default: https://192.168.100.254:5380
#   TECHNITIUM_ADMIN_USER     default: admin
#   TECHNITIUM_ADMIN_PASSWORD required (same var used by docker-compose .env)
#
# Usage: TECHNITIUM_ADMIN_PASSWORD=... ./scripts/dns/setup-reverse-zone.sh

set -euo pipefail

HOST="${TECHNITIUM_HOST:-https://192.168.100.254:5380}"
USER="${TECHNITIUM_ADMIN_USER:-admin}"
PASS="${TECHNITIUM_ADMIN_PASSWORD:?TECHNITIUM_ADMIN_PASSWORD required}"
DOMAIN_SUFFIX="${TECHNITIUM_DOMAIN_SUFFIX:-home.disconnesso.com}"
ZONE="100.168.192.in-addr.arpa"
CURL=(curl -sSk --max-time 15)

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [setup-reverse-zone] $1"; }

# --- login → token ----------------------------------------------------------
log "Logging into Technitium at $HOST"
TOKEN=$("${CURL[@]}" -G "$HOST/api/user/login" \
    --data-urlencode "user=$USER" \
    --data-urlencode "pass=$PASS" \
    --data-urlencode "includeInfo=false" \
  | grep -oE '"token":"[^"]+"' | head -1 | cut -d'"' -f4)
[[ -n $TOKEN ]] || { log "ERROR: failed to obtain token"; exit 1; }

api() {
    local path="$1"; shift
    "${CURL[@]}" -G "$HOST$path" --data-urlencode "token=$TOKEN" "$@"
}

# --- create zone (idempotent) -----------------------------------------------
log "Ensuring zone $ZONE exists (type=Primary)"
api /api/zones/create \
    --data-urlencode "zone=$ZONE" \
    --data-urlencode "type=Primary" \
  | grep -qE '"status":"ok"|already exists' \
  || { log "WARN: zone create response unexpected (continuing — may already exist)"; }

# --- enable auto-PTR globally -----------------------------------------------
# DnsSettings.useReverseZoneForCatalogAndPrimary controls automatic PTR
# creation for primary zones. Key name varies by Technitium version — try the
# documented one; fall back is a no-op (admin can toggle in UI).
log "Enabling auto-create-PTR setting (best-effort; manual toggle in UI if no-op)"
api /api/settings/set \
    --data-urlencode "useReverseZoneForUpdatingPtrAndNs=true" \
  | grep -q '"status":"ok"' \
  || log "WARN: auto-PTR setting endpoint returned non-ok (toggle in UI: Settings → General)"

# --- seed static PTRs --------------------------------------------------------
declare -A HOSTS=(
    [4]=reginald
    [38]=winston
    [100]=flatcar
    [106]=pdm
    [187]=pbs
    [254]=qnap
)

for octet in "${!HOSTS[@]}"; do
    fqdn="${HOSTS[$octet]}.${DOMAIN_SUFFIX}."
    ptr_domain="${octet}.${ZONE}"
    log "PTR $ptr_domain → $fqdn"
    api /api/zones/records/add \
        --data-urlencode "domain=$ptr_domain" \
        --data-urlencode "zone=$ZONE" \
        --data-urlencode "type=PTR" \
        --data-urlencode "ttl=3600" \
        --data-urlencode "ptrName=$fqdn" \
        --data-urlencode "overwrite=true" \
      | grep -qE '"status":"ok"' \
      || log "WARN: failed PTR for $ptr_domain (continuing)"
done

log "Done. Verify: dig @192.168.100.254 -x 192.168.100.38 +short → winston.${DOMAIN_SUFFIX}."
