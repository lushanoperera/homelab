# Winston - Primary Proxmox Host

## Hardware

| Component | Specification                            |
| --------- | ---------------------------------------- |
| Chassis   | Minisforum MS-01                         |
| CPU       | Intel i9-13900H (14C/20T, up to 5.2 GHz) |
| RAM       | 32 GB                                    |
| Proxmox   | 9.1.4 (Kernel 6.17.2-2-pve)              |

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

- SR-IOV GPU passthrough (7 VFs available, 3 assigned — see GPU section)
- Quick Sync hardware transcoding
- Thermal management (powersave governor, thermald)
- KSM enabled (`ksm-enable.service`) — deduplicates shared pages across LXCs
- Zram swap: 8 GB with zstd, swappiness=60

## GPU SR-IOV Allocation

| Consumer            | PCI Device   | Host Device        | Type             | Status    |
| ------------------- | ------------ | ------------------ | ---------------- | --------- |
| Plex (LXC 105)      | PF 00:02.0   | card0 / renderD128 | Privileged LXC   | Working   |
| Nextcloud (LXC 101) | VF 1 00:02.2 | card2 / renderD130 | Unprivileged LXC | Working   |
| Immich (LXC 103)    | VF 2 00:02.3 | card3 / renderD131 | Unprivileged LXC | Working   |
| Flatcar (VM 100)    | VF 0 00:02.1 | card1 / renderD129 | VM (sysext)      | Working   |
| VF 3-6              | 00:02.4-7    | card4-7            | —                | Available |

**Flatcar GPU**: Uses `i915-sriov-dkms` compiled as a systemd-sysext image. See `vms/flatcar-media/sysext/i915-sriov/` for build/deploy/test.

### Unprivileged LXC GPU Setup

Unprivileged LXCs need three things to use VF GPUs:

1. **Proxmox `dev0`/`dev1`** — by-path device with correct GID matching container's group
2. **Host udev rules** — set VF device GID to mapped GID (`99-sriov-lxc.rules`)
3. **`lxc.mount.entry`** — bind-mount host `/dev/dri/cardN` → container `/dev/dri/card0`

See `99-sriov-lxc.rules` in this directory for the udev rule deployed to `/etc/udev/rules.d/`.

## Storage

| Name          | Type | Size   | Purpose                   |
| ------------- | ---- | ------ | ------------------------- |
| local         | dir  | —      | ISOs, templates           |
| local-lvm     | lvm  | —      | Container rootfs, VM disk |
| pbs-backupnas | pbs  | —      | PBS backup target         |
| vmpool        | lvm  | 967 GB | VM disk images            |

## VMs

| VMID | Name          | IP                         | CPU | Memory               | Disk    | Purpose                     |
| ---- | ------------- | -------------------------- | --- | -------------------- | ------- | --------------------------- |
| 100  | flatcar-media | 192.168.100.100            | 4   | 8 GB (balloon: 2 GB) | 41.3 GB | Media stack                 |
| 102  | homeassistant | .100.102 / .4.102 / .5.102 | 2   | 4 GB (balloon: 1 GB) | 34.4 GB | Home Assistant (multi-VLAN) |

## LXC Containers

| CTID | Service   | IP              | CPU | Memory | Disk    |
| ---- | --------- | --------------- | --- | ------ | ------- |
| 101  | Nextcloud | 192.168.100.101 | 4   | 4 GB   | 53.7 GB |
| 103  | Immich    | 192.168.100.103 | 4   | 4 GB   | 21.5 GB |
| 104  | WireGuard | 192.168.100.104 | 1   | 512 MB | 4.3 GB  |
| 105  | Plex      | 192.168.100.105 | 4   | 3 GB   | 12.9 GB |
| 106  | PDM       | 192.168.100.106 | 1   | 512 MB | 10 GB   |

See `../../docs/thermal-management.md` for thermal configuration.
