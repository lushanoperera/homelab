#!/bin/bash
# build.sh — Build i915-sriov-dkms as a systemd-sysext image.
#
# Run ON Flatcar VM 100:  ssh core@192.168.100.100
# Deploy script:          scp build.sh core@192.168.100.100:/home/core/i915-sriov/
#
# Usage:
#   ./build.sh [KERNEL_VERSION] [--dkms-version VERSION]
#
#   KERNEL_VERSION   defaults to $(uname -r)
#   --dkms-version   git tag to check out; default 2025.10.10
#
# Outputs:
#   i915-sriov-<KERNEL>-<DKMS>.raw  — versioned squashfs sysext image
#   i915-sriov.raw                  — symlink → versioned image (deploy target)
#
# The script is idempotent: re-running it rebuilds cleanly.

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
KERN=""
DKMS_VERSION="2025.07.22"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dkms-version)
      DKMS_VERSION="$2"
      shift 2
      ;;
    --dkms-version=*)
      DKMS_VERSION="${1#*=}"
      shift
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      KERN="$1"
      shift
      ;;
  esac
done

if [[ -z "${KERN}" ]]; then
  KERN="$(uname -r)"
fi

IMAGE_NAME="i915-sriov-builder"
OUTPUT_RAW="i915-sriov-${KERN}-${DKMS_VERSION}.raw"
LINK_RAW="i915-sriov.raw"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== i915-sriov-dkms sysext builder ==="
echo "  Kernel       : ${KERN}"
echo "  DKMS version : ${DKMS_VERSION}"
echo "  Work dir     : ${WORKDIR}"
echo "  Output image : ${OUTPUT_RAW}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Validate kernel headers
# ---------------------------------------------------------------------------
echo "[1/6] Validating kernel headers..."

HEADERS_DIR="/lib/modules/${KERN}"
BUILD_DIR="${HEADERS_DIR}/build"

if [[ ! -d "${HEADERS_DIR}" ]]; then
  echo "ERROR: /lib/modules/${KERN} does not exist." >&2
  echo "       Flatcar ships kernel headers in this path for the running kernel." >&2
  echo "       Run: uname -r   to confirm the kernel version." >&2
  exit 1
fi

if [[ ! -f "${BUILD_DIR}/Makefile" ]]; then
  echo "ERROR: ${BUILD_DIR}/Makefile not found." >&2
  echo "       Kernel headers appear incomplete. On Flatcar, headers are" >&2
  echo "       available under /lib/modules/\$(uname -r)/build/." >&2
  exit 1
fi

echo "  Headers OK: ${BUILD_DIR}"

# ---------------------------------------------------------------------------
# Step 2: Build the builder Docker image (no kernel headers baked in)
# ---------------------------------------------------------------------------
echo "[2/6] Building Docker builder image (deps + source clone)..."

cd "${WORKDIR}"

# Pass both build args so the correct source tag is cloned into the image layer.
docker build \
  --build-arg "KERNEL_VERSION=${KERN}" \
  --build-arg "DKMS_VERSION=${DKMS_VERSION}" \
  -t "${IMAGE_NAME}:${DKMS_VERSION}" \
  -f Dockerfile \
  .

echo "  Image: ${IMAGE_NAME}:${DKMS_VERSION}"

# ---------------------------------------------------------------------------
# Step 3: Compile the module — run the builder with host headers bind-mounted
# ---------------------------------------------------------------------------
echo "[3/6] Compiling i915.ko against host kernel headers..."

OUTPUT_DIR="${WORKDIR}/output"
mkdir -p "${OUTPUT_DIR}"

# Remove stale .ko from a previous run so we can detect failures cleanly.
rm -f "${OUTPUT_DIR}/i915.ko"

# The container entrypoint does the compile; /output is writable by the container.
docker run --rm \
  -v "${HEADERS_DIR}:/host-modules:ro" \
  -v "${OUTPUT_DIR}:/output" \
  "${IMAGE_NAME}:${DKMS_VERSION}"

if [[ ! -f "${OUTPUT_DIR}/i915.ko" ]]; then
  echo "ERROR: Compilation did not produce i915.ko." >&2
  exit 1
fi

