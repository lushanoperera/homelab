# Intel iGPU SR-IOV Setup Guide for Minisforum MS-01 (i9-13900H)

**Last Updated**: 2025-10-11
**Hardware**: Minisforum MS-01 with Intel i9-13900H
**Target**: Proxmox VE with Intel iGPU sharing via SR-IOV

---

## ⚠️ Important Safety Warnings

**READ THIS SECTION CAREFULLY BEFORE PROCEEDING**

- **EXPERIMENTAL**: This configuration is **NOT officially supported** by Intel or Proxmox
- **USE AT YOUR OWN RISK**: This is a community-driven workaround that may cause system instability
- **KERNEL COMPATIBILITY**: Kernel 6.8.x has known issues - **USE KERNEL 6.5.x** (recommended: 6.5.13-3-pve)
- **BACKUP REQUIRED**: Create full system backup before proceeding
- **NO WARRANTY**: This may void warranty or cause hardware issues
- **SECURE BOOT**: Requires MOK key management if Secure Boot is enabled

---

## What is SR-IOV and What Can You Do With It?

**SR-IOV (Single Root I/O Virtualization)** allows the Intel integrated GPU to be split into up to **7 Virtual Functions (VFs)**. Each VF acts as an independent GPU that can be assigned to different VMs or LXC containers simultaneously.

### Use Cases

- **Media Servers**: Hardware-accelerated transcoding in Plex/Jellyfin across multiple containers
- **Windows VMs**: GPU acceleration for multiple Windows 11 guests (Remote Desktop only)
- **Development**: Test GPU-dependent applications across multiple environments
- **Gaming Streaming**: GPU-accelerated game streaming services

### Limitations

- **No Physical Display**: VMs with assigned VFs cannot output to physical monitors
- **Remote Access Only**: Windows guests require Remote Desktop or similar remote access
- **Max 7 VFs**: Can create up to 7 virtual GPU instances
- **Shared Resources**: All VFs share the same physical GPU memory and compute resources

---

## Hardware & Software Requirements

### Hardware Requirements

- **CPU**: Intel i9-13900H (12th/13th Gen Intel Core)
- **System**: Minisforum MS-01
- **RAM**: 32GB+ recommended (96GB for heavy workloads)
- **Optional**: HDMI dummy plug (for stability)

### Software Requirements

- **Proxmox VE**: 8.1.4+ or 9.0 (based on Debian 13 "Trixie")
  - **Proxmox 9.0**: Kernel 6.14.11-3-pve (CONFIRMED WORKING ✅)
  - **Proxmox 8.x**: Kernel 6.5.11-8-pve or 6.5.13-3-pve recommended
  - **AVOID**: Kernel 6.8.x (known DKMS compilation issues)
- **Kernel Compatibility**: i915-sriov-dkms supports kernels 6.12.19 ~ 6.17.x
- **DKMS Module**: i915-sriov-dkms (latest release from GitHub)
- **Git**: For cloning repositories
- **Build Tools**: proxmox-headers, dkms, sysfsutils

---

## Phase 1: BIOS Configuration

### Access BIOS

1. Reboot the MS-01
2. Press **DEL** or **F2** during POST to enter BIOS

### Required BIOS Settings

#### Virtualization Settings

Navigate to: **Advanced → CPU Configuration**

- **Intel Virtualization Technology (VT-x)**: **Enabled**
- **VT-d (Intel Virtualization Technology for Directed I/O)**: **Enabled**

#### SR-IOV Settings

Navigate to: **Advanced → PCI Subsystem Settings**

- **SR-IOV Support**: **Enabled**

#### Graphics Settings

Navigate to: **Advanced → Onboard Devices Configuration**

- **Primary Video Device**: **Hybrid** (or **iGPU**)
  - **CRITICAL**: Do NOT set to "Auto" or "PCIe" if you want to use SR-IOV

#### Power Management (Optional but Recommended)

- **Power Management**: Disable CPU C-States for better stability
- **ASPM (Active State Power Management)**: **Disabled**

### Save and Exit

- Press **F10** to save changes and reboot

