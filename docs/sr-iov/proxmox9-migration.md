# Proxmox 9.0 SR-IOV Migration Guide for MS-01

**Last Updated**: 2025-10-11
**Your System**: Proxmox VE 9.0.10, Kernel 6.14.11-3-pve
**Hardware**: Minisforum MS-01 with Intel i9-13900H

---

## Your Current Configuration Analysis

Based on your system information:

```
Proxmox VE: 9.0.10
Kernel: 6.14.11-3-pve (current) + 6.8.12-15-pve (installed)
Bootloader: GRUB
Kernel params: quiet (only)
Modules: i915 + xe (BOTH LOADED - CONFLICT!)
SR-IOV VFs: 0 (not configured)
DKMS: Not installed
GPU: 00:02.0 Intel Iris Xe (physical only, no VFs)
Groups: video=44, render=104
```

### Current Plex Container Setup

- Container ID: 105
- Using physical GPU: `/dev/dri/by-path/pci-0000:00:02.0-card`
- Device mapping: GID 44 (video), GID 104 (render)
- Privileged container
- Working hardware transcoding ✅

---

## Migration Strategy

### Phase 1: Preparation (No Downtime)

1. Install prerequisites
2. Blacklist xe module
3. Configure GRUB kernel parameters
4. Install i915-sriov-dkms

### Phase 2: Enable SR-IOV (Requires Reboot)

1. Reboot with new kernel parameters
2. Verify VFs created
3. Test with existing Plex container

### Phase 3: Migrate Plex to VF (Brief Downtime)

1. Stop Plex container
2. Update device mappings to use VF
3. Start container and verify

---

## Step-by-Step Migration

### Step 1: Install Prerequisites

```bash
# Install DKMS and build tools
apt update
apt install -y dkms build-essential pve-headers-$(uname -r) intel-gpu-tools

# Verify installation
dkms --version
gcc --version
```

### Step 2: Hold Kernel Packages (Prevent 6.8.x Issues)

Even though you're on 6.14.x, let's prevent accidental downgrades:

```bash
# Hold current kernel
apt-mark hold proxmox-kernel-6.14.11-3-pve-signed

# Optional: Remove problematic 6.8.x kernels (after testing 6.14.x works)
# apt remove proxmox-kernel-6.8.12-15-pve-signed proxmox-kernel-6.8.12-4-pve-signed
```

### Step 3: Blacklist xe Driver

**CRITICAL**: Both i915 and xe are currently loaded. xe conflicts with SR-IOV.

```bash
# Create blacklist file
cat > /etc/modprobe.d/blacklist-xe.conf << 'EOF'
# Blacklist xe driver - conflicts with i915 SR-IOV
blacklist xe
install xe /bin/false
EOF

# Verify file created
cat /etc/modprobe.d/blacklist-xe.conf
```

### Step 4: Configure GRUB Kernel Parameters

Since you're using GRUB (not systemd-boot):

```bash
# Backup current GRUB config
cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d)

# Edit GRUB configuration
nano /etc/default/grub
```

**Change this line**:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
```

**To this**:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe"
```

**Save and exit** (Ctrl+X, Y, Enter)

**Update GRUB**:

```bash
update-grub

# Verify the change
grep CMDLINE /etc/default/grub
```

### Step 5: Install i915-sriov-dkms

```bash
# Download latest release (check GitHub for newest version)
cd /tmp
wget https://github.com/strongtz/i915-sriov-dkms/releases/latest/download/i915-sriov-dkms_2025.10.10_all.deb

# Install the package
dpkg -i i915-sriov-dkms_*.deb

# Verify DKMS installation
dkms status
```

**Expected output**:

```
i915-sriov-dkms/2025.10.10, 6.14.11-3-pve, x86_64: installed
```

### Step 6: Configure Persistent VFs

```bash
# Create sysfs configuration
cat > /etc/sysfs.conf << 'EOF'
# Intel iGPU SR-IOV Virtual Functions
devices/pci0000:00/0000:00:02.0/sriov_numvfs = 7
EOF

# Verify file created
cat /etc/sysfs.conf
```

### Step 7: Update initramfs

```bash
update-initramfs -u -k all
```

---

## Reboot and Verify

### Step 8: Reboot System

```bash
# Reboot to apply changes
reboot
```

### Step 9: Verify SR-IOV After Reboot

