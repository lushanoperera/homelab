---
paths:
  - "hosts/**"
  - "networking/**"
  - "storage/garage/**"
  - "storage/minio/**"
  - "scripts/migrations/**"
recall:
  - proxmox
  - garage
  - minio
  - migration
  - macvlan
---

# Infrastructure Lessons

## Proxmox Networking

| Issue                                   | Solution                                                                                                                                                  |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VM VLAN tag but no traffic (0 rx bytes) | Check `bridge-vids` on vmbr0 includes that VLAN                                                                                                           |
| Multicast/mDNS discovery broken in VM   | Remove `firewall=1` from NIC or add multicast allow rules                                                                                                 |
| DHCP works but discovery doesn't        | DHCP unicast succeeds even when multicast is filtered                                                                                                     |
| KSM persistence via sysctl              | PVE kernel has no /proc/sys/kernel/ksm/ — use systemd unit writing to /sys/kernel/mm/ksm/                                                                 |
| ksmtuned disables custom KSM            | ksmtuned only monitors QEMU, not LXCs — disable it if KSM always-on needed                                                                                |
| Balloon config via `qm set`             | Persists immediately but takes effect on next VM reboot (no live disruption)                                                                              |
| PBS storage offline                     | `pbs-backupnas` can timeout if QNAP NAS is unreachable — check `pvesm status` first                                                                       |
| LXC snapshot with NFS mounts            | `pct snapshot` fails ("feature not available") when LXC has NFS mountpoints (mp0/mp1) — use vzdump or docker rollback instead                             |
| pvesh storage content path              | `/nodes/<node>/storage/<id>/content` not `/storage/<id>/content`                                                                                          |
| No scheduled backups                    | Fixed 2026-03-01: 2 vzdump jobs on winston (A: 103-106 at 04:00, B: 100-102 at 05:00) + 1 on reginald (120 at 08:00). Verify: `pvesh get /cluster/backup` |

## Proxmox Host Firewall

See `hosts/firewall.md` for the full runbook. Key lessons:

| Lesson                                | Detail                                                                                                                         |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| cluster.fw NOT auto-synced standalone | winston + reginald are not clustered — `/etc/pve/firewall/cluster.fw` must be copied to each host individually                 |
| Both enables required                 | Rules only match when `cluster.fw enable: 1` AND host.fw `enable: 1`. Flipping cluster.fw to 0 is the fastest kill switch      |
| Conntrack survives reloads            | Existing SSH sessions stay alive across `pve-firewall reload`. Always test new policy from a **fresh** connection, not the old |
| Per-VM FW stays off                   | Enabling it on VM NICs breaks multicast/mDNS (see row above). Host-level FW is sufficient for this threat model                |
| pmxcfs lost on reinstall              | `/etc/pve/firewall/*` and `/etc/pve/nodes/*/host.fw` are NOT preserved on bare-metal reinstall — repo copy is DR source        |
| Dead-man cron mandatory               | Arm before every enable flip: `touch /root/.fw-deadman-armed` + cron auto-disables FW at 600s if not disarmed                  |
| Phase A log-first, Phase B drop       | Run `policy_in: ACCEPT` + `log_level_in: info` for 30 min before flipping to DROP — catches unexpected legit traffic cheaply   |
| Hardcode laptop IP in admin_sources   | Belt + braces alongside the `192.168.2.0/24` range in case VLAN routing hiccups                                                |
| Outbound stays ACCEPT                 | Egress filtering on a hypervisor is maintenance pain with no real value — root already owns the box if attacker is there      |

## PBS / Vzdump

- `/etc/pve/jobs.cfg` lives in pmxcfs (cluster filesystem) — **lost on bare-metal reinstall**. After any Proxmox rebuild, verify vzdump jobs exist: `cat /etc/pve/jobs.cfg`
- Backup gap Oct 2025 – Mar 2026: jobs.cfg not preserved during winston rebuild, no scheduled backups ran for ~5 months. Recreated 2026-03-01.
- Manual backup verification: `pvesh get /nodes/{node}/tasks --typefilter vzdump --limit 5`
- PBS storage on Storage LAN (192.168.200.x) — check connectivity separately from Infra LAN (192.168.100.x)
- PBS on QNAP intermittently slow (high memory/load) — causes `read timeout` in pvestatd, but vzdump transfers complete fine

## Proxmox Kernel Upgrades