---

## Phase 2: Proxmox Preparation

### Step 1: Check Current Kernel Version

```bash
uname -r
```

**Expected Output**: `6.5.11-8-pve` or `6.5.13-3-pve`

If you have kernel 6.8.x, you **MUST** downgrade to 6.5.x (see Troubleshooting section).

### Step 2: Hold Kernel Packages to Prevent 6.8.x Installation

**CRITICAL**: Prevent accidental kernel upgrade to 6.8.x before updating system.

```bash
# For Proxmox 9.0 (kernel 6.14.x)
apt-mark hold proxmox-kernel-6.14*

# For Proxmox 8.x (kernel 6.5.x)
apt-mark hold pve-kernel-6.5*

# List held packages to verify
apt-mark showhold
```

### Step 3: Update System and Install Dependencies

```bash
apt update
apt upgrade -y
apt install -y build-essential git dkms sysfsutils pve-headers-$(uname -r) mokutil
```

**Dependencies Explained**:

- `build-essential` - Compiler toolchain for DKMS module compilation
- `git` - For cloning repositories
- `dkms` - Dynamic Kernel Module Support
- `sysfsutils` - For persistent VF configuration
- `pve-headers-$(uname -r)` - Kernel headers matching current kernel
- `mokutil` - For Secure Boot key management

### Step 4: Verify IOMMU is Available

```bash
dmesg | grep -e DMAR -e IOMMU
```

**Expected Output**: Should show IOMMU initialization messages like:

```
DMAR: IOMMU enabled
DMAR: Intel(R) Virtualization Technology for Directed I/O
```

If you see "IOMMU disabled", check BIOS settings.

---

## Phase 3: Configure Bootloader Kernel Parameters

**IMPORTANT**: Proxmox VE uses different bootloaders depending on installation type. Follow the correct method for your system.

### Determine Your Bootloader Type

```bash
# Check if using systemd-boot (most common with ZFS)
ls /etc/kernel/cmdline && echo "Using systemd-boot" || echo "Using GRUB"
```

### Method A: systemd-boot (Default for Proxmox VE 8.x ZFS installations)

**Step 1: Edit Kernel Command Line**

```bash
nano /etc/kernel/cmdline
```

**Step 2: Replace entire contents with**:

```
root=ZFS=rpool/ROOT/pve-1 boot=zfs quiet intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

**Note**: Adjust `root=` parameter to match your existing configuration (check current `/proc/cmdline` first).

**Step 3: Apply Changes**

```bash
proxmox-boot-tool refresh
```

### Method B: GRUB Bootloader

**Note**: This method applies to most Proxmox installations, including Proxmox 9.0.

**Step 1: Edit GRUB Configuration**

```bash
nano /etc/default/grub
```

**Step 2: Modify Kernel Parameters**

Find the line starting with `GRUB_CMDLINE_LINUX_DEFAULT` and replace it with:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe"
```

**Step 3: Update GRUB**

```bash
update-grub
```

### Kernel Parameter Explanation

- `intel_iommu=on` - Enables Intel IOMMU
- `iommu=pt` - IOMMU passthrough mode (better performance)
- `i915.enable_guc=3` - Enables GuC (Graphics micro-controller) submission and HuC (HEVC/H.265)
- `i915.max_vfs=7` - Creates 7 virtual functions (maximum supported)
- `module_blacklist=xe` - Prevents xe driver from loading (conflicts with i915)

### Verify Configuration

```bash
# Check current kernel parameters
cat /proc/cmdline

# After reboot, verify new parameters will be applied
# For systemd-boot:
cat /etc/kernel/cmdline
# For GRUB:
cat /etc/default/grub | grep CMDLINE
```

**DO NOT REBOOT YET** - Install DKMS driver first.

---

## Phase 4: Install i915-sriov-dkms Driver

### Method 1: Using Pre-built .deb Package (Recommended)

#### Step 1: Download Latest Release

Visit: https://github.com/strongtz/i915-sriov-dkms/releases

Download the latest `.deb` file, for example:

