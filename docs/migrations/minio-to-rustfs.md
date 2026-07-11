# Migration Runbook: MinIO → RustFS (Restic Backups)

Replaces the deprecated [MinIO → Garage plan](./minio-to-garage.md). Garage work
is archived — this plan uses RustFS (Rust-based, Apache 2.0, MinIO drop-in) as
the S3 backend for `restic-nextcloud` and `restic-immich`.

## Decision Summary

| Axis             | MinIO (current) | RustFS (target)                      |
| ---------------- | --------------- | ------------------------------------ |
| Language         | Go              | Rust                                 |
| License          | AGPL v3         | Apache 2.0                           |
| S3 API           | Full            | Core (drop-in for restic/mc/rclone)  |
| Large-obj perf   | Baseline        | ~0.5× on 20 MB+ (community benches)  |
| Maturity         | Stable          | v1.0.0-alpha (single-node OK)        |
| Console          | Built-in        | Built-in (MinIO-compatible)          |

**Risks accepted:**

1. **Alpha stage** — distributed mode, lifecycle, KMS marked "Under Testing"
   upstream. We run single-node only, so distributed risk is N/A. Lifecycle not
   used (restic `forget --prune` handles retention).
2. **Large-object perf** — restic packs ~16 MB; benchmarks suggest ~2× slower
   than MinIO in that range. Nightly backup currently finishes well before the
   00:00 window so there is headroom.
3. **Silent corruption** — mitigated by keeping MinIO read-only for one full
   retention cycle (6 months), weekly `restic check --read-data-subset=10%`
   post-migration, and a full `restic check --read-data` before MinIO decom.

## Current State

```yaml
# storage/minio/docker-compose.yml
image: minio/minio
data: /share/Data/minio
ports: 9000 (S3), 9001 (console)
ips: 192.168.100.210 (Infra), 192.168.200.210 (Storage LAN)
buckets: restic-nextcloud, restic-immich
```

Consumers (both on Flatcar VM 100 — LXC 101/103 no longer exist):

- Nextcloud → `/srv/docker/nextcloud/.restic-env`
- Immich → `/srv/docker/immich/.restic-env`
- restic daily 00:00 via systemd timers, ~16 MB pack files

## Target State

```yaml
# storage/rustfs/docker-compose.yml
image: rustfs/rustfs:latest
data: /share/Data/rustfs/data
meta: /share/Data/rustfs/meta
ports: 9000 (S3), 9001 (console)
ips: 192.168.100.212 (Infra), 192.168.200.212 (Storage LAN)
buckets: restic-nextcloud, restic-immich
```

Both MinIO (`.210`) and RustFS (`.212`) run in parallel for 6 months. MinIO
becomes read-only immediately after cutover.

---

## Phase 1 — Pre-Migration Baseline

**Goal:** record known-good state before touching anything.

```bash
# On Flatcar VM 100 (ssh core@192.168.100.100; env files are root-owned)
sudo bash -c 'source /srv/docker/nextcloud/.restic-env && /opt/bin/restic check --read-data'
sudo bash -c 'source /srv/docker/nextcloud/.restic-env && /opt/bin/restic snapshots --json | jq length'

sudo bash -c 'source /srv/docker/immich/.restic-env && /opt/bin/restic check --read-data'
sudo bash -c 'source /srv/docker/immich/.restic-env && /opt/bin/restic snapshots --json | jq length'

# MinIO usage baseline
rclone size minio:restic-nextcloud
rclone size minio:restic-immich
```

Record: snapshot counts, total bytes, last-snapshot IDs. These are the cutover
acceptance criteria.

## Phase 2 — Deploy RustFS

```bash
ssh admin@192.168.100.254
sudo mkdir -p /share/Data/rustfs/data /share/Data/rustfs/meta
sudo chown 1000:1000 /share/Data/rustfs/data /share/Data/rustfs/meta
```

From workstation:

```bash
# Fill storage/rustfs/.env from .env.example first (plain gitignored .env)
scp storage/rustfs/docker-compose.yml storage/rustfs/.env \
    admin@192.168.100.254:/share/Container/rustfs/

ssh admin@192.168.100.254 'cd /share/Container/rustfs && docker compose up -d'
```

Health check:

```bash
curl -sS http://192.168.200.212:9000/ | head -1   # expect <?xml … InvalidRequest
docker logs rustfs --tail 50
```

## Phase 3 — Provision Buckets + Scoped Key

```bash
mc alias set rustfs http://192.168.200.212:9000 "$RUSTFS_ROOT_USER" "$RUSTFS_ROOT_PASSWORD"
mc mb rustfs/restic-nextcloud
mc mb rustfs/restic-immich

# Scoped service account for restic (never use root creds)
mc admin user svcacct add rustfs "$RUSTFS_ROOT_USER" --name restic
```

