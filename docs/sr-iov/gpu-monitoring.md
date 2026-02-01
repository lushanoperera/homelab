# GPU Monitoring Guide for SR-IOV on MS-01

**Issue**: Traditional `intel_gpu_top` doesn't work with SR-IOV Virtual Functions
**Solution**: Use alternative monitoring methods based on debugfs and sysfs

---

## Why intel_gpu_top Doesn't Work

```bash
$ intel_gpu_top -l
Failed to detect engines! (No such file or directory)
(Kernel 4.16 or newer is required for i915 PMU support.)
```

**Reason**: The i915-sriov-dkms driver doesn't expose PMU (Performance Monitoring Unit) interfaces that intel_gpu_top requires. This is a known limitation with SR-IOV VFs.

---

## Monitoring Solutions

### 1. Custom GPU Monitor Script (Recommended)

The `gpu-monitor` script provides a dashboard view of all GPUs and VFs.

#### Installation

```bash
# Already installed at:
/usr/local/bin/gpu-monitor
```

#### Usage

```bash
# Single snapshot
sudo gpu-monitor

# Continuous monitoring (updates every 1 second)
watch -n 1 -c sudo gpu-monitor

# Continuous monitoring (updates every 2 seconds)
watch -n 2 -c sudo gpu-monitor
```

#### Output Example

```
╔════════════════════════════════════════════════════════════════════════╗
║          MS-01 Intel iGPU SR-IOV Monitoring Dashboard                 ║
╚════════════════════════════════════════════════════════════════════════╝

═══ Overall GPU Status ═══

Virtual Functions: 7
Total GPU Devices: 8 (1 physical + 7 VFs)

═══ Physical GPU (00:02.0) ═══
PCI Address:    00:02.0
Card Device:    card0
Render Device:  renderD128
Frequency:      433/450 MHz (Current/Actual)
Status:         IDLE
Engine Runtime: 0ms

═══ Virtual Functions ═══

VF 0 - CT 101 (Nextcloud)
  PCI:       00:02.1  │  Card: card1  │  Render: renderD129
  Status:    IDLE  │  Runtime: 0ms

VF 1 - CT 103 (Immich)
  PCI:       00:02.2  │  Card: card2  │  Render: renderD130
  Status:    IDLE  │  Runtime: 0ms

VF 2 - CT 105 (Plex)
  PCI:       00:02.3  │  Card: card3  │  Render: renderD131
  Status:    ACTIVE  │  Runtime: 12453ms
```

---

### 2. Manual Debug Interface Monitoring

#### Check GPU Frequency

```bash
# Physical GPU
cat /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info

# Shows:
# Current freq: 433 MHz
# Actual freq: 450 MHz
# Min freq: 100 MHz
# Max freq: 1500 MHz
```

#### Check Engine Activity

```bash
# Physical GPU
cat /sys/kernel/debug/dri/0000:00:02.0/i915_engine_info

# Shows all engines (rcs0, vcs0, vcs1, vecs0) with:
# - Awake status
# - Runtime
# - Heartbeat interval
# - Ring buffer status
```

#### Check GPU Info

```bash
# Detailed GPU information
cat /sys/kernel/debug/dri/0000:00:02.0/i915_gpu_info | less

# Shows:
# - Driver info
# - Memory info
# - Engine capabilities
# - GuC firmware status
```

#### Check Power Domain Info

```bash
cat /sys/kernel/debug/dri/0000:00:02.0/i915_power_domain_info

# Shows which power domains are active
```

---

### 3. Monitor Specific VFs

Each VF has its own debug directory:

```bash
# VF 0 (Container 101 - Nextcloud)
ls -la /sys/kernel/debug/dri/0000:00:02.1/

# VF 1 (Container 103 - Immich)
ls -la /sys/kernel/debug/dri/0000:00:02.2/

# VF 2 (Container 105 - Plex)
ls -la /sys/kernel/debug/dri/0000:00:02.3/
```

**Note**: VFs have limited debug info compared to the physical GPU.

---

