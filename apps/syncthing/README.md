# Syncthing hub (Flatcar VM 100)

Hub for the Obsidian vault and the aim store. Clients always dial the hub; the hub never dials.

| Item | Value |
| ---- | ----- |
| Version | `syncthing/syncthing:2.1.5`, pinned by digest in `compose.yaml` |
| Stack dir | `/srv/docker/syncthing/` (`compose.yaml`, `config/`, `brain/`, `gui.env`) |
| Device ID | `VWPSBM5-POWFNSK-KQ4DAZC-KJQU52X-JREKNLT-MP24UST-5RBPHC3-6XB6WA2` |
| Clients dial | `tcp://192.168.100.100:22000`, `quic://192.168.100.100:22000` |
| GUI | `127.0.0.1:8384` on the VM only: `ssh -L 8384:127.0.0.1:8384 core@192.168.100.100` |
| GUI login | user `admin`, password in `/srv/docker/syncthing/gui.env` (mode 600; template `gui.env.example`) |
| Runs as | uid/gid 500 (`core`), `PUID`/`PGID` |

Container paths equal host paths (`/srv/docker/syncthing` and `/srv/docker/aim/store` mount at
the same path), so folder paths in the GUI are the host paths.

## Options

Set once through the REST API (`PATCH /rest/config/options`, API key in `config/config.xml`):
listen `tcp://0.0.0.0:22000` + `quic://0.0.0.0:22000`; relays, global discovery, local discovery,
NAT traversal, LAN-address announce, usage reporting, crash reporting and auto-upgrade all off.
With discovery off, the hub has no address for a client, so it never dials. Add client devices
with the address `dynamic`.

## Folders

| ID | Type | Path | Notes |
| -- | ---- | ---- | ----- |
| `brain` | send-receive | `/srv/docker/syncthing/brain` | staggered versioning, `maxAge` 7776000 s (90 days) |
| `aim` | send-only | `/srv/docker/aim/store` | mounted read-only; `.stignore` = `!memory*.jsonl` then `*` |

The `aim` folder is read-only in the container, so the hub cannot change the canonical aim
store. Syncthing reads the files as uid 500, their owner. `.stfolder` and `.stignore` were created
by `core` before the first start.

## Firewall and rate limit

- Port 22000 tcp+udp: same source allow-list as the aim KG (`scripts/vms/aim-fw.sh`).
- `scripts/vms/syncthing-ratelimit.sh` + `systemd/syncthing-ratelimit.{service,timer}`: inside
  03:30–05:30 Europe/Rome it sets `maxSendKbps`/`maxRecvKbps` to 1000 KiB/s, outside it sets 0.
  The window covers the nwlab → homelab PBS push at 04:00 on the same tunnel. The script reads
  the clock, so missed runs and run order do not matter.

## Deploy

```bash
ssh core@192.168.100.100 'sudo mkdir -p /srv/docker/syncthing/config /srv/docker/syncthing/brain \
  && sudo chown -R core:core /srv/docker/syncthing'
ssh core@192.168.100.100 'mkdir -p /srv/docker/aim/store/.stfolder \
  && printf "!memory*.jsonl\n*\n" > /srv/docker/aim/store/.stignore'
rsync -az apps/syncthing/compose.yaml core@192.168.100.100:/srv/docker/syncthing/
ssh core@192.168.100.100 'cd /srv/docker/syncthing && /opt/bin/docker-compose up -d'
```

Then apply the options, the GUI password and the folders through the REST API, and restart the
container once so the listeners pick up the options.

## Backup

The daily vzdump of VM 100 covers `/srv/docker/syncthing` (config, keys and `brain/`).
