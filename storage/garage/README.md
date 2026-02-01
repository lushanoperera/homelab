# MinIO to Garage Migration

Migrate S3 storage on QNAP NAS from MinIO to Garage for Restic backups.

## Why Garage?

| Metric          | MinIO   | Garage          |
| --------------- | ------- | --------------- |
| RAM (idle)      | ~218 MB | ~5 MB           |
| RAM (active)    | 4-32 GB | 1-2 GB          |
| Complexity      | Medium  | Low             |
| NAS suitability | Heavy   | Designed for it |

## Files Overview

```
minio-to-garage/
├── MIGRATION-PLAN.md         # Full evaluation and detailed guide
├── garage.toml               # Garage configuration
├── garage-docker-compose.yml # Docker deployment
├── restic-env.sh             # Environment variables for Restic
├── rclone.conf.template      # Rclone config for migration
├── migrate.sh                # Step-by-step migration helper
└── qnap-minio_docker-compose.yml # Original MinIO config
```

## Quick Start on QNAP

### 1. Copy files to NAS

Copy all files to your QNAP NAS.

### 2. Edit configuration

Edit `migrate.sh` and set `MINIO_BUCKET` to your current bucket name:

```bash
MINIO_BUCKET="your-restic-bucket"  # UPDATE THIS
```

### 3. Run migration steps

```bash
chmod +x migrate.sh

# Step 1: Create Garage directories
./migrate.sh 1

# Step 2: Start Garage container
./migrate.sh 2

# Step 3: Configure node, create bucket and key
./migrate.sh 3
# IMPORTANT: Save the Key ID and Secret Key output!

# Step 4: Configure rclone
# Edit rclone.conf.template with your credentials
# Copy to ~/.config/rclone/rclone.conf

# Step 5: Verify source data
./migrate.sh 4

# Step 6: Migrate data
./migrate.sh 5

# Step 7: Verify with Restic
./migrate.sh 6
```

### 4. Update backup scripts

After verification, update your backup scripts to use:

```bash
source restic-env.sh
restic backup /path/to/data
```

### 5. Decommission MinIO

Once confident, stop MinIO:

```bash
docker-compose -f qnap-minio_docker-compose.yml down
```

## Network Configuration

| Service | IP              | Port | Purpose            |
| ------- | --------------- | ---- | ------------------ |
| MinIO   | 192.168.100.210 | 9000 | S3 API (existing)  |
| MinIO   | 192.168.100.210 | 9001 | Console (existing) |
| Garage  | 192.168.100.211 | 3900 | S3 API (new)       |
| Garage  | 192.168.100.211 | 3902 | Web hosting        |
| Garage  | 192.168.100.211 | 3903 | Admin API          |

## Important Notes

### AWS SDK Compatibility

Recent AWS SDKs require these environment variables (already in `restic-env.sh`):

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```

### Restic Password

Use the same `RESTIC_PASSWORD` you used with MinIO - your backup encryption is unchanged.

### Data Safety

- Keep MinIO running until migration is verified
- Run `restic check` after migration
- Verify all snapshots appear with `restic snapshots`

## Verification Checklist

- [ ] `docker exec garage /garage status` shows healthy node
- [ ] `docker exec garage /garage bucket list` shows `restic-backups`
- [ ] `rclone size garage:restic-backups` matches source
- [ ] `restic check` passes
- [ ] `restic snapshots` shows all historical backups
- [ ] `restic backup /test` creates new backup
- [ ] `docker stats garage` shows low RAM (~5 MB idle)

## Resources

- [Garage Documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [Garage Backup Guide](https://garagehq.deuxfleurs.fr/documentation/connect/backup/)
- [Restic S3 Backend](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)
