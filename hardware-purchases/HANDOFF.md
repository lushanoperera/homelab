# Handoff: Hardware Purchases Research

## Context

Researching hardware purchases for a **3-node Proxmox HA cluster with Ceph storage over Thunderbolt 4 ring**:

1. **NAS HDDs**: 4-6TB CMR drives for QNAP NAS or future ZFS pool
2. **DDR5 RAM**: 64GB (2x32GB) DDR5-5600 SO-DIMM for MS-01 (x3 nodes)
3. **MS-01 Units (x2)**: i9-13900H barebones — nodes 2 and 3 (Winston is node 1)
4. **NVMe Boot (x3)**: 256GB M.2 2280 — Proxmox OS on each node
5. **NVMe Ceph (x3)**: 512GB-2TB M.2 2280 high-endurance — Ceph OSD/cache per node
6. **TB4 Cables (x3)**: Thunderbolt 4 cables for Ceph replication ring

## Location Constraint

User is in **Italy** — all purchases must be **EU-only** (no UK post-Brexit, no non-EU international). EU consumer law gives 2-year warranty minimum and 14-day return right.

## What Was Done

### Phase 1 (Initial Research)

- [x] Ran `fabric` on YouTube video about saving money on NAS HDDs
- [x] Created project structure at `hardware-purchases/`
- [x] Populated EU prices for 6 NAS HDD models from idealo.it, Geizhals.de, Amazon.it
- [x] Populated EU prices for 3 DDR5 SO-DIMM kits with MS-01 compatibility data
- [x] Added cost-per-TB analysis — 6TB sweet spot (~30 EUR/TB vs 39 EUR/TB for 4TB)
- [x] Added shucking research — WD My Book 8TB at ~170 EUR = 21 EUR/TB
- [x] Created DDR5 buying guide with DRAM market context and clear recommendation
- [x] Noted Amazon Spring Sale active March 2026

### Phase 2 (Cluster Expansion)

- [x] Created MS-01 buying guide — new + used pricing, EU platforms, risk factors
- [x] Created NVMe buying guide — boot (256GB) + Ceph/cache (512GB-2TB) with endurance analysis
- [x] Created Thunderbolt Ceph ring guide — topology, cable types, Linux networking, Proxmox config
- [x] Updated price-tracking.md with MS-01, NVMe, TB4 cable sections + used marketplace monitoring
- [x] Updated CLAUDE.md with cluster architecture, expanded shopping list, new file tree
- [x] Updated HANDOFF.md (this file)

## What's Next

### Immediate (Purchase Decisions)

- **Buy DDR5 RAM** — Crucial CT2K32G56C46S5 recommended, prices rising. Need 3x kits for cluster.
- **Buy NAS HDDs** — Toshiba N300 6TB or WD Red Plus 6TB. Check Amazon Spring Sale.
- **Set up eBay alerts** — saved searches for "MS-01 i9-13900H" on eBay.it and eBay.de
- **Set up Keepa alerts** — price monitoring on Amazon.it/.de for NVMe drives and TB4 cables

### Short-Term (Procurement)

- **Acquire 2x MS-01** — monitor used market for deals; buy new if used prices stay above €500
- **Order NVMe drives** — 3x WD SN770 256GB (boot) + 3x Crucial T500 1TB (Ceph)
- **Order TB4 cables** — measure node distances first, then buy 3x passive (0.8m) or active (1.8m)
- **Verify WD My Book shucking** — check r/DataHoarders for 2026 batch CMR/SATA confirmation

### Medium-Term (Cluster Build)

- **Assemble nodes** — install DDR5 + NVMe in new MS-01 units
- **Install Proxmox** — boot from 256GB NVMe, configure networking
- **Set up TB4 ring** — thunderbolt-net module, static IPs, udev rules
- **Deploy Ceph** — cluster_network on TB ring, public_network on 2.5GbE
- **Migrate to HA** — move VMs/LXCs to HA groups, test failover

## Key Files to Read First

```
hardware-purchases/CLAUDE.md                                    # Overview + cluster architecture + shopping list
hardware-purchases/research/price-tracking.md                   # All prices with sources
hardware-purchases/reports/ms01-buying-guide.md                 # MS-01 procurement (new + used)
hardware-purchases/reports/nvme-buying-guide.md                 # NVMe boot + Ceph recommendations
hardware-purchases/reports/thunderbolt-ceph-ring-guide.md       # TB4 ring + Linux setup
hardware-purchases/reports/ddr5-ms01-buying-guide.md            # DDR5 compatibility + recommendation
hardware-purchases/reports/nas-hdd-buying-guide.md              # HDD strategy + cost analysis
```

## Resume Prompt

> Continue the hardware purchases project. I'm in Italy, EU-only. Building a 3-node Proxmox HA cluster with Ceph over TB4 ring. Research is done for all components — help me finalize purchases, set up price alerts, or plan the cluster build.
