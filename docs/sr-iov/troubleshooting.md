# MS-01 iGPU SR-IOV Troubleshooting Guide

**Last Updated**: 2025-10-11
**Hardware**: Minisforum MS-01 with Intel i9-13900H
**Target**: Proxmox VE SR-IOV Issues

---

## Table of Contents

1. [Kernel 6.8.x Issues](#kernel-68x-issues)
2. [DKMS Compilation Failures](#dkms-compilation-failures)
3. [Virtual Functions Not Creating](#virtual-functions-not-creating)
4. [BIOS/IOMMU Issues](#biosiommu-issues)
5. [VM/LXC Configuration Problems](#vmlxc-configuration-problems)
6. [Performance Issues](#performance-issues)
7. [Secure Boot Issues](#secure-boot-issues)
8. [Driver Conflicts](#driver-conflicts)
9. [System Stability Issues](#system-stability-issues)
10. [Recovery Procedures](#recovery-procedures)

---

## Critical: Kernel 6.8.x Issues

### Problem: DKMS Fails to Build on Kernel 6.8.x

**Symptoms**:

- DKMS compilation errors during `apt upgrade`
- Error messages mentioning "too many arguments to function pm_runtime_get_if_active"
- Virtual functions not created after upgrading to kernel 6.8.12-x-pve

**Cause**:
Kernel 6.8.x introduced API changes that break i915-sriov-dkms compilation. Multiple GitHub issues document these problems.

**Solution**: Downgrade to Kernel 6.5.x

#### Step 1: Check Available Kernels

```bash
dpkg --list | grep pve-kernel
```

#### Step 2: Install Kernel 6.5.13-3-pve (if not present)

```bash
apt install pve-kernel-6.5.13-3-pve pve-headers-6.5.13-3-pve
```

If not available in repositories, download from Proxmox archives:

```bash
cd /tmp
wget http://download.proxmox.com/debian/pve/dists/bookworm/pve-no-subscription/binary-amd64/pve-kernel-6.5.13-3-pve_6.5.13-3_amd64.deb
wget http://download.proxmox.com/debian/pve/dists/bookworm/pve-no-subscription/binary-amd64/pve-headers-6.5.13-3-pve_6.5.13-3_amd64.deb
dpkg -i pve-kernel-6.5.13-3-pve*.deb pve-headers-6.5.13-3-pve*.deb
```

#### Step 3: Set Kernel 6.5.13 as Default

```bash
proxmox-boot-tool kernel pin 6.5.13-3-pve
```

#### Step 4: Update GRUB

```bash
update-grub
proxmox-boot-tool refresh
```

#### Step 5: Reboot

```bash
reboot
```

#### Step 6: Verify Kernel

```bash
uname -r
```

**Expected Output**: `6.5.13-3-pve`

#### Step 7: Rebuild DKMS for 6.5.13

```bash
dkms install -m i915-sriov-dkms -v $(dkms status | grep i915-sriov | cut -d',' -f2 | cut -d':' -f1 | tr -d ' ') -k 6.5.13-3-pve
```

#### Step 8: Remove Old 6.8.x Kernel (Optional)

```bash
apt remove pve-kernel-6.8*
apt autoremove
```

### Prevent Future Kernel Upgrades

#### Option 1: Hold Kernel Packages

```bash
apt-mark hold pve-kernel-6.5.13-3-pve pve-headers-6.5.13-3-pve
```

#### Option 2: Exclude in APT Configuration

```bash
echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/99-no-kernel-upgrade
echo 'APT::Get::AllowUnauthenticated "0";' >> /etc/apt/apt.conf.d/99-no-kernel-upgrade
echo 'Package: pve-kernel-6.8*' > /etc/apt/preferences.d/no-kernel-68
echo 'Pin: release *' >> /etc/apt/preferences.d/no-kernel-68
echo 'Pin-Priority: -1' >> /etc/apt/preferences.d/no-kernel-68
```

---

## DKMS Compilation Failures

### Problem: DKMS Module Fails to Build

**Symptoms**:

```
Error! Build of i915-sriov-dkms/2025.10.10 for kernel 6.x.x (x86_64) failed
```

### Solution 1: Install Build Dependencies

```bash
apt install -y build-essential dkms git pve-headers-$(uname -r)
```

### Solution 2: Clean and Reinstall DKMS Module

```bash
# Remove existing module
dkms remove i915-sriov-dkms/$(dkms status | grep i915-sriov | cut -d',' -f2 | cut -d':' -f1 | tr -d ' ') --all

# Clean up
rm -rf /var/lib/dkms/i915-sriov-dkms
rm -rf /usr/src/i915-sriov-dkms*

# Reinstall from .deb
cd /tmp
wget https://github.com/strongtz/i915-sriov-dkms/releases/latest/download/i915-sriov-dkms_*.deb
dpkg -i i915-sriov-dkms_*.deb

# Verify
dkms status
```

### Solution 3: Check Kernel Headers Match

```bash
dpkg --list | grep pve-headers
dpkg --list | grep pve-kernel
```

Ensure headers version matches kernel version. If mismatch:

```bash
apt install pve-headers-$(uname -r)
```

---

## Virtual Functions Not Creating

### Problem: No VFs Appear After Reboot

**Symptoms**:

```bash
lspci | grep VGA
# Only shows one device (00:02.0)

cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs
# Returns: 0
```

### Solution 1: Verify Kernel Parameters

```bash
cat /proc/cmdline
```

Must include: `intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7`

If missing, re-edit `/etc/default/grub` and run:

```bash
update-grub
proxmox-boot-tool refresh
reboot
```

### Solution 2: Manually Create VFs

```bash
echo 7 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs
```

Then verify:

```bash
lspci | grep VGA
```

If this works, check `/etc/sysfs.conf`:

```bash
cat /etc/sysfs.conf
```

Should contain:

```
devices/pci0000:00/0000:00:02.0/sriov_numvfs = 7
```

### Solution 3: Check DKMS Module Loading

```bash
lsmod | grep i915
dmesg | grep i915 | tail -20
```

Look for errors. If i915 is not loaded:

```bash
modprobe i915
```

If errors appear, DKMS module may not be properly built.

### Solution 4: Verify IOMMU Groups

```bash
find /sys/kernel/iommu_groups/ -type l
```

Should show IOMMU groups. If empty, BIOS settings may be incorrect.

---

## BIOS/IOMMU Issues

### Problem: IOMMU Not Detected

**Symptoms**:

```bash
dmesg | grep -i iommu
# No output or "IOMMU disabled"
```

### Solution: Verify BIOS Settings

1. Reboot and enter BIOS (DEL or F2)
2. Check these settings:

**Advanced → CPU Configuration**:

- Intel Virtualization Technology (VT-x): **Enabled**
- VT-d: **Enabled**

**Advanced → PCI Subsystem Settings**:

- SR-IOV Support: **Enabled**

3. Save and exit
4. Boot into Proxmox and verify:

```bash
dmesg | grep -e DMAR -e IOMMU
```

### Problem: Graphics Mode Not Set to Hybrid

**Symptoms**:

- VFs not creating
- GPU not available for SR-IOV

**Solution**:

1. Enter BIOS
2. Navigate: **Advanced → Onboard Devices Configuration**
3. Set **Primary Video Device** to **Hybrid** or **iGPU**
4. Save and reboot

---

## VM/LXC Configuration Problems

### Problem: LXC Container Can't Access GPU

**Symptoms**:

```bash
# Inside container
ls /dev/dri
# ls: cannot access '/dev/dri': No such file or directory
```

### Solution 1: Check Container Configuration

```bash
nano /etc/pve/lxc/[CONTAINER_ID].conf
```

Must include:

```bash
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri/card0 dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
```

### Solution 2: Verify Devices Exist on Host

```bash
ls -la /dev/dri/
```

Should show `renderD128`, `renderD129`, etc.

### Solution 3: Use Privileged Container

For initial testing, create a **privileged** container:

- Uncheck "Unprivileged container" during creation
- Or edit config: `unprivileged: 0`

### Problem: VM Fails to Start with PCI Passthrough Error

**Symptoms**:

```
kvm: -device vfio-pci,host=0000:00:02.1: vfio 0000:00:02.1: failed to open /dev/vfio/XX: Device or resource busy
```

### Solution 1: Check VF is Not Already Assigned

```bash
qm config [VM_ID]
```

Remove duplicate `hostpci` entries.

### Solution 2: Verify VF Address

```bash
lspci | grep VGA
```

Use correct VF address (00:02.1 through 00:02.7).

### Solution 3: Reset VF

```bash
# Reset specific VF
echo 1 > /sys/bus/pci/devices/0000:00:02.1/remove
echo 1 > /sys/bus/pci/rescan
```

---

## Performance Issues

### Problem: Low Transcoding Performance

**Symptoms**:

- Jellyfin/Plex using CPU instead of GPU
- Transcoding slower than expected

### Solution 1: Verify Hardware Acceleration Enabled

**Jellyfin**:

- Dashboard → Playback → Hardware acceleration: **Intel QuickSync (QSV)**

**Plex**:

- Settings → Transcoder → Use hardware acceleration: **Enabled**

### Solution 2: Check GPU is Accessible

```bash
# Inside container
vainfo
```

Should show Intel iHD driver and supported profiles.

If not installed:

```bash
apt install intel-media-va-driver-non-free vainfo
```

### Solution 3: Monitor GPU Usage

```bash
# On host
intel_gpu_top -d sriov
```

Start transcoding and verify GPU utilization increases.

### Problem: Multiple Streams Cause Stuttering

**Symptoms**:

- First stream works, additional streams stutter
- GPU usage at 100%

**Cause**: GPU overcommit or insufficient system RAM.

**Solution**:

- Reduce number of active VMs/containers using VFs
- Increase system RAM (96GB recommended for heavy workloads)
- Lower transcoding quality settings

---

## Secure Boot Issues

### Problem: Module Not Loading Due to Secure Boot

**Symptoms**:

```bash
dmesg | grep i915
# Shows signature verification failed
```

### Solution: Import MOK Key

```bash
mokutil --import /var/lib/dkms/mok.pub
```

Enter a password when prompted, then:

```bash
reboot
```

During boot:

1. MOK Manager appears
2. Select "Enroll MOK"
3. Continue
4. Enter password
5. Reboot

### Verify MOK Enrolled

```bash
mokutil --list-enrolled
```

### Alternative: Disable Secure Boot

1. Enter BIOS
2. Navigate to Security settings
3. Disable Secure Boot
4. Save and exit

**Note**: Disabling Secure Boot may be required for some hardware configurations.

---

## Driver Conflicts

### Problem: xe Driver Loading Instead of i915

**Symptoms**:

```bash
lsmod | grep xe
# Shows xe module loaded
```

**Cause**: Kernel trying to use newer xe driver which doesn't support SR-IOV.

### Solution: Blacklist xe Driver

```bash
nano /etc/modprobe.d/blacklist-xe.conf
```

Add:

```
blacklist xe
```

Update initramfs:

```bash
update-initramfs -u -k all
```

Verify GRUB parameters include:

```
module_blacklist=xe
```

Reboot and verify:

```bash
lsmod | grep xe
# Should show no output
lsmod | grep i915
# Should show i915 loaded
```

---

## System Stability Issues

### Problem: System Freezes or Crashes

**Symptoms**:

- Random system freezes
- Kernel panics
- NULL pointer dereference errors in dmesg

**Cause**: Kernel 6.8.x stability issues with SR-IOV.

### Solution: Downgrade to Kernel 6.5.x

See [Kernel 6.8.x Issues](#kernel-68x-issues) section above.

### Additional Stability Tweaks

#### Disable CPU C-States (BIOS)

1. Enter BIOS
2. Advanced → CPU Configuration → Power Management
3. Disable C-States
4. Save and reboot

#### Disable ASPM

Add to GRUB parameters:

```
pcie_aspm=off
```

Update and reboot:

```bash
update-grub
proxmox-boot-tool refresh
reboot
```

---

## Recovery Procedures

### Emergency: System Won't Boot After Changes

#### Recovery Method 1: GRUB Recovery

1. Reboot system
2. Hold SHIFT during boot to access GRUB menu
3. Select an older kernel (6.5.x)
4. Boot into system
5. Fix configuration

#### Recovery Method 2: Boot from Live USB

1. Boot Proxmox installer USB
2. Select "Rescue Mode"
3. Mount root filesystem
4. Chroot into system:

```bash
mount /dev/sdX /mnt
chroot /mnt
```

5. Fix GRUB config:

```bash
nano /etc/default/grub
# Remove problematic parameters
update-grub
```

6. Reboot

### Complete DKMS Removal

If all else fails, completely remove i915-sriov-dkms:

```bash
# Stop all VMs/containers using VFs

# Remove DKMS module
dkms remove i915-sriov-dkms --all

# Clean up files
rm -rf /usr/src/i915-sriov-dkms*
rm -rf /var/lib/dkms/i915-sriov-dkms

# Remove package
dpkg -P i915-sriov-dkms

# Reset VFs
echo 0 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# Restore GRUB defaults
nano /etc/default/grub
# Remove all SR-IOV parameters

update-grub
proxmox-boot-tool refresh
reboot
```

### Restore System to Pre-SR-IOV State

```bash
# Remove kernel parameters
nano /etc/default/grub
# Change back to: GRUB_CMDLINE_LINUX_DEFAULT="quiet"

# Remove sysfs config
rm /etc/sysfs.conf

# Update boot
update-grub
proxmox-boot-tool refresh

# Unload i915 module
modprobe -r i915

# Reboot
reboot
```

---

## Diagnostic Commands

### Quick Diagnostic Script

Save as `/root/sr-iov-diag.sh`:

```bash
#!/bin/bash

echo "=== Kernel Version ==="
uname -r

echo -e "\n=== Kernel Parameters ==="
cat /proc/cmdline

echo -e "\n=== DKMS Status ==="
dkms status

echo -e "\n=== VGA Devices ==="
lspci | grep VGA

echo -e "\n=== Virtual Functions ==="
cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

echo -e "\n=== i915 Module ==="
lsmod | grep i915

echo -e "\n=== DRI Devices ==="
ls -la /dev/dri/

echo -e "\n=== Recent i915 Messages ==="
dmesg | grep i915 | tail -20

echo -e "\n=== IOMMU Status ==="
dmesg | grep -i iommu | head -10

echo -e "\n=== Secure Boot Status ==="
mokutil --sb-state 2>/dev/null || echo "mokutil not installed"
```

Make executable and run:

```bash
chmod +x /root/sr-iov-diag.sh
/root/sr-iov-diag.sh
```

---

## Common Error Messages

### Error: "operation not supported"

**When running**: `echo 7 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs`

**Cause**: DKMS module not loaded or BIOS settings incorrect.

**Solution**:

1. Check `lsmod | grep i915`
2. Check BIOS SR-IOV settings
3. Verify kernel parameters

### Error: "Device or resource busy"

**When starting VM with VF**

**Cause**: VF already assigned to another VM/container.

**Solution**:

```bash
# Find which VM is using it
grep -r "00:02.1" /etc/pve/qemu-server/*.conf
grep -r "renderD" /etc/pve/lxc/*.conf
```

### Error: "Failed to open /dev/vfio/XX"

**When starting VM**

**Cause**: VFIO not properly configured or VF not available.

**Solution**:

```bash
# Check IOMMU groups
ls /sys/kernel/iommu_groups/

# Verify vfio-pci module
lsmod | grep vfio_pci
```

If not loaded:

```bash
modprobe vfio-pci
```

---

## Logging and Debugging

### Enable Verbose i915 Logging

```bash
# Add to kernel parameters
i915.debug=0x1e

# Update and reboot
update-grub
proxmox-boot-tool refresh
reboot
```

**Warning**: Creates large amount of logs. Use for debugging only.

### Monitor System Logs

```bash
# Watch live
journalctl -f

# i915 specific
journalctl -f | grep i915

# Kernel messages
dmesg -w | grep i915
```

### Save Diagnostic Information

```bash
# Create diagnostic bundle
mkdir /tmp/sr-iov-debug
dmesg > /tmp/sr-iov-debug/dmesg.log
lspci -vvv > /tmp/sr-iov-debug/lspci.log
dkms status > /tmp/sr-iov-debug/dkms.log
cat /proc/cmdline > /tmp/sr-iov-debug/cmdline.log
lsmod > /tmp/sr-iov-debug/lsmod.log
cp /etc/default/grub /tmp/sr-iov-debug/
cp /etc/sysfs.conf /tmp/sr-iov-debug/
tar -czf /root/sr-iov-debug-$(date +%Y%m%d).tar.gz -C /tmp sr-iov-debug
```

---

## Getting Help

### Before Asking for Help

Prepare this information:

1. Proxmox version: `pveversion`
2. Kernel version: `uname -r`
3. DKMS status: `dkms status`
4. Diagnostic output from script above
5. Relevant error messages from `dmesg`

### Where to Get Help

- **Proxmox Forums**: https://forum.proxmox.com
- **Level1Techs Forum**: https://forum.level1techs.com
- **GitHub Issues**: https://github.com/strongtz/i915-sriov-dkms/issues
- **Reddit**: r/homelab, r/proxmox

### Reporting Issues

When reporting issues, include:

- Hardware: "Minisforum MS-01, i9-13900H"
- Proxmox version
- Kernel version
- DKMS version
- Exact error messages
- Steps to reproduce

---

## Prevention Best Practices

### Before Making Changes

1. **Snapshot or backup** Proxmox system
2. **Document current state**: Save configs, kernel version
3. **Test on single VM/container** before mass deployment
4. **Have recovery plan** ready

### Maintenance Schedule

- **Weekly**: Check for VF availability
- **Monthly**: Review system logs for i915 errors
- **Before updates**: Check GitHub issues for kernel compatibility
- **After updates**: Verify DKMS rebuilt, VFs still work

---

## Success Verification Checklist

After troubleshooting, verify all is working:

- [ ] Kernel 6.5.x booted (not 6.8.x)
- [ ] `lspci | grep VGA` shows 8 devices
- [ ] `dkms status` shows i915-sriov-dkms installed
- [ ] `/proc/cmdline` contains all SR-IOV parameters
- [ ] `ls /dev/dri/` shows renderD128-135
- [ ] VMs/containers start without errors
- [ ] Hardware transcoding works in Jellyfin/Plex
- [ ] `intel_gpu_top` shows GPU activity during transcoding
- [ ] System stable for 24+ hours

---

**Related Documents**:

- MS-01-iGPU-SR-IOV-Guide.md - Main installation guide
- MS-01-Config-Reference.md - Configuration templates
