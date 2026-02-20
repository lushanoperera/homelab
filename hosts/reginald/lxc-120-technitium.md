# LXC 120 - Technitium DNS (Reginald)

Replaces previous Pi-hole LXC. Technitium runs as native install (no Docker needed on Zimaboard).

## Specs

| Setting | Value |
|---------|-------|
| VMID | 120 |
| Hostname | technitium |
| IP | 192.168.100.120/24 |
| Gateway | 192.168.100.1 |
| Memory | 512 MB |
| Cores | 2 |
| Disk | 4 GB (local-lvm) |
| OS | Debian 12 |
| Type | Unprivileged |

## Installation

```bash
# On Reginald - create Debian 12 LXC
pct create 120 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname technitium \
  --memory 512 \
  --cores 2 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.100.120/24,gw=192.168.100.1 \
  --storage local-lvm \
  --rootfs local-lvm:4 \
  --unprivileged 1 \
  --start 1

# Install Technitium inside LXC
pct exec 120 -- bash -c '
  apt update && apt install -y curl
  curl -sSL https://download.technitium.com/dns/install.sh | bash
'
```

## Web UI

```
http://192.168.100.120:5380
```

## Cluster Role

Secondary node in 3-node Technitium cluster (domain: `dns.disconnesso.home.arpa`). Joins primary at `https://192.168.100.254:53443`.

## Rollback

Restore from PBS backup (original Pi-hole LXC):
```bash
pct restore 120 <PBS_BACKUP_PATH> --storage local-lvm
pct start 120
```
