# Minisforum MS-01 Hardware-Specific Notes

**Last Updated**: 2025-10-11
**Purpose**: MS-01-specific hardware information, BIOS settings, and compatibility notes

---

## Hardware Overview

### Processor Options
- **Intel Core i9-13900H** (Raptor Lake, 13th Gen)
  - 14 cores (6P + 8E), 20 threads
  - Base: 2.6 GHz, Boost: up to 5.4 GHz
  - Integrated: Intel Iris Xe Graphics (96 EU)
- **Intel Core i9-12900H** (Alder Lake, 12th Gen)
  - Alternative option, also supports SR-IOV

### Memory Compatibility

#### Tested and Confirmed Working

**Crucial DDR5**:
- CT48G56C46S5.M16B1 (48GB modules)
- DDR5-5600 CL46
- Configuration: 2x 48GB = 96GB total
- **Status**: ✓ Stable

**Kingston ValueRAM**:
- DDR5-4800
- Configuration: Various capacities
- **Status**: ✓ Works

#### Recommended Configuration
- **Capacity**: 96GB (2x 48GB) for heavy SR-IOV workloads
- **Speed**: DDR5-5600 or DDR5-4800
- **Note**: Some users report better stability at slightly reduced speeds

### Storage

**NVMe Slots**: 3x M.2 2280 NVMe slots

**Tested Drives**:
- Samsung 990 Pro (4TB)
- Crucial P2 (2TB) - CT2000P2SSD8
- Western Digital SN850X

**ZFS Configuration**: Mirrored setup works well (2x 2TB for redundancy)

---

## BIOS Information

### Current BIOS Versions

**Latest Stable**: Version 1.26 (as of 2025)
- Improved system stability
- Updated microcode (0x4121)
- C-State support improvements
- Addresses crashes reported in earlier versions

**Previous Versions**:
- 1.25 (Beta) - Significantly improved stability
- 1.24 - Some stability issues reported
- Earlier versions - More frequent crashes

### BIOS Update Process

**Important**: Always update to latest BIOS before configuring SR-IOV

#### Step 1: Download BIOS

Visit Minisforum support page:
- https://www.minisforum.com/support

Download latest BIOS file for MS-01

#### Step 2: Prepare USB Drive

```bash
# Format USB as FAT32 (on Linux)
sudo mkfs.vfat -F 32 /dev/sdX1

# Mount and extract BIOS files
mount /dev/sdX1 /mnt
unzip MS-01-BIOS-*.zip -d /mnt/
umount /mnt
```

#### Step 3: Flash BIOS

1. Insert USB drive into MS-01
2. Enter BIOS (DEL or F2)
3. Navigate to Security → **Disable Secure Boot**
4. Save and restart
5. Press **F7** during POST to access boot menu
6. Select **UEFI Shell**
7. Run: `AfuEfiFlash.nsh`
8. Wait for completion (DO NOT POWER OFF)
9. System will reboot automatically

#### Step 4: Verify

After reboot:
1. Enter BIOS
2. Check version in System Information
3. Re-enable Secure Boot if needed

---

## Critical BIOS Settings for SR-IOV

### Mandatory Settings

**Advanced → CPU Configuration**:
```
Intel Virtualization Technology (VT-x): [Enabled]
VT-d (Virtualization for Directed I/O): [Enabled]
```

**Advanced → PCI Subsystem Settings**:
```
SR-IOV Support: [Enabled]
```

**Advanced → Onboard Devices Configuration**:
```
Primary Video Device: [Hybrid]
    ⚠️ CRITICAL: Do NOT use "Auto" or "PCIe Only"
```

### Recommended for Stability

**Advanced → CPU Configuration → Power Management**:
```
Intel C-State: [Enabled] (improved in BIOS 1.26)
Intel SpeedStep: [Enabled]
Turbo Mode: [Enabled]
```

**Advanced → Power**:
```
ASPM (Active State Power Management): [Disabled]
    Note: Can improve SR-IOV stability
```

**Advanced → Chipset Configuration**:
```
Above 4G Decoding: [Enabled]
Re-Size BAR Support: [Enabled] (if using discrete GPU)
```

### Optional Settings for Troubleshooting

**If experiencing stability issues**:
```
Advanced → CPU Configuration → Power Management:
  C1E: [Disabled]
  C3 State: [Disabled]
  C6/C7/C8 State: [Disabled]
```

**Note**: Disabling C-States increases power consumption but may improve stability.

---

## Known Hardware Issues

### System Stability and Crashes

**Symptoms**:
- Random system crashes every 3-14 days
- Kernel panics
- System freezes under load

