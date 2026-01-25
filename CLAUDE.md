# CLAUDE.md - Proxmox Homelab Project

## Host Inventory

| Host | IP | Role |
|------|------|------|
| winston | 192.168.100.38 | Proxmox VE host |
| reginald | 192.168.100.4 | Proxmox VE host |

## SSH Access

```bash
# Connect to hosts
ssh root@192.168.100.38  # winston
ssh root@192.168.100.4   # reginald
```

## Common Operations

```bash
# Check Proxmox version
pveversion

# List VMs
qm list

# List containers
pct list

# Check storage
pvesm status

# Check cluster status
pvecm status
```

## Safety Rules

**HARD BLOCK - Always confirm before:**
- `rm -rf` or any recursive deletion
- VM/container destruction (`qm destroy`, `pct destroy`)
- Storage removal
- Network configuration changes
- Cluster operations

**Never:**
- Run destructive commands without explicit user confirmation
- Modify production VMs without backup verification
- Change network settings that could cause connectivity loss