```bash
# 1. Check kernel parameters
cat /proc/cmdline
# Should show: intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe

# 2. Verify xe is NOT loaded
lsmod | grep xe
# Should return NOTHING (xe should be blacklisted)

# 3. Verify i915 is loaded
lsmod | grep i915
# Should show i915 module

# 4. Check VGA devices (should see 8: 1 physical + 7 VFs)
lspci | grep VGA

# 5. Verify VF count
cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs
# Should return: 7

# 6. Check render devices
ls -la /dev/dri/
# Should show: renderD128, renderD129, renderD130, renderD131, renderD132, renderD133, renderD134, renderD135

# 7. List devices by path
ls -la /dev/dri/by-path/
# Should show multiple pci-0000:00:02.X-render devices

# 8. Monitor GPU
intel_gpu_top -l
# Should list all GPU devices
```

**Expected VF Mapping**:

| VF #     | PCI Address | Card Device | Render Device | By-Path                 |
| -------- | ----------- | ----------- | ------------- | ----------------------- |
| Physical | 00:02.0     | card0       | renderD128    | pci-0000:00:02.0-render |
| VF 0     | 00:02.1     | card1       | renderD129    | pci-0000:00:02.1-render |
| VF 1     | 00:02.2     | card2       | renderD130    | pci-0000:00:02.2-render |
| VF 2     | 00:02.3     | card3       | renderD131    | pci-0000:00:02.3-render |
| VF 3     | 00:02.4     | card4       | renderD132    | pci-0000:00:02.4-render |
| VF 4     | 00:02.5     | card5       | renderD133    | pci-0000:00:02.5-render |
| VF 5     | 00:02.6     | card6       | renderD134    | pci-0000:00:02.6-render |
| VF 6     | 00:02.7     | card7       | renderD135    | pci-0000:00:02.7-render |

---

## Migrate Plex Container to VF

### Step 10: Update Plex Container Configuration

**Current configuration** (using physical GPU):

```bash
dev0: /dev/dri/by-path/pci-0000:00:02.0-card,gid=44
dev1: /dev/dri/by-path/pci-0000:00:02.0-render,gid=104
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
```

**Stop Plex container**:

```bash
pct stop 105
```

**Edit container configuration**:

```bash
nano /etc/pve/lxc/105.conf
```

**Option A: Keep using by-path (recommended for stability)**

Replace these lines:

```bash
dev0: /dev/dri/by-path/pci-0000:00:02.0-card,gid=44
dev1: /dev/dri/by-path/pci-0000:00:02.0-render,gid=104
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
```

With (using VF 0):

```bash
# Assign VF 0 to Plex
dev0: /dev/dri/by-path/pci-0000:00:02.1-card,gid=44
dev1: /dev/dri/by-path/pci-0000:00:02.1-render,gid=104
lxc.cgroup2.devices.allow: c 226:1 rwm
lxc.cgroup2.devices.allow: c 226:129 rwm
```

**Option B: Direct device reference**

```bash
# Remove old dev0/dev1 lines and add:
lxc.cgroup2.devices.allow: c 226:129 rwm
lxc.mount.entry: /dev/dri/renderD129 dev/dri/renderD129 none bind,optional,create=file
```

**Save and exit** (Ctrl+X, Y, Enter)

**Start Plex container**:

```bash
pct start 105
```

### Step 11: Verify Plex Hardware Acceleration

```bash
# Enter container
pct enter 105

# Check GPU device
ls -la /dev/dri/

# Test VA-API
vainfo --display drm --device /dev/dri/renderD129

# Exit container
exit
```

**On Proxmox host, monitor GPU usage**:

```bash
# Monitor VF 0 (Plex)
intel_gpu_top --device /dev/dri/renderD129
```

Start a transcode in Plex and watch GPU utilization increase.

---

## Add Additional Containers

Now that SR-IOV is working, you can add more containers with GPU acceleration.

### Example: Add Jellyfin Container with VF 1

**Create Jellyfin container** (via Proxmox web UI or CLI)

**Edit Jellyfin container config**:

```bash
nano /etc/pve/lxc/[JELLYFIN_CTID].conf
```

**Add these lines**:

```bash
# Assign VF 1 to Jellyfin
features: nesting=1
unprivileged: 0

# Use by-path for stability
dev0: /dev/dri/by-path/pci-0000:00:02.2-card,gid=44
dev1: /dev/dri/by-path/pci-0000:00:02.2-render,gid=104
lxc.cgroup2.devices.allow: c 226:2 rwm
lxc.cgroup2.devices.allow: c 226:130 rwm

# Framebuffer (optional)
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file
```

**Container allocation strategy**:

- Container 105 (Plex): VF 0 (renderD129)
- Container 106 (Jellyfin): VF 1 (renderD130)
- Container 107 (Emby): VF 2 (renderD131)
- VM 200 (Windows 11): VF 3 (00:02.4)
- etc.

---

## Troubleshooting

