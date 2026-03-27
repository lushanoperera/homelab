---
paths:
  - "vms/flatcar-media/**"
  - "apps/**"
  - "scripts/vms/**"
  - "homepage/**"
  - "networking/caddy/**"
  - "networking/traefik/**"
recall:
  - ssh
  - flatcar
  - container
  - docker
  - forgejo
  - couchdb
  - immich
  - nextcloud
  - caddy
  - traefik
  - crowdsec
  - proxmox
  - ignition
  - butane
  - migration
  - garage
---

# Operations Quick Reference

## SSH Access

```bash
ssh root@192.168.100.38   # winston
ssh root@192.168.100.4    # reginald
ssh core@192.168.100.100  # flatcar VM 100
ssh root@192.168.100.187  # PBS on QNAP
```

## Flatcar VM Operations

```bash
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}"'
ssh core@192.168.100.100 'cd /srv/docker/media-stack && /opt/bin/docker-compose ps'
ssh core@192.168.100.100 'cd /srv/docker/traefik && /opt/bin/docker-compose ps'

# VPN
ssh core@192.168.100.100 'docker exec gluetun wget -qO- https://ipinfo.io/ip'
ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port'
ssh core@192.168.100.100 '/opt/bin/qbt-port-sync.sh'

# NFS
ssh core@192.168.100.100 'systemctl status mnt-media.mount'

# Media audit
ssh core@192.168.100.100 '/opt/bin/media-audit.sh'
ssh core@192.168.100.100 '/opt/bin/media-cleanup.sh --dry-run'
```

## App Operations

**Forgejo**: Web `https://forgejo.home.disconnesso.com`, SSH `forgejo:` alias, admin `lushano`, SQLite, registration disabled.

**CouchDB**: `curl -s http://localhost:5984/_up` | `curl -s http://localhost:5984/obsidian-livesync | jq .doc_count`

**Immich**: `/srv/docker/immich/`, photos `/mnt/immich/upload` (NFS), GPU VF 0 (`/dev/dri/renderD129`).

**Nextcloud**: `/srv/docker/nextcloud/`, data `/mnt/ncdata` (NFS), `php occ` via `docker exec -u www-data nextcloud-app`.

## Reverse Proxy

**Caddy** (internal): `docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile` | `caddy reload`

**Traefik** (public DMZ): `docker exec crowdsec cscli decisions list` | `cscli decisions add --ip X --duration 24h`

## Proxmox

`pveversion` | `qm list` | `pct list` | `pvesm status`

## Ignition Workflow

```bash
docker run --rm -i quay.io/coreos/butane:latest --strict < vms/flatcar-media/butane/config.bu > vms/flatcar-media/ignition/config.ign
```

## VM Deployment

```bash
./scripts/vms/deploy-flatcar-vm.sh --vm-id 105 --vm-ip 10.21.21.105
```
