#!/usr/bin/env bash
# MinIO → RustFS migration helper.
# Runs on workstation or QNAP — needs rclone with `minio` + `rustfs` aliases
# configured in ~/.config/rclone/rclone.conf (template in phase 4 of the runbook:
# docs/migrations/minio-to-rustfs.md).

set -euo pipefail

BUCKETS=(restic-nextcloud restic-immich)
MINIO_REMOTE="minio"
RUSTFS_REMOTE="rustfs"
SAMPLE_COUNT=5

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date '+%H:%M:%S')] $*"; }

require_rclone() {
  command -v rclone >/dev/null || die "rclone not found"
  rclone listremotes | grep -q "^${MINIO_REMOTE}:$"  || die "missing rclone remote ${MINIO_REMOTE}"
  rclone listremotes | grep -q "^${RUSTFS_REMOTE}:$" || die "missing rclone remote ${RUSTFS_REMOTE}"
}

cmd_baseline() {
  require_rclone
  for b in "${BUCKETS[@]}"; do
    log "MinIO size: ${b}"
    rclone size "${MINIO_REMOTE}:${b}"
  done
}

cmd_dryrun() {
  require_rclone
  for b in "${BUCKETS[@]}"; do
    log "DRY-RUN sync ${b}"
    rclone sync "${MINIO_REMOTE}:${b}" "${RUSTFS_REMOTE}:${b}" \
      --checksum --dry-run -P
  done
}

cmd_sync() {
  require_rclone
  for b in "${BUCKETS[@]}"; do
    log "SYNC ${b}"
    rclone sync "${MINIO_REMOTE}:${b}" "${RUSTFS_REMOTE}:${b}" \
      --checksum --transfers 4 --checkers 8 -P
  done
}

cmd_verify() {
  require_rclone
  for b in "${BUCKETS[@]}"; do
    log "Size compare ${b}"
    src=$(rclone size --json "${MINIO_REMOTE}:${b}")
    dst=$(rclone size --json "${RUSTFS_REMOTE}:${b}")
    src_bytes=$(echo "$src" | grep -o '"bytes":[0-9]*' | cut -d: -f2)
    dst_bytes=$(echo "$dst" | grep -o '"bytes":[0-9]*' | cut -d: -f2)
    src_count=$(echo "$src" | grep -o '"count":[0-9]*' | cut -d: -f2)
    dst_count=$(echo "$dst" | grep -o '"count":[0-9]*' | cut -d: -f2)
    echo "  src: ${src_count} objs / ${src_bytes} bytes"
    echo "  dst: ${dst_count} objs / ${dst_bytes} bytes"
    [[ "$src_bytes" == "$dst_bytes" ]] || die "byte count mismatch on ${b}"
    [[ "$src_count" == "$dst_count" ]] || die "object count mismatch on ${b}"

    log "SHA spot-check ${b} (${SAMPLE_COUNT} random objects)"
    mapfile -t samples < <(rclone lsf "${MINIO_REMOTE}:${b}" --files-only --recursive \
      | shuf -n "$SAMPLE_COUNT")
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    for key in "${samples[@]}"; do
      rclone copyto "${MINIO_REMOTE}:${b}/${key}"  "${tmp}/src"
      rclone copyto "${RUSTFS_REMOTE}:${b}/${key}" "${tmp}/dst"
      src_sha=$(sha256sum "${tmp}/src" | awk '{print $1}')
      dst_sha=$(sha256sum "${tmp}/dst" | awk '{print $1}')
      if [[ "$src_sha" != "$dst_sha" ]]; then
        die "SHA mismatch on ${b}/${key}: ${src_sha} vs ${dst_sha}"
      fi
      echo "  ok ${key:0:60} ${src_sha:0:12}"
    done
  done
  log "Verification passed for all buckets."
}

usage() {
  cat <<USAGE
Usage: $0 <command>

Commands:
  baseline   Print rclone size of each MinIO bucket (pre-sync snapshot)
  dryrun     Show what rclone would copy (no writes)
  sync       Actually sync both buckets MinIO → RustFS
  verify     Compare byte/object counts + SHA-sum ${SAMPLE_COUNT} random objects per bucket

Typical flow:
  $0 baseline
  $0 dryrun
  $0 sync
  $0 verify
USAGE
}

case "${1:-}" in
  baseline) cmd_baseline ;;
  dryrun)   cmd_dryrun   ;;
  sync)     cmd_sync     ;;
  verify)   cmd_verify   ;;
  *)        usage; exit 1 ;;
esac
