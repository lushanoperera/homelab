# i915-sriov-dkms Sysext for Flatcar VM 100

Packages the patched [i915-sriov-dkms](https://github.com/strongtz/i915-sriov-dkms) kernel module as a systemd-sysext image for Flatcar Container Linux. This enables Intel iGPU SR-IOV Virtual Function passthrough to VM 100 — the stock i915 driver cannot drive VFs (MMIO returns 0xFFFFFFFF).

## Prerequisites

- VM 100 running Flatcar (kernel >= 6.12 with `CONFIG_DRM_I915=m`)
- Kernel headers available at `/lib/modules/$(uname -r)/build/`
- Docker running on the VM
- VF allocated on Proxmox host (winston)

## Quick Start

### 1. Build (on VM)

```bash
# Copy build files to VM
scp Dockerfile build.sh entrypoint.sh core@192.168.100.100:~/i915-sriov/

# SSH to VM and build
ssh core@192.168.100.100
cd ~/i915-sriov
./build.sh
```

The build compiles the module inside a Docker container using bind-mounted kernel headers, then packages it as a squashfs sysext image.

Output: `i915-sriov-<kernel>-<dkms-version>.raw`

### 2. Deploy (from workstation)

```bash
# Copy the .raw to the VM and deploy configs
./deploy.sh
```

This copies the sysext image, config files, and systemd services to the VM.

### 3. Configure VF Passthrough (on Proxmox host)

```bash
ssh root@192.168.100.38
qm stop 100
qm set 100 -hostpci0 0000:00:02.1,x-vga=0,rombar=0,pcie=1
qm start 100
```

### 4. Test

```bash
./test-gpu.sh
```

Runs 25 TAP-format integration tests covering sysext activation, module loading, DRI devices, Docker GPU access, VAAPI, and regression checks.

## How It Works

```
Boot sequence:
  1. systemd-sysext.service merges /etc/extensions/i915-sriov.raw → /usr overlay
  2. i915-sriov-rebuild.service checks if module matches running kernel
     (rebuilds via Docker if kernel changed after Flatcar auto-update)
  3. gpu-setup.service:
     a. modprobe DRM dependencies (drm, ttm, intel-gtt, i2c-algo-bit, hwmon, etc.)
     b. insmod sysext i915.ko (uses explicit path, not modprobe, since depmod
        can't update indexes on Flatcar's read-only /lib/modules)
     c. udev trigger → verify-gpu.sh
```

Stock i915 is blacklisted in `/etc/modprobe.d/i915-blacklist.conf` to prevent udev from auto-loading it before sysext is ready. The gpu-setup.service explicitly loads the patched module via `insmod` after sysext activation.

## DKMS Version Compatibility

The DKMS tag must match the Flatcar kernel version:

| Flatcar Kernel | DKMS Tag    | Origin Kernel |
| -------------- | ----------- | ------------- |
| 6.12.x         | 2025.07.22  | 6.12          |
| 6.17.x+        | 2025.10.10+ | 6.17          |

Using a mismatched DKMS version causes `Unknown symbol` errors at module load time.

## Directory Structure

```
i915-sriov/
  build.sh              # Build orchestrator (runs on VM via Docker)
  Dockerfile            # Compile environment (Debian trixie, GCC 14)
  entrypoint.sh         # Container entrypoint: patch Makefile, compile, copy .ko
  deploy.sh             # SCP sysext to VM + activate + enable services
  test-gpu.sh           # 25 SSH-based integration tests (TAP format)
  README.md             # This file
  configs/
    modprobe/
      i915-blacklist.conf   # Prevent udev auto-loading stock i915
      i915-sriov.conf       # Module options (enable_guc=3)
    udev/
      70-dri-permissions.rules  # DRI device permissions
    systemd/
      gpu-setup.service             # Load patched i915 + verify
      i915-sriov-rebuild.service    # Auto-rebuild on kernel change
    scripts/
      verify-gpu.sh             # GPU health check (7 checks)
      i915-sriov-rebuild.sh     # Kernel mismatch rebuild logic
```

## Build Fixes Applied at Compile Time

The `entrypoint.sh` patches the DKMS Makefile before compiling:

1. **Remove kvmgt/xe targets** — we only need i915 for SR-IOV VF, not GVT-g or Xe
2. **Force conditional sources to i915-y** — `CONFIG_HWMON=m` (not `=y`) on Flatcar breaks the Makefile's `addprefix` logic; forcing `i915-$(CONFIG_*)` → `i915-y` ensures all sources get the correct path prefix

## Kernel Update Handling

Flatcar auto-updates can change the kernel. The `i915-sriov-rebuild.service` detects mismatches at boot:

1. Checks if `/usr/lib/modules/$(uname -r)/updates/i915/i915.ko` exists
2. If missing: rebuilds the sysext using cached Docker image + new kernel headers
3. Refreshes sysext before gpu-setup.service starts

## Rollback

```bash
# Remove VF passthrough (VM must be stopped)
ssh root@192.168.100.38 'qm stop 100 && qm set 100 -delete hostpci0 && qm start 100'

# Remove sysext from VM
ssh core@192.168.100.100 'sudo rm /etc/extensions/i915-sriov.raw && sudo systemd-sysext refresh'
```

## Troubleshooting

| Problem                         | Solution                                                                         |
| ------------------------------- | -------------------------------------------------------------------------------- |
| GCC version mismatch in build   | Dockerfile must use GCC >= 14 (Debian trixie) to match Flatcar's kernel compiler |
| `Unknown symbol` at insmod      | DKMS version doesn't match kernel — check table above                            |
| Module loads but no /dev/dri    | Check VF is passed through: `lspci \| grep VGA`                                  |
| Stock i915 loaded instead       | Check blacklist: `cat /etc/modprobe.d/i915-blacklist.conf`                       |
| depmod errors (read-only fs)    | Expected on Flatcar — gpu-setup uses insmod, not modprobe                        |
| MMIO 0xFFFFFFFF in dmesg        | Sysext module not loading — check `systemd-sysext status`                        |
| VM won't start after adding GPU | Remove: `qm set 100 -delete hostpci0`                                            |
| gpu-setup fails on restart      | Expected if module already loaded — will succeed on next boot                    |