echo "  Compiled: ${OUTPUT_DIR}/i915.ko ($(du -sh "${OUTPUT_DIR}/i915.ko" | cut -f1))"

# ---------------------------------------------------------------------------
# Step 4: Assemble sysext directory tree
# ---------------------------------------------------------------------------
echo "[4/6] Assembling sysext directory tree..."

SYSEXT_ROOT="${WORKDIR}/sysext-root"

# Wipe any previous assembly to ensure a clean image.
rm -rf "${SYSEXT_ROOT}"

KO_DESTDIR="${SYSEXT_ROOT}/usr/lib/modules/${KERN}/updates/i915"
COMPAT_DESTDIR="${SYSEXT_ROOT}/usr/lib/modules/${KERN}/updates/i915-sriov-compat"
RELEASE_DIR="${SYSEXT_ROOT}/usr/lib/extension-release.d"

mkdir -p "${KO_DESTDIR}"
mkdir -p "${RELEASE_DIR}"

cp "${OUTPUT_DIR}/i915.ko" "${KO_DESTDIR}/i915.ko"

# Include the compat module if it was produced (provides DRM/TTM symbols).
if [[ -f "${OUTPUT_DIR}/intel_sriov_compat.ko" ]]; then
  mkdir -p "${COMPAT_DESTDIR}"
  cp "${OUTPUT_DIR}/intel_sriov_compat.ko" "${COMPAT_DESTDIR}/intel_sriov_compat.ko"
fi

# extension-release file: ID=_any lets the sysext load on any OS image.
# To restrict to a specific Flatcar version, use ID=flatcar and VERSION_ID.
cat > "${RELEASE_DIR}/extension-release.i915-sriov" <<'EOF'
ID=_any
EOF

echo "  Tree:"
find "${SYSEXT_ROOT}" -type f | sed 's|^|    |'

# ---------------------------------------------------------------------------
# Step 5: Pack sysext root into a squashfs image via Docker
# ---------------------------------------------------------------------------
echo "[5/6] Creating squashfs image (via Docker alpine)..."

# Flatcar does not ship mksquashfs; use a throwaway alpine container.
# We do NOT need privileged — mksquashfs works as a regular process.
docker run --rm \
  -v "${SYSEXT_ROOT}:/input:ro" \
  -v "${WORKDIR}:/output" \
  alpine:latest \
  sh -c 'apk add --no-cache squashfs-tools -q \
    && mksquashfs /input "/output/'"${OUTPUT_RAW}"'" \
         -noappend \
         -comp xz \
         -no-progress \
    && echo "squashfs created: /output/'"${OUTPUT_RAW}"'"'

if [[ ! -f "${WORKDIR}/${OUTPUT_RAW}" ]]; then
  echo "ERROR: squashfs image was not created." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 6: Create convenience symlink and clean up intermediates
# ---------------------------------------------------------------------------
echo "[6/6] Creating symlink and cleaning up..."

cd "${WORKDIR}"
ln -sf "${OUTPUT_RAW}" "${LINK_RAW}"

# Remove the builder image to keep disk usage tidy; source is in the image
# layer so the next run re-downloads only if the tag changed.
docker image rm "${IMAGE_NAME}:${DKMS_VERSION}" 2>/dev/null || true

# Remove the intermediate directory — the .raw is the artefact.
rm -rf "${SYSEXT_ROOT}"
rm -rf "${OUTPUT_DIR}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Build complete ==="
RAW_SIZE="$(du -sh "${WORKDIR}/${OUTPUT_RAW}" | cut -f1)"
echo "  Image  : ${WORKDIR}/${OUTPUT_RAW}"
echo "  Symlink: ${WORKDIR}/${LINK_RAW}"
echo "  Size   : ${RAW_SIZE}"
echo ""
echo "Next steps:"
echo "  1. Copy to sysext drop-in:"
echo "     sudo cp ${LINK_RAW} /etc/extensions/i915-sriov.raw"
echo ""
echo "  2. Activate:"
echo "     sudo systemd-sysext refresh && sudo depmod -a"
echo ""
echo "  3. Verify:"
echo "     systemd-sysext status"
echo "     modinfo /usr/lib/modules/${KERN}/updates/i915/i915.ko"
