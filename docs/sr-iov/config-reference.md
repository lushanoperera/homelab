# MS-01 iGPU SR-IOV Configuration Reference

**Last Updated**: 2025-10-11
**Hardware**: Minisforum MS-01 with Intel i9-13900H
**Purpose**: Quick reference for all SR-IOV configuration files and templates

---

## Table of Contents

1. [System Configuration Files](#system-configuration-files)
2. [LXC Container Configurations](#lxc-container-configurations)
3. [VM Configurations](#vm-configurations)
4. [Kernel and Boot Configuration](#kernel-and-boot-configuration)
5. [Application Configurations](#application-configurations)
6. [Monitoring and Diagnostics](#monitoring-and-diagnostics)
7. [Backup and Restore](#backup-and-restore)

---

## System Configuration Files

### /etc/default/grub

**Purpose**: Kernel boot parameters

```bash
# MS-01 SR-IOV Configuration
# Kernel 6.5.x recommended (avoid 6.8.x)

GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Proxmox Virtual Environment"
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe"
GRUB_CMDLINE_LINUX=""
```

**Parameter Breakdown**:
- `quiet` - Reduces boot messages
- `intel_iommu=on` - Enables Intel IOMMU
- `iommu=pt` - IOMMU passthrough mode (better performance)
- `i915.enable_guc=3` - Enables GuC submission (1) + HuC loading (2)
- `i915.max_vfs=7` - Creates 7 virtual functions (max supported)
- `module_blacklist=xe` - Prevents xe driver from loading (conflicts with i915)

**After editing, always run**:
```bash
update-grub
proxmox-boot-tool refresh
```

### /etc/sysfs.conf

**Purpose**: Persistent VF creation at boot

```bash
# Intel iGPU SR-IOV Virtual Functions
# Creates 7 VFs automatically at boot
devices/pci0000:00/0000:00:02.0/sriov_numvfs = 7
```

**Alternative configurations**:

```bash
# Create only 3 VFs (if you only need a few)
devices/pci0000:00/0000:00:02.0/sriov_numvfs = 3

# Create 1 VF (minimal setup)
devices/pci0000:00/0000:00:02.0/sriov_numvfs = 1
```

**Note**: Adjust number (1-7) based on your needs. Fewer VFs = more resources per VF.

### /etc/modprobe.d/blacklist-xe.conf

**Purpose**: Prevent xe driver from loading

```bash
# Blacklist xe driver - conflicts with i915 SR-IOV
blacklist xe
```

**After creating, run**:
```bash
update-initramfs -u -k all
```

### /etc/apt/preferences.d/no-kernel-68

**Purpose**: Prevent kernel 6.8.x installation

```bash
# Prevent kernel 6.8.x installation (DKMS issues)
Package: pve-kernel-6.8*
Pin: release *
Pin-Priority: -1
```

### /etc/apt/apt.conf.d/99-kernel-hold

**Purpose**: Hold current kernel version

```bash
# Prevent automatic kernel upgrades
APT::Install-Recommends "0";
```

---

## LXC Container Configurations

### Standard Jellyfin/Plex Container

**File**: `/etc/pve/lxc/[CONTAINER_ID].conf`

```bash
# Basic container settings
arch: amd64
cores: 4
memory: 8192
swap: 512
hostname: jellyfin
net0: name=eth0,bridge=vmbr0,firewall=1,ip=dhcp,type=veth
ostype: debian
rootfs: local-lvm:vm-[ID]-disk-0,size=32G

# Unprivileged container - set to 0 for privileged
unprivileged: 0

# Enable features for GPU access
features: nesting=1,keyctl=1

# GPU device access (renderD128 = first VF)
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri/card0 dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file

# Auto-start on boot (optional)
onboot: 1
startup: order=1
```

**VF Mapping**:
- `renderD128` → VF 0 (00:02.1)
- `renderD129` → VF 1 (00:02.2)
- `renderD130` → VF 2 (00:02.3)
- `renderD131` → VF 3 (00:02.4)
- `renderD132` → VF 4 (00:02.5)
- `renderD133` → VF 5 (00:02.6)
- `renderD134` → VF 6 (00:02.7)

### Multiple Containers with Different VFs

**Container 100 (Jellyfin)** - Uses VF 0:
```bash
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
```

**Container 101 (Plex)** - Uses VF 1:
```bash
lxc.cgroup2.devices.allow: c 226:129 rwm
lxc.mount.entry: /dev/dri/renderD129 dev/dri/renderD129 none bind,optional,create=file
```

**Container 102 (Emby)** - Uses VF 2:
```bash
lxc.cgroup2.devices.allow: c 226:130 rwm
lxc.mount.entry: /dev/dri/renderD130 dev/dri/renderD130 none bind,optional,create=file
```

### Unprivileged Container with GPU (Advanced)

```bash
# Requires UID/GID mapping
unprivileged: 1

# Map render group
lxc.idmap: u 0 100000 65536
lxc.idmap: g 0 100000 44
lxc.idmap: g 44 44 1
lxc.idmap: g 45 100045 65491

# Device access
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
```

**Note**: Unprivileged containers are more complex. Start with privileged for testing.

---

## VM Configurations

### Windows 11 VM with VF

**Command to add VF**:
```bash
# Add VF 1 (00:02.1) to VM 200
qm set 200 -hostpci0 0000:00:02.1,x-vga=0,rombar=0

# Add VF 2 (00:02.2) to VM 201
qm set 201 -hostpci0 0000:00:02.2,x-vga=0,rombar=0
```

**Full VM config** (`/etc/pve/qemu-server/200.conf`):
```bash
# Windows 11 VM with SR-IOV VF
agent: 1
balloon: 2048
bios: ovmf
boot: order=scsi0;ide2;net0
cores: 4
cpu: host
efidisk0: local-lvm:vm-200-disk-0,efitype=4m,size=4M
hostpci0: 0000:00:02.1,x-vga=0,rombar=0
ide2: local:iso/windows-11.iso,media=cdrom,size=5G
machine: q35
memory: 8192
meta: creation-qemu=8.1.5,ctime=1234567890
name: windows11-gpu
net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,firewall=1
numa: 0
ostype: win11
scsi0: local-lvm:vm-200-disk-1,iothread=1,size=100G
scsihw: virtio-scsi-single
smbios1: uuid=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
sockets: 1
tpmstate0: local-lvm:vm-200-disk-2,size=4M,version=v2.0
vmgenid: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX

# Auto-start (optional)
onboot: 1
startup: order=2
```

**Parameter explanations**:
- `hostpci0: 0000:00:02.1` - PCI passthrough of VF 1
- `x-vga=0` - Not primary display adapter
- `rombar=0` - Disable ROM BAR (required for iGPU VFs)
- `bios: ovmf` - UEFI firmware (required for Windows 11)
- `tpmstate0` - TPM 2.0 for Windows 11 requirements

### Ubuntu Desktop VM with VF

```bash
# Add VF to Ubuntu VM
qm set 300 -hostpci0 0000:00:02.3,x-vga=0,rombar=0
```

**VM config** (`/etc/pve/qemu-server/300.conf`):
```bash
agent: 1
balloon: 2048
bios: ovmf
boot: order=scsi0;ide2;net0
cores: 6
cpu: host
efidisk0: local-lvm:vm-300-disk-0,efitype=4m,size=4M
hostpci0: 0000:00:02.3,x-vga=0,rombar=0
ide2: local:iso/ubuntu-22.04-desktop.iso,media=cdrom
machine: q35
memory: 16384
name: ubuntu-desktop-gpu
net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,firewall=1
numa: 0
ostype: l26
scsi0: local-lvm:vm-300-disk-1,iothread=1,size=120G
scsihw: virtio-scsi-single
smbios1: uuid=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
sockets: 1
```

---

## Kernel and Boot Configuration

### Pin Specific Kernel Version

```bash
# Pin kernel 6.5.13-3-pve
proxmox-boot-tool kernel pin 6.5.13-3-pve

# List pinned kernels
proxmox-boot-tool kernel list

# Unpin kernel (allow updates)
proxmox-boot-tool kernel unpin
```

### Hold Kernel Packages

```bash
# Hold kernel packages to prevent upgrade
apt-mark hold pve-kernel-6.5.13-3-pve
apt-mark hold pve-headers-6.5.13-3-pve

# List held packages
apt-mark showhold

# Unhold packages
apt-mark unhold pve-kernel-6.5.13-3-pve
apt-mark unhold pve-headers-6.5.13-3-pve
```

### Manual VF Creation Script

**File**: `/usr/local/bin/create-vfs.sh`

```bash
#!/bin/bash
# Manual VF creation script
# Use if sysfs.conf not working

# Remove existing VFs
echo 0 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# Wait for cleanup
sleep 2

# Create 7 VFs
echo 7 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# Verify
lspci | grep VGA
```

**Make executable**:
```bash
chmod +x /usr/local/bin/create-vfs.sh
```

**Create systemd service** (`/etc/systemd/system/create-vfs.service`):
```ini
[Unit]
Description=Create Intel iGPU Virtual Functions
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/create-vfs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Enable service**:
```bash
systemctl enable create-vfs.service
systemctl start create-vfs.service
```

---

## Application Configurations

### Jellyfin Hardware Acceleration

**Location**: Jellyfin Dashboard → Playback → Hardware Acceleration

**Configuration**:
```
Hardware acceleration: Intel QuickSync (QSV)
VA-API Device: /dev/dri/renderD128
Enable hardware decoding for:
  ☑ H264
  ☑ HEVC
  ☑ VP9
  ☑ AV1
  ☑ MPEG2
Enable hardware encoding: ☑
Enable VPP Tone mapping: ☑
Prefer OS native DXVA or VA-API hardware decoders: ☑
```

**Test transcoding**:
```bash
# Inside container
vainfo --display drm --device /dev/dri/renderD128
```

### Plex Hardware Transcoding

**Location**: Settings → Transcoder

**Configuration**:
```
Use hardware acceleration when available: Enabled
Use hardware-accelerated video encoding: Enabled
```

**Verify** (requires Plex Pass):
- Dashboard during transcoding shows "(hw)" indicator

### Emby Hardware Acceleration

**Location**: Dashboard → Playback → Transcoding

**Configuration**:
```
Hardware acceleration: Video Acceleration API (VAAPI)
VA API Device: /dev/dri/renderD128
Enable hardware encoding for:
  ☑ H264
  ☑ HEVC
```

---

## Monitoring and Diagnostics

### Intel GPU Top Configuration

**Install**:
```bash
apt install intel-gpu-tools
```

**Monitor all VFs**:
```bash
intel_gpu_top -d sriov
```

**Output format**: Shows GPU usage per VF

### Automated Monitoring Script

**File**: `/usr/local/bin/monitor-sr-iov.sh`

```bash
#!/bin/bash
# SR-IOV Monitoring Script

echo "=== SR-IOV Status Report ==="
echo "Generated: $(date)"
echo ""

echo "=== Kernel Version ==="
uname -r
echo ""

echo "=== Virtual Functions ==="
VFS=$(cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs)
echo "Active VFs: $VFS"
lspci | grep VGA
echo ""

echo "=== DRI Devices ==="
ls -la /dev/dri/
echo ""

echo "=== GPU Utilization ==="
timeout 5 intel_gpu_top -s 1000 -J | jq '.engines[]' 2>/dev/null || echo "intel_gpu_top not available"
echo ""

echo "=== Container GPU Access ==="
for CTID in $(pct list | awk '{print $1}' | grep -v VMID); do
    echo "Container $CTID:"
    pct exec $CTID -- ls /dev/dri 2>/dev/null || echo "  No GPU access"
done
echo ""

echo "=== DKMS Status ==="
dkms status | grep i915
echo ""
```

**Make executable**:
```bash
chmod +x /usr/local/bin/monitor-sr-iov.sh
```

**Run**:
```bash
/usr/local/bin/monitor-sr-iov.sh
```

### Cron Job for Daily Checks

```bash
crontab -e
```

Add:
```bash
# SR-IOV daily health check at 6 AM
0 6 * * * /usr/local/bin/monitor-sr-iov.sh > /var/log/sr-iov-daily-$(date +\%Y\%m\%d).log 2>&1
```

---

## Backup and Restore

### Backup Critical Configuration Files

**Script**: `/usr/local/bin/backup-sr-iov-config.sh`

```bash
#!/bin/bash
# Backup SR-IOV configuration

BACKUP_DIR="/root/sr-iov-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/sr-iov-config-$TIMESTAMP.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create temporary directory
TEMP_DIR=$(mktemp -d)

# Copy configuration files
cp /etc/default/grub "$TEMP_DIR/"
cp /etc/sysfs.conf "$TEMP_DIR/" 2>/dev/null
cp -r /etc/modprobe.d "$TEMP_DIR/" 2>/dev/null
cp -r /etc/apt/preferences.d "$TEMP_DIR/" 2>/dev/null

# Save DKMS status
dkms status > "$TEMP_DIR/dkms-status.txt"

# Save kernel version
uname -r > "$TEMP_DIR/kernel-version.txt"

# Save VF status
cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs > "$TEMP_DIR/vf-count.txt" 2>/dev/null

# Save lspci output
lspci > "$TEMP_DIR/lspci.txt"

# Create archive
tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" .

# Cleanup
rm -rf "$TEMP_DIR"

echo "Backup created: $BACKUP_FILE"

# Keep only last 7 backups
cd "$BACKUP_DIR"
ls -t sr-iov-config-*.tar.gz | tail -n +8 | xargs rm -f 2>/dev/null
```

**Make executable**:
```bash
chmod +x /usr/local/bin/backup-sr-iov-config.sh
```

**Run before changes**:
```bash
/usr/local/bin/backup-sr-iov-config.sh
```

### Restore Configuration

```bash
# List backups
ls -lh /root/sr-iov-backups/

# Extract specific backup
cd /tmp
tar -xzf /root/sr-iov-backups/sr-iov-config-YYYYMMDD-HHMMSS.tar.gz

# Review files
ls -la

# Manually restore files
cp grub /etc/default/grub
cp sysfs.conf /etc/sysfs.conf

# Update boot
update-grub
proxmox-boot-tool refresh

# Reboot
reboot
```

### Export VM/LXC Configurations

```bash
# Backup all LXC configs
tar -czf /root/lxc-configs-$(date +%Y%m%d).tar.gz -C /etc/pve lxc/

# Backup all VM configs
tar -czf /root/vm-configs-$(date +%Y%m%d).tar.gz -C /etc/pve qemu-server/
```

---

## Quick Reference Commands

### VF Management

```bash
# Check VF count
cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# Manually create 7 VFs
echo 7 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# Remove all VFs
echo 0 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs

# List VGA devices
lspci | grep VGA

# List DRI devices
ls -la /dev/dri/
```

### DKMS Management

```bash
# Check DKMS status
dkms status

# Install DKMS for current kernel
dkms install -m i915-sriov-dkms -v VERSION -k $(uname -r)

# Remove DKMS module
dkms remove i915-sriov-dkms/VERSION --all

# Rebuild for all kernels
dkms install -m i915-sriov-dkms -v VERSION -k all
```

### Container Management

```bash
# List containers
pct list

# Edit container config
nano /etc/pve/lxc/CTID.conf

# Enter container
pct enter CTID

# Check GPU in container
pct exec CTID -- ls /dev/dri
pct exec CTID -- vainfo
```

### VM Management

```bash
# List VMs
qm list

# Add PCI device to VM
qm set VMID -hostpci0 0000:00:02.1,x-vga=0,rombar=0

# Remove PCI device from VM
qm set VMID -delete hostpci0

# Show VM config
qm config VMID
```

### Monitoring

```bash
# GPU utilization (all VFs)
intel_gpu_top -d sriov

# Kernel messages for i915
dmesg | grep i915

# System logs
journalctl -u create-vfs.service
journalctl -xe | grep i915
```

---

## Device Mapping Reference

### PCI Addresses to Render Devices

| PCI Address | Device Type | Render Device | Container Config |
|-------------|-------------|---------------|------------------|
| 0000:00:02.0 | Physical GPU | card0 | N/A (host only) |
| 0000:00:02.1 | VF 0 | renderD128 | c 226:128 rwm |
| 0000:00:02.2 | VF 1 | renderD129 | c 226:129 rwm |
| 0000:00:02.3 | VF 2 | renderD130 | c 226:130 rwm |
| 0000:00:02.4 | VF 3 | renderD131 | c 226:131 rwm |
| 0000:00:02.5 | VF 4 | renderD132 | c 226:132 rwm |
| 0000:00:02.6 | VF 5 | renderD133 | c 226:133 rwm |
| 0000:00:02.7 | VF 6 | renderD134 | c 226:134 rwm |

### Character Device Major/Minor Numbers

```bash
# List actual device numbers
ls -l /dev/dri/

# Example output:
crw-rw---- 1 root video 226,   0 Oct 11 10:00 card0
crw-rw---- 1 root video 226,   1 Oct 11 10:00 card1
crw-rw---- 1 root render 226, 128 Oct 11 10:00 renderD128
crw-rw---- 1 root render 226, 129 Oct 11 10:00 renderD129
```

**Major number**: Always 226 for DRM devices
**Minor numbers**:
- 0-15: card devices
- 128+: render devices

---

## Environment Variables

### For Jellyfin/Plex in Containers

**Add to container startup script or systemd override**:

```bash
# Force use of specific render device
export LIBVA_DRIVER_NAME=iHD
export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri

# For debugging
export LIBVA_MESSAGING_LEVEL=1
export VAAPI_DEVICE=/dev/dri/renderD128
```

---

## Validation Scripts

### Validate SR-IOV Setup

**File**: `/usr/local/bin/validate-sr-iov.sh`

```bash
#!/bin/bash
# Validate SR-IOV configuration

ERRORS=0

echo "=== SR-IOV Configuration Validator ==="
echo ""

# Check kernel version
KERNEL=$(uname -r)
if [[ $KERNEL == *"6.8"* ]]; then
    echo "❌ Kernel 6.8.x detected - known issues!"
    ERRORS=$((ERRORS+1))
else
    echo "✓ Kernel version: $KERNEL"
fi

# Check kernel parameters
if grep -q "intel_iommu=on" /proc/cmdline && \
   grep -q "i915.enable_guc=3" /proc/cmdline && \
   grep -q "i915.max_vfs=7" /proc/cmdline; then
    echo "✓ Kernel parameters configured"
else
    echo "❌ Missing kernel parameters"
    ERRORS=$((ERRORS+1))
fi

# Check DKMS
if dkms status | grep -q "i915-sriov-dkms.*installed"; then
    echo "✓ DKMS module installed"
else
    echo "❌ DKMS module not installed"
    ERRORS=$((ERRORS+1))
fi

# Check VFs
VFS=$(cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs 2>/dev/null)
if [[ "$VFS" -ge 1 ]]; then
    echo "✓ Virtual Functions created: $VFS"
else
    echo "❌ No Virtual Functions created"
    ERRORS=$((ERRORS+1))
fi

# Check i915 module
if lsmod | grep -q "^i915"; then
    echo "✓ i915 module loaded"
else
    echo "❌ i915 module not loaded"
    ERRORS=$((ERRORS+1))
fi

# Check for xe conflict
if lsmod | grep -q "^xe"; then
    echo "⚠ xe module loaded (may conflict)"
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo "✓ All checks passed!"
    exit 0
else
    echo "❌ $ERRORS error(s) found"
    exit 1
fi
```

**Make executable and run**:
```bash
chmod +x /usr/local/bin/validate-sr-iov.sh
/usr/local/bin/validate-sr-iov.sh
```

---

## File Permissions Reference

### Required Permissions for Container Access

```bash
# Host system
ls -l /dev/dri/renderD128
# Should show: crw-rw---- 1 root render 226, 128

# Inside container
ls -l /dev/dri/renderD128
# Should show same permissions

# Add user to render group (if needed)
usermod -aG render [USERNAME]
```

---

## Related Documentation

- **MS-01-iGPU-SR-IOV-Guide.md** - Complete installation guide
- **MS-01-Troubleshooting.md** - Problem resolution guide

---

**Note**: This is a living document. Update as configurations change or new best practices emerge.