```bash
cd /tmp
wget https://github.com/strongtz/i915-sriov-dkms/releases/download/2025.10.10/i915-sriov-dkms_2025.10.10_all.deb
```

#### Step 2: Install the Package

```bash
dpkg -i i915-sriov-dkms_*.deb
```

#### Step 3: Verify DKMS Installation

```bash
dkms status
```

**Expected Output**:

```
i915-sriov-dkms/2025.10.10, 6.5.11-8-pve, x86_64: installed
```

### Method 2: Manual Installation from Git (Alternative)

```bash
cd /usr/src
git clone https://github.com/strongtz/i915-sriov-dkms.git
cd i915-sriov-dkms
dkms add .
dkms install -m i915-sriov-dkms -v $(cat VERSION)
```

---

## Phase 5: Configure Virtual Functions

### Step 1: Create sysfs Configuration

```bash
nano /etc/sysfs.conf
```

Add the following line:

```bash
devices/pci0000:00/0000:00:02.0/sriov_numvfs = 7
```

**Note**: This creates 7 VFs automatically at boot. Adjust the number (1-7) based on your needs.

### Step 2: Update Initramfs

```bash
update-initramfs -u -k all
```

---

## Phase 6: Handle Secure Boot (If Enabled)

### Check if Secure Boot is Enabled

```bash
mokutil --sb-state
```

If Secure Boot is **enabled**, you must sign the DKMS module:

### Import MOK Key

```bash
mokutil --import /var/lib/dkms/mok.pub
```

You'll be prompted to create a password. **Remember this password**.

### Reboot and Enroll Key

1. Reboot the system
2. MOK Manager will appear during boot
3. Select "Enroll MOK"
4. Enter the password you created
5. Reboot again

---

## Phase 7: Reboot and Verify

### Step 1: Reboot System

```bash
reboot
```

### Step 2: Verify Kernel Parameters

```bash
cat /proc/cmdline
```

Verify all kernel parameters are present.

### Step 3: Check Virtual Functions

```bash
lspci | grep VGA
```

**Expected Output**: You should see 8 devices (1 physical + 7 virtual):

```
00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)
00:02.1 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)
00:02.2 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)
...
00:02.7 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)
```

### Step 4: Verify SR-IOV Driver

```bash
dmesg | grep i915
```

Look for messages about SR-IOV initialization and VF creation.

### Step 5: Check Virtual Function Status

```bash
cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs
```

**Expected Output**: `7`

---

## Phase 8: Configure VMs/LXC Containers

### For LXC Containers (Jellyfin/Plex Example)

#### Step 1: Create Privileged LXC Container

When creating the container, ensure:

- **Unprivileged container**: No (create privileged container)
- **Nesting**: Enabled
- **Keyctl**: Enabled

#### Step 2: Identify VF Device Numbers

First, identify available VF render nodes:

```bash
ls -la /dev/dri/
stat /dev/dri/renderD*
```

**VF to Device Mapping**:

| VF #         | PCI Address | Card Device | Render Device | Major:Minor |
| ------------ | ----------- | ----------- | ------------- | ----------- |
| Physical GPU | 00:02.0     | card0       | renderD128    | 226:128     |
| VF 0         | 00:02.1     | card1       | renderD129    | 226:129     |
| VF 1         | 00:02.2     | card2       | renderD130    | 226:130     |
| VF 2         | 00:02.3     | card3       | renderD131    | 226:131     |
| VF 3         | 00:02.4     | card4       | renderD132    | 226:132     |
| VF 4         | 00:02.5     | card5       | renderD133    | 226:133     |
| VF 5         | 00:02.6     | card6       | renderD134    | 226:134     |
| VF 6         | 00:02.7     | card7       | renderD135    | 226:135     |

**Note**: Do NOT use card0/renderD128 (physical GPU) - use VF devices instead.

#### Step 3: Add VF to Container Configuration

Edit container configuration:

```bash
nano /etc/pve/lxc/[CONTAINER_ID].conf
```

**Example: Assign VF 0 (renderD129) to container**:

