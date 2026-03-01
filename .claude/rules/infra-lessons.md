---
paths:
  - "hosts/**"
  - "networking/**"
  - "storage/garage/**"
  - "storage/minio/**"
  - "scripts/migrations/**"
---

# Infrastructure Lessons

## Proxmox Networking

| Issue                                   | Solution                                                                                                                      |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| VM VLAN tag but no traffic (0 rx bytes) | Check `bridge-vids` on vmbr0 includes that VLAN                                                                               |
| Multicast/mDNS discovery broken in VM   | Remove `firewall=1` from NIC or add multicast allow rules                                                                     |
| DHCP works but discovery doesn't        | DHCP unicast succeeds even when multicast is filtered                                                                         |
| KSM persistence via sysctl              | PVE kernel has no /proc/sys/kernel/ksm/ — use systemd unit writing to /sys/kernel/mm/ksm/                                     |
| ksmtuned disables custom KSM            | ksmtuned only monitors QEMU, not LXCs — disable it if KSM always-on needed                                                    |
| Balloon config via `qm set`             | Persists immediately but takes effect on next VM reboot (no live disruption)                                                  |
| PBS storage offline                     | `pbs-backupnas` can timeout if QNAP NAS is unreachable — check `pvesm status` first                                           |
| LXC snapshot with NFS mounts            | `pct snapshot` fails ("feature not available") when LXC has NFS mountpoints (mp0/mp1) — use vzdump or docker rollback instead |
| pvesh storage content path              | `/nodes/<node>/storage/<id>/content` not `/storage/<id>/content`                                                              |
| No scheduled backups                    | Verify vzdump jobs exist via `pvesh get /cluster/backup` — currently returns `[]`                                             |

## GPU SR-IOV

Intel iGPU SR-IOV passthrough to Flatcar **not working** - guest requires patched `i915-sriov-dkms` driver. See `docs/sr-iov/` for details.

## AWS SDK (Garage)

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```
