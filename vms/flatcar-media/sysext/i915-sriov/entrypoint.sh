#!/bin/bash
# Container entrypoint — runs inside the builder container.
# Kernel headers must be bind-mounted at /host-modules before this runs.
# Writes i915.ko to /output/.
set -euo pipefail

BUILD_DIR="/host-modules/build"
SRC_DIR="/build/i915-sriov-dkms"

echo "[entrypoint] Checking kernel build directory: ${BUILD_DIR}"
if [[ ! -f "${BUILD_DIR}/Makefile" ]]; then
  echo "[entrypoint] ERROR: ${BUILD_DIR}/Makefile not found." >&2
  echo "[entrypoint] Ensure /host-modules is bind-mounted from the host:" >&2
  echo "[entrypoint]   -v /lib/modules/<KERNEL>:/host-modules:ro" >&2
  exit 1
fi

KERNEL_VERSION="$(basename "$(readlink -f /host-modules)")"
echo "[entrypoint] Kernel: ${KERNEL_VERSION}"
echo "[entrypoint] DKMS source: ${SRC_DIR}"

cd "${SRC_DIR}"

# Remove kvmgt from obj-m — we only need the patched i915 for SR-IOV VFs.
# Handle both old format (obj-m += kvmgt.o) and new format (obj-m += drivers/...).
sed -i '/obj-m.*kvmgt/d' Makefile
sed -i '/obj-m.*drivers\/gpu\/drm\/xe/d' Makefile

# Fix conditional sources that use i915-$(CONFIG_FOO). When CONFIG_FOO=m (module)
# instead of =y (builtin), these become i915-m which bypasses the addprefix that
# converts paths to drivers/gpu/drm/i915/. Force them to i915-y.
sed -i 's/^i915-\$(CONFIG_HWMON)/i915-y/' Makefile
sed -i 's/^i915-\$(CONFIG_COMPAT)/i915-y/' Makefile
sed -i 's/^i915-\$(CONFIG_DEBUG_FS)/i915-y/' Makefile
sed -i 's/^i915-\$(CONFIG_PERF_EVENTS)/i915-y/' Makefile
sed -i 's/^i915-\$(CONFIG_ACPI)/i915-y/' Makefile
sed -i 's/^i915-\$(CONFIG_DRM_FBDEV_EMULATION)/i915-y/' Makefile
sed -i 's/^i915-\$(CONFIG_DRM_I915_CAPTURE_ERROR)/i915-y/' Makefile
sed -i 's/^i915-\$(CONFIG_X86)/i915-y/' Makefile
sed -i 's/^gt-\$(CONFIG_X86)/gt-y/' Makefile

echo "[entrypoint] Running make..."
make -C "${BUILD_DIR}" M="$(pwd)" modules

# Find i915.ko — location varies by DKMS version:
#   older tags (<=2025.07): i915.ko in repo root
#   newer tags (>=2025.10): drivers/gpu/drm/i915/i915.ko
I915_KO=""
for candidate in i915.ko drivers/gpu/drm/i915/i915.ko; do
  if [[ -f "${candidate}" ]]; then
    I915_KO="${candidate}"
    break
  fi
done

if [[ -z "${I915_KO}" ]]; then
  echo "[entrypoint] ERROR: i915.ko not produced by make." >&2
  find . -name "i915.ko" 2>/dev/null | head -5
  exit 1
fi

cp "${I915_KO}" /output/i915.ko
echo "[entrypoint] Copied: ${I915_KO} -> /output/i915.ko"

# Copy compat module if present (newer DKMS versions produce a separate one).
if [[ -f "compat/intel_sriov_compat.ko" ]]; then
  cp compat/intel_sriov_compat.ko /output/intel_sriov_compat.ko
  echo "[entrypoint] Copied: intel_sriov_compat.ko"
fi

echo "[entrypoint] Done."
