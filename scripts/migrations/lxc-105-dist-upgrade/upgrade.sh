#!/usr/bin/env bash
# LXC 105 (Plex) dist-upgrade: Ubuntu 22.04 → 24.04 → 26.04
# Run on winston (192.168.100.38) as root
#
# Usage:
#   ./upgrade.sh phase0   # Backup & baseline
#   ./upgrade.sh phase1   # Pre-flight checks
#   ./upgrade.sh phase2   # Upgrade 22.04 → 24.04
#   ./upgrade.sh phase3   # Verify 24.04
#   ./upgrade.sh phase4   # Upgrade 24.04 → 26.04
#   ./upgrade.sh phase5   # Final verification
#
# Each phase is idempotent and safe to re-run.

set -euo pipefail

CTID=105
PBS_STORAGE="pbs-backupnas"
BACKUP_DIR="/root"
BASELINE_FILE="${BACKUP_DIR}/lxc-105-baseline.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GPU packages needed in each Ubuntu release
GPU_PACKAGES=(
    intel-media-va-driver
    intel-opencl-icd
    mesa-va-drivers
    vainfo
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
err() { log "ERROR: $1" >&2; exit 1; }
ct_exec() { pct exec "$CTID" -- bash -c "$1"; }

check_root() {
    [[ $EUID -eq 0 ]] || err "Must run as root on winston"
}

check_running() {
    local status
    status=$(pct status "$CTID" | awk '{print $2}')
    [[ "$status" == "running" ]] || err "LXC $CTID is not running (status: $status)"
}

# ─── Phase 0: Backup & Baseline ─────────────────────────────────────────────

phase0() {
    log "=== Phase 0: Backup & Baseline ==="

    # PBS snapshot
    log "Creating PBS backup..."
    vzdump "$CTID" --storage "$PBS_STORAGE" --compress zstd --mode snapshot \
        --notes "pre-upgrade-22-to-24"
    log "PBS backup complete"

    # Export LXC config
    log "Saving LXC config..."
    cp "/etc/pve/lxc/${CTID}.conf" "${BACKUP_DIR}/lxc-${CTID}-pre-upgrade.conf"
    log "Saved to ${BACKUP_DIR}/lxc-${CTID}-pre-upgrade.conf"

    # Backup Plex data (preferences + databases)
    log "Backing up Plex data..."
    ct_exec 'tar czf /root/plex-data-backup.tar.gz \
        "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml" \
        "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/"'
    log "Plex data backed up inside container at /root/plex-data-backup.tar.gz"

    # Capture baseline
    log "Capturing baseline..."
    {
        echo "=== Baseline captured $(date) ==="
        echo ""
        echo "--- OS ---"
        ct_exec 'cat /etc/os-release'
        echo ""
        echo "--- GPU devices ---"
        ct_exec 'ls -la /dev/dri/ 2>/dev/null || echo "No /dev/dri"'
        echo ""
        echo "--- vainfo ---"
        ct_exec 'vainfo --display drm --device /dev/dri/renderD128 2>&1 || echo "vainfo failed"'
        echo ""
        echo "--- GIDs ---"
        ct_exec 'getent group video render'
        echo ""
        echo "--- Apt sources ---"
        ct_exec 'cat /etc/apt/sources.list.d/plexmediaserver.list 2>/dev/null || echo "No plex source"'
        ct_exec 'ls /etc/apt/trusted.gpg.d/ 2>/dev/null || echo "No trusted keys dir"'
        echo ""
        echo "--- Plex version ---"
        ct_exec 'dpkg -l plexmediaserver 2>/dev/null | grep plex || echo "Plex not found via dpkg"'
        echo ""
        echo "--- Plex identity ---"
        ct_exec 'curl -sf http://localhost:32400/identity || echo "Plex not responding"'
    } > "$BASELINE_FILE"
    log "Baseline saved to $BASELINE_FILE"
    cat "$BASELINE_FILE"
}

# ─── Phase 1: Pre-Flight ────────────────────────────────────────────────────

phase1() {
    log "=== Phase 1: Pre-Flight Checks ==="
    local failures=0

    # Check PBS backup exists
    log "Checking PBS backup..."
    if pvesm list "$PBS_STORAGE" --content backup --vmid "$CTID" 2>/dev/null | grep -q "$CTID"; then
        log "OK: PBS backup found"
    else
        log "WARN: No PBS backup found for LXC $CTID"
        failures=$((failures + 1))
    fi

    # Check NFS mount on host
    log "Checking NFS mount..."
    if mount | grep -q nfs_media; then
        log "OK: NFS media mount present on host"
    else
        log "WARN: NFS media mount not found on host"
        failures=$((failures + 1))
    fi

    # Check GPU passthrough
    log "Checking GPU devices..."
    if ct_exec 'test -c /dev/dri/renderD128'; then
        log "OK: renderD128 present"
    else
        log "WARN: renderD128 not found"
        failures=$((failures + 1))
    fi

    # Check vainfo
    log "Checking VA-API..."
    if ct_exec 'vainfo --display drm --device /dev/dri/renderD128 2>&1' | grep -q "iHD"; then
        log "OK: iHD VA-API driver working"
    else
        log "WARN: iHD driver not detected"
        failures=$((failures + 1))
    fi

    # Check Plex
    log "Checking Plex..."
    if ct_exec 'curl -sf http://localhost:32400/identity' | grep -q "MediaContainer"; then
        log "OK: Plex responding"
    else
        log "WARN: Plex not responding"
        failures=$((failures + 1))
    fi

    # Check GIDs
    log "Checking GIDs..."
    local video_gid render_gid
    video_gid=$(ct_exec 'getent group video | cut -d: -f3')
    render_gid=$(ct_exec 'getent group render | cut -d: -f3')
    if [[ "$video_gid" == "44" && "$render_gid" == "104" ]]; then
        log "OK: GIDs correct (video=44, render=104)"
    else
        log "WARN: GID mismatch — video=$video_gid, render=$render_gid (expected 44, 104)"
        failures=$((failures + 1))
    fi

    # Note Plex apt source
    log "Plex apt source:"
    ct_exec 'cat /etc/apt/sources.list.d/plexmediaserver.list 2>/dev/null || \
             cat /etc/apt/sources.list.d/plexmediaserver.sources 2>/dev/null || \
             echo "Not found"'

    if ((failures > 0)); then
        err "Pre-flight failed with $failures issue(s). Fix before proceeding."
    fi
    log "All pre-flight checks passed"
}

# ─── Phase 2: Upgrade 22.04 → 24.04 ────────────────────────────────────────

phase2() {
    log "=== Phase 2: Upgrade 22.04 → 24.04 ==="
    check_running

    # Full update first
    log "Updating current packages..."
    ct_exec 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y && apt-get autoremove -y'

    # Save Plex repo config
    log "Saving Plex apt source..."
    ct_exec 'cp /etc/apt/sources.list.d/plexmediaserver.list /root/plexmediaserver.list.bak 2>/dev/null || true'
    ct_exec 'cp /etc/apt/sources.list.d/plexmediaserver.sources /root/plexmediaserver.sources.bak 2>/dev/null || true'
    # Save signing key (PlexSign.asc on 22.04)
    ct_exec 'cp /usr/share/keyrings/PlexSign.asc /root/PlexSign.asc.bak 2>/dev/null || \
             cp /etc/apt/trusted.gpg.d/plexmediaserver.gpg /root/plexmediaserver.gpg.bak 2>/dev/null || true'

    # Install update-manager-core and run upgrade
    log "Installing update-manager-core..."
    ct_exec 'apt-get install -y update-manager-core'

    log "Starting do-release-upgrade (22.04 → 24.04)..."
    log "This will take a while. Third-party repos will be disabled automatically."
    ct_exec 'do-release-upgrade -f DistUpgradeViewNonInteractive'

    # Restore Plex apt source
    log "Restoring Plex apt source..."
    restore_plex_repo

    # Reinstall GPU packages
    log "Reinstalling GPU userspace packages..."
    ct_exec "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ${GPU_PACKAGES[*]} intel-gpu-tools"

    # Verify GIDs
    verify_gids

    # Restart container
    log "Restarting container..."
    pct stop "$CTID"
    sleep 3
    pct start "$CTID"
    sleep 10  # wait for services

    log "Phase 2 complete — run './upgrade.sh phase3' to verify"
}

# ─── Phase 3: Verify 24.04 ──────────────────────────────────────────────────

phase3() {
    log "=== Phase 3: Verify 24.04 ==="
    check_running

    "$SCRIPT_DIR/verify.sh" "$CTID" "24.04"

    log "Creating post-24.04 PBS backup..."
    vzdump "$CTID" --storage "$PBS_STORAGE" --compress zstd --mode snapshot \
        --notes "post-upgrade-24.04-verified"

    log "Phase 3 complete"
    log ""
    log ">>> SOAK 24-48 hours before proceeding to phase4 <<<"
    log ">>> Monitor Tautulli for transcode failures <<<"
    log ">>> Then run: ./upgrade.sh phase4"
}

# ─── Phase 4: Upgrade 24.04 → 26.04 ────────────────────────────────────────

phase4() {
    log "=== Phase 4: Upgrade 24.04 → 26.04 ==="
    check_running

    # Verify we're on 24.04
    local version
    version=$(ct_exec 'grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d \"')
    [[ "$version" == "24.04" ]] || err "Expected Ubuntu 24.04, got $version"

    # Full update
    log "Updating current packages..."
    ct_exec 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y && apt-get autoremove -y'

    # Save Plex repo
    log "Saving Plex apt source..."
    ct_exec 'cp /etc/apt/sources.list.d/plexmediaserver.list /root/plexmediaserver.list.bak 2>/dev/null || true'
    ct_exec 'cp /etc/apt/sources.list.d/plexmediaserver.sources /root/plexmediaserver.sources.bak 2>/dev/null || true'
    ct_exec 'cp /usr/share/keyrings/PlexSign.asc /root/PlexSign.asc.bak 2>/dev/null || \
             cp /etc/apt/trusted.gpg.d/plexmediaserver.gpg /root/plexmediaserver.gpg.bak 2>/dev/null || true'

    # Run upgrade — use -d if LTS-to-LTS path not yet enabled
    log "Starting do-release-upgrade (24.04 → 26.04)..."
    log "Trying standard upgrade first, falling back to -d if needed..."
    local upgrade_out
    upgrade_out=$(ct_exec 'do-release-upgrade -f DistUpgradeViewNonInteractive 2>&1 || true')
    echo "$upgrade_out" | tail -20
    if echo "$upgrade_out" | grep -qi "no new release found"; then
        log "Standard path not available, using -d (development) flag..."
        ct_exec 'do-release-upgrade -d -f DistUpgradeViewNonInteractive'
    else
        log "Standard upgrade path completed"
    fi

    # Restore Plex apt source (may need DEB822 format on 26.04)
    log "Restoring Plex apt source..."
    restore_plex_repo

    # Reinstall GPU packages — intel-gpu-tools may be renamed to igt-gpu-tools
    log "Reinstalling GPU userspace packages..."
    ct_exec "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ${GPU_PACKAGES[*]}"
    # Try both names for gpu-tools
    ct_exec 'DEBIAN_FRONTEND=noninteractive apt-get install -y igt-gpu-tools 2>/dev/null || \
             DEBIAN_FRONTEND=noninteractive apt-get install -y intel-gpu-tools 2>/dev/null || \
             echo "WARN: Neither igt-gpu-tools nor intel-gpu-tools available"'

    # Verify GIDs
    verify_gids

    # Restart container
    log "Restarting container..."
    pct stop "$CTID"
    sleep 3
    pct start "$CTID"
    sleep 10

    log "Phase 4 complete — run './upgrade.sh phase5' to verify"
}

# ─── Phase 5: Final Verification ────────────────────────────────────────────

phase5() {
    log "=== Phase 5: Final Verification ==="
    check_running

    "$SCRIPT_DIR/verify.sh" "$CTID" "26.04"

    # Compare LXC config
    log "Comparing LXC config to pre-upgrade backup..."
    if [[ -f "${BACKUP_DIR}/lxc-${CTID}-pre-upgrade.conf" ]]; then
        if diff -u "${BACKUP_DIR}/lxc-${CTID}-pre-upgrade.conf" "/etc/pve/lxc/${CTID}.conf"; then
            log "OK: LXC config unchanged"
        else
            log "WARN: LXC config differs from pre-upgrade (see diff above)"
        fi
    else
        log "WARN: No pre-upgrade config backup found"
    fi

    log "Creating final PBS backup..."
    vzdump "$CTID" --storage "$PBS_STORAGE" --compress zstd --mode snapshot \
        --notes "post-upgrade-26.04-verified"

    log "=== Upgrade complete: Ubuntu 22.04 → 24.04 → 26.04 ==="
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

restore_plex_repo() {
    # Check if DEB822 .sources format is preferred (24.04+)
    local use_deb822
    use_deb822=$(ct_exec 'test -d /etc/apt/sources.list.d && ls /etc/apt/sources.list.d/*.sources 2>/dev/null | head -1 || echo ""')

    # Ensure signing key is in place
    ct_exec 'if [ -f /root/PlexSign.asc.bak ]; then
        cp /root/PlexSign.asc.bak /usr/share/keyrings/PlexSign.asc
    elif [ -f /root/plexmediaserver.gpg.bak ]; then
        cp /root/plexmediaserver.gpg.bak /usr/share/keyrings/PlexSign.asc
    fi'

    if [[ -n "$use_deb822" ]]; then
        log "Using DEB822 format for Plex repo..."
        ct_exec 'cat > /etc/apt/sources.list.d/plexmediaserver.sources << "REPO"
Types: deb
URIs: https://downloads.plex.tv/repo/deb
Suites: public
Components: main
Signed-By: /usr/share/keyrings/PlexSign.asc
REPO'
        # Remove old .list if exists
        ct_exec 'rm -f /etc/apt/sources.list.d/plexmediaserver.list 2>/dev/null || true'
    else
        log "Using traditional format for Plex repo..."
        ct_exec 'cat > /etc/apt/sources.list.d/plexmediaserver.list << "REPO"
deb [signed-by=/usr/share/keyrings/PlexSign.asc] https://downloads.plex.tv/repo/deb/ public main
REPO'
    fi
}

verify_gids() {
    local video_gid render_gid
    video_gid=$(ct_exec 'getent group video | cut -d: -f3')
    render_gid=$(ct_exec 'getent group render | cut -d: -f3')

    if [[ "$video_gid" != "44" ]]; then
        log "Fixing video GID: $video_gid → 44"
        ct_exec 'groupmod -g 44 video'
    fi
    if [[ "$render_gid" != "104" ]]; then
        log "Fixing render GID: $render_gid → 104"
        ct_exec 'groupmod -g 104 render'
    fi

    # Ensure plex user is in both groups
    ct_exec 'usermod -aG video,render plex 2>/dev/null || true'
    log "GIDs verified: video=$(ct_exec 'getent group video | cut -d: -f3'), render=$(ct_exec 'getent group render | cut -d: -f3')"
}

# ─── Main ────────────────────────────────────────────────────────────────────

check_root

case "${1:-}" in
    phase0) phase0 ;;
    phase1) phase1 ;;
    phase2) phase2 ;;
    phase3) phase3 ;;
    phase4) phase4 ;;
    phase5) phase5 ;;
    *)
        echo "Usage: $0 {phase0|phase1|phase2|phase3|phase4|phase5}"
        echo ""
        echo "  phase0  Backup & baseline"
        echo "  phase1  Pre-flight checks"
        echo "  phase2  Upgrade 22.04 → 24.04"
        echo "  phase3  Verify 24.04 + backup"
        echo "  phase4  Upgrade 24.04 → 26.04"
        echo "  phase5  Final verification + backup"
        exit 1
        ;;
esac
