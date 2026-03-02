# Winston Host Scripts

Maintenance and monitoring scripts for **winston** (192.168.100.38), the primary Proxmox VE host.

## Scripts

| Script              | Deploy Path               | Schedule             | Purpose                                                        |
| ------------------- | ------------------------- | -------------------- | -------------------------------------------------------------- |
| `gpu-freq-watch.sh` | `/root/gpu-freq-watch.sh` | Manual (interactive) | Live GPU frequency, SR-IOV VF status, and container monitoring |

Also see `../check-nfs-mounts.sh` — shared NFS mount checker used on winston at boot.

## Deployment

```bash
scp scripts/hosts/winston/gpu-freq-watch.sh root@192.168.100.38:/root/
```

## Usage

```bash
# Interactive GPU monitor (refreshes every 1s, Ctrl+C to exit)
ssh root@192.168.100.38 '/root/gpu-freq-watch.sh'
```