### 4. One-Liner Quick Checks

#### Quick GPU Frequency Check

```bash
grep "freq:" /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info
```

#### Check if Any Engine is Busy

```bash
grep "Awake?" /sys/kernel/debug/dri/0000:00:02.0/i915_engine_info
```

#### Monitor All Runtimes

```bash
grep "Runtime:" /sys/kernel/debug/dri/0000:00:02.0/i915_engine_info
```

#### Continuous Frequency Watch

```bash
watch -n 1 'grep -E "Current|Actual" /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info'
```

---

### 5. Container-Level Monitoring

#### From Inside Plex Container (105)

```bash
# Enter container
pct enter 105

# Check available GPU devices
ls -la /dev/dri/

# Test GPU with vainfo
vainfo --display drm --device /dev/dri/by-path/pci-0000:00:02.3-render

# Monitor Plex transcoder (if transcoding)
tail -f /var/lib/plexmediaserver/Library/Application\ Support/Plex\ Media\ Server/Logs/Plex\ Transcoder\ Statistics.log
```

---

### 6. sysfs-Based Monitoring

#### Check VF Count

```bash
cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs
# Output: 7
```

#### List All GPU Devices

```bash
ls -la /dev/dri/
# Shows: card0-7, renderD128-135
```

#### Check Device Permissions

```bash
ls -la /dev/dri/by-path/ | grep pci
# Shows all PCI device mappings
```

---

## Alternative Tools

### 1. radeontop

**Status**: ❌ Doesn't work (AMD GPUs only)

### 2. nvtop

**Status**: ❌ Doesn't work (NVIDIA GPUs only)

### 3. gpustat

**Status**: ⚠️ May work with modifications

```bash
# Try installing
apt install python3-pip
pip3 install gpustat

# Test
gpustat
```

### 4. igt-gpu-tools

**Status**: ✅ Partially works

```bash
# Already installed as intel-gpu-tools
apt list --installed | grep intel-gpu-tools

# Available commands:
intel_gpu_frequency  # May work
intel_gpu_time       # May work
```

**Try these**:

```bash
# Check if these work
intel_gpu_frequency --get
intel_gpu_time
```

---

## Creating Custom Monitoring

### Simple Frequency Monitor Script

```bash
#!/bin/bash
# Save as: /usr/local/bin/gpu-freq-watch

while true; do
    clear
    echo "GPU Frequency Monitor - $(date)"
    echo "================================"
    grep -E "Current|Actual|Min|Max" \
        /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info
    sleep 1
done
```

Make it executable:

```bash
chmod +x /usr/local/bin/gpu-freq-watch
```

Run:

```bash
sudo gpu-freq-watch
```

---

### Engine Activity Monitor

```bash
#!/bin/bash
# Save as: /usr/local/bin/gpu-engine-watch

while true; do
    clear
    echo "GPU Engine Activity - $(date)"
    echo "================================"
    grep -A 1 "^[a-z]*[0-9]$" \
        /sys/kernel/debug/dri/0000:00:02.0/i915_engine_info | \
        grep -E "^[a-z]|Awake|Runtime"
    sleep 1
done
```

---

### Combined Dashboard

```bash
#!/bin/bash
# Save as: /usr/local/bin/gpu-dashboard

while true; do
    clear
    echo "╔═══════════════════════════════════════╗"
    echo "║     GPU Monitoring Dashboard          ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "Time: $(date '+%H:%M:%S')"
    echo ""

    echo "VF Count: $(cat /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs)"
    echo "GPU Devices: $(lspci | grep -c 'VGA.*Intel')"
    echo ""

    echo "Frequency:"
    grep -E "Current|Actual" \
        /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info | \
        sed 's/^/  /'
    echo ""

    echo "Containers:"
    pct list | grep -E "101|103|105" | awk '{print "  " $1 " - " $2 " (" $NF ")"}'
    echo ""

    echo "Press Ctrl+C to exit"
    sleep 1
done
```

---

## tmux Monitoring Setup

For persistent monitoring, use tmux:

