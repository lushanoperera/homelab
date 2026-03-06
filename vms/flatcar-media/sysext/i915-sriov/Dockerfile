# i915-sriov-dkms builder
#
# This image is built on Flatcar VM 100. It contains all build dependencies but
# NOT the kernel headers — those are bind-mounted from the host at runtime so the
# compiled module always matches the running kernel.
#
# Usage (via build.sh, not directly):
#   docker build -t i915-sriov-builder .
#   docker run --rm \
#     -v /lib/modules/${KERNEL_VERSION}:/host-modules:ro \
#     -v $(pwd)/output:/output \
#     i915-sriov-builder ${DKMS_VERSION}
#
# The entrypoint clones the repo and compiles; output lands in /output/i915.ko.

FROM debian:trixie-slim

ARG KERNEL_VERSION=6.12.66-flatcar
ARG DKMS_VERSION=2025.07.22

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    bc \
    flex \
    bison \
    libelf-dev \
    libssl-dev \
    kmod \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone the patched i915 source at the requested tag.
# The clone happens at image build time so the layer is cached.
# If you need a different DKMS_VERSION, rebuild with --build-arg.
RUN git clone --depth 1 --branch ${DKMS_VERSION} \
      https://github.com/strongtz/i915-sriov-dkms.git \
    && echo "Cloned i915-sriov-dkms @ ${DKMS_VERSION}"

# Entrypoint script: compile against bind-mounted host headers.
# Accepts the DKMS_VERSION as $1 so the same image can recompile
# against a different kernel without rebuilding the image.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# /host-modules is expected to be bind-mounted from the host at container run time:
#   -v /lib/modules/${KERNEL_VERSION}:/host-modules:ro
VOLUME ["/host-modules", "/output"]

ENTRYPOINT ["/entrypoint.sh"]
