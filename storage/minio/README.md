# MinIO S3 Storage

Current S3-compatible storage for Restic backups on QNAP NAS.

## Access

| Service | IP              | Port |
| ------- | --------------- | ---- |
| S3 API  | 192.168.200.210 | 9000 |
| Console | 192.168.200.210 | 9001 |

## Migration

This service is being migrated to RustFS. See `../rustfs/` and `../../docs/migrations/minio-to-rustfs.md`.
(The earlier Garage plan was abandoned — `../garage/` is kept for reference only.)
