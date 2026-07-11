# Technitium Config Backup (Restic) — DORMANT

> **⚠ DORMANT (verified live 2026-07-11):** this backup was designed against Garage
> (`192.168.200.211:3900`), which was **never deployed** (plan abandoned — see
> `scripts/migrations/minio-to-garage/DEPRECATED.md`). No `technitium-backup.timer`
> is active on any node. The env template (`apps/technitium/restic-env.example`)
> has been retargeted to the live MinIO backend (`192.168.200.210:9000`); create the
> `technitium-config` bucket there before activating. The Garage commands below are
> kept for historical reference only.

Per-node restic backup of the Technitium config directory to the S3 bucket
`technitium-config`. Retention keeps daily 7 / weekly 4 / monthly 6.

## Paths per node

| Node                      | Config dir                       | Schedule mechanism                |
| ------------------------- | -------------------------------- | --------------------------------- |
| QNAP (primary)            | `/share/Data/technitium/config`  | Container Station scheduled task  |
| Flatcar VM 100 (secondary)| `/srv/docker/dns/config`         | systemd timer (`technitium-backup.timer`) |
| Reginald LXC 120 (secondary) | `/etc/dns`                    | systemd timer (`technitium-backup.timer`) |

Verify the Reginald path before first run — the Debian installer places config
in `/etc/dns` by default, but a non-default install may differ.

## Garage bucket bootstrap

On QNAP, before any node runs the script:

```bash
docker exec garage /garage bucket create technitium-config
docker exec garage /garage key new --name technitium
docker exec garage /garage bucket allow --read --write --owner \
    technitium-config --key technitium
```

Copy the access key + secret into each node's `/etc/restic/technitium.env`
(template at `apps/technitium/restic-env.example`).

## Flatcar / Reginald deploy

```bash
# As root on the target host
install -m 0755 scripts/backup/technitium-config-backup.sh /opt/bin/
install -d -m 0700 /etc/restic
install -m 0600 apps/technitium/restic-env.example /etc/restic/technitium.env
# Edit /etc/restic/technitium.env — set access key, secret, password,
# TECHNITIUM_CONFIG_DIR, TECHNITIUM_NODE
install -m 0644 systemd/technitium-backup.service /etc/systemd/system/
install -m 0644 systemd/technitium-backup.timer  /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now technitium-backup.timer
```

On Flatcar, restic isn't shipped; install via the same sysext pattern used for
other tools or run from a one-shot container:

```bash
# Container fallback (no system restic install required)
sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/docker run --rm \
    --env-file /etc/restic/technitium.env \
    -v /srv/docker/dns/config:/srv/docker/dns/config:ro \
    restic/restic:latest backup --host technitium-flatcar --tag technitium /srv/docker/dns/config|' \
    /etc/systemd/system/technitium-backup.service
```

Prefer a wrapper script if the container path is used regularly — the inline
form is illustrative only.

## QNAP scheduled task

Container Station → Schedule → New Task:

- Image: `restic/restic:latest`
- Command: `backup --host technitium-qnap --tag technitium /share/Data/technitium/config`
- Volumes: `/share/Data/technitium/config:/share/Data/technitium/config:ro`
- Env file: `/share/Data/technitium/restic.env`
- Schedule: daily 03:30

Pair with a second task that runs `forget --keep-daily 7 --keep-weekly 4
--keep-monthly 6 --prune --host technitium-qnap --tag technitium`.

## Verify

```bash
# From any node with the env file:
restic snapshots --tag technitium
restic snapshots --tag technitium --host technitium-flatcar --json | jq length

# Restore test (do not overwrite live config):
restic restore latest --target /tmp/dns-restore --host technitium-flatcar
diff -r /tmp/dns-restore/srv/docker/dns/config /srv/docker/dns/config
```

Expect ≥1 snapshot per node within 24h of first timer fire.
