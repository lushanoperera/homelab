# Intel iGPU SR-IOV GPU Passthrough Guide

**Last Updated**: 2026-03-06
**Host**: Winston (192.168.100.38) — Proxmox VE 9.1.6
**Driver**: `i915-sriov-dkms/2025.10.10` on kernel `6.17.13-1-pve`

---

## Overview

This guide covers Intel iGPU SR-IOV Virtual Function (VF) assignment to LXC containers and VMs on the winston Proxmox host. 7 VFs are available (00:02.1–00:02.7).

### Current VF Allocation

| Consumer            | PCI Device   | Host Device        | Type             | Status  |
| ------------------- | ------------ | ------------------ | ---------------- | ------- |
| Plex (LXC 105)      | PF 00:02.0   | card0 / renderD128 | Privileged LXC   | Working |
| Nextcloud (LXC 101) | VF 1 00:02.2 | card2 / renderD130 | Unprivileged LXC | Working |
| Immich (LXC 103)    | VF 2 00:02.3 | card3 / renderD131 | Unprivileged LXC | Working |
| Immich ML (LXC 107) | PF 00:02.0   | card0 / renderD128 | Unprivileged LXC | Working |
| Flatcar (VM 100)    | VF 0 00:02.1 | card1 / renderD129 | VM (sysext)      | No consumer since 2026-08-25 |
| VF 0-6              | 00:02.1-7    | card4-7            | —                | Free    |

### What Works

- **Privileged LXCs** (e.g., Plex): PF or VF, just set `dev0`/`dev1` + cgroup rules. Symlinks auto-created.
- **Unprivileged LXCs** (e.g., Nextcloud, Immich): VFs only, requires udev rules + bind mounts (see below).

### Immich ML on LXC 107 (PF, no VF) — 2026-08-25

Immich machine learning moved from Flatcar VM 100 into unprivileged LXC 107 (`immich-ml`,
192.168.100.107). It shares the host PF render node exactly like Plex, so a Flatcar kernel update
cannot take it down. Immich server and Nextcloud on VM 100 no longer bind `/dev/dri` at all
(`immich-server` transcodes in software, Nextcloud never used the GPU).

- Create: `scripts/hosts/create-immich-ml-lxc.sh` (idempotent). Stack: `apps/immich-ml/`.
- Devices: `dev0: /dev/dri/renderD128,gid=992`, `dev1: /dev/dri/card0,gid=44`. Pass the **resolved**
  node path — a `by-path` path only creates `/dev/dri/by-path/...` inside the CT, and Docker
  `devices:` needs the real `renderD128`/`card0` names. `gid=` is the CT's own group id
  (Debian 13: `render` = 992, `video` = 44), not the host's (104).
- Rootfs on `local-lvm` (ext4 thin LVM), so Docker gets overlay2 without the ZFS-subvol pitfall.
  `local-lvm` needed `content images,rootdir` first (`pvesm set`).
- Verify GPU use: `intel_gpu_top` fails on the host (no i915 PMU with the SR-IOV module). Use
  `cat /sys/kernel/debug/dri/0/clients` during an ML job — the ML `python` process appears with
  uid 100000. The ML log must show `OpenVINOExecutionProvider` first.
- Wired from VM 100 via `IMMICH_MACHINE_LEARNING_URL=http://192.168.100.107:3003`.

### VM GPU Passthrough (Flatcar Sysext)

- **Flatcar VM 100**: Uses `i915-sriov-dkms` compiled as a systemd-sysext image. VF 0 (00:02.1) passed through via `hostpci0`. The stock kernel's i915 cannot drive VFs (`MMIO returns 0xFFFFFFFF`) — the sysext overlays the patched module onto `/usr`.
- **Build/deploy/test**: See `vms/flatcar-media/sysext/i915-sriov/`
- **Auto-rebuild**: `i915-sriov-rebuild.service` detects kernel changes after Flatcar updates and rebuilds the sysext via Docker.

---

## Prerequisites

### Proxmox Host Requirements

1. **SR-IOV Enabled**: Virtual Functions must be created on Proxmox host
   - Check with: `lspci | grep "00:02.[1-7].*VGA"`
   - Should see 7 VGA devices (00:02.1 through 00:02.7)
   - See: `docs/sr-iov/igpu-guide.md`

2. **VF 0 Available**: Ensure VF 0 (00:02.1) is not assigned to another VM/LXC

   ```bash
   # On Proxmox host
   grep -rl "00:02.1" /etc/pve/qemu-server/ /etc/pve/lxc/ 2>/dev/null
   ```