Store the returned access key + secret for the cutover: they go into the
node-side `/srv/docker/{nextcloud,immich}/.restic-env` files (root:root 0600)
in Phase 6. Never commit them.

## Phase 4 — Sync Existing Repos (MinIO → RustFS)

Use `scripts/migrations/minio-to-rustfs/migrate.sh`. rclone config template:

```ini
[minio]
type = s3
provider = Minio
access_key_id = <minio-user>
secret_access_key = <minio-pass>
endpoint = http://192.168.200.210:9000

[rustfs]
type = s3
provider = Minio
access_key_id = <rustfs-restic-key>
secret_access_key = <rustfs-restic-secret>
endpoint = http://192.168.200.212:9000
region = rustfs
```

Sync:

```bash
./scripts/migrations/minio-to-rustfs/migrate.sh sync
# Runs: rclone sync minio:restic-nextcloud rustfs:restic-nextcloud --checksum -P
#       rclone sync minio:restic-immich    rustfs:restic-immich    --checksum -P
./scripts/migrations/minio-to-rustfs/migrate.sh verify
# Compares rclone size both sides + SHA spot-check of 5 random objects per bucket
```

## Phase 5 — Parallel-Write Window (Dry Read)

**Do not cut over yet.** Test the new endpoint against a second copy of the env
file:

```bash
# On Flatcar VM 100 (sudo — files are root-owned)
sudo cp /srv/docker/nextcloud/.restic-env /srv/docker/nextcloud/.restic-env.rustfs
sudo sed -i 's|192.168.200.210|192.168.200.212|' /srv/docker/nextcloud/.restic-env.rustfs
# swap access keys to the rustfs restic key

sudo bash -c 'source /srv/docker/nextcloud/.restic-env.rustfs && /opt/bin/restic snapshots'
# must list the same IDs as MinIO; then restic check must pass
```

Cold-restore gate (non-optional):

```bash
restic restore latest --target /tmp/restore-test --include '<one-small-file>'
diff /tmp/restore-test/<file> /mnt/ncdata/<file>  # must be identical
```

Repeat both for Immich (`/srv/docker/immich/.restic-env`).

## Phase 6 — Cutover

1. Set MinIO buckets to read-only (prevents accidental writes post-cutover):

   ```bash
   mc anonymous set download minio/restic-nextcloud
   mc anonymous set download minio/restic-immich
   # or per-user: mc admin policy attach minio readonly --user <restic-user>
   ```

2. Replace both `/srv/docker/<app>/.restic-env` on VM 100 with the RustFS
   version. Timers pick it up on next run.

3. Run one manual backup per repo and confirm a new snapshot lands on RustFS
   (and **not** on MinIO — verify via `rclone size`).

4. Update `docs/backups.md` to reflect RustFS as the active endpoint.

## Phase 7 — Post-Cutover Monitoring

- Weekly: `restic check --read-data-subset=10%` via cron for the first month
- Monthly thereafter until 6-month rollback buffer expires
- Watch `docker stats rustfs` for memory creep (alpha stage — trust nothing)
- First full `restic check --read-data` at month 3 and month 6

## Phase 8 — Decommission MinIO (T+6 months)

Only after:

- [ ] 6 months of successful nightly backups on RustFS
- [ ] Full `restic check --read-data` passes on both repos
- [ ] One successful end-to-end restore drill from RustFS

Then:

```bash
# Stop MinIO
ssh admin@192.168.100.254 'cd /share/Container/minio && docker compose down'
# Archive data dir for 30 more days before delete
sudo mv /share/Data/minio /share/Data/minio.archived-$(date +%Y%m%d)
```

Update `CLAUDE.md` QNAP NAS row to drop MinIO and list RustFS as the sole S3
backend. Remove `storage/minio/` from the repo.

## Rollback (any time before Phase 8)

1. Revert both `/srv/docker/<app>/.restic-env` on VM 100 to `192.168.200.210` + MinIO keys.
2. Re-enable MinIO writes: `mc anonymous set none minio/restic-*`.
3. Run one backup to confirm new snapshots land on MinIO again.

No data migration needed — MinIO retained everything.

## File Changes Tracked by This Plan

- **Created**: `storage/rustfs/{docker-compose.yml,README.md,.env.example}`,
  `docs/migrations/minio-to-rustfs.md`,
  `scripts/migrations/minio-to-rustfs/migrate.sh`
- **Modified**: `apps/nextcloud/restic-env.example`,
  `apps/immich/restic-env.example`, `docs/backups.md`
- **Archived** (kept for reference, do not delete): `storage/garage/`,
  `docs/migrations/minio-to-garage.md`, `scripts/migrations/minio-to-garage/`
- **Not yet modified** (update after Phase 6 cutover only): `CLAUDE.md` QNAP
  row, `storage/minio/*` (decom in Phase 8)
