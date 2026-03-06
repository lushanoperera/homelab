#!/bin/bash
# deploy.sh — Deploy i915-sriov sysext to Flatcar VM 100
# Run from workstation (not on the VM)
set -euo pipefail

VM="core@192.168.100.100"
SYSEXT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIGS_DIR="${SYSEXT_DIR}/configs"

# Find the sysext image
RAW_FILE=$(ls -1 "${SYSEXT_DIR}"/i915-sriov*.raw 2>/dev/null | head -1)
if [ -z "$RAW_FILE" ]; then
  echo "ERROR: No i915-sriov*.raw found in ${SYSEXT_DIR}"
  echo "Run build.sh on the VM first: ssh ${VM} '~/i915-sriov-build/build.sh'"
  exit 1
fi

echo "=== i915-sriov Sysext Deployment ==="
echo "Image: $(basename "$RAW_FILE") ($(du -h "$RAW_FILE" | cut -f1))"
echo "Target: ${VM}"
echo ""

# Step 1: Copy sysext image
echo "[1/5] Copying sysext image to VM..."
scp "$RAW_FILE" "${VM}:/tmp/i915-sriov.raw"
ssh "$VM" 'sudo cp /tmp/i915-sriov.raw /etc/extensions/i915-sriov.raw && rm /tmp/i915-sriov.raw'
echo "  Done."

# Step 2: Copy config files
echo "[2/5] Deploying configuration files..."

# modprobe configs
ssh "$VM" 'sudo mkdir -p /etc/modprobe.d'
scp "${CONFIGS_DIR}/modprobe/i915-blacklist.conf" "${VM}:/tmp/"
scp "${CONFIGS_DIR}/modprobe/i915-sriov.conf" "${VM}:/tmp/"
ssh "$VM" 'sudo cp /tmp/i915-blacklist.conf /tmp/i915-sriov.conf /etc/modprobe.d/ && rm /tmp/i915-blacklist.conf /tmp/i915-sriov.conf'

# udev rules
ssh "$VM" 'sudo mkdir -p /etc/udev/rules.d'
scp "${CONFIGS_DIR}/udev/70-dri-permissions.rules" "${VM}:/tmp/"
ssh "$VM" 'sudo cp /tmp/70-dri-permissions.rules /etc/udev/rules.d/ && rm /tmp/70-dri-permissions.rules'

# systemd services
scp "${CONFIGS_DIR}/systemd/gpu-setup.service" "${VM}:/tmp/"
scp "${CONFIGS_DIR}/systemd/i915-sriov-rebuild.service" "${VM}:/tmp/"
ssh "$VM" 'sudo cp /tmp/gpu-setup.service /tmp/i915-sriov-rebuild.service /etc/systemd/system/ && rm /tmp/gpu-setup.service /tmp/i915-sriov-rebuild.service'

# scripts
ssh "$VM" 'sudo mkdir -p /opt/bin /opt/i915-sriov-build'
scp "${CONFIGS_DIR}/scripts/verify-gpu.sh" "${VM}:/tmp/"
scp "${CONFIGS_DIR}/scripts/i915-sriov-rebuild.sh" "${VM}:/tmp/"
ssh "$VM" 'sudo cp /tmp/verify-gpu.sh /tmp/i915-sriov-rebuild.sh /opt/bin/ && sudo chmod +x /opt/bin/verify-gpu.sh /opt/bin/i915-sriov-rebuild.sh && rm /tmp/verify-gpu.sh /tmp/i915-sriov-rebuild.sh'

# Copy build infrastructure for rebuild service
scp "${SYSEXT_DIR}/Dockerfile" "${SYSEXT_DIR}/build.sh" "${VM}:/tmp/"
ssh "$VM" 'sudo cp /tmp/Dockerfile /tmp/build.sh /opt/i915-sriov-build/ && sudo chmod +x /opt/i915-sriov-build/build.sh && rm /tmp/Dockerfile /tmp/build.sh'

echo "  Done."

# Step 3: Activate sysext
echo "[3/5] Activating sysext..."
ssh "$VM" 'sudo systemd-sysext refresh && sudo depmod -a'

# Verify sysext is active
if ssh "$VM" 'systemd-sysext status 2>&1 | grep -q i915-sriov'; then
  echo "  Sysext active."
else
  echo "  WARNING: Sysext may not be active. Check: ssh ${VM} 'systemd-sysext status'"
fi

# Step 4: Enable systemd services
echo "[4/5] Enabling systemd services..."
ssh "$VM" 'sudo systemctl daemon-reload && sudo systemctl enable gpu-setup.service i915-sriov-rebuild.service'
echo "  Done."

# Step 5: Verify module is available
echo "[5/5] Verifying module availability..."
KERN=$(ssh "$VM" 'uname -r')
if ssh "$VM" "test -f /usr/lib/modules/${KERN}/updates/i915/i915.ko"; then
  echo "  Module found at /usr/lib/modules/${KERN}/updates/i915/i915.ko"
else
  echo "  WARNING: Module not found for kernel ${KERN}"
  echo "  Sysext contents:"
  ssh "$VM" "ls -la /usr/lib/modules/${KERN}/updates/i915/ 2>/dev/null || echo '  (directory missing)'"
fi

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Stop VM 100 on Proxmox:  ssh root@192.168.100.38 'qm stop 100'"
echo "  2. Add VF 0 passthrough:    ssh root@192.168.100.38 'qm set 100 -hostpci0 0000:00:02.1,x-vga=0,rombar=0,pcie=1'"
echo "  3. Start VM 100:            ssh root@192.168.100.38 'qm start 100'"
echo "  4. Run tests:               ./test-gpu.sh"
