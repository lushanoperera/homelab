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

## GPU Consumer Containers (Immich, Nextcloud)

| Issue                           | Solution                                                                                                                                            |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| GPU temporarily unavailable     | Comment out `devices:` in compose, `docker-compose up -d` to run without GPU. Re-enable when fixed                                                  |
| Immich ML hardware acceleration | Set `IMMICH_MACHINE_LEARNING_HARDWARE_ACCELERATION=intel` in `.env` — base `release` image handles it, no `-openvino` tag needed in recent versions |
| Docker compose on Flatcar       | Use `/opt/bin/docker-compose`, not `docker compose` (plugin not installed on read-only Flatcar)                                                     |
| GPU devices in container        | Both `renderD128` AND `card0` must be passed — some apps need card0 for capabilities enumeration                                                    |

## Recovery Checklist (GPU broken after kernel update)

1. Check if patched module exists: `ls /usr/lib/modules/$(uname -r)/updates/i915/i915.ko`
2. If missing → rebuild: `cd /opt/i915-sriov-build && sudo ./build.sh $(uname -r)`
3. Deploy sysext: `sudo cp i915-sriov.raw /etc/extensions/i915-sriov.raw && sudo systemd-sysext refresh`
4. Swap module: `sudo rmmod i915; sudo insmod /usr/lib/modules/$(uname -r)/updates/i915/i915.ko enable_guc=3`
5. Trigger udev: `sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=drm`
6. Verify: `/opt/bin/verify-gpu.sh` (expect 7/7 pass)
7. Re-enable GPU in containers: uncomment `devices:` in compose, `docker-compose up -d`
