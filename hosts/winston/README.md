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

`pct config 105` reports `unprivileged: 0` (privileged), but part of the rootfs is still owned by
UID/GID **100000** and its derivatives — the unprivileged ID-map base. The container was converted
from unprivileged to privileged (to reach the iGPU PF) without remapping rootfs ownership.

Census taken 2026-09-11 with `find / -xdev -printf '%U\n' | sort | uniq -c`:

| UID | Files | Correct? |
| --- | --- | --- |
| 0 | 34,901 | yes |
| 999 (plex) | 15,021 | yes |
| **100000** | **3,102** | **no — shifted root** |
| 100101 / 100102 | 48 | no — shifted 101 / 102 |

So roughly 6% of the rootfs is misowned, and the split widens with every upgrade: packages
installed since the conversion write UID 0, the originals stay at 100000.

### Fixed 2026-09-11 with targeted, minimal changes

All five failed units are now resolved and the container reports zero failed units.

| Unit | Cause | Fix applied |
| --- | --- | --- |
| `logrotate.service` | `Ignoring /etc/logrotate.conf because the file owner is wrong` — logs had not rotated since at least Sep 8 | `chown 0:0` on `/etc/logrotate.conf`, `/etc/logrotate.d` and its 9 files. Service now exits 0 |
| `postfix.service` | `postsuper: fatal: scan_dir_push: open directory hold: Permission denied`, then `open lock file /var/lib/postfix/master.lock: Permission denied` | `postfix set-permissions`, then `chown 102:109 /var/lib/postfix/master.lock` (it was 100102:100109). Service now active |
| `motd-news.service` | `Unable to locate executable /etc/update-motd.d/50-motd-news: Permission denied` — files were 100000-owned AND mode 644 | `chown 0:0` plus `chmod 0755`. The 0755 mode is the packaged one, verified against `dpkg -c` on `base-files` and `update-notifier-common`, not invented |
| `apparmor.service` | `apparmor_parser: Access denied. You need policy admin privileges to manage profiles` | Masked. AppArmor policy belongs to the host; this is permanent, not a symptom of the UID split |
| `netplan-configure.service` | `udevadm: Failed to send reload request: No such file or directory` | Masked. No udev in an LXC, and networking here is set by PVE through `pct config`, not netplan |

### Resolved 2026-09-11 — offline selective remap

After a PBS backup (`vzdump 105 --mode snapshot`, notes `pre-uidshift-fix`) and a ZFS snapshot
`vmpool/subvol-105-disk-2@pre-uidshift-202609111634` (rollback point), the container was stopped and
every entry with a UID or GID in `100000..165535` was shifted down by 100000 on the rootfs dataset
(`chown -h` / `chgrp -h`, so symlink ownership was fixed without following links). Setuid/setgid
modes (26 files) were recorded before and restored after, because `chown` clears them.

| Shift | Entries |
| --- | --- |
| uid 100000 → 0 | 3098 |
| uid 100101 → 101, 100105 → 105 | 19 |
| gid 100000 → 0 | 3088 |
| gid 100004/8/42/43/50/104/112/113 → −100000 | 86 |

Result: 0 shifted entries remain, 26 setuid files intact, zero failed units, `logrotate` and
`motd-news` run with `Result=success`, postfix active, Plex HTTP 200 with `/dev/dri` present, no
permission errors in the journal since boot. The script is kept at `/root/lxc105-uidshift-fix.sh`
on winston. Delete the ZFS snapshot after a few clean days: `zfs destroy
vmpool/subvol-105-disk-2@pre-uidshift-202609111634`.

CAUTION: Do not run a blanket `chown -R 0:0` on this container. It would rewrite the 15,021 files
that must stay owned by UID 999 (plex).


See `../../docs/thermal-management.md` for thermal configuration.
