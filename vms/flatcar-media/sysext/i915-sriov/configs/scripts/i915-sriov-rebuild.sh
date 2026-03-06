#!/bin/bash
set -euo pipefail
KERN=$(uname -r)
# Check if current sysext has module for running kernel
if [ -f "/usr/lib/modules/${KERN}/updates/i915/i915.ko" ]; then
  echo "i915-sriov sysext matches kernel ${KERN}, no rebuild needed"
  exit 0
fi
echo "Kernel mismatch - rebuilding i915-sriov sysext for ${KERN}..."
# Delegate to build.sh which handles Docker-based compilation
cd /opt/i915-sriov-build
./build.sh "${KERN}"
# Move new sysext into place
cp -f "i915-sriov-${KERN}"*.raw /etc/extensions/i915-sriov.raw
systemd-sysext refresh
depmod -a
echo "Rebuild complete for kernel ${KERN}"