3. **VM Stopped**: VM 100 must be stopped for PCI passthrough configuration
   ```bash
   # On Proxmox host
   qm status 100
   ```

---

## Deployment Steps

### Phase 0: Build i915-sriov Sysext (on VM)

Before configuring PCI passthrough, build and deploy the patched i915 module as a sysext:

```bash
# Build on VM (compiles via Docker, packages as squashfs sysext)
ssh core@192.168.100.100 'cd ~/i915-sriov-build && ./build.sh'

# Deploy from workstation (copies sysext + configs + enables services)
cd vms/flatcar-media/sysext/i915-sriov
./deploy.sh
```

See `vms/flatcar-media/sysext/i915-sriov/README.md` for full details.

### Phase 1: Proxmox Host Configuration

**Important**: These steps must be performed on the Proxmox host via SSH.

#### Step 1: Verify VF 0 Availability

```bash
# SSH to Proxmox host
ssh root@<PROXMOX_IP>

# Check if VF 0 exists
lspci | grep "00:02.1"
```

**Expected Output**:

```
00:02.1 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)
```

#### Step 2: Stop VM 100

```bash
qm stop 100
```

Wait for VM to fully stop:

```bash
qm status 100
# Should show: status: stopped
```

#### Step 3: Add VF 0 to VM Configuration

```bash
qm set 100 -hostpci0 0000:00:02.1,x-vga=0,rombar=0,pcie=1
```

**Parameter Explanation**:

- `0000:00:02.1` - PCI address of VF 0
- `x-vga=0` - Not primary display (headless GPU)
- `rombar=0` - Disable ROM BAR (required for Intel iGPU VFs)
- `pcie=1` - Enable PCIe mode (required for Q35 machine type)

#### Step 4: Verify Configuration

```bash
qm config 100 | grep hostpci
```

**Expected Output**:

```
hostpci0: 0000:00:02.1,pcie=1,rombar=0,x-vga=0
```

#### Step 5: Start VM

```bash
qm start 100
```

Monitor startup:

```bash
qm status 100
# Wait for: status: running
```

---

### Phase 2: Verify GPU Passthrough Inside VM

**Important**: These steps are performed inside the Flatcar VM via SSH.

#### Step 1: SSH to VM

```bash
ssh core@192.168.100.100
```

#### Step 2: Check PCI Device

```bash
lspci | grep VGA
```

**Expected Output**:

```
00:06.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)
```

**Note**: PCI address may differ inside VM (e.g., 00:06.0 instead of 00:02.1).

#### Step 3: Check DRI Device

```bash
ls -la /dev/dri/
```

**Expected Output**:

```
total 0
drwxr-xr-x  2 root root         80 Oct 11 10:00 .
drwxr-xr-x 16 root root       3280 Oct 11 10:00 ..
crw-rw----  1 root video  226,   0 Oct 11 10:00 card0
crw-rw----  1 root render 226, 128 Oct 11 10:00 renderD128
```

**Note**: The device may be `renderD128` (first VF) or `renderD132` depending on kernel enumeration.

#### Step 4: Run GPU Verification Script

```bash
/opt/bin/verify-gpu.sh
```

**Expected Output**:

```
=== Intel iGPU VF 0 Verification ===

Checking PCI device (0000:00:02.1)...
✓ PCI device found
00:06.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics]

Checking DRI device (/dev/dri/renderD132)...
✓ DRI device exists
crw-rw---- 1 root render 226, 128 Oct 11 10:00 /dev/dri/renderD128

Checking device permissions...
✓ Device is readable

=== GPU Passthrough Status: READY ===

To use in Docker containers, add:
  devices:
    - /dev/dri/renderD132:/dev/dri/renderD132
```

#### Step 5: Check GPU Setup Service

```bash
sudo systemctl status gpu-setup.service
```

**Expected Output**:

```
● gpu-setup.service - Setup Intel iGPU VF 0 for Docker
     Loaded: loaded (/etc/systemd/system/gpu-setup.service; enabled; preset: enabled)
     Active: active (exited) since ...
    Process: ... ExecStartPre=/usr/bin/udevadm control --reload-rules (code=exited, status=0/SUCCESS)
    Process: ... ExecStartPre=/usr/bin/udevadm trigger --subsystem-match=drm (code=exited, status=0/SUCCESS)
    Process: ... ExecStart=/opt/bin/verify-gpu.sh (code=exited, status=0/SUCCESS)
```

---

### Phase 3: Test GPU in Docker Container

#### Test 1: Verify Device Accessibility

