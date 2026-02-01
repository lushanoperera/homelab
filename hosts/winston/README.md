# Winston - Primary Proxmox Host

## Hardware

| Component | Specification                            |
| --------- | ---------------------------------------- |
| Chassis   | Minisforum MS-01                         |
| CPU       | Intel i9-13900H (14C/20T, up to 5.2 GHz) |
| RAM       | TBD                                      |
| Network   | 2.5GbE + Storage LAN                     |

## Network

| Interface | IP             | Purpose      |
| --------- | -------------- | ------------ |
| Infra     | 192.168.100.38 | Management   |
| Storage   | 192.168.200.38 | NFS, backups |

## SSH

```bash
ssh root@192.168.100.38
```

## Features

- SR-IOV GPU passthrough (7 VFs available)
- Quick Sync hardware transcoding
- Thermal management (powersave governor, thermald)

## LXC Containers

| CTID | Service   |
| ---- | --------- |
| 101  | Nextcloud |
| 103  | Immich    |
| 104  | WireGuard |
| 105  | Plex      |

## VMs

| VMID | Name          | Purpose     |
| ---- | ------------- | ----------- |
| 100  | flatcar-media | Media stack |

See `../../docs/thermal-management.md` for thermal configuration.
