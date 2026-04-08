#!/usr/bin/env bash
# Verify LXC 105 (Plex) after dist-upgrade
# Usage: ./verify.sh <CTID> <expected-version>
# Example: ./verify.sh 105 24.04

set -euo pipefail

CTID="${1:?Usage: $0 <CTID> <expected-version>}"
EXPECTED_VERSION="${2:?Usage: $0 <CTID> <expected-version>}"

PASS=0
FAIL=0
WARN=0

ct_exec() { pct exec "$CTID" -- bash -c "$1"; }

check() {
    local name="$1" result="$2" expected="$3"
    if echo "$result" | grep -q "$expected"; then
        echo "  PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name (got: ${result:0:80})"
        FAIL=$((FAIL + 1))
    fi
}

warn_check() {
    local name="$1" result="$2" expected="$3"
    if echo "$result" | grep -q "$expected"; then
        echo "  PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "  WARN  $name (got: ${result:0:80})"
        WARN=$((WARN + 1))
    fi
}

echo "=== LXC $CTID Post-Upgrade Verification (expecting Ubuntu $EXPECTED_VERSION) ==="
echo ""

# OS version
version=$(ct_exec 'grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d \"')
check "OS version" "$version" "$EXPECTED_VERSION"

# GPU devices
gpu_devs=$(ct_exec 'ls /dev/dri/ 2>/dev/null || echo "missing"')
check "card0 present" "$gpu_devs" "card0"
check "renderD128 present" "$gpu_devs" "renderD128"

# VA-API driver
vainfo_out=$(ct_exec 'vainfo --display drm --device /dev/dri/renderD128 2>&1 || echo "vainfo failed"')
check "iHD VA-API driver" "$vainfo_out" "iHD"

# Check for key codec profiles
for codec in H264 HEVC VP9; do
    warn_check "VA-API $codec" "$vainfo_out" "$codec"
done

# GIDs
video_gid=$(ct_exec 'getent group video | cut -d: -f3')
render_gid=$(ct_exec 'getent group render | cut -d: -f3')
check "video GID = 44" "$video_gid" "44"
check "render GID = 104" "$render_gid" "104"

# NFS mount
nfs_out=$(ct_exec 'df -h /mnt/media 2>/dev/null || echo "not mounted"')
check "NFS /mnt/media" "$nfs_out" "/mnt/media"

# Plex service
plex_status=$(ct_exec 'systemctl is-active plexmediaserver 2>/dev/null || echo "inactive"')
check "Plex service active" "$plex_status" "active"

# Plex API
plex_identity=$(ct_exec 'curl -sf http://localhost:32400/identity 2>/dev/null || echo "no response"')
check "Plex API responds" "$plex_identity" "MediaContainer"

# Plex apt repo
apt_out=$(ct_exec 'apt-get update 2>&1 | grep -i plex || echo "no plex repo"')
warn_check "Plex apt repo" "$apt_out" "plex"

# Plex user groups
plex_groups=$(ct_exec 'id plex 2>/dev/null || echo "no plex user"')
check "plex in video group" "$plex_groups" "video"
check "plex in render group" "$plex_groups" "render"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="

if ((FAIL > 0)); then
    echo "VERIFICATION FAILED — fix issues before proceeding"
    exit 1
fi
if ((WARN > 0)); then
    echo "Passed with warnings — review before proceeding"
    exit 0
fi
echo "All checks passed"
