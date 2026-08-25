#!/usr/bin/env bash
# Create LXC 107 "immich-ml" on winston: unprivileged Debian 13 with Docker,
# iGPU shared from the host PF (/dev/dri/by-path/pci-0000:00:02.0-*), same
# pattern as Plex LXC 105. No SR-IOV VF, no patched kernel module.
#
# Why: Immich ML was the only GPU consumer on Flatcar VM 100, and every
# Flatcar kernel auto-update broke the i915 SR-IOV sysext (4 outages in 2026).
#
# Usage: run ON winston as root, or: ssh root@192.168.100.38 'bash -s' < this
# Idempotent: exits 0 if CT 107 already exists.

set -euo pipefail

CTID=107
TEMPLATE="local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
IP="192.168.100.107/24"
GW="192.168.100.1"

if pct status "$CTID" >/dev/null 2>&1; then
  echo "CT $CTID already exists — nothing to do"
  exit 0
fi

# ext4-backed local-lvm on purpose: overlay2 on a ZFS subvol is the known
# Docker-in-LXC pitfall ("overlayfs: upper fs missing required features").
# local-lvm ships with content=images only; allow container rootfs on it too.
if ! pvesm status --storage local-lvm --content rootdir >/dev/null 2>&1; then
  pvesm set local-lvm --content images,rootdir
fi
pct create "$CTID" "$TEMPLATE" \
  --hostname immich-ml --unprivileged 1 --features nesting=1,keyctl=1 \
  --cores 4 --memory 6144 --swap 0 \
  --rootfs local-lvm:32 \
  --net0 "name=eth0,bridge=vmbr0,ip=${IP},gw=${GW}" \
  --onboot 1 --start 0

# Pass the resolved node paths, not by-path: pct creates the same path inside
# the CT, and Docker "devices:" needs /dev/dri/renderD128 + card0 as real
# char devices. gid = the CT's own group ids (Debian 13: render 992, video 44),
# not the host's (render 104). Verify with `getent group render` inside the CT.
RENDER_NODE=$(readlink -f /dev/dri/by-path/pci-0000:00:02.0-render)   # /dev/dri/renderD128
CARD_NODE=$(readlink -f /dev/dri/by-path/pci-0000:00:02.0-card)       # /dev/dri/card0
pct set "$CTID" --dev0 "${RENDER_NODE},gid=992" --dev1 "${CARD_NODE},gid=44"

pct start "$CTID"
sleep 5

# shellcheck disable=SC2016  # expansion happens inside the CT on purpose
pct exec "$CTID" -- bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -y -q docker.io docker-compose intel-gpu-tools curl rsync unattended-upgrades
  systemctl enable --now docker
  # Debian security + stable updates daily; Docker images stay on watchtower/manual.
  printf "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\nAPT::Periodic::AutocleanInterval \"7\";\n" > /etc/apt/apt.conf.d/20auto-upgrades
  systemctl enable --now unattended-upgrades apt-daily.timer apt-daily-upgrade.timer
  mkdir -p /srv/docker/immich-ml
  echo "render gid: $(getent group render | cut -d: -f3)  video gid: $(getent group video | cut -d: -f3)"
  echo "if render gid != 992: pct set '"$CTID"' --dev0 /dev/dri/renderD128,gid=<gid> && pct reboot '"$CTID"'"
  ls -l /dev/dri
  docker info 2>/dev/null | grep -i "storage driver"
'

echo "CT $CTID ready at ${IP%/*}. Next: rsync apps/immich-ml/ root@${IP%/*}:/srv/docker/immich-ml/ && docker compose up -d"
