# Reginald Host Scripts

Maintenance, monitoring, and UPS management scripts for **reginald** (192.168.100.4), the secondary Proxmox VE host (ZimaBoard).

## Scripts

### Monitoring

| Script                    | Deploy Path       | Schedule           | Purpose                                              |
| ------------------------- | ----------------- | ------------------ | ---------------------------------------------------- |
| `zimaboard-monitor.sh`    | `/usr/local/bin/` | Cron `*/5 * * * *` | CPU temp/load/memory logging with thermal throttling |
| `proxmox-temp-monitor.sh` | `/usr/local/bin/` | Daemon (5min loop) | Temperature monitoring with email alerts at 70/80°C  |
| `temp-monitor.sh`         | `/usr/local/bin/` | Daemon (60s loop)  | Temperature + frequency logging with email alerts    |
| `check-temp-monitor.sh`   | `/usr/local/bin/` | Manual             | Quick status check of temp-monitor service           |
| `zfs-monitor.sh`          | `/root/`          | Manual             | ZFS pool status, ARC stats, dataset space logger     |
| `monitor-logs.sh`         | `/usr/local/bin/` | Manual             | Log disk usage checker with ZFS quota alerts         |
| `monitor-updates.sh`      | `/usr/local/bin/` | Manual             | APT/unattended-upgrades status checker               |
| `zimaboard-report.sh`     | `/usr/local/bin/` | Manual             | Full system report (CPU, memory, storage, network)   |

### Optimization

| Script                       | Deploy Path       | Schedule       | Purpose                                                                                                |
| ---------------------------- | ----------------- | -------------- | ------------------------------------------------------------------------------------------------------ |
| `zimaboard-cpu-optimize.sh`  | `/usr/local/bin/` | Cron `@reboot` | Set optimal CPU governor (schedutil > ondemand > performance)                                          |
| `zimaboard-optimize-boot.sh` | `/usr/local/bin/` | Boot (systemd) | CPU governor + I/O scheduler + memory tuning at boot                                                   |
| `zfs-tune.sh`                | `/root/`          | One-shot       | Apply Zimaboard-aware ZFS tuning: ARC 2.5G, dirty 512M, lz4, logbias, primarycache, autotrim, initrd   |

### UPS Power Management

| Script               | Deploy Path       | Schedule           | Purpose                                                                 |
| -------------------- | ----------------- | ------------------ | ----------------------------------------------------------------------- |
| `upssched-cmd.sh`    | `/usr/local/bin/` | Event-driven (NUT) | UPS event handler (shutdown-warning, power-restored, critical-shutdown) |
| `shutdown-device.sh` | `/usr/local/bin/` | Called by upssched | Orderly shutdown of ms01/qnap/zimaboard via SSH                         |
| `startup-devices.sh` | `/usr/local/bin/` | Called by upssched | WoL startup of devices after power restore (2+3 min delays)             |
| `system-shutdown.sh` | `/usr/local/bin/` | Called by upsmon   | Final UPS-triggered system shutdown                                     |

### Security & Updates

| Script                        | Deploy Path       | Schedule | Purpose                                                   |
| ----------------------------- | ----------------- | -------- | --------------------------------------------------------- |
| `security-updates-manager.sh` | `/usr/local/bin/` | Manual   | Security update automation with ZFS snapshot rollback     |
| `lxc-security-setup.sh`       | `/root/`          | One-time | Install unattended-upgrades on all running LXC containers |
| `install-wazauh.sh`           | `/root/`          | One-time | Wazuh SIEM agent installer                                |

### Immich Mount Management

| Script                   | Deploy Path       | Schedule    | Purpose                                                              |
| ------------------------ | ----------------- | ----------- | -------------------------------------------------------------------- |
| `fix-immich-mounts.sh`   | `/usr/local/bin/` | Manual/cron | Verify and fix NFS mounts for Immich LXC 103, auto-restart if broken |
| `setup-immich-mounts.sh` | `/usr/local/bin/` | Manual      | Initial bind mount setup for Immich LXC 103 (NFS → rootfs)           |

## Crontab