```bash
# Create new tmux session for monitoring
tmux new-session -s gpu-monitor

# Split into panes
Ctrl+b "    # Split horizontally
Ctrl+b %    # Split vertically

# In different panes:
# Pane 1: GPU frequency
watch -n 1 'grep -E "Current|Actual" /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info'

# Pane 2: Container status
watch -n 2 'pct list | grep -E "VMID|101|103|105"'

# Pane 3: Full GPU monitor
watch -n 1 -c sudo gpu-monitor

# Pane 4: System load
htop

# Detach: Ctrl+b d
# Reattach: tmux attach -t gpu-monitor
```

---

## Monitoring During Transcoding

### Test GPU Load with Plex

1. **Start a transcode in Plex**
   - Play a 4K video
   - Force transcoding (change quality)

2. **Monitor on host**:

   ```bash
   # Terminal 1: Watch frequency
   watch -n 0.5 'grep -E "Current|Actual" /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info'

   # Terminal 2: Watch engines
   watch -n 0.5 'grep -E "Awake|Runtime" /sys/kernel/debug/dri/0000:00:02.0/i915_engine_info'

   # Terminal 3: Watch overall
   watch -n 1 -c sudo gpu-monitor
   ```

3. **Verify in container**:
   ```bash
   pct enter 105
   tail -f /var/lib/plexmediaserver/Library/Application\ Support/Plex\ Media\ Server/Logs/Plex\ Transcoder\ Statistics.log
   ```

**Expected**:

- GPU frequency should increase (300-1500 MHz)
- Video engines (vcs0, vcs1) should show "Awake? 1"
- Runtime should increase over time

---

## Troubleshooting Monitoring Issues

### "Permission denied" errors

```bash
# Add your user to video group
usermod -aG video $USER

# Or run as root
sudo gpu-monitor
```

### "No such file or directory" for debugfs

```bash
# Check if debugfs is mounted
mount | grep debugfs

# If not mounted:
mount -t debugfs none /sys/kernel/debug

# Make persistent:
echo "debugfs /sys/kernel/debug debugfs defaults 0 0" >> /etc/fstab
```

### VF debugfs not available

**Expected**: VFs have limited debug interfaces compared to physical GPU.

**Workaround**: Monitor the physical GPU (00:02.0) which shows aggregate activity.

---

## Recommended Monitoring Approach

**For daily use**:

```bash
# Quick check
sudo gpu-monitor

# Continuous monitoring
watch -n 2 -c sudo gpu-monitor
```

**For troubleshooting**:

```bash
# Full debug info
cat /sys/kernel/debug/dri/0000:00:02.0/i915_gpu_info | less
cat /sys/kernel/debug/dri/0000:00:02.0/i915_engine_info | less
```

**For transcoding tests**:

```bash
# Monitor frequency in real-time
watch -n 0.5 'grep -E "Current|Actual" /sys/kernel/debug/dri/0000:00:02.0/i915_frequency_info'
```

---

## Future Improvements

Potential future enhancements:

1. Web-based dashboard (Grafana + Prometheus)
2. Per-VF GPU metrics (requires kernel driver support)
3. Historical usage tracking
4. Alert system for GPU issues
5. Integration with Proxmox monitoring

---

## Summary

| Tool                 | Status    | Use Case                  |
| -------------------- | --------- | ------------------------- |
| intel_gpu_top        | ❌ Broken | N/A                       |
| gpu-monitor (custom) | ✅ Works  | Dashboard view of all VFs |
| debugfs interfaces   | ✅ Works  | Detailed GPU info         |
| sysfs interfaces     | ✅ Works  | Basic device info         |
| vainfo               | ✅ Works  | Test GPU from containers  |
| watch commands       | ✅ Works  | Real-time monitoring      |

**Best Practice**: Use `gpu-monitor` for overview, debugfs for detailed troubleshooting.

---

**Last Updated**: October 12, 2025
**Proxmox Version**: 9.0.10
**Kernel**: 6.14.11-3-pve
**Driver**: i915-sriov-dkms 2025.10.10
