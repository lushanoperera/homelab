# Reginald - Storage Host

## Hardware

| Component | Specification |
|-----------|---------------|
| Chassis | Zimaboard 832 |
| CPU | Intel Celeron N3450 (4C/4T) |
| Expansion | SATA PCIe controller card |
| Storage | 7x SSD in ZFS RAIDZ2 pool |

## Network

| Interface | IP | Purpose |
|-----------|-----|---------|
| Infra | 192.168.100.4 | Management |
| Storage | 192.168.200.4 | NFS server |

## SSH

```bash
ssh root@192.168.100.4
```

## Role

Primary NFS server for LXC container data on winston. Storage LAN (192.168.200.0/24) provides dedicated bandwidth for NFS traffic.

## ZFS Pool

7x SSD in RAIDZ2 configuration.
