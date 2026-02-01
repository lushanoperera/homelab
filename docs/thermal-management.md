# Thermal Management

## Overview

Winston (Minisforum MS-01, i9-13900H) thermal configuration for optimal performance and temperature control.

| Load                              | Expected | Actual |
| --------------------------------- | -------- | ------ |
| Idle                              | 35-45°C  | ~47°C  |
| Light (backup, Plex HW transcode) | 45-60°C  | ~50°C  |
| Heavy                             | 60-85°C  | —      |
| Throttle                          | 100°C    | —      |

---

## Configuration

### CPU Governor

Set to `powersave` for dynamic frequency scaling instead of always running at max frequency.

| Setting      | Value                                      |
| ------------ | ------------------------------------------ |
| Governor     | `powersave`                                |
| Persistence  | systemd service                            |
| Service file | `/etc/systemd/system/cpu-governor.service` |

**Service file:**

```ini
[Unit]
Description=Set CPU Governor to Powersave and Enable HWP Dynamic Boost
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo powersave | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor && echo 1 > /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### thermald (Intel Thermal Daemon)

Auto-detects i9-13900H and applies appropriate thermal policies.

```bash
apt install thermald
systemctl enable --now thermald
```

### Intel P-State Settings

| Parameter           | Value | Description                                      |
| ------------------- | ----- | ------------------------------------------------ |
| `hwp_dynamic_boost` | 1     | Hardware P-state dynamic boost enabled           |
| `max_perf_pct`      | 100   | Max performance percentage (can lower if needed) |
| `no_turbo`          | 0     | Turbo Boost enabled                              |

---

## Verification

```bash
ssh root@192.168.100.38 << 'EOF'
echo "=== Governor ==="
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

echo "=== Package Temp (°C) ==="
echo "$(( $(cat /sys/class/thermal/thermal_zone1/temp) / 1000 ))°C"

echo "=== thermald Status ==="
systemctl is-active thermald

echo "=== Intel P-State ==="
echo "max_perf_pct: $(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)"
echo "no_turbo: $(cat /sys/devices/system/cpu/intel_pstate/no_turbo)"
echo "hwp_dynamic_boost: $(cat /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost)"

echo "=== CPU Frequencies ==="
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | sort -n | awk '{sum+=$1; count++} END {print "Average: " sum/count/1000 " MHz"}'
EOF
```

**Expected output:**

- Governor: `powersave`
- Temperature: <60°C under light load
- thermald: `active`
- HWP Dynamic Boost: `1`

---

## Rollback

If issues occur (e.g., SR-IOV instability):

```bash
ssh root@192.168.100.38 << 'EOF'
# Revert governor to performance
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Disable services
systemctl disable --now thermald cpu-governor.service

# Remove service file
rm /etc/systemd/system/cpu-governor.service
systemctl daemon-reload

# Optionally remove thermald
apt remove thermald
EOF
```

---

## Additional Tuning (If Needed)

### Limit Turbo Boost

If temperatures still exceed 70°C under sustained load:

```bash
# Limit to 70% max performance (~3.8 GHz)
echo 70 > /sys/devices/system/cpu/intel_pstate/max_perf_pct

# Or disable turbo entirely
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

Add to `cpu-governor.service` ExecStart for persistence.

---

## SR-IOV Consideration

Winston has SR-IOV enabled for GPU passthrough (`i915.enable_guc=3 i915.max_vfs=7`).

**If GPU passthrough becomes unstable after thermal changes:**

- C-state modifications from thermald may conflict with SR-IOV
- Monitor for GPU VF stability
- Rollback thermal changes if needed

See: `proxmox-sr-iov/ms-01/MS-01-Troubleshooting.md` for C-state/ASPM stability notes.

---

## History

| Date       | Change                                                                 |
| ---------- | ---------------------------------------------------------------------- |
| 2025-01-25 | Initial configuration: powersave governor, thermald, HWP dynamic boost |