| Lesson                                       | Detail                                                                                                                                                                                  |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Always install matching `proxmox-headers-X`  | DKMS modules (i915-sriov-dkms etc.) silently skip rebuild if headers missing → SR-IOV breaks on next boot. Install `proxmox-default-headers` + per-version headers alongside any kernel |
| Verify DKMS post-upgrade                     | `dkms status` must list new kernel version. Force build: `dkms autoinstall -k <ver>`. Verify module: `modinfo /lib/modules/<ver>/updates/dkms/i915.ko \| grep max_vfs`                  |
| 7.0 kernel = no SR-IOV (Apr 2026)            | i915-sriov-dkms has `BUILD_EXCLUSIVE` blocking 7.0. Stock i915 in 7.0 lost SR-IOV sysfs support. Workaround = xe driver (`xe.max_vfs=7 xe.force_probe=0xa7a0 module_blacklist=i915`) — VFs visible in lspci but VM functional path unvalidated. Track strongtz/i915-sriov-dkms#429 |
| ESP capacity on systemd-boot hosts           | Reginald (Zimaboard, eMMC) ESP = 511M, fits ~5 kernels. Purge stale kernels BEFORE upgrade or postinst fails mid-initrd: `apt purge proxmox-kernel-X.Y.Z-N-pve-signed`                  |
| `proxmox-boot-tool kernel pin` ≠ systemd-boot | On systemd-boot hosts (no proxmox-boot-uuids file), `pin` only writes GRUB config which isn't used. Must manually edit `/boot/efi/loader/loader.conf` `default` line to specific entry  |
| Winston = GRUB, Reginald = systemd-boot      | Different bootloaders → different pin/default mechanisms. Always check `bootctl list` (systemd-boot) or `grub.cfg` `set default` (GRUB) before reboot                                   |
| `bootctl set-default` requires UEFI boot     | Returns "Not booted with UEFI" on hosts that booted via legacy/CSM. Edit `loader.conf` instead — that's persistent and bootloader-side                                                  |
| Stale kernels cleanup                        | `dpkg -l \| awk '/^rc.*proxmox-kernel/ {print $2}' \| xargs apt purge -y` removes residual configs after auto-removal                                                                  |
| Guest auto-start is sequential               | PVE waits per `startup: order=N,up=Ns` between VMs. With 5 guests + 30s delays, full stack restart can take 3-5 min. Don't panic if `qm list` shows stopped 90s after reboot            |
| Reboot verification checklist                | (1) `uname -r`, (2) `zpool status -x`, (3) `lspci \| grep -c VFs` if SR-IOV, (4) `dkms status`, (5) `qm list && pct list`, (6) sleep 60-90s and re-check guests                          |

> **Flatcar VM kernel 6.12.87 + i915-sriov-dkms**: Two upstream blockers — (1) DKMS 2025.07.22 references removed `__copy_from_user_inatomic_nocache` (shim required in `entrypoint.sh`); (2) DKMS 2026.03.05.x compat module needs `drm_gpuva_*` from kernel `CONFIG_DRM_GPUVM` which Flatcar does not enable (verify with `zcat /proc/config.gz | grep DRM_GPUVM`). Stay on 2025.07.22 + sed shim until Flatcar enables `DRM_GPUVM` or ships kernel ≥6.17.

### Pre-reboot pinning recipe

**GRUB host (winston):**

```bash
proxmox-boot-tool kernel pin <ver>-pve   # writes /etc/default/grub.d/proxmox-kernel-pin.cfg
grep 'set default' /boot/grub/grub.cfg   # verify
```

**systemd-boot host (reginald):**

```bash
sed -i 's|^default .*|default <machine-id>-<ver>-pve.conf|' /boot/efi/loader/loader.conf
bootctl list | grep -E 'title|default' | head   # verify (default) tag on intended kernel
```

## GPU SR-IOV

### VM Passthrough (Flatcar Sysext)

Intel iGPU SR-IOV passthrough to VMs requires patched `i915-sriov-dkms` in BOTH host AND guest. Stock kernel i915 fails with `MMIO returns 0xFFFFFFFF`. For Flatcar (immutable /usr), the module is packaged as a systemd-sysext squashfs image.

| Lesson                         | Detail                                                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Sysext `ID=_any`               | Use `ID=_any` in extension-release so sysext works across Flatcar versions; kernel specificity enforced by module path    |
| `updates/` priority            | Modules in `updates/` override `kernel/` in depmod — sysext module takes precedence over stock i915                       |
| Blacklist + explicit load      | Blacklist prevents udev auto-loading stock i915; `gpu-setup.service` explicitly loads after sysext activation             |
| Docker build can't bind-mount  | `docker build -v` doesn't exist — use `docker run` with bind-mount for compilation against host kernel headers            |
| Squashfs via Docker            | Flatcar lacks `mksquashfs` — run it inside an Alpine container                                                            |
| Auto-rebuild on kernel change  | `i915-sriov-rebuild.service` checks module path at boot; if kernel changed, rebuilds sysext via Docker                    |
| DKMS version must match kernel | DKMS 2025.07.22 targets 6.12.x, 2025.10.10 targets 6.17.x — mismatched version causes `Unknown symbol` at insmod          |
| GCC >= 14 required             | Flatcar kernel built with GCC 14.3 (`-fmin-function-alignment`); Dockerfile must use Debian trixie, not bookworm          |
| `insmod` not `modprobe`        | depmod can't write to read-only `/lib/modules` on Flatcar — use `insmod` with explicit sysext path                        |
| CONFIG_FOO=m breaks Makefile   | Flatcar sets `CONFIG_HWMON=m` not `=y`; `i915-$(CONFIG_HWMON)` becomes `i915-m`, bypasses `addprefix` — force to `i915-y` |
| Older DKMS has inline compat   | Tags <=2025.07.22 include compat backports in i915.ko itself; tags >=2025.10.10 have separate `intel_sriov_compat.ko`     |

