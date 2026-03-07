# Reginald - Storage Host

## Hardware

| Component | Specification               |
| --------- | --------------------------- |
| Chassis   | Zimaboard 832               |
| CPU       | Intel Celeron N3450 (4C/4T) |
| RAM       | 8 GB                        |
| Expansion | SATA PCIe controller card   |
| Storage   | 7x SSD in ZFS RAIDZ2 pool   |
| Proxmox   | 9.1.6 (Kernel 6.17.9-1-pve) |

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

| VMID | Hostname   | IP              | CPU | Memory | Disk   | Service                    |
| ---- | ---------- | --------------- | --- | ------ | ------ | -------------------------- |
| 120  | technitium | 192.168.100.120 | 2   | 512 MB | 4.1 GB | Technitium DNS (secondary) |
| 123  | fileserver | 192.168.100.123 | 2   | 512 MB | 8.4 GB | Samba file share           |

See [lxc-120-technitium.md](lxc-120-technitium.md) for setup details.

## ZFS Pool

7x SSD in RAIDZ2 configuration.

| Metric    | Value   |
| --------- | ------- |
| Total     | ~9.3 TB |
| Used      | 7.36 TB |
| Available | 1.94 TB |
| Capacity  | 79%     |
