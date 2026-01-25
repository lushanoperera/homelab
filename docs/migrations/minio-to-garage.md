# Migration Evaluation: MinIO to Garage for Restic Backups

## Executive Summary

**Recommendation: Migrate to Garage**

For your use case (Restic backups on QNAP NAS), Garage is the better choice due to:
- **40x lower memory usage** (~5 MB idle vs ~218 MB for MinIO)
- **Official Restic support** documented at [Garage HQ](https://garagehq.deuxfleurs.fr/documentation/connect/backup/)
- **Simpler operation** - single binary, minimal dependencies
- **Designed for NAS/constrained hardware** - runs on Raspberry Pi to Synology NAS

---

## Current Setup Analysis

```yaml
# Your MinIO Configuration
- Image: minio/minio
- Data: /share/Data/minio
- Ports: 9000 (S3 API), 9001 (Console)
- Networks: 192.168.100.210, 192.168.200.210
- Purpose: Restic backup storage
```

---

## Comparison Matrix

| Aspect | MinIO | Garage | Winner |
|--------|-------|--------|--------|
| **RAM (idle)** | ~218 MB | ~5 MB | Garage |
| **RAM (active)** | 4-32 GB | 1-2 GB | Garage |
| **Throughput** | 2.8 GB/s | 1.6 GB/s | MinIO |
| **S3 Compatibility** | Full | Core operations | MinIO |
| **Restic Support** | Yes | Official docs | Tie |
| **Setup Complexity** | Medium | Low | Garage |
| **Web Console** | Built-in | Separate | MinIO |
| **Small File Handling** | Poor | Better | Garage |
| **Erasure Coding** | Yes | No (replication) | MinIO |
| **Object Versioning** | Yes | No | MinIO |

---

## S3 Compatibility for Restic

Garage implements all S3 operations Restic needs:

| Operation | Status |
|-----------|--------|
| GetObject / PutObject | Supported |
| DeleteObject / DeleteObjects | Supported |
| ListObjects / ListObjectsV2 | Supported |
| Multipart uploads | Supported |
| Signature v4 | Supported |
| Path-style URLs | Supported |
| Presigned URLs | Supported |

**Not supported but not needed for Restic:**
- ACLs/IAM policies
- Object versioning
- Object tagging
- Object locking

---

## Migration Plan

### Phase 1: Deploy Garage

**1. Create garage.toml configuration:**
```toml
metadata_dir = "/share/Data/garage/meta"
data_dir = "/share/Data/garage/data"
db_engine = "lmdb"

replication_factor = 1  # Single-node setup

[s3_api]
api_bind_addr = "[::]:3900"
s3_region = "garage"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"

[admin]
api_bind_addr = "[::]:3903"
```

**2. Docker Compose for Garage:**
```yaml
services:
  garage:
    image: dxflrs/garage:v1.0.1
    container_name: garage
    restart: always
    volumes:
      - /share/Data/garage/meta:/var/lib/garage/meta
      - /share/Data/garage/data:/var/lib/garage/data
      - ./garage.toml:/etc/garage.toml:ro
    ports:
      - "3900:3900"  # S3 API
      - "3902:3902"  # Web
      - "3903:3903"  # Admin
    networks:
      qnet-static-eth0-076754:
        ipv4_address: 192.168.100.211
      qnet-static-eth1-400be2:
        ipv4_address: 192.168.200.211

networks:
  qnet-static-eth0-076754:
    external: true
  qnet-static-eth1-400be2:
    external: true
```

### Phase 2: Configure Garage

```bash
# Get node ID
docker exec garage /garage status

# Configure layout (replace NODE_ID)
docker exec garage /garage layout assign -z dc1 -c 1T <NODE_ID>
docker exec garage /garage layout apply --version 1

# Create access key
docker exec garage /garage key create restic-key

# Create bucket
docker exec garage /garage bucket create restic-backups

# Grant permissions
docker exec garage /garage bucket allow restic-backups \
  --read --write --key restic-key
```

### Phase 3: Migrate Existing Restic Data

**Step 1: Configure rclone for both endpoints**

Create/edit `~/.config/rclone/rclone.conf`:
```ini
[minio]
type = s3
provider = Minio
access_key_id = admin
secret_access_key = <your-minio-password>
endpoint = http://192.168.100.210:9000

[garage]
type = s3
provider = Other
access_key_id = <garage-key-id>
secret_access_key = <garage-secret>
endpoint = http://192.168.100.211:3900
region = garage
```

**Step 2: Verify source data**
```bash
# List existing MinIO buckets
rclone lsd minio:

# Check size of data to migrate
rclone size minio:<your-restic-bucket>
```

**Step 3: Sync data to Garage**
```bash
# Dry run first
rclone sync minio:<your-restic-bucket> garage:restic-backups --dry-run -P

# Actual migration (with progress)
rclone sync minio:<your-restic-bucket> garage:restic-backups -P --transfers 4
```

**Step 4: Verify migration**
```bash
# Set environment for Garage
export AWS_ACCESS_KEY_ID=<garage-key-id>
export AWS_SECRET_ACCESS_KEY=<garage-secret>
export AWS_DEFAULT_REGION=garage
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
export RESTIC_REPOSITORY="s3:http://192.168.100.211:3900/restic-backups"
export RESTIC_PASSWORD="<your-existing-password>"

# Verify repository integrity
restic check

# List snapshots (should show your existing backups)
restic snapshots
```

### Phase 4: Verify & Cutover

1. Test Restic operations:
   ```bash
   restic snapshots
   restic check
   restic backup /test/path
   ```

2. Run parallel for 1-2 weeks

3. Update backup scripts to point to Garage

4. Decommission MinIO

---

## Important Configuration Notes

### AWS SDK Checksum Fix
Recent AWS SDKs require these environment variables:
```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```

### Region Setting
Ensure your AWS region matches garage.toml:
```bash
export AWS_DEFAULT_REGION=garage
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Data loss during migration | High | Keep MinIO running until verified |
| Performance difference | Low | Backups are not throughput-critical |
| AWS SDK compatibility | Medium | Use env vars documented above |
| No erasure coding | Low | Single-node anyway; use filesystem redundancy |

---

## Files to Create

1. `storage/garage/garage.toml`
2. `storage/garage/docker-compose.yml`
3. `storage/garage/restic-env.sh` (environment variables)

---

## Verification Steps

1. `docker exec garage /garage status` - Node healthy
2. `docker exec garage /garage bucket list` - Bucket exists
3. `rclone size garage:restic-backups` - Data size matches source
4. `restic check` - Repository integrity verified
5. `restic snapshots` - All historical snapshots visible
6. `restic backup /small/test` - New backup succeeds
7. `restic restore latest --target /tmp/restore` - Restore works
8. `docker stats garage` - Verify low RAM usage (~5 MB idle)

---

## Sources

- [Garage Quick Start](https://garagehq.deuxfleurs.fr/documentation/quick-start/)
- [Garage S3 Compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- [Garage Backup Documentation](https://garagehq.deuxfleurs.fr/documentation/connect/backup/)
- [Hello Garage, Goodbye MinIO](https://karnwong.me/posts/2025/06/hello-garage-goodbye-minio/)
- [MinIO vs Ceph vs SeaweedFS vs Garage 2025](https://onidel.com/blog/minio-ceph-seaweedfs-garage-2025)
