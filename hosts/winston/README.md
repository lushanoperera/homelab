# Winston - Primary Proxmox Host

## Hardware

| Component | Specification                            |
| --------- | ---------------------------------------- |
| Chassis   | Minisforum MS-01                         |
| CPU       | Intel i9-13900H (14C/20T, up to 5.2 GHz) |
| RAM       | 32 GB                                    |
| Proxmox   | 9.1.6 (Kernel 6.17.13-1-pve)             |

## Network

| Interface | Bridge/Dev | IP             | Purpose                                                       |
| --------- | ---------- | -------------- | ------------------------------------------------------------- |
| Infra     | vmbr0      | 192.168.100.38 | Management (VLANs 4,5,7,100)                                  |
| Storage   | vmbr1      | 192.168.200.38 | NFS, backups                                                  |
| wg-nwlab  | WireGuard  | 10.0.0.5       | nwlab site-to-site tunnel (routes 10.0.0.0/24, 10.21.21.0/24) |

## SSH

```bash
ssh root@192.168.100.38
```

## Features

- SR-IOV GPU passthrough (7 VFs available, 1 assigned to VM 100 — see GPU section)
- Quick Sync hardware transcoding
- Thermal management (powersave governor, thermald)
- KSM enabled (`ksm-enable.service`) — deduplicates shared pages across LXCs
- Zram swap: 8 GB with zstd, swappiness=60

## GPU SR-IOV Allocation

| Consumer         | PCI Device   | Host Device        | Type           | Status    |
| ---------------- | ------------ | ------------------ | -------------- | --------- |
| Plex (LXC 105)   | PF 00:02.0   | card0 / renderD128 | Privileged LXC | Working   |
| Flatcar (VM 100) | VF 0 00:02.1 | card1 / renderD129 | VM (sysext)    | Working   |
| VF 1-6           | 00:02.2-7    | card2-7            | —              | Available |

Flatcar VM 100 shares VF 0 across Nextcloud, Immich, and media stack containers via Docker device mapping.

**Flatcar GPU**: Uses `i915-sriov-dkms` compiled as a systemd-sysext image. See `vms/flatcar-media/sysext/i915-sriov/` for build/deploy/test.

## Storage

| Name          | Type | Size   | Purpose                   |
| ------------- | ---- | ------ | ------------------------- |
| local         | dir  | —      | ISOs, templates           |
| local-lvm     | lvm  | —      | Container rootfs, VM disk |
| pbs-backupnas | pbs  | —      | PBS backup target         |
| vmpool        | lvm  | 967 GB | VM disk images            |

## VMs

| VMID | Name          | IP                         | CPU | Memory                | Disk    | Purpose                     |
| ---- | ------------- | -------------------------- | --- | --------------------- | ------- | --------------------------- |
| 100  | flatcar-media | .100.100/.101/.103         | 4   | 16 GB (balloon: 8 GB) | 41.3 GB | Media + Nextcloud + Immich  |
| 102  | homeassistant | .100.102 / .4.102 / .5.102 | 2   | 4 GB (balloon: 2 GB)  | 34.4 GB | Home Assistant (multi-VLAN) |

## LXC Containers

| CTID | Service   | IP              | CPU | Memory | Disk    | OS              |
| ---- | --------- | --------------- | --- | ------ | ------- | --------------- |
| 104  | WireGuard | 192.168.100.104 | 1   | 512 MB | 4.3 GB  | Debian 12       |
| 105  | Plex      | 192.168.100.105 | 4   | 3 GB   | 12.9 GB | Ubuntu 26.04    |
| 106  | PDM       | 192.168.100.106 | 1   | 512 MB | 10 GB   | Debian 12       |

See `../../docs/thermal-management.md` for thermal configuration.
