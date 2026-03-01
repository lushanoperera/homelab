---
name: network-diagnostics
description: Network and WiFi diagnostics for UniFi infrastructure
tools: Bash, Read
---

# Network Diagnostics

Run WiFi assessment and network inventory with guided interpretation.

## When to Use

- WiFi performance issues or interference
- After adding/moving APs
- Periodic network health checks
- Before/after WiFi optimization changes

## Instructions

### Phase 1: Network Health

Check gateway and network health:

```bash
./scripts/network/unifi-inventory.sh --health
```

Expected: All networks UP, gateway healthy.

### Phase 2: WiFi Radio Assessment

Run WiFi radio analysis:

```bash
./scripts/network/unifi-inventory.sh --wifi
```

Parse output for issues:

1. **Co-channel interference** (HIGH): Same channel on multiple APs in same band
2. **DFS channel warnings** (MEDIUM): UNII-2/2e range (ch 52-140) — subject to radar detection and CAC delays
3. **High channel utilization** (HIGH): >50% `cu_total` on any radio
4. **Low satisfaction** (MEDIUM): Score <50 (note: -1 = N/A, insufficient samples)
5. **TX power mismatches** (LOW): Unusual power levels for deployment size

### Phase 3: Mesh Topology

Check for mesh constraints:

- Mesh APs share 5 GHz channel with parent — cannot optimize independently
- Camera AP is meshed to Salotto — same 5 GHz channel required

If mesh AP channel conflicts found, note that Ethernet backhaul is the only fix.

### Phase 4: Full Inventory (if needed)

For deeper investigation:

```bash
# All clients with connection details
./scripts/network/unifi-inventory.sh --clients

# Network/VLAN configuration
./scripts/network/unifi-inventory.sh --networks

# Device details
./scripts/network/unifi-inventory.sh --devices

# JSON for programmatic analysis
./scripts/network/unifi-inventory.sh --wifi --json
```

### Phase 5: Recommendations

If issues found:

1. Suggest running `./scripts/network/unifi-wifi-optimize.sh --dry-run` to preview changes
2. Review proposed changes before applying
3. Apply with `./scripts/network/unifi-wifi-optimize.sh --apply`
4. Rollback available via `./scripts/network/unifi-wifi-optimize.sh --rollback`

## Output Format

```
## Network Diagnostics Report

### Gateway Health
- Status: Healthy/Degraded
- Uptime: X days
- Networks: X/X UP

### WiFi Assessment
| AP | Band | Channel | Width | Utilization | Satisfaction | Issues |
|----|------|---------|-------|-------------|--------------|--------|

### Issues Found
- [HIGH] Description
- [MEDIUM] Description
- [LOW] Description

### Recommendations
1. [Action if any]

### Mesh Topology
- [AP name] → meshed to [parent] (shared ch X)
```

## Troubleshooting

### Script Fails to Connect

Check credentials exist:

```bash
ls -la scripts/network/.env
```

If missing, copy from example:

```bash
cp scripts/network/.env.example scripts/network/.env
# Edit with UniFi local admin credentials
```

### Empty WiFi Data

APs may be adopting or updating. Check device status:

```bash
./scripts/network/unifi-inventory.sh --devices --json | jq '.[].state'
```