```bash
docker run --rm --device=/dev/dri/renderD128 alpine:latest ls -la /dev/dri/renderD128
```

**Expected Output**:

```
crw-rw---- 1 root 226, 128 Oct 11 10:00 /dev/dri/renderD128
```

#### Test 2: Test VAAPI Support (Optional)

```bash
docker run --rm --device=/dev/dri/renderD128 jrottenberg/ffmpeg:4-vaapi vainfo
```

**Expected Output**:
Should show Intel iHD driver information and supported codec profiles.

---

## Using GPU in Docker Compose

### Example Configuration

To use the GPU in your media stack or other containers, add the following to your `docker-compose.yml`:

```yaml
services:
  your-service:
    image: your-image:latest
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128 # Adjust device name if different
    # Optional: Add environment variables for VAAPI
    environment:
      - LIBVA_DRIVER_NAME=iHD
      - VAAPI_DEVICE=/dev/dri/renderD128
```

### Media Transcoding Example (Jellyfin/Plex)

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
    environment:
      - LIBVA_DRIVER_NAME=iHD
    volumes:
      - /mnt/media:/media
    ports:
      - "8096:8096"
    restart: unless-stopped
```

---

## Troubleshooting

### Problem: No DRI Device Found

**Symptoms**:

```bash
ls /dev/dri/
# Returns: No such file or directory
```

**Solutions**:

1. **Check PCI Passthrough**:

   ```bash
   lspci | grep VGA
   ```

   - If no VGA device, check Proxmox host configuration
   - Verify `qm config 100` shows hostpci0

2. **Check Kernel Modules**:

   ```bash
   lsmod | grep i915
   ```

   - Should show i915 module loaded
   - If not: `sudo modprobe i915`

3. **Check udev**:
   ```bash
   sudo udevadm trigger --subsystem-match=drm
   sudo systemctl restart gpu-setup.service
   ```

### Problem: Device Permission Denied

**Symptoms**:

```bash
docker run --rm --device=/dev/dri/renderD128 alpine:latest ls /dev/dri/renderD128
# Returns: Permission denied
```

**Solutions**:

1. **Check Device Permissions**:

   ```bash
   ls -la /dev/dri/renderD128
   ```

   - Should show: `crw-rw---- 1 root render`

2. **Add User to Render Group**:

   ```bash
   sudo usermod -aG render core
   # Logout and login again
   ```

3. **Reload udev Rules**:
   ```bash
   sudo udevadm control --reload-rules
   sudo udevadm trigger --subsystem-match=drm
   ```

### Problem: Wrong Device Number

**Symptoms**:

- Verification script looks for renderD132 but device is renderD128

**Solution**:

- The device number may vary based on kernel enumeration
- Use whichever renderD device is available (128, 129, 130, etc.)
- Update verification script and docker-compose files accordingly

### Problem: VM Won't Start After Adding GPU

**Symptoms**:

```bash
qm start 100
# Returns: Error or VM fails to start
```

**Solutions**:

1. **Check VF Availability on Host**:

   ```bash
   # On Proxmox host
   lspci | grep "00:02.1"
   ```

   - Ensure VF exists on host

2. **Check IOMMU Groups**:

   ```bash
   # On Proxmox host
   find /sys/kernel/iommu_groups/ -type l | grep 00:02.1
   ```

3. **Remove and Re-add PCI Device**:

   ```bash
   # On Proxmox host
   qm set 100 -delete hostpci0
   qm set 100 -hostpci0 0000:00:02.1,x-vga=0,rombar=0,pcie=1
   ```

4. **Check Proxmox Logs**:
   ```bash
   # On Proxmox host
   journalctl -u qemu-server@100 -n 50
   ```

---

## Configuration Files

### Butane Configuration

- **Location**: `configs/flatcar-proxmox-100-docker.bu`
- **Compiled To**: `ignition/flatcar-proxmox-100-docker.ign`

### Added Components

1. **Kernel Modules** (`/etc/modules-load.d/drm.conf`)
   - Loads `drm` and `i915` modules at boot

2. **Udev Rules** (`/etc/udev/rules.d/70-dri-permissions.rules`)
   - Sets permissions for DRI devices
   - Grants render group access

3. **Verification Script** (`/opt/bin/verify-gpu.sh`)
   - Checks PCI device availability
   - Verifies DRI device existence
   - Tests permissions

4. **Systemd Service** (`gpu-setup.service`)
   - Reloads udev rules at boot
   - Triggers DRM subsystem
   - Runs verification script

---

## Important Notes

### Ignition Configuration

**WARNING**: Flatcar Container Linux applies Ignition configuration **ONLY on first boot**.

To apply this GPU configuration to an existing VM:

1. **Option A: Recreate VM** (Recommended)
   - Destroy existing VM 100
   - Create new VM with updated Ignition config
   - Lost: All VM state, containers, data

2. **Option B: Manual Configuration**
   - SSH to VM
   - Manually create files from Butane config
   - Enable and start systemd services
   - Preserves: All VM state and data

### Device Naming

- **Host PCI**: Always `0000:00:02.1`
- **VM PCI**: May differ (e.g., `00:06.0`)
- **DRI Device**: Depends on kernel enumeration
  - First VF usually: `renderD128`
  - May be: `renderD129`, `renderD130`, etc.
  - Use `ls /dev/dri/` to identify actual device

### Performance Expectations

**Hardware Transcoding** (Jellyfin/Plex/Emby):

- **4K HEVC → 1080p H.264**: 120-150 FPS
- **Concurrent Streams**: 3-5 simultaneous 4K transcodes
- **Power Usage**: 5-10W (vs 40-60W CPU transcoding)

**Encoding Quality**:

- Similar to x264 "fast" preset
- QuickSync (QSV) hardware encoder

---

## Verification Checklist

Before considering deployment complete, verify:

- [ ] VF 0 visible on Proxmox host: `lspci | grep "00:02.1"`
- [ ] VM 100 has hostpci0 configured: `qm config 100 | grep hostpci`
- [ ] VM boots successfully after adding GPU
- [ ] PCI device visible inside VM: `lspci | grep VGA`
- [ ] DRI device exists: `ls /dev/dri/`
- [ ] GPU verification script passes: `/opt/bin/verify-gpu.sh`
- [ ] Docker can access device: `docker run --rm --device=/dev/dri/renderD128 alpine ls /dev/dri/`
- [ ] VAAPI test successful (optional): Test with ffmpeg container

---

## Reference Documentation

### Proxmox SR-IOV Setup

- **Location**: `docs/sr-iov/`
- **Key File**: `igpu-guide.md`
- Contains complete SR-IOV setup for Proxmox host

### Flatcar Documentation

- **Official Docs**: https://www.flatcar.org/docs/latest/
- **Ignition Spec**: https://coreos.github.io/ignition/
- **Butane Spec**: https://coreos.github.io/butane/

### Intel SR-IOV

- **Device Mapping**: See MS-01-Config-Reference.md lines 682-691
- **VF to renderD mapping**: renderD128-135 (VF 0-6)

---

## Quick Command Reference

### Proxmox Host Commands

```bash
# Check VF availability
lspci | grep "00:02.[1-7].*VGA"