### Issue: VFs Not Created After Reboot

```bash
# Check kernel parameters
cat /proc/cmdline | grep i915

# Manually create VFs
echo 7 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# Check dmesg for errors
dmesg | grep i915 | tail -30
```

### Issue: xe Module Still Loading

```bash
# Check if xe is loaded
lsmod | grep xe

# If loaded, remove it
modprobe -r xe

# Rebuild initramfs
update-initramfs -u -k all

# Reboot
reboot
```

### Issue: DKMS Module Not Building

```bash
# Check DKMS status
dkms status

# Reinstall
dkms remove i915-sriov-dkms --all
cd /tmp
wget https://github.com/strongtz/i915-sriov-dkms/releases/latest/download/i915-sriov-dkms_*.deb
dpkg -i i915-sriov-dkms_*.deb

# Check build logs
dmesg | grep i915
```

### Issue: Plex Transcoding Not Using GPU

```bash
# Enter container
pct enter 105

# Check device access
ls -la /dev/dri/

# Test VA-API
vainfo

# Check Plex logs
tail -f /var/lib/plexmediaserver/Library/Application\ Support/Plex\ Media\ Server/Logs/Plex\ Transcoder\ Statistics.log
```

---

## Performance Monitoring

### Monitor Multiple VFs Simultaneously

```bash
# Terminal 1: Plex (VF 0)
watch -n 1 'intel_gpu_top --device /dev/dri/renderD129 | head -20'

# Terminal 2: Jellyfin (VF 1)
watch -n 1 'intel_gpu_top --device /dev/dri/renderD130 | head -20'

# Terminal 3: Overall system
htop
```

### Expected Performance

- **Single 4K HEVC → 1080p H.264**: 120-150 FPS
- **Concurrent 4K transcodes**: 3-5 streams per VF
- **Power consumption**: +5-10W vs physical GPU passthrough
- **Latency**: No noticeable difference

---

## Rollback Procedure (If Needed)

### Quick Rollback

```bash
# 1. Stop all containers using VFs
pct stop 105

# 2. Edit Plex config back to physical GPU
nano /etc/pve/lxc/105.conf
# Change back to: dev1: /dev/dri/by-path/pci-0000:00:02.0-render,gid=104

# 3. Remove SR-IOV configuration
echo 0 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# 4. Edit GRUB back
nano /etc/default/grub
# Change to: GRUB_CMDLINE_LINUX_DEFAULT="quiet"

# 5. Update GRUB
update-grub

# 6. Reboot
reboot

# 7. Start Plex
pct start 105
```

---

## Kernel 6.14.x Compatibility Notes

Your kernel (6.14.11-3-pve) is **newer than documented** in most SR-IOV guides. Based on the i915-sriov-dkms repository:

- **Supported kernel versions**: 6.12.19 ~ 6.17.x ✅
- **Your kernel**: 6.14.11-3-pve ✅ **SUPPORTED**

However, be aware:

- This is newer than the community-tested 6.5.x kernels
- The DKMS module supports it according to the GitHub repo
- If you encounter issues, you can boot into kernel 6.8.12-15 (though 6.8.x has known SR-IOV issues) or wait for community feedback on 6.14.x

### Recommended Approach

1. Try SR-IOV on 6.14.11-3-pve first (should work per DKMS docs)
2. If issues occur, document them and potentially test with an older kernel
3. Report any issues to the i915-sriov-dkms GitHub repo

---

## Next Steps After Migration

### Expand Your Setup

- Add Jellyfin (VF 1)
- Add Emby (VF 2)
- Add Frigate for NVR (VF 3)
- Add Windows 11 VM for testing (VF 4)

### Monitor and Optimize

- Set up monitoring dashboards
- Tune transcoding settings per application
- Monitor VRAM usage across VFs
- Document performance metrics

---

## Summary Checklist

- [ ] Prerequisites installed (DKMS, build-essential, headers)
- [ ] xe module blacklisted
- [ ] GRUB kernel parameters configured
- [ ] i915-sriov-dkms installed
- [ ] sysfs.conf created
- [ ] System rebooted
- [ ] 7 VFs created and visible
- [ ] Plex container migrated to VF
- [ ] Hardware transcoding verified
- [ ] Monitoring tools configured
- [ ] Performance baseline documented

---

**Your System Specifics**:

- Bootloader: GRUB (update via `update-grub`)
- Kernel: 6.14.11-3-pve (supported by DKMS)
- Groups: video=44, render=104
- Current Plex: Container 105 on physical GPU
- Target: Container 105 on VF 0 (renderD129)

**Estimated Downtime**: ~10 minutes (single reboot + container reconfiguration)
