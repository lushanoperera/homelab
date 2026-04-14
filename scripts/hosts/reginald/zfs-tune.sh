#!/usr/bin/env bash
# Reginald ZFS tuning — hot-applyable, reversible, Zimaboard-832-aware.
#
# Hardware assumptions (Zimaboard 832):
#   - Celeron N3450 (4c, weak on zstd)
#   - 8 GB LPDDR4 soldered (non-upgradable)
#   - 7x SATA SSDs in raidz2 via onboard AHCI + JMB58x HBA (PCIe 2.0 x2)
#   - Storage LAN on bond0 = eth_usb1 2.5 GbE primary + enp3s0 1 GbE backup
#   - zram swap already configured (1.2 GB, zstd, priority 100)
#
# Changes (all reversible):
#   1. ARC max 4G -> 2.5G, min 512M
#   2. zfs_dirty_data_max 2G -> 512M (wire is ~280 MB/s peak, no need for 2G buffer)
#   3. vm.dirty_ratio 60 -> 20, dirty_background_ratio 20 -> 10
#   4. zpool autotrim=on
#   5. compression zstd-3 -> lz4 on media/library/nextcloud (ratios ~1.00-1.05x)
#   6. logbias throughput -> latency on sync-NFS datasets (no SLOG)
#   7. primarycache=metadata on media/{movies,tv,music} (streaming, no reuse)
#
# Out of scope:
#   - ORICO disk replacement (hardware)
#   - rpool/swap zvol removal (kept as OOM safety net since zram is only 1.2 GB)
#   - Capacity planning

set -euo pipefail

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
run()  {
  if (( APPLY )); then
    log "RUN: $*"
    "$@"
  else
    log "DRY: $*"
  fi
}

if [[ $EUID -ne 0 ]]; then
  echo "must run as root" >&2
  exit 1
fi

if ! zpool list rpool >/dev/null 2>&1; then
  echo "rpool not found — wrong host?" >&2
  exit 1
fi

(( APPLY )) || log "=== DRY RUN === (pass --apply to commit)"
log "host: $(hostname) | uptime: $(uptime -p)"

# ---------------------------------------------------------------------------
# 1. ARC: 4G -> 2.5G, min 512M
# ---------------------------------------------------------------------------
log ""
log "--- [1/7] ARC sizing ---"
CUR_MAX=$(cat /sys/module/zfs/parameters/zfs_arc_max)
CUR_MIN=$(cat /sys/module/zfs/parameters/zfs_arc_min)
log "current: c_max=${CUR_MAX} c_min=${CUR_MIN}"

NEW_ARC_MAX=2684354560    # 2.5 GiB
NEW_ARC_MIN=536870912     # 512 MiB
NEW_DIRTY=536870912       # 512 MiB

MODPROBE_CONF=/etc/modprobe.d/zfs.conf
if [[ -f $MODPROBE_CONF ]] && (( APPLY )); then
  BACKUP="${MODPROBE_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
  run cp -a "$MODPROBE_CONF" "$BACKUP"
fi

update_modprobe_line() {
  local key=$1 val=$2 comment=$3
  if (( ! APPLY )); then
    log "DRY: would set 'options zfs ${key}=${val}' in ${MODPROBE_CONF}"
    return
  fi
  if grep -qE "^options zfs ${key}=" "$MODPROBE_CONF"; then
    sed -i "s|^options zfs ${key}=.*|options zfs ${key}=${val}  # ${comment}|" "$MODPROBE_CONF"
  else
    echo "options zfs ${key}=${val}  # ${comment}" >> "$MODPROBE_CONF"
  fi
}

update_modprobe_line zfs_arc_max        "$NEW_ARC_MAX"  "2.5G — tuned 2026-04-14"
update_modprobe_line zfs_arc_min        "$NEW_ARC_MIN"  "512M — tuned 2026-04-14"
update_modprobe_line zfs_dirty_data_max "$NEW_DIRTY"    "512M — tuned 2026-04-14 (storage LAN ~280 MB/s)"

if (( APPLY )); then
  echo "$NEW_ARC_MAX" > /sys/module/zfs/parameters/zfs_arc_max
  echo "$NEW_ARC_MIN" > /sys/module/zfs/parameters/zfs_arc_min
  echo "$NEW_DIRTY"   > /sys/module/zfs/parameters/zfs_dirty_data_max
  log "live sysfs applied: arc_max=2.5G arc_min=512M dirty_data_max=512M"
fi

# ---------------------------------------------------------------------------
# 2. VM dirty ratios (stop double-buffering on top of ZFS)
# ---------------------------------------------------------------------------
log ""
log "--- [2/7] sysctl dirty ratios ---"
CUR_DR=$(sysctl -n vm.dirty_ratio)
CUR_DBR=$(sysctl -n vm.dirty_background_ratio)
log "current: vm.dirty_ratio=${CUR_DR} vm.dirty_background_ratio=${CUR_DBR}"

SYSCTL_FILE=/etc/sysctl.d/90-reginald-dirty.conf
if (( APPLY )); then
  cat >"$SYSCTL_FILE" <<'EOF'
# Reginald — reduce VM dirty buffer (ZFS has its own, we were double-buffering)
# Tuned 2026-04-14 for 8 GB host + 2.5 GbE storage LAN
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
EOF
  sysctl -p "$SYSCTL_FILE" >/dev/null
  log "sysctl applied via ${SYSCTL_FILE}"
else
  log "DRY: would write ${SYSCTL_FILE} with dirty_ratio=20 dirty_background_ratio=10"
