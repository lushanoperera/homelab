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

## PBS / Vzdump

- `/etc/pve/jobs.cfg` lives in pmxcfs (cluster filesystem) — **lost on bare-metal reinstall**. After any Proxmox rebuild, verify vzdump jobs exist: `cat /etc/pve/jobs.cfg`
- Backup gap Oct 2025 – Mar 2026: jobs.cfg not preserved during winston rebuild, no scheduled backups ran for ~5 months. Recreated 2026-03-01.
- Manual backup verification: `pvesh get /nodes/{node}/tasks --typefilter vzdump --limit 5`
- PBS storage on Storage LAN (192.168.200.x) — check connectivity separately from Infra LAN (192.168.100.x)
- PBS on QNAP intermittently slow (high memory/load) — causes `read timeout` in pvestatd, but vzdump transfers complete fine

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