**Causes**:
1. **Older BIOS versions** (pre-1.25)
2. **Incompatible RAM** speeds/timings
3. **Kernel 6.8.x** issues with SR-IOV
4. **Power management** conflicts

**Solutions**:
1. **Update BIOS to 1.26** (highest priority)
2. **Use kernel 6.5.x** (avoid 6.8.x)
3. **Adjust RAM settings** in BIOS:
   - Try running DDR5-5200 instead of 5600
   - Enable XMP/EXPO profiles
4. **Disable aggressive C-States** (see BIOS settings above)

### iGPU Passthrough Challenges

**Issue**: Full iGPU passthrough (not SR-IOV) is problematic

**Symptoms**:
- i915 driver crashes in guest
- Video output not working
- VM fails to start

**Workarounds**:
1. **Use SR-IOV instead** of full passthrough
2. Try ROM files from: https://github.com/gangqizai/igd
3. Add kernel parameters to guest: `nomodeset i915.force_probe=4680`
4. Blacklist i915 on host if doing full passthrough (not recommended)

**Recommendation**: Stick with SR-IOV method for best results

### Network Card Issues

**Issue**: Intel I225-V network card quirks

**Symptoms**:
- Link drops
- Performance issues
- AMT configuration problems

**Solutions**:
- Update network card firmware via BIOS
- Disable AMT if not needed
- Use kernel parameter: `e1000e.EEE=0`

---

## Power Consumption

### Idle Power
- **Without SR-IOV**: ~15-18W
- **With SR-IOV active**: ~17-20W
- **Under load**: 40-65W (depending on workload)

### Power Management Tips

```bash
# Use powersave governor for lower idle power
echo powersave | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Check current power usage
sensors | grep Package
```

### UPS Recommendations
- **Minimum**: 600VA for MS-01 alone
- **Recommended**: 1000VA+ if running external drives/switches

---

## Thermal Management

### Operating Temperatures

**Normal Operating Range**:
- **Idle**: 35-45°C
- **Light load**: 45-60°C
- **Heavy load**: 60-85°C
- **Max (throttle point)**: 100°C

### Cooling Recommendations

**Stock Cooling**: Adequate for most workloads

**Improvements**:
1. **Ensure good airflow** around unit
2. **Clean dust** from intake vents monthly
3. **Room temperature**: Keep <25°C for best performance
4. **Avoid enclosed spaces** without ventilation

**Monitor temps**:
```bash
# Install monitoring tools
apt install lm-sensors

# Run sensor detection
sensors-detect

# Monitor temperatures
watch -n 1 sensors
```

---

## Expansion Options

### PCIe Slot

**Specifications**: PCIe 4.0 x16 (physical), x8 (electrical)

**Compatible GPUs** (SFF/Low Profile):
- Nvidia RTX A2000 (6GB) - Confirmed working
- Nvidia RTX A4000 (16GB) - Confirmed working
- Nvidia T1000 (4GB) - Compatible
- Intel Arc A310 - Compatible

**Note**: Full-size GPUs require external enclosure

### Thunderbolt 4

**Ports**: 2x Thunderbolt 4

**Use Cases**:
- External GPU enclosures (eGPU)
- High-speed storage
- Docking stations

**Tested eGPU Setup**:
- ADT-Link UT3G
- GTX 1080 Ti
- PCIe 4.0 speeds achievable

---

## Proxmox-Specific Notes

### Supported Versions

**Proxmox VE 9.0** (Current Stable):
- Based on Debian 13 "Trixie"
- Kernel: 6.14.x (experimental SR-IOV support)
- **Note**: Still recommend kernel 6.5.x for SR-IOV stability

**Proxmox VE 8.x**:
- Based on Debian 12 "Bookworm"
- Kernel: 6.5.x or 6.8.x
- **Recommended**: Stay on 6.5.x for SR-IOV

### Installation Tips

1. **Use balanced/server BIOS profile** during installation
2. **Set static IP** to avoid network issues
3. **Configure ZFS** during installation if using mirrored setup
4. **Update immediately** after installation

```bash
# Post-installation updates
apt update
apt dist-upgrade -y
reboot
```

### Network Configuration

**Interfaces**: 2x Intel I225-V (2.5GbE)

**Bonding Configuration** (optional):
```bash
# /etc/network/interfaces
auto bond0
iface bond0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
    bond-slaves enp3s0 enp4s0
    bond-mode active-backup
    bond-miimon 100

auto vmbr0
iface vmbr0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
```

---

## Community Resources

### Official Support
- **Minisforum Forum**: https://www.minisforum.com/forum
- **Support Email**: support@minisforum.com

### Community Forums
- **ServeTheHome**: https://forums.servethehome.com
  - Active MS-01 discussion thread
  - Users sharing BIOS updates, stability tips
