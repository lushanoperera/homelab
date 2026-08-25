---
paths:
  - "vms/flatcar-media/sysext/**"
  - "apps/immich/**"
  - "apps/nextcloud/**"
  - "**/gpu*"
  - "**/i915*"
  - "**/sriov*"
recall:
  - gpu
  - sr-iov
  - i915
  - sysext
  - transcoding
---

# GPU SR-IOV Operational Lessons

## Build & Deploy

| Issue                                 | Solution                                                                                                                                                                                                                                                       |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| kvmgt linker error during build       | The `entrypoint.sh` sed patterns remove `obj-m += kvmgt.o` from the DKMS Makefile. If build fails with kvmgt errors, the Docker image may have a stale entrypoint — rebuild with `--no-cache` or verify `/opt/i915-sriov-build/entrypoint.sh` matches the repo |
| `depmod -a` fails on Flatcar          | Expected — Flatcar `/lib/modules/` is read-only. The `gpu-setup.service` uses `insmod` with explicit sysext path instead of `modprobe`                                                                                                                         |
| Stock i915 loaded after kernel update | Auto-rebuild service (`i915-sriov-rebuild.service`) triggers at boot but may fail silently. Check `journalctl -u i915-sriov-rebuild.service` first                                                                                                             |
| Module swap at runtime                | `sudo rmmod i915 && sudo insmod /usr/lib/modules/$(uname -r)/updates/i915/i915.ko enable_guc=3` — no reboot needed if no consumers hold the module                                                                                                             |
| Compose files need `sudo sed`         | `/srv/docker/{immich,nextcloud}/` are root-owned — all sed/edit operations require sudo                                                                                                                                                                        |
| Kernel 6.12.87+ removes `__copy_from_user_inatomic_nocache` | `entrypoint.sh` sed-renames it to `__copy_from_user_inatomic` in `i915_gem.c` before make. Applies to DKMS 2025.07.22 series. Newer DKMS 2026.03.05.x is blocked by Flatcar's missing `CONFIG_DRM_GPUVM` |
| Picking a DKMS version for Flatcar    | Flatcar stable now ships kernel 6.12.95 (auto-updated 2026-07-09; stale note said 6.12.87). Kernels ≤6.12.90 → DKMS `2025.07.22` (with the `nocache` shim above). Kernels 6.12.91+ → DKMS `2025.10.10` (auto-selected by `i915-sriov-rebuild.service`; ships a compat module, see below). DKMS 2026.03.05.x requires `CONFIG_DRM_GPUVM` which Flatcar disables |
| DKMS 2025.10.10 ships `intel_sriov_compat.ko` | This series splits `backport_*` symbols into a second module at `updates/i915-sriov-compat/intel_sriov_compat.ko`. **Must be insmod'ed BEFORE i915.ko** or i915 fails with "Unknown symbol backport_*" and `/dev/dri` never appears. `gpu-setup.service` has a guarded ExecStartPre for it (added 2026-07-09 after 6.12.95 auto-update broke GPU) |
| Picking a DKMS version for PVE host (kernel 7.0) | DKMS `2026.05.06` (released 2026-05-06) adds kernel 7.0.x support via PR #438. Works on kernel 6.17.x + 7.0.x simultaneously. Stale rule said 7.0 blocked by `BUILD_EXCLUSIVE` — that's pre-2026.05.06; not true after the release. Use 2026.05.06 on winston host alongside PVE 9.2. |

## GPU Consumer Containers (Immich, Nextcloud)

| Issue                           | Solution                                                                                                                                            |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Immich/Nextcloud no longer bind `/dev/dri` (2026-08-25) | Immich ML moved to LXC 107 on winston (host PF render node, like Plex). `immich-server` and `nextcloud-app` have no `devices:` block, so a Flatcar kernel update cannot take them down anymore. VF 0 on VM 100 has no consumer — the sysext is optional |
| GPU temporarily unavailable     | Comment out `devices:` in compose, `docker-compose up -d` to run without GPU. Re-enable when fixed                                                  |
| Immich ML hardware acceleration | Set `IMMICH_MACHINE_LEARNING_HARDWARE_ACCELERATION=intel` in `.env` — base `release` image handles it, no `-openvino` tag needed in recent versions |
| Docker compose on Flatcar       | Use `/opt/bin/docker-compose`, not `docker compose` (plugin not installed on read-only Flatcar)                                                     |
| GPU devices in container        | Both `renderD128` AND `card0` must be passed — some apps need card0 for capabilities enumeration                                                    |

## Recovery Checklist (GPU broken after kernel update)

1. Check if patched module exists: `ls /usr/lib/modules/$(uname -r)/updates/i915/i915.ko`
2. If missing → rebuild: `cd /opt/i915-sriov-build && sudo ./build.sh $(uname -r)`
3. Deploy sysext: `sudo cp i915-sriov.raw /etc/extensions/i915-sriov.raw && sudo systemd-sysext refresh`
4. Load compat module first (DKMS 2025.10.10+ only): `test -f /usr/lib/modules/$(uname -r)/updates/i915-sriov-compat/intel_sriov_compat.ko && sudo insmod ...intel_sriov_compat.ko`
5. Swap module: `sudo rmmod i915; sudo insmod /usr/lib/modules/$(uname -r)/updates/i915/i915.ko enable_guc=3`
6. Trigger udev: `sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=drm`
7. Verify: `/opt/bin/verify-gpu.sh` (expect 7/7 pass)
8. Re-enable GPU in containers: uncomment `devices:` in compose, `docker-compose up -d`
