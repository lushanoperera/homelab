#!/usr/bin/env bash
# test-gpu.sh — Integration tests for i915-sriov-dkms sysext on Flatcar VM 100
set -uo pipefail

VM="core@192.168.100.100"
HOST="root@192.168.100.38"
PASS=0; FAIL=0; SKIP=0; TOTAL=0

run_test() {
  local name="$1"; shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf "ok %d - %s\n" "$TOTAL" "$name"
  else
    FAIL=$((FAIL + 1))
    printf "not ok %d - %s\n" "$TOTAL" "$name"
  fi
}

skip_test() {
  TOTAL=$((TOTAL + 1)); SKIP=$((SKIP + 1))
  printf "ok %d - %s # SKIP %s\n" "$TOTAL" "$1" "$2"
}

echo "TAP version 13"
echo "1..25"

# === Pre-flight ===
run_test "T01 VM reachable"           ssh -o ConnectTimeout=5 $VM true
run_test "T02 Host reachable"         ssh -o ConnectTimeout=5 $HOST true

# === Sysext ===
run_test "T03 Sysext image exists"    ssh $VM 'test -f /etc/extensions/i915-sriov.raw'
run_test "T04 Sysext active"          ssh $VM 'systemd-sysext status 2>&1 | grep -q i915-sriov'
run_test "T05 Extension-release OK"   ssh $VM 'test -f /usr/lib/extension-release.d/extension-release.i915-sriov'

# === Kernel Module ===
run_test "T06 i915 module loaded"     ssh $VM 'test -d /sys/module/i915'
run_test "T07 Module is SR-IOV"       ssh $VM 'cat /sys/module/i915/version 2>/dev/null | grep -qi sriov'
run_test "T08 Module version string"  ssh $VM 'cat /sys/module/i915/version 2>/dev/null | grep -q .'
run_test "T09 i915 blacklisted"       ssh $VM 'test -f /etc/modprobe.d/i915-blacklist.conf'

# === PCI / DRI ===
run_test "T10 VGA device visible"     ssh $VM 'lspci | grep -qi vga'
run_test "T11 /dev/dri exists"        ssh $VM 'test -d /dev/dri'
run_test "T12 card device exists"     ssh $VM 'ls /dev/dri/card* >/dev/null 2>&1'
run_test "T13 renderD device exists"  ssh $VM 'ls /dev/dri/renderD* >/dev/null 2>&1'
run_test "T14 renderD permissions"    ssh $VM 'stat -c %a /dev/dri/renderD* 2>/dev/null | head -1 | grep -q 660'

# === Docker GPU Access ===
RENDER_DEV=$(ssh $VM 'ls /dev/dri/renderD* 2>/dev/null | head -1' 2>/dev/null)
if [ -n "$RENDER_DEV" ]; then
  run_test "T15 Docker sees DRI"      ssh $VM "docker run --rm --device=${RENDER_DEV} alpine ls /dev/dri/"
  run_test "T16 VAAPI functional"     ssh $VM "docker run --rm --device=${RENDER_DEV} linuxserver/ffmpeg:latest \
                                        -hwaccel vaapi -vaapi_device ${RENDER_DEV} \
                                        -f lavfi -i testsrc=duration=1:size=320x240 \
                                        -vf format=nv12,hwupload -c:v h264_vaapi -frames:v 1 -f null - 2>&1 | grep -q 'frame=.*1'"
else
  skip_test "T15 Docker sees DRI"     "no renderD device found"
  skip_test "T16 VAAPI functional"    "no renderD device found"
fi

# === Systemd Services ===
run_test "T17 gpu-setup active"       ssh $VM 'systemctl is-active gpu-setup.service'
run_test "T18 rebuild svc exists"     ssh $VM 'systemctl cat i915-sriov-rebuild.service >/dev/null 2>&1'
run_test "T19 verify-gpu.sh exists"   ssh $VM 'test -x /opt/bin/verify-gpu.sh'

# === Proxmox Host ===
run_test "T20 VF 0 assigned to VM"    ssh $HOST 'qm config 100 | grep -q "hostpci.*00:02.1"'
run_test "T21 VF 0 single assignment" bash -c '[[ $(ssh '$HOST' "grep -rl 00:02.1 /etc/pve/lxc/ /etc/pve/qemu-server/ 2>/dev/null | wc -l") -le 1 ]]'

# === Regression ===
run_test "T22 Critical containers up" ssh $VM 'for c in sonarr radarr gluetun caddy traefik; do
                                        docker ps --format "{{.Names}}" | grep -q "$c" || exit 1; done'
run_test "T23 NFS mounts intact"      ssh $VM 'mountpoint -q /mnt/media && mountpoint -q /mnt/media/movies'

# === Rebuild Safety ===
run_test "T24 Kernel version match"   ssh $VM 'test -f /usr/lib/modules/$(uname -r)/updates/i915/i915.ko'
run_test "T25 Rebuild script exists"  ssh $VM 'test -x /opt/bin/i915-sriov-rebuild.sh'

# === Summary ===
echo "---"
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped out of $TOTAL tests"
exit $((FAIL > 0 ? 1 : 0))
