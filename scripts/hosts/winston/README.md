# Winston Host Scripts

Maintenance and monitoring scripts for **winston** (192.168.100.38), the primary Proxmox VE host.

## Scripts

| Script              | Deploy Path               | Schedule             | Purpose                                                        |
| ------------------- | ------------------------- | -------------------- | -------------------------------------------------------------- |
| `gpu-freq-watch.sh` | `/root/gpu-freq-watch.sh` | Manual (interactive) | Live GPU frequency, SR-IOV VF status, and container monitoring |
| `aim-history-watch.sh` | `/usr/local/bin/aim-history-watch.sh` | `systemd/aim-history-watch.timer`, every 15 min | Reads `aim-history.service` on VM 100 through the guest agent; posts to ntfy `homelab-alerts` on a state change (failed, or no success for 2 h) |
| `ipv6-pd-watch.sh` | `/usr/local/bin/ipv6-pd-watch.sh` | `systemd/ipv6-pd-watch.timer`, every minute | Pings public IPv6 from LXC 108 (Navigabene /56, ticket VYU-510137); logs failures to `/var/log/ipv6-pd-watch.log`, posts to ntfy `homelab-alerts` on a state change |

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