- **Proxmox Forum**: https://forum.proxmox.com
  - MS-01-specific threads
- **Level1Techs**: https://forum.level1techs.com
  - Detailed SR-IOV guides

### Documentation
- **SystemZ Notes**: https://notes.systemz.pl/IT/Hardware/Minisforum-MS-01
- **SpaceTerran Blog**: https://spaceterran.com (vGPU guides)

---

## Recommended Accessories

### Essential
- **HDMI Dummy Plug** ($5-10)
  - Purpose: Maintains GPU initialization without monitor
  - Model: Any 4K@60Hz EDID emulator

### Recommended
- **UPS (Uninterruptible Power Supply)**
  - Minimum: APC Back-UPS 600VA
  - Recommended: CyberPower 1000VA
  - Provides safe shutdown during power loss

- **USB-C Hub/Dock** (for management)
  - Useful for initial setup
  - Keyboard/mouse/monitor connectivity

---

## Upgrade Path

### Cost-Effective Configuration (Starting Point)
```
MS-01 Barebone (i9-13900H): $589-649
RAM (2x 32GB DDR5-5600): $100-150
NVMe (1TB Samsung 990 Pro): $80-120
Total: ~$800-900
```

### Prosumer Configuration (Recommended)
```
MS-01 Barebone (i9-13900H): $589-649
RAM (2x 48GB DDR5-5600): $150-200
NVMe (2x 2TB Samsung 990 Pro): $250-320
Total: ~$1000-1200
```

### Professional Configuration (Maximum)
```
MS-01 Barebone (i9-13900H): $589-649
RAM (2x 48GB DDR5-5600): $150-200
NVMe (3x 4TB Samsung 990 Pro): $750-900
PCIe GPU (RTX A2000): $400-500
Total: ~$2000-2500
```

---

## Comparison: MS-01 vs Alternatives

| Feature | MS-01 | Intel NUC 13 | Lenovo ThinkCentre |
|---------|-------|--------------|-------------------|
| Processor | i9-13900H | i9-13900K | i9-13900T |
| Max RAM | 96GB DDR5 | 64GB DDR5 | 64GB DDR5 |
| PCIe Slot | Yes (x8) | No | Limited |
| SR-IOV | Yes | Yes | Yes |
| Price | $590 | $800+ | $700+ |
| Expandability | Excellent | Limited | Good |

**Verdict**: MS-01 offers best price/performance for homelab SR-IOV setups

---

## Warranty and Support

**Standard Warranty**: 1 year from purchase

**Extended Warranty**: Available from Minisforum

**RMA Process**:
1. Contact support@minisforum.com
2. Provide purchase proof and issue details
3. Receive RMA number
4. Ship unit (customer pays shipping)

**User Reports**: Generally positive RMA experiences, 2-4 week turnaround

---

## Future-Proofing

### Expected Lifespan
- **Hardware**: 5-7 years (for homelab/SMB use)
- **Software Support**: 3-5 years (limited by Intel driver support)

### Upgrade Considerations
- **RAM**: Maxed at 96GB (sufficient for most use cases)
- **Storage**: 3x NVMe slots allow for future expansion
- **GPU**: PCIe slot allows GPU upgrades as needed

### When to Upgrade
- If you need >96GB RAM
- If you need more than 7 GPU VFs
- If you need PCIe 5.0 (MS-01 is PCIe 4.0)

**Recommendation**: MS-01 will remain viable for SR-IOV homelab use through 2028-2030

---

## Quick Specs Summary

```yaml
Model: Minisforum MS-01
Processor: Intel Core i9-13900H (14C/20T)
Base Clock: 2.6 GHz
Boost Clock: 5.4 GHz
iGPU: Intel Iris Xe Graphics (96 EU)
Max RAM: 96GB DDR5-5600
RAM Slots: 2x SO-DIMM
Storage: 3x M.2 2280 NVMe
Network: 2x Intel I225-V (2.5GbE)
Expansion: 1x PCIe 4.0 x8
USB: 2x Thunderbolt 4, 4x USB 3.2, 2x USB 2.0
Power: 120W adapter
Dimensions: 195 x 189 x 55mm
BIOS: AMI UEFI (latest: 1.26)
SR-IOV VFs: Up to 7 virtual GPUs
Tested OS: Proxmox VE 8.x, 9.0
```

---

## Related Documentation

- **MS-01-iGPU-SR-IOV-Guide.md** - Complete SR-IOV setup guide
- **MS-01-Troubleshooting.md** - Problem resolution
- **MS-01-Config-Reference.md** - Configuration templates

---

**Maintenance Note**: Check Minisforum website quarterly for BIOS updates and apply when stable versions are released.