# Stop VM
qm stop 100

# Add GPU passthrough
qm set 100 -hostpci0 0000:00:02.1,x-vga=0,rombar=0,pcie=1

# Remove GPU passthrough
qm set 100 -delete hostpci0

# Start VM
qm start 100

# Check VM status
qm status 100

# View VM config
qm config 100
```

### Flatcar VM Commands

```bash
# Check PCI devices
lspci | grep VGA

# List DRI devices
ls -la /dev/dri/

# Run verification script
/opt/bin/verify-gpu.sh

# Check GPU service status
sudo systemctl status gpu-setup.service

# Check service logs
sudo journalctl -u gpu-setup.service

# Reload GPU setup
sudo systemctl restart gpu-setup.service

# Check kernel modules
lsmod | grep i915

# Reload udev
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=drm
```

### Docker Commands

```bash
# Test GPU access
docker run --rm --device=/dev/dri/renderD128 alpine:latest ls -la /dev/dri/

# Test VAAPI (requires ffmpeg image)
docker run --rm --device=/dev/dri/renderD128 jrottenberg/ffmpeg:4-vaapi vainfo

# Check container GPU usage (requires intel-gpu-tools in container)
docker exec <container> intel_gpu_top
```

---

## Next Steps

1. **Deploy Configuration** (follow Phase 1-3 above)
2. **Update Media Stack** (`/srv/docker/media-stack/docker-compose.yml`)
   - Add GPU device passthrough to transcoding services
3. **Configure Applications**
   - Jellyfin: Dashboard → Playback → Hardware Acceleration
   - Plex: Settings → Transcoder → Hardware Acceleration
4. **Monitor Performance**
   - Check GPU utilization during transcoding
   - Verify reduced CPU usage

---

**Deployment Complete!** The Intel iGPU VF 0 is now available for hardware-accelerated workloads in Docker containers.