### Unprivileged LXC GPU (3-layer fix)

| Layer                    | What                                                         | Why                                                                              |
| ------------------------ | ------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| 1. Proxmox `dev0`/`dev1` | `by-path` device with `gid=N`                                | Creates char device in container `/dev/dri/by-path/` but NOT standard names      |
| 2. Host udev rule        | Set VF device GID to **mapped** GID (100000 + container GID) | `lxc.mount.entry` bind mounts use HOST ownership; must match container's UID map |
| 3. `lxc.mount.entry`     | Bind-mount `/dev/dri/cardN` → `dev/dri/card0`                | Applications and Docker expect `/dev/dri/card0` + `/dev/dri/renderD128`          |

### Key Gotchas

| Gotcha                                                     | Detail                                                                                                               |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `gid=` in Proxmox dev must match **container's** group GID | `render` group GID varies per distro/image (108, 993, etc.) — always check `grep render /etc/group` inside container |
| Proxmox hookscripts run with `/bin/sh`                     | Ignores shebang — use POSIX syntax, no `[[ ]]`                                                                       |
| `mknod` blocked in unprivileged LXCs                       | Even with `c 226:* rwm` cgroup rule — kernel blocks `mknod` in user namespaces                                       |
| Docker `devices:` skips symlinks                           | Only picks up actual char devices, not symlinks. Use `lxc.mount.entry` bind mounts to create real device nodes       |
| Docker `--device` can't handle colons in paths             | `by-path` names contain `:` which Docker interprets as host:container separator                                      |
| Card minor = VF index, render minor = 128 + VF index       | `00:02.3` → card3 (minor 3) → renderD131 (minor 131)                                                                 |

## AWS SDK (Garage)

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```

## ZFS Tuning — Reginald (Zimaboard 832)

Reginald is hardware-constrained: Celeron N3450, **8 GB LPDDR4 soldered**, 7-drive SATA raidz2 (mix of brands, one QLC QVO), JMB58x HBA on PCIe 2.0 x2, storage LAN on 2.5 GbE USB NIC bond. Generic ZFS defaults are wrong for this box — apply via `scripts/hosts/reginald/zfs-tune.sh`.

| Lesson                              | Detail                                                                                                                                                     |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ARC sizing on 8 GB host             | Default 50% (4 GB) starves page cache. Set to **2.5 GB** — leaves room for 16 nfsd threads + LXC + Proxmox daemons without thrashing. Validate via `arc_summary`. |
| ARC ghost lists signal undersizing  | `mru_ghost_size` + `mfu_ghost_size` > c_max means shrinking more will thrash. Don't cut blindly; offload with `primarycache=metadata`.                     |
| zram is not "swapping to disk"      | Reginald has zramswap.service (zstd L3, 15%). `swap used` > 0 is fine if zd0 shows 0 B. Check `swapon --show` before diagnosing swap pressure.             |
| zstd-3 on Apollo Lake is expensive  | N3450 is weak. On datasets with 1.0x ratio (media, photos, nextcloud blobs) it's pure CPU waste. Use `lz4` except where ratio justifies it (immich DB).    |
| primarycache=metadata on media      | Plex streams each movie once — caching data blocks in ARC evicts hot nextcloud/immich-db pages. Set metadata-only on `rpool/shared/media` + tv/music children. |
| logbias=latency without SLOG        | `throughput` skips ZIL and writes direct to pool, costing latency on sync NFS writes. With no SLOG, `latency` (in-pool ZIL) wins for nextcloud/vaultwarden. |
| `zfs_dirty_data_max` bounded by NIC | Default 10% of RAM = too much when wire is 2.5 GbE. 512 MB flushes in ~2 s, matches storage LAN throughput without holding RAM hostage.                    |
| `vm.dirty_ratio` double-buffers     | Default 60/20 stacks on top of ZFS dirty buffer. Set 20/10 on any ZFS-heavy NFS server.                                                                    |
| Keep `rpool/swap` zvol as failsafe  | 0 B used, but zram is only 1.2 GB. If zram fills, zvol is the OOM cushion. Don't remove just because it looks idle.                                        |
| autotrim on all-SSD pools           | Must be explicitly enabled (`zpool set autotrim=on`). Not the default. Critical >70% capacity to keep SSD FTL healthy.                                     |
| Hardlinks across media datasets     | Sonarr/Radarr/Lidarr hardlink from `/media/downloads` to movies/tv/music. `du` on downloads overstates real usage. `zfs list` USED on parent is truthful.  |
| ORICO SSD on JMB58x flaky           | `sdg` has recurring READ/CKSUM errors. Before replacing the disk, swap to a different JMB58x port — the HBA controller may be the fault, not the drive.   |