```bash
# Allow access to VF 0 render device (226:129)
lxc.cgroup2.devices.allow: c 226:129 rwm
lxc.mount.entry: /dev/dri/renderD129 dev/dri/renderD129 none bind,optional,create=file
```

**For multiple containers, use different VFs**:

- Container 100: Use VF 0 (renderD129, minor 129)
- Container 101: Use VF 1 (renderD130, minor 130)
- Container 102: Use VF 2 (renderD131, minor 131)
- etc.

#### Step 4: Install Intel Media Drivers in Container

```bash
# Inside the container
apt update
apt install -y intel-media-va-driver-non-free vainfo
```

#### Step 5: Verify GPU in Container

```bash
# Inside the container - adjust renderD number to match your VF
vainfo --display drm --device /dev/dri/renderD129
ls -la /dev/dri
```

**Expected Output**: Should show Intel iHD driver and supported codecs

### For Windows 11 VMs

#### Step 1: Create Windows 11 VM

- Use OVMF (UEFI) BIOS
- Enable TPM 2.0
- Install with VirtIO drivers

#### Step 2: Add VF to VM

```bash
qm set [VM_ID] -hostpci0 0000:00:02.1,x-vga=0,rombar=0,pcie=1
```

**Parameter Explanation**:

- `0000:00:02.1` - VF 0 PCI address (use .2, .3, etc. for other VFs)
- `x-vga=0` - Not primary display adapter
- `rombar=0` - Disable ROM BAR (required for iGPU VFs)
- `pcie=1` - Enable PCIe (required for Q35/OVMF guests)

**Note**: Use different VF addresses for different VMs:

- VM 200: Use 0000:00:02.1 (VF 0)
- VM 201: Use 0000:00:02.2 (VF 1)
- VM 202: Use 0000:00:02.3 (VF 2)
- etc.

#### Step 3: Install Intel Graphics Driver

Inside Windows VM:

1. Download Intel Graphics Driver from intel.com
2. Install driver (may show warnings about unsigned driver)
3. Reboot VM
4. Verify in Device Manager

**Limitation**: No physical display output, Remote Desktop only

---

## Phase 9: Monitoring and Performance

### Monitor GPU Usage

```bash
# Install intel-gpu-tools
apt install intel-gpu-tools

# List available GPU devices
intel_gpu_top -l

# Monitor specific VF (example: VF 0 using renderD129)
intel_gpu_top --device /dev/dri/renderD129

# Monitor multiple VFs in separate terminals
intel_gpu_top --device /dev/dri/renderD129  # Terminal 1
intel_gpu_top --device /dev/dri/renderD130  # Terminal 2
intel_gpu_top --device /dev/dri/renderD131  # Terminal 3
```

**Note**: There is no `-d sriov` option. Monitor each VF individually using `--device`.

### Check Render Devices

```bash
ls -la /dev/dri/
```

**Expected Output**:

```
card0 (Physical GPU)
card1-7 (Virtual Functions)
renderD128 (Physical GPU render node)
renderD129-135 (VF render nodes)
```

### Monitor Container GPU Usage

```bash
# Inside container - adjust renderD number to match assigned VF
vainfo --display drm --device /dev/dri/renderD129
```

---

## Jellyfin Hardware Acceleration Setup

### Step 1: Access Jellyfin Dashboard

1. Navigate to **Dashboard** → **Playback**
2. Scroll to **Hardware Acceleration**

### Step 2: Configure Hardware Acceleration

- **Hardware acceleration**: Intel QuickSync (QSV)
- **Enable hardware decoding for**: Enable all codecs
  - H264
  - HEVC
  - VP9
  - AV1
- **Enable hardware encoding**: Enabled
- **Enable VPP Tone mapping**: Enabled
- **Prefer OS native DXVA or VA-API hardware decoders**: Enabled

### Step 3: Test Transcoding

Play a video that requires transcoding and check:

```bash
# Monitor the VF assigned to your Jellyfin container (e.g., renderD129)
intel_gpu_top --device /dev/dri/renderD129
```

You should see GPU utilization increase during transcoding.

---

## Plex Hardware Acceleration Setup

### Prerequisites

