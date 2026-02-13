#!/bin/sh
set -e

# Read Docker secrets into environment variables
if [ -f /run/secrets/cloudflare_api_token ]; then
    export CF_API_TOKEN=$(cat /run/secrets/cloudflare_api_token)
fi

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile "$@"
