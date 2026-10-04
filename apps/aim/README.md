# aim — central knowledge-graph MCP server (Flatcar VM 100)

One aim server (knowledge-graph MCP over streamable HTTP) behind Caddy. Caddy checks a bearer
token, caps request bodies at 4 MB and strips the token before the upstream. The aim container
sits on an internal network with no published port.

| Item | Value |
| ---- | ----- |
| URL | `http://192.168.100.100:18282/mcp` (also `/sse`) |
| Stack dir | `/srv/docker/aim-stack/` (`compose.yaml`, `Caddyfile`, `.env`) |
| Data | `/srv/docker/aim/store` (persistent `memory*.jsonl`, git history) and `/srv/docker/aim/run` (locks, `MAINTENANCE`, `tmp/`) |
| Owner | `core` (500:500); the container runs as `user: "500:500"` |
| Image | `aim-server:<commit>`, built on the VM from `mcp/knowledge-graph/` of the private `lushanoperera/ai-harness` repo; source tree at `/srv/docker/aim-src/` |
| Firewall | `scripts/vms/aim-fw.sh` + `systemd/aim-fw.service` |
| History | `systemd/aim-history.{service,timer}` (hourly) |
| Alert | `scripts/hosts/winston/aim-history-watch.sh` → nwlab ntfy topic `homelab-alerts` |

The stack dir is separate from the data dir on purpose: `/srv/docker/aim` mounts into the
container as `/data`, so a `.env` there would expose the token to the server.

## Deploy

```bash
# Source + image (on the macbook, from the ai-harness checkout)
git -C ~/Developer/ai-harness archive <commit> mcp/knowledge-graph \
  | ssh core@192.168.100.100 'mkdir -p /srv/docker/aim-src && tar -x -C /srv/docker/aim-src'
ssh core@192.168.100.100 'docker build -t aim-server:<commit> /srv/docker/aim-src/mcp/knowledge-graph'

# Data dirs (one filesystem, no symlinks) and token
ssh core@192.168.100.100 'sudo mkdir -p /srv/docker/aim/store /srv/docker/aim/run/tmp /srv/docker/aim-stack \
  && sudo chown -R core:core /srv/docker/aim /srv/docker/aim-stack'
ssh core@192.168.100.100 'umask 077; printf "AIM_TOKEN=%s\n" "$(openssl rand -hex 32)" > /srv/docker/aim-stack/.env'

rsync -az apps/aim/compose.yaml apps/aim/Caddyfile core@192.168.100.100:/srv/docker/aim-stack/
ssh core@192.168.100.100 'cd /srv/docker/aim-stack && /opt/bin/docker-compose up -d'
```

History repo (once): `git init -b main` in `store/` as core, `.gitignore` = `*`, `!.gitignore`,
`!memory*.jsonl`. Then install `systemd/aim-history.{service,timer}` and enable the timer. The
timer runs `aim-history.sh` from the source tree; never replace it with a hand-written commit.

## Clients

Each client reads the token from `~/.config/nwdesigns/aim.env` (mode 600, one line
`AIM_TOKEN=<token>`). Only the WireGuard path (source 192.168.100.104) and the macbook
(192.168.2.245, UCG fixed IP) reach port 18282. See `scripts/vms/aim-fw.sh`.

## Token rotation

1. Write a new `AIM_TOKEN=$(openssl rand -hex 32)` into `/srv/docker/aim-stack/.env` (mode 600).
2. `cd /srv/docker/aim-stack && /opt/bin/docker-compose up -d caddy`.
3. Copy the new line to `~/.config/nwdesigns/aim.env` on every client. Sessions pick it up at reconnect.

## Maintenance barrier

Writers other than the server (migration, repair) run only through `aim-maint.sh` from the
source tree: `docker stop aim-aim-1`, `touch /srv/docker/aim/run/MAINTENANCE`, then
`AIM_ROOT=/srv/docker/aim /srv/docker/aim-src/mcp/knowledge-graph/aim-maint.sh <cmd>`. While the
marker exists, the server refuses to start (exit 75, restart loop) and the history job skips.
Remove the marker, run `aim-history.service` once, then start the container.

## Restore

The daily vzdump of VM 100 (winston, 05:00, `pbs-backupnas`) covers `store/` with its `.git`. It
also captures `run/`, because a block-level image cannot exclude a directory.

**After a whole-VM restore, delete `/srv/docker/aim/run/MAINTENANCE` if it came back**, or the
aim container refuses to start.

Single-file restore from PBS (on winston; the PVE API download cannot stream binary files):

```bash
export PBS_REPOSITORY="root@pam@192.168.200.187:pbs-backups"
export PBS_PASSWORD="$(cat /etc/pve/priv/storage/pbs-backupnas.pw)"
export PBS_FINGERPRINT="$(awk '/^pbs: pbs-backupnas/{f=1;next} /^[a-z]+: /{f=0} f && $1=="fingerprint"{print $2}' /etc/pve/storage.cfg)"
proxmox-file-restore extract "vm/100/<snapshot>" \
  /drive-scsi0.img.fidx/part/9/srv/docker/aim/store/<file> /root/restore/
```

Older versions of one store: `git -C /srv/docker/aim/store log -- <file>`, then
`git --work-tree=<scratch> checkout <commit> -- <file>`.

## Expected noise

One `starlette.requests.ClientDisconnect` traceback in the aim log per 413 (body over 4 MB).
