---
name: gpu-fix
description: Diagnose and fix SR-IOV GPU issues on Flatcar VM 100 - rebuild sysext, swap modules, re-enable containers
tools: Bash, Read
---

# GPU SR-IOV Fix

Diagnose and repair Intel iGPU SR-IOV on Flatcar VM 100. Covers the full chain: sysext build, module loading, and container GPU access.

## When to Use

- GPU broken after Flatcar kernel auto-update
- `verify-gpu.sh` failing
- Immich/Nextcloud containers lack `/dev/dri`
- `MMIO returns 0xFFFFFFFF` in dmesg
- `i915-sriov-rebuild.service` failed

## Instructions

### Phase 1: Diagnose

```bash
# Check current kernel
ssh core@192.168.100.100 'uname -r'

# Check if patched module exists for running kernel
ssh core@192.168.100.100 'ls /usr/lib/modules/$(uname -r)/updates/i915/i915.ko 2>/dev/null && echo "Patched module exists" || echo "MISSING - rebuild needed"'

# Check what i915 is loaded
ssh core@192.168.100.100 'cat /sys/module/i915/version 2>/dev/null || echo "No SR-IOV version (stock or not loaded)"'

# Check rebuild service status
ssh core@192.168.100.100 'systemctl status i915-sriov-rebuild.service --no-pager 2>/dev/null; systemctl status gpu-setup.service --no-pager 2>/dev/null'

# Run GPU verification
ssh core@192.168.100.100 '/opt/bin/verify-gpu.sh'
```

### Phase 2: Rebuild (if module missing)

```bash
# Build sysext for current kernel
ssh core@192.168.100.100 'cd /opt/i915-sriov-build && sudo ./build.sh $(uname -r) --dkms-version 2025.07.22'

# Deploy sysext
ssh core@192.168.100.100 'cd /opt/i915-sriov-build && sudo cp i915-sriov.raw /etc/extensions/i915-sriov.raw && sudo systemd-sysext refresh'
```

DKMS version mapping:

- Flatcar kernel 6.12.x ≤ 6.12.90 → `--dkms-version 2025.07.22`
- Flatcar kernel 6.12.91+ (e.g. 6.12.95) → `--dkms-version 2025.10.10` (ships `intel_sriov_compat.ko` — see Phase 3)
- Flatcar kernel 6.17.x+ → `--dkms-version 2025.10.10`

### Phase 3: Load Module

```bash
# Unload stock module (if loaded)
ssh core@192.168.100.100 'sudo rmmod i915 2>/dev/null; echo "Unloaded"'

# DKMS 2025.10.10+ builds a second module providing backport_* symbols — MUST load first,
# otherwise i915.ko fails with "Unknown symbol". Guarded no-op on older DKMS builds.
ssh core@192.168.100.100 'test -f /usr/lib/modules/$(uname -r)/updates/i915-sriov-compat/intel_sriov_compat.ko && sudo insmod /usr/lib/modules/$(uname -r)/updates/i915-sriov-compat/intel_sriov_compat.ko || echo "no compat module (pre-2025.10.10 DKMS)"'

# Load patched module
ssh core@192.168.100.100 'sudo insmod /usr/lib/modules/$(uname -r)/updates/i915/i915.ko enable_guc=3'

# Trigger udev for /dev/dri
ssh core@192.168.100.100 'sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=drm'

# Wait and verify
sleep 2
ssh core@192.168.100.100 '/opt/bin/verify-gpu.sh'
```

### Phase 4: Re-enable GPU in Containers

If GPU devices were commented out as a workaround:

```bash
# Immich - uncomment devices
ssh core@192.168.100.100 'cd /srv/docker/immich && sudo sed -i "s|^#    devices:|    devices:|; s|^#      - /dev/dri|      - /dev/dri|" docker-compose.yml && /opt/bin/docker-compose up -d'

# Nextcloud - uncomment devices
ssh core@192.168.100.100 'cd /srv/docker/nextcloud && sudo sed -i "s|^#    devices:|    devices:|; s|^#      - /dev/dri|      - /dev/dri|" docker-compose.yml && /opt/bin/docker-compose up -d'
```

### Phase 5: Verify Container GPU Access

```bash
ssh core@192.168.100.100 'docker exec immich_server ls /dev/dri/ && docker exec nextcloud-app ls /dev/dri/'
```

Expected: Both show `card0` and `renderD128`.

## Entrypoint Fix (if build itself fails)

If the build fails with kvmgt or Makefile errors, the `entrypoint.sh` may need updating:

```bash
# Sync entrypoint from repo to VM
scp vms/flatcar-media/sysext/i915-sriov/entrypoint.sh core@192.168.100.100:/opt/i915-sriov-build/entrypoint.sh
```

Key sed patches in entrypoint.sh:

1. `sed -i '/obj-m.*kvmgt/d' Makefile` — removes kvmgt build target
2. `sed -i '/obj-m.*drivers\/gpu\/drm\/xe/d' Makefile` — removes xe target
3. `sed -i 's/^i915-\$(CONFIG_.*)/i915-y/' Makefile` — fixes CONFIG_FOO=m breakage

## Output Format

```
## GPU Fix Report

### Diagnosis
- Kernel: [version]
- Patched module: [exists/missing]
- Loaded module: [stock/patched/none]

### Actions Taken
1. [action]
2. [action]

### Verification
- verify-gpu.sh: [X/7 pass]
- Immich GPU: [yes/no]
- Nextcloud GPU: [yes/no]

### Status
[Fixed / Partially fixed / Needs manual intervention]
```