```cron
@reboot (sleep 60 && echo "ondemand" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)
@reboot /usr/local/bin/zimaboard-cpu-optimize.sh
*/5 * * * * /usr/local/bin/zimaboard-monitor.sh
0 0 * * 0 PATH=... /bin/bash -c "$(wget -qLO - .../update-lxcs-cron.sh)" >>/var/log/update-lxcs-cron.log
```

## Deployment

```bash
# Monitoring & optimization scripts
scp scripts/hosts/reginald/zimaboard-*.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/proxmox-temp-monitor.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/temp-monitor.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/check-temp-monitor.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/monitor-*.sh root@192.168.100.4:/usr/local/bin/

# UPS scripts
scp scripts/hosts/reginald/upssched-cmd.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/shutdown-device.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/startup-devices.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/system-shutdown.sh root@192.168.100.4:/usr/local/bin/

# Security scripts
scp scripts/hosts/reginald/security-updates-manager.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/lxc-security-setup.sh root@192.168.100.4:/root/
scp scripts/hosts/reginald/install-wazauh.sh root@192.168.100.4:/root/

# Immich mount scripts
scp scripts/hosts/reginald/fix-immich-mounts.sh root@192.168.100.4:/usr/local/bin/
scp scripts/hosts/reginald/setup-immich-mounts.sh root@192.168.100.4:/usr/local/bin/

# ZFS monitor + tuning
scp scripts/hosts/reginald/zfs-monitor.sh root@192.168.100.4:/root/
scp scripts/hosts/reginald/zfs-tune.sh root@192.168.100.4:/root/
```

## ZFS Tuning

`zfs-tune.sh` applies Zimaboard-832-specific ZFS tuning — designed for the 8 GB LPDDR4 + Celeron N3450 + 7-drive raidz2 workload of this host.

Run dry-run first, then `--apply`:

```bash
ssh root@192.168.100.4 '/root/zfs-tune.sh'          # dry-run
ssh root@192.168.100.4 '/root/zfs-tune.sh --apply'  # commit
```

Applied settings (all hot, reversible, persistent across reboot via `update-initramfs`):

| Setting                  | Before    | After            | Why                                                                    |
| ------------------------ | --------- | ---------------- | ---------------------------------------------------------------------- |
| `zfs_arc_max`            | 4 GB      | **2.5 GB**       | 8 GB host needs page-cache headroom; ghost lists already pressured     |
| `zfs_arc_min`            | 1 GB      | 512 MB           | Lower floor gives scheduler room to shrink under pressure              |
| `zfs_dirty_data_max`     | 2 GB      | **512 MB**       | Storage LAN peaks ~280 MB/s; 2 GB buffer = 7 s flush, wastes RAM       |
| `vm.dirty_ratio`         | 60        | **20**           | Was double-buffering on top of ZFS                                     |
| `vm.dirty_background_ratio` | 20     | **10**           | Same                                                                   |
| `autotrim` (rpool)       | off       | **on**           | All-SSD pool at 75% needs TRIM for SSD garbage collection              |
| compression (media / library / nextcloud) | zstd-3 | **lz4** | Achieved ratios 1.00–1.05x — zstd-3 burns CPU on N3450 for no benefit |
| `logbias` (sync-NFS datasets) | throughput | **latency** | No SLOG — in-pool ZIL via `latency` beats `throughput` for sync writes |
| `primarycache` (media/movies/tv/music) | all | **metadata** | Plex streams once; caching data blocks evicts hot nextcloud/immich pages |

Keeps `primarycache=all` on immich/database, immich/library (thumbnail re-reads), nextcloud, and vaultwarden.
Does **not** touch `rpool/swap` zvol (kept as OOM safety net since zram is only 1.2 GB).

## Notes

- All scripts use Italian-language log messages (written by the original author)
- UPS scripts email alerts to `lushano.perera@gmail.com`
- `security-updates-manager.sh` creates a ZFS snapshot before applying updates, with auto-rollback on failure
- `proxmox-temp-monitor.sh` and `temp-monitor.sh` overlap in functionality — consider consolidating
