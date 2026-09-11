# Winston - Primary Proxmox Host

## Hardware

| Component | Specification                            |
| --------- | ---------------------------------------- |
| Chassis   | Minisforum MS-01                         |
| CPU       | Intel i9-13900H (14C/20T, up to 5.2 GHz) |
| RAM       | 32 GB                                    |
| Proxmox   | 9.2.18 (running 7.0.2-6-pve; 7.0.14-16-pve installed, pending reboot) |

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

## LXC 105 (Plex) — rootfs UID-shift inconsistency (found 2026-09-11)

`pct config 105` reports `unprivileged: 0` (privileged), but most of the rootfs is still owned by
UID/GID **100000** — the unprivileged ID-map base. The container was converted from unprivileged to
privileged (to reach the iGPU PF) without shifting rootfs ownership back to UID 0.

The split widens with every upgrade: packages installed since the conversion write UID 0, the
original files stay at 100000. Measured in `/etc` on 2026-09-11: 402 entries at UID 0, 1070 at
UID 100000.

Three services fail from this single cause:

| Unit | Error |
| --- | --- |
| `logrotate.service` | `Ignoring /etc/logrotate.conf because the file owner is wrong` — **logs are not rotating** |
| `motd-news.service` | `Unable to locate executable /etc/update-motd.d/50-motd-news: Permission denied` |
| `postfix.service` | `postsuper: fatal: scan_dir_push: open directory hold: Permission denied` |

Plex itself is unaffected (`/var/lib/plexmediaserver` is 999:999 and the service answers HTTP 200).

**Do not run a blanket `chown -R 0:0`** — that would also rewrite the 402 entries that are already
correct. The remediation is to shift only the 100000-owned entries, from a PBS restore or offline:

```bash
pct stop 105
# on the rootfs, shift ONLY the entries still at the unprivileged base
find <rootfs> -uid 100000 -exec chown -h 0 {} +
find <rootfs> -gid 100000 -exec chgrp -h 0 {} +
pct start 105
```

Take a PBS backup first. This has not been done — the three units above remain failed.

`apparmor.service` and `netplan-configure.service` were masked on 2026-09-11 for a different,
permanent reason: both are inapplicable inside an LXC. AppArmor policy is owned by the host
(`apparmor_parser: Access denied. You need policy admin privileges to manage profiles`) and
`netplan-configure` calls `udevadm`, which has no udev to talk to (`Failed to send reload request`).
Networking for this container is set by PVE through `pct config`, not netplan.

See `../../docs/thermal-management.md` for thermal configuration.
