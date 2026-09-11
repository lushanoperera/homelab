# Reginald - Storage Host

## Hardware

| Component | Specification               |
| --------- | --------------------------- |
| Chassis   | Zimaboard 832               |
| CPU       | Intel Celeron N3450 (4C/4T) |
| RAM       | 8 GB                        |
| Expansion | SATA PCIe controller card   |
| Storage   | 7x SSD in ZFS RAIDZ2 pool   |
| Proxmox   | 9.2.18 (Kernel 7.0.14-16-pve) |

## Network

| Interface | Bridge        | IP            | Purpose    |
| --------- | ------------- | ------------- | ---------- |
| Infra     | vmbr0         | 192.168.100.4 | Management |
| Storage   | vmbr1 (bond0) | 192.168.200.4 | NFS server |

## SSH

```bash
ssh root@192.168.100.4
```

## Role

Primary NFS server for media, Nextcloud, Immich, and Vaultwarden data. Storage LAN (192.168.200.0/24) provides dedicated bandwidth for NFS traffic.

## LXC Containers

| VMID | Hostname   | IP              | CPU | Memory | Disk   | Service                     |
| ---- | ---------- | --------------- | --- | ------ | ------ | --------------------------- |
| 120  | technitium | 192.168.100.120 | 2   | 512 MB | 4.1 GB | Technitium DNS (secondary)  |
| 123  | fileserver | 192.168.100.123 | 1   | 384 MB | 6 GB   | Samba + Cockpit (Debian 13) |

See [lxc-120-technitium.md](lxc-120-technitium.md) for Technitium DNS setup details.
See [lxc-123-samba.md](lxc-123-samba.md) for Samba file server setup details.

### LXC 123 restored to running (2026-09-11)

LXC 123 was found stopped with `onboot: 0`, with no PVE start record since 2026-04-15. The intended
state is RUNNING (user decision 2026-09-11), and it is now running with `onboot: 1`:

- The cutover procedure in [lxc-123-samba.md](lxc-123-samba.md) sets `--onboot 1`, and nothing in
  that document retires or deprecates the container.
- Nextcloud on VM 100 depends on it. `occ setupchecks` had exactly one error, the `/NAS` external
  storage mount that points at this Samba share, with 828 log entries across 2026-09-10 and -11.

Verified after the start: `smbd` active (Samba 4.22.10), port 445 reachable, both `[Media]` and
`[Lushano]` shares present with their paths intact. The container was 153 packages behind (89 of
them security) and is now fully patched with zero failed units. The Nextcloud mount then failed
with "Storage unauthorized" (stale SMB password); the user re-entered the password in Nextcloud and
`occ files_external:verify 2` returns ok.

Open item: `/rpool/shared/media` is owned by UID/GID 100000, unlike `/rpool/shared/lushano` which is
`lushano:mediauser`. The `[Media]` share may misbehave for `mediauser`. Not investigated here.

## Services

### openipmi — intentionally masked (2026-09-11)

`openipmi.service` failed continuously since 2026-05-22. The Zimaboard 832 has no BMC:
`ipmi_si: Unable to find any System Interface(s)` at boot, no `/dev/ipmi*` node, and
`dmidecode -t 38` returns no IPMI Device Information record. The intended state is therefore
disabled, not repaired:

```bash
systemctl disable openipmi && systemctl mask openipmi
```

Unmask only if reginald is ever replaced by hardware that has a BMC.

## ZFS Pool

7x SSD in RAIDZ2 configuration.

| Metric    | Value   |
| --------- | ------- |
| Total     | ~9.3 TB |
| Used      | 7.36 TB |
| Available | 1.94 TB |
| Capacity  | 79%     |
