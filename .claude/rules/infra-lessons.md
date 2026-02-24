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

| Issue                                        | Solution                                                     |
| -------------------------------------------- | ------------------------------------------------------------ |
| VM VLAN tag but no traffic (0 rx bytes)      | Check `bridge-vids` on vmbr0 includes that VLAN              |
| Multicast/mDNS discovery broken in VM        | Remove `firewall=1` from NIC or add multicast allow rules    |
| DHCP works but discovery doesn't             | DHCP unicast succeeds even when multicast is filtered         |

## GPU SR-IOV

Intel iGPU SR-IOV passthrough to Flatcar **not working** - guest requires patched `i915-sriov-dkms` driver. See `docs/sr-iov/` for details.

## AWS SDK (Garage)

```bash
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```
