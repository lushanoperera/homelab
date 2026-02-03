---
name: proxmox-manage
description: Proxmox VM/LXC management - list, start, stop, snapshots, migrations
allowed-tools: Bash, Read
---

# Proxmox Management

Manage VMs and LXC containers across Proxmox hosts.

## Hosts

| Host     | IP             | Role                |
| -------- | -------------- | ------------------- |
| winston  | 192.168.100.38 | Primary PVE         |
| reginald | 192.168.100.4  | Secondary PVE + NFS |

## VMs and LXCs

| ID  | Name          | Type | Host    | Purpose      |
| --- | ------------- | ---- | ------- | ------------ |
| 100 | flatcar-media | VM   | winston | Media stack  |
| 101 | nextcloud     | LXC  | winston | File sync    |
| 103 | immich        | LXC  | winston | Photos       |
| 104 | wireguard     | LXC  | winston | VPN          |
| 105 | plex          | LXC  | winston | Media server |

## Instructions

### List VMs and Containers

All VMs:

```bash
ssh root@192.168.100.38 'qm list'
ssh root@192.168.100.4 'qm list'
```

All LXCs:

```bash
ssh root@192.168.100.38 'pct list'
ssh root@192.168.100.4 'pct list'
```

### Check Status

VM status:

```bash
ssh root@192.168.100.38 'qm status [vmid]'
```

LXC status:

```bash
ssh root@192.168.100.38 'pct status [ctid]'
```

### Start/Stop/Restart

VM:

```bash
ssh root@192.168.100.38 'qm start [vmid]'
ssh root@192.168.100.38 'qm stop [vmid]'
ssh root@192.168.100.38 'qm reboot [vmid]'
ssh root@192.168.100.38 'qm shutdown [vmid]'  # graceful
```

LXC:

```bash
ssh root@192.168.100.38 'pct start [ctid]'
ssh root@192.168.100.38 'pct stop [ctid]'
ssh root@192.168.100.38 'pct reboot [ctid]'
ssh root@192.168.100.38 'pct shutdown [ctid]'  # graceful
```

### Resource Usage

VM resources:

```bash
ssh root@192.168.100.38 'qm monitor [vmid] -c "info status"'
```

All resources:

```bash
ssh root@192.168.100.38 'pvesh get /nodes/winston/status'
```

Per-guest resources:

```bash
ssh root@192.168.100.38 'pvesh get /cluster/resources --type vm'
```

### Snapshots

Create snapshot:

```bash
# VM
ssh root@192.168.100.38 'qm snapshot [vmid] [snapname] --description "reason"'

# LXC
ssh root@192.168.100.38 'pct snapshot [ctid] [snapname] --description "reason"'
```

List snapshots:

```bash
ssh root@192.168.100.38 'qm listsnapshot [vmid]'
ssh root@192.168.100.38 'pct listsnapshot [ctid]'
```

Rollback:

```bash
ssh root@192.168.100.38 'qm rollback [vmid] [snapname]'
ssh root@192.168.100.38 'pct rollback [ctid] [snapname]'
```

Delete snapshot:

```bash
ssh root@192.168.100.38 'qm delsnapshot [vmid] [snapname]'
ssh root@192.168.100.38 'pct delsnapshot [ctid] [snapname]'
```

### Migration

Migrate VM between hosts (online):

```bash
ssh root@192.168.100.38 'qm migrate [vmid] reginald --online'
```

Migrate LXC:

```bash
ssh root@192.168.100.38 'pct migrate [ctid] reginald'
```

Check migration status:

```bash
ssh root@192.168.100.38 'qm status [vmid]'
```

### Backup

Manual backup to PBS:

```bash
ssh root@192.168.100.38 'vzdump [vmid] --storage pbs --mode snapshot'
```

Check backup jobs:

```bash
ssh root@192.168.100.38 'cat /etc/pve/jobs.cfg'
```

### Configuration

View VM config:

```bash
ssh root@192.168.100.38 'qm config [vmid]'
```

View LXC config:

```bash
ssh root@192.168.100.38 'pct config [ctid]'
```

Modify config (example - add memory):

```bash
ssh root@192.168.100.38 'qm set [vmid] --memory 8192'
ssh root@192.168.100.38 'pct set [ctid] --memory 4096'
```

### Console Access

VM console:

```bash
ssh root@192.168.100.38 'qm terminal [vmid]'
```

LXC console:

```bash
ssh root@192.168.100.38 'pct enter [ctid]'
```

### Storage Status

```bash
ssh root@192.168.100.38 'pvesm status'
```

### Cluster Status

```bash
ssh root@192.168.100.38 'pvecm status'
```

## Safety Rules

**ALWAYS confirm before:**

- `qm destroy` / `pct destroy`
- Rollback to snapshot (loses current state)
- Migration of production VMs

**Recommended workflow:**

1. Create snapshot before changes
2. Make changes
3. Verify functionality
4. Delete snapshot if successful

## Output Format

```
## Proxmox Operation Report

### Action
[What was requested]

### Affected Resources
| ID | Name | Type | Host |
|----|------|------|------|
| 100 | flatcar-media | VM | winston |

### Result
[Success/Failure with details]

### Current State
[Output of status command]
```