fi

# ---------------------------------------------------------------------------
# 3. autotrim
# ---------------------------------------------------------------------------
log ""
log "--- [3/7] autotrim ---"
CUR_TRIM=$(zpool get -H -o value autotrim rpool)
log "current: autotrim=${CUR_TRIM}"
if [[ "$CUR_TRIM" != "on" ]]; then
  run zpool set autotrim=on rpool
else
  log "already on"
fi

# ---------------------------------------------------------------------------
# 4. Compression zstd-3 -> lz4 on low-ratio datasets
# ---------------------------------------------------------------------------
log ""
log "--- [4/7] compression (new writes only) ---"
COMPRESS_TARGETS=(
  rpool/shared/media
  rpool/shared/media/music
  rpool/shared/media/tv
  rpool/shared/immich/library
  rpool/shared/nextcloud
)
for ds in "${COMPRESS_TARGETS[@]}"; do
  if ! zfs list "$ds" >/dev/null 2>&1; then
    log "skip $ds (missing)"
    continue
  fi
  CUR=$(zfs get -H -o value compression "$ds")
  if [[ "$CUR" != "lz4" ]]; then
    log "$ds: $CUR -> lz4"
    run zfs set compression=lz4 "$ds"
  else
    log "$ds: already lz4"
  fi
done

# ---------------------------------------------------------------------------
# 5. logbias -> latency on sync-NFS datasets (no SLOG)
# ---------------------------------------------------------------------------
log ""
log "--- [5/7] logbias ---"
LATENCY_TARGETS=(
  rpool/shared            # vaultwarden lives here as subdir
  rpool/shared/nextcloud
)
for ds in "${LATENCY_TARGETS[@]}"; do
  CUR=$(zfs get -H -o value logbias "$ds")
  if [[ "$CUR" != "latency" ]]; then
    log "$ds: $CUR -> latency"
    run zfs set logbias=latency "$ds"
  else
    log "$ds: already latency"
  fi
done

# keep throughput on async media trees
THROUGHPUT_TARGETS=(
  rpool/shared/media
  rpool/shared/media/downloads
)
for ds in "${THROUGHPUT_TARGETS[@]}"; do
  if ! zfs list "$ds" >/dev/null 2>&1; then
    continue
  fi
  CUR=$(zfs get -H -o value logbias "$ds")
  if [[ "$CUR" != "throughput" ]]; then
    log "$ds: $CUR -> throughput"
    run zfs set logbias=throughput "$ds"
  else
    log "$ds: already throughput"
  fi
done

# ---------------------------------------------------------------------------
# 6. primarycache=metadata on streaming media (stop Plex polluting ARC)
# ---------------------------------------------------------------------------
log ""
log "--- [6/7] primarycache=metadata on streaming media ---"
METADATA_ONLY=(
  rpool/shared/media          # parent — covers 'movies' subdir (not its own dataset)
  rpool/shared/media/tv
  rpool/shared/media/music
)
for ds in "${METADATA_ONLY[@]}"; do
  if ! zfs list "$ds" >/dev/null 2>&1; then
    log "skip $ds (missing — likely a subdir not a dataset)"
    continue
  fi
  CUR=$(zfs get -H -o value primarycache "$ds")
  if [[ "$CUR" != "metadata" ]]; then
    log "$ds: $CUR -> metadata"
    run zfs set primarycache=metadata "$ds"
  else
    log "$ds: already metadata"
  fi
done
# Immich library stays 'all' (thumbnail/search re-reads it)

# ---------------------------------------------------------------------------
# 7. Rebuild initramfs so module params survive reboot
# ---------------------------------------------------------------------------
log ""
log "--- [7/7] initramfs ---"
if command -v update-initramfs >/dev/null; then
  run update-initramfs -u -k all
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "=== final state ==="
log "ARC live:"
printf '      c_max = %s bytes\n' "$(cat /sys/module/zfs/parameters/zfs_arc_max)"
printf '      c_min = %s bytes\n' "$(cat /sys/module/zfs/parameters/zfs_arc_min)"
printf '      dirty = %s bytes\n' "$(cat /sys/module/zfs/parameters/zfs_dirty_data_max)"
log "pool:"
printf '      autotrim = %s\n' "$(zpool get -H -o value autotrim rpool)"
log "sysctl:"
printf '      vm.dirty_ratio = %s\n' "$(sysctl -n vm.dirty_ratio)"
printf '      vm.dirty_background_ratio = %s\n' "$(sysctl -n vm.dirty_background_ratio)"
log "datasets:"
for ds in rpool/shared rpool/shared/nextcloud rpool/shared/immich/library rpool/shared/immich/database rpool/shared/media rpool/shared/media/movies rpool/shared/media/tv rpool/shared/media/music; do
  if zfs list "$ds" >/dev/null 2>&1; then
    C=$(zfs get -H -o value compression "$ds")
    L=$(zfs get -H -o value logbias "$ds")
    P=$(zfs get -H -o value primarycache "$ds")
    printf '      %-40s comp=%-6s logbias=%-10s primarycache=%s\n' "$ds" "$C" "$L" "$P"
  fi
done

if (( APPLY )); then
  log ""
  log "done. verification:"
  log "  free -h                                    # RAM should ease in ~5 min"
  log "  arc_summary | grep -A2 'ARC size'          # ARC shrinks gradually"
  log "  zpool status rpool                         # still ONLINE"
else
  log ""
  log "DRY RUN complete. Re-run with --apply to commit."
fi
