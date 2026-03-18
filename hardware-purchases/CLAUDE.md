# Hardware Purchases

Tracking hardware research, price monitoring, and purchase decisions for homelab upgrades.

## Cluster Architecture

Building a **3-node Proxmox HA cluster with Ceph storage** interconnected via a Thunderbolt 4 ring:

- **Node 1**: Winston (existing MS-01 i9-13900H, 32GB RAM, Proxmox VE 9.1.4)
- **Node 2**: New MS-01 i9-13900H barebones (to buy)
- **Node 3**: New MS-01 i9-13900H barebones (to buy)

**Networking**: 2.5GbE for client/public traffic, TB4 ring (40 Gbps per link) for Ceph replication.

```
  Winston (Node A)
   /            \
  TB4           TB4
 /                \
Node B ——TB4—— Node C
```

Each node: 1x 256GB NVMe (boot) + 1x 1TB NVMe (Ceph OSD) + 64GB DDR5.

**Winston's current NVMe drives:**

- nvme2n1: SanDisk SSD Plus 250GB (boot) — PCIe 3.0, DRAM-less, stays as boot
- nvme1n1: Kingston OM8PGP41024N-A0 1TB (VMs) — PCIe 4.0, DRAM, reuse as Ceph OSD
- nvme0n1: ORICO J10 1TB (NFS cache) — PCIe 3.0, DRAM-less, retire (spare/sell)

**NVMe strategy**: Keep Kingston 1TB as Winston's Ceph OSD. Buy 2x new 1TB with DRAM for new nodes. ORICO retired — DRAM-less drives unsuitable for Ceph write workload. NFS cache dropped — Reginald's 2.5GbE sufficient for media. ~1TB usable Ceph with 3 replicas. Upgrade to 2TB later if needed.

## Current Shopping List

| Item          | Target Specs                                | Budget        | Priority | Status                                 |
| ------------- | ------------------------------------------- | ------------- | -------- | -------------------------------------- |
| NAS HDDs      | 4-6TB CMR (Seagate Ironwolf / WD Red Plus)  | Best value    | High     | Prices found — ready to buy            |
| DDR5 RAM x3   | 64GB (2x32GB) DDR5-5600 SO-DIMM per node    | ~€357-480     | High     | Prices rising — buy ASAP               |
| MS-01 x2      | i9-13900H barebones (for cluster nodes 2+3) | ~€1,100-1,500 | High     | Research done — monitoring used market |
| NVMe Boot x2  | 256GB M.2 2280 (new nodes only)             | ~€70-90       | Medium   | Research done                          |
| NVMe Ceph x2  | 1TB M.2 2280 PCIe 4.0 with DRAM             | ~€160-200     | Medium   | Winston keeps Kingston; ORICO retired  |
| TB4 Cables x3 | 0.8m passive or 1.8m active for ring        | ~€75-270      | Medium   | Research done                          |
| Raspberry Pi  | Pi 4B/5 for NUT server (2x UPS via USB)     | ~€40-80       | High     | Needed — no UPS monitoring currently   |

## Quick Recommendations

| Item      | Pick                                     | Price (EUR)   | Why                                        |
| --------- | ---------------------------------------- | ------------- | ------------------------------------------ |
| NAS HDD   | Toshiba N300 6TB bulk OR WD Red Plus 6TB | ~178-187      | Best EUR/TB (~30/TB) for new CMR drives    |
| DDR5 RAM  | 3x Crucial CT2K32G56C46S5 (2x32GB)       | ~357+ (3x119) | Pre-installed in MS-01, best compat        |
| Shuck     | WD My Book 8TB (if CMR verified)         | ~170          | 21 EUR/TB — cheapest option                |
| MS-01     | Barebones i9-13900H (new or used)        | ~400-700 each | Used from eBay EU ~€400-550; new ~€550-700 |
| NVMe Boot | WD Blue SN580 256GB (or similar)         | ~30-35        | Budget boot, 2 new nodes only              |
| NVMe Ceph | 2x Crucial T500 1TB or WD SN850X 1TB     | ~80-100 each  | PCIe 4.0 + DRAM; Kingston stays on Winston |
| TB4 Cable | Cable Matters 0.8m passive               | ~25-35        | Budget pick for adjacent nodes             |

## Buying Strategy (EU/Italy)

- **Primary**: Amazon.it/.de/.fr/.es (cross-EU, no customs, 2-year EU warranty)
- **Refurbished**: Amazon Warehouse, EU-based refurb sellers
- **Used (MS-01)**: eBay.it/.de/.fr, Subito.it, Kleinanzeigen.de, Vinted, Facebook Marketplace
- **Price tracking**: Keepa (multi-region Amazon), Geizhals.de, idealo.it
- **Avoid**: UK sellers (post-Brexit customs), non-EU international (import duties + VAT)
- **Shucking**: WD My Book from Amazon EU — check r/DataHoarders for CMR models
- **Timing**: Amazon Spring Sale active NOW (March 2026). DDR5 prices rising — buy sooner.
- **Used MS-01 tips**: Check BIOS version, physical condition, accessories. Set eBay saved searches with alerts.

## Key Constraints

- Located in Italy — EU purchases strongly preferred
- No customs duties within EU, VAT included, 2-year minimum warranty by law
- CMR only for NAS drives (no SMR) — critical for RAID/ZFS reliability
- DDR5 must be SO-DIMM (laptop form factor) for MS-01
- NVMe must be M.2 2280 PCIe 4.0 (MS-01 has 2x 2280 slots)
- Ceph drives need DRAM cache or HMB — avoid DRAM-less for write-intensive workloads
- TB4 cables: passive up to 0.8m, active for longer distances

## Files

```
hardware-purchases/
├── CLAUDE.md                                        # This file
├── HANDOFF.md                                       # Session handoff notes
├── reports/
│   ├── nas-hdd-buying-guide.md                      # HDD strategy + cost-per-TB analysis
│   ├── ddr5-ms01-buying-guide.md                    # DDR5 compatibility + market context
│   ├── ms01-buying-guide.md                         # MS-01 i9-13900H procurement guide (new + used)
│   ├── nvme-buying-guide.md                         # NVMe boot + Ceph drive recommendations
│   └── thunderbolt-ceph-ring-guide.md               # TB4 ring topology + cable guide + Linux setup
└── research/
    └── price-tracking.md                            # EU prices, sources, used marketplaces, purchase log
```