- Plex Pass subscription required for hardware transcoding

### Step 1: Enable Hardware Acceleration

1. Navigate to **Settings** → **Transcoder**
2. **Use hardware acceleration when available**: Enabled
3. **Use hardware-accelerated video encoding**: Enabled

### Step 2: Verify

Check transcoding sessions during playback:

- Dashboard should show "(hw)" next to transcoding streams

---

## Best Practices

### Resource Allocation

- **Don't overcommit**: If running 7 VMs/containers, monitor performance
- **VRAM sharing**: All VFs share system RAM (consider 32GB+ RAM)
- **CPU allocation**: i9-13900H has 14 cores (6P+8E), allocate wisely

### Kernel Management

- **Pin kernel version**: Prevent automatic upgrades to 6.8.x

```bash
proxmox-boot-tool kernel pin 6.5.13-3-pve
```

### DKMS Updates

- After kernel updates, rebuild DKMS:

```bash
dkms install -m i915-sriov-dkms -v [VERSION] -k $(uname -r)
```

### Backup Strategy

- **Before kernel updates**: Snapshot Proxmox system
- **Configuration files**: Backup `/etc/default/grub`, `/etc/sysfs.conf`
- **VM/LXC configs**: Regular backups of `/etc/pve/`

---

## Performance Expectations

### Transcoding Performance (Jellyfin/Plex)

- **4K HEVC → 1080p H.264**: 120-150 FPS per stream
- **Concurrent streams**: 3-5 simultaneous 4K transcodes
- **Tone mapping**: Hardware VPP tone mapping supported

### Encoding Performance

- **x264 preset**: Similar to "fast" CPU preset
- **Power efficiency**: 5-10W GPU vs 40-60W CPU transcoding

---

## Maintenance

### Monthly Tasks

- Check kernel version (ensure not accidentally upgraded to 6.8.x)
- Review DKMS status: `dkms status`
- Monitor system logs: `dmesg | grep i915`

### After Proxmox Updates

1. Check kernel version: `uname -r`
2. Verify DKMS module: `dkms status`
3. If kernel changed, rebuild DKMS
4. Reboot and verify VFs: `lspci | grep VGA`

### Signs of Issues

- VFs not appearing after reboot
- VMs failing to start with PCI passthrough errors
- GPU not visible in VMs/containers
- Transcoding falling back to CPU

**Solution**: Refer to MS-01-Troubleshooting.md

---

## Additional Resources

### Official Documentation

- **Proxmox PCI Passthrough**: https://pve.proxmox.com/wiki/PCI(e)_Passthrough
- **Intel SR-IOV Documentation**: https://www.intel.com/sriov

### Community Resources

- **Level1Techs Forum**: https://forum.level1techs.com/t/i915-sr-iov-on-i9-13900h-minisforum-ms-01-proxmox-pve-kernel-6-5-jellyfin-full-hardware-accelerated-lxc/209943
- **Derek Seaman's Blog**: https://www.derekseaman.com/2024/07/proxmox-ve-8-2-windows-11-vgpu-vt-d-passthrough-with-intel-alder-lake.html
- **GitHub Repository**: https://github.com/strongtz/i915-sriov-dkms

### Support

- **Proxmox Forums**: https://forum.proxmox.com
- **r/homelab**: Reddit community
- **GitHub Issues**: strongtz/i915-sriov-dkms issues page

---

## Summary Checklist

- [ ] BIOS settings configured (VT-x, VT-d, SR-IOV, Hybrid graphics)
- [ ] Kernel 6.5.x installed (not 6.8.x)
- [ ] GRUB kernel parameters configured
- [ ] i915-sriov-dkms installed and loaded
- [ ] sysfs.conf created for persistent VFs
- [ ] System rebooted
- [ ] 7 Virtual Functions visible in `lspci`
- [ ] VMs/LXC containers configured with VF assignment
- [ ] Hardware acceleration tested and working
- [ ] Monitoring tools installed (intel_gpu_top)
- [ ] Backup created

---

**Next Steps**: See MS-01-Troubleshooting.md for common issues and solutions.
