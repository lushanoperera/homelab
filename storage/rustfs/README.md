# RustFS — S3 Backend for Restic Backups

Single-node RustFS on QNAP Container Station. Drop-in MinIO replacement for the
`restic-nextcloud` and `restic-immich` repos.

## Why RustFS

- Rust memory safety (vs MinIO Go + history of CVEs)
- Apache 2.0, active upstream
- S3 API compatible — MinIO clients (`mc`, rclone, restic, AWS SDK) work unchanged
- Lower idle footprint than MinIO on NAS-class hardware

**Risks accepted** (see `docs/migrations/minio-to-rustfs.md`):

- v1.0.0-alpha: distributed mode / lifecycle / KMS upstream marked "Under Testing"
  — we run single-node only
- Community benchmarks show MinIO ~2× faster on >20 MB payloads. Restic packs
  are ~16 MB. Acceptable as long as nightly 00:00 backups finish before next day.

## Network

| Service | IP                                 | Port | Purpose         |
| ------- | ---------------------------------- | ---- | --------------- |
| MinIO   | `192.168.100.210` / `.200.210`     | 9000 | S3 API (legacy) |
| MinIO   | `192.168.100.210` / `.200.210`     | 9001 | Console (legacy) |
| RustFS  | `192.168.100.212` / `.200.212`     | 9000 | S3 API (new)    |
| RustFS  | `192.168.100.212` / `.200.212`     | 9001 | Console (new)   |

MinIO stays running in parallel for one full restic retention cycle (6 months)
before decommissioning.

## Deploy

On QNAP:

```bash
# Create data + meta dirs
sudo mkdir -p /share/Data/rustfs/data /share/Data/rustfs/meta

# Copy compose + env (fill .env from .env.example first; plain gitignored .env)
scp storage/rustfs/docker-compose.yml admin@qnap:/share/Container/rustfs/
scp storage/rustfs/.env               admin@qnap:/share/Container/rustfs/

cd /share/Container/rustfs
docker compose up -d
```

Verify:

```bash
docker ps --filter name=rustfs
curl -sS http://192.168.200.212:9000/ | head  # expect S3 XML error, not conn refused
```

## Provision Buckets + Access Key

RustFS ships a MinIO-compatible admin API, so `mc` works:

```bash
mc alias set rustfs http://192.168.200.212:9000 "$RUSTFS_ROOT_USER" "$RUSTFS_ROOT_PASSWORD"

mc mb rustfs/restic-nextcloud
mc mb rustfs/restic-immich

# Issue scoped access key for restic (not the root creds)
mc admin user svcacct add rustfs "$RUSTFS_ROOT_USER" --name restic
```

Store the resulting `Access Key` / `Secret Key` in the node-side
`/srv/docker/<app>/.restic-env` files (root:root 0600) at cutover time.

## Smoke Test with `mc`

```bash
mc ls rustfs/
echo "hello" | mc pipe rustfs/restic-nextcloud/_smoke
mc cat rustfs/restic-nextcloud/_smoke
mc rm  rustfs/restic-nextcloud/_smoke
```

## Secrets

Plain gitignored `.env` next to the compose file (repo policy — migrated off
varlock/rbw 2026-05-20). Copy `.env.example` → `.env` and fill in:

| Var                    | Purpose                        |
| ---------------------- | ------------------------------ |
| `RUSTFS_ROOT_USER`     | Root admin user                |
| `RUSTFS_ROOT_PASSWORD` | Root admin password            |
| `RUSTFS_REGION`        | S3 region label (e.g. rustfs)  |

## Migration Runbook

See `docs/migrations/minio-to-rustfs.md` for the full phased runbook. Helper
script: `scripts/migrations/minio-to-rustfs/migrate.sh`.

## Rollback

MinIO stays running (writes disabled, reads allowed) for 6 months post-cutover.
To roll back: flip `/srv/docker/{nextcloud,immich}/.restic-env` on Flatcar VM 100
back to `192.168.200.210`. No data loss — MinIO still holds the original snapshots.
