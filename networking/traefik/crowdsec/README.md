# CrowdSec Security

CrowdSec intrusion detection and prevention for Traefik.

## Components

| Container | Port | Purpose |
|-----------|------|---------|
| crowdsec | 8080 | Main CrowdSec engine |
| crowdsec-bouncer | 8082 | Traefik ForwardAuth |
| crowdsec-metabase | 3001 | Dashboard |

## Common Operations

```bash
# Check decisions (bans)
docker exec crowdsec cscli decisions list

# Check metrics
docker exec crowdsec cscli metrics

# Manual ban
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 24h --reason "manual"

# Unban
docker exec crowdsec cscli decisions delete --ip 1.2.3.4

# Check bouncer status
docker exec crowdsec cscli bouncers list
```

## Regenerate Bouncer API Key

```bash
docker exec crowdsec cscli bouncers delete crowdsec-bouncer-traefik
docker exec crowdsec cscli bouncers add crowdsec-bouncer-traefik
# Update .env with new key, then restart bouncer
```

## Configuration

- `acquis.yaml` - Log acquisition configuration
- `config/` - CrowdSec configuration files

## Collections

- `crowdsecurity/traefik` - Traefik log parsing
- `crowdsecurity/http-cve` - HTTP CVE detection
- `crowdsecurity/sshd` - SSH brute force detection
