# Hardware Purchases

Tracking hardware research, price monitoring, and purchase decisions for homelab upgrades.

**Active cart:** [3-node-ms01-ceph-cluster-cart.md](3-node-ms01-ceph-cluster-cart.md) — €4,552.24 total, finalized 2026-05-04.

## Cluster Architecture

Building a **3-node Proxmox HA cluster with Ceph storage** interconnected via a Thunderbolt 4 ring:

- **Node 1**: Winston (existing MS-01 i9-13900H, **64GB RAM**, Proxmox VE 9.2.2)
- **Node 2**: New MS-01 i9-13900H barebones (to buy)
- **Node 3**: New MS-01 i9-13900H barebones (to buy)

**Networking** (per node):

- TB4 ring (40 Gbps full mesh) → Ceph **cluster network** (OSD↔OSD replication)
- 1x SFP+ via 10GBASE-T transceiver (10 Gbps) → Ceph **public** + VM traffic (XG-8-PoE switch)
- 1x 2.5GbE → corosync ring0 (XG-8-PoE)
- 2nd 2.5GbE → corosync ring1 (optional, depends on free switch ports)

```
  Winston (Node A)
   /            \
  TB4           TB4
 /                \
Node B ——TB4—— Node C
```

Each node: 1x 250GB NVMe (boot) + 1x 2TB NVMe (Ceph OSD) + 64GB DDR5.

**Winston's current NVMe drives:**

- nvme2n1: SanDisk SSD Plus 250GB (boot) — PCIe 3.0, DRAM-less, **stays as boot**
- nvme1n1: Kingston OM8PGP41024N-A0 1TB (VMs) — PCIe 4.0, DRAM. Migrate VMs to Ceph, then **retire or repurpose as local scratch** (do NOT mix as OSD — asymmetric size hurts Ceph balance)
- nvme0n1: ORICO J10 1TB (NFS cache) — PCIe 3.0, DRAM-less, **retire** (sell/spare)

**NVMe strategy (revised 2026-05-04):** Buy **3x WD Black SN850X 2TB** for symmetric Ceph OSD across all 3 nodes. ~1.7TB usable Ceph after replica 3/2. Future expansion: MS-01 has 3 M.2 slots → add 2nd OSD per node later (~3.4TB usable). Consumer TLC + DRAM acceptable given UPS-protected shutdown and homelab write rate (~5-30 TB/year per OSD).

**Existing UPS:** Eaton 3S 850 DIN (850 VA / 510 W, 4x Schuko, USB HID `0463:ffff` MGE). NUT running on Reginald — **no Raspberry Pi NUT server needed**. Powers UCG-Fiber + Reginald + storage switch today (~70W). Add XG-8-PoE post-cluster (~95W total, ~20+ min runtime).

## Cluster Shopping List (finalized)

| Item                       | Qty | Unit € | Total €  | Status                     |
| -------------------------- | --- | ------ | -------- | -------------------------- |
| Minisforum MS-01 barebone  | 2   | 700    | 1,400    | Verify SKU + vPro          |
| Crucial DDR5 64GB (2x32)   | 2   | 650    | 1,300    | Match Winston (CT2K32G56C46S5) |
| Samsung 970 EVO 250GB used | 2   | 100    | 200      | Boot for new nodes (check SMART) |
| WD Black SN850X 2TB        | 3   | 200    | 600      | Ceph OSD — TLC + DRAM      |
| UniFi USW-Pro-XG-8-PoE     | 1   | 538.80 | 538.80   | EU UniFi store, VAT incl.  |
| Mikrotik S+RJ10 transceiver| 3   | 50     | 150      | MS-01 SFP+ → switch RJ45   |
| Lenovo TB4 0.7m 4X91K16968 | 4   | 21.86  | 87.44    | 3 ring + 1 spare           |
| Cat6a 1m patch             | 6   | 5      | 30       | SFP+ + corosync runs       |
| Eaton 5E Gen2 1600         | 1   | 220    | 220      | UPS for cluster (NUT)      |
| C13 cord 1.5m              | 2   | 8      | 16       | MS-01 spares               |
| Schuko→C13 cord 1.5m       | 1   | 10     | 10       | XG-8-PoE on existing 3S 850 |
| **TOTAL**                  |     |        | **€4,552.24** | |

## Separate Decisions (NOT in cluster cart)

| Item     | Target                                     | Budget   | Status                   |
| -------- | ------------------------------------------ | -------- | ------------------------ |
| NAS HDDs | 4-6TB CMR (Toshiba N300 / WD Red Plus)     | ~€30/TB  | Independent of cluster   |
| Shucked drives | WD My Book 8TB (verify CMR)         | ~€170    | Independent              |

## Buying Strategy (EU/Italy)

- **Primary**: Amazon.it/.de/.fr/.es (cross-EU, no customs, 2-year EU warranty)
- **Refurbished**: Amazon Warehouse, EU-based refurb sellers
- **Used (MS-01)**: eBay.it/.de/.fr, Subito.it, Kleinanzeigen.de, Vinted, Facebook Marketplace
- **UniFi**: eu.store.ui.com (XG-8-PoE official EU stock, VAT incl.)
- **Price tracking**: Keepa (multi-region Amazon), Geizhals.de, idealo.it
- **Avoid**: UK sellers (post-Brexit customs), non-EU international (import duties + VAT)
- **TB4 cables**: China eBay sellers offer Lenovo OEM at ~€22 — order 4 (1 spare for counterfeit risk), iperf3 test before deploy
- **Used MS-01 tips**: BIOS version, physical condition, accessories check. eBay saved searches with alerts.

## Key Constraints

- Italy — EU purchases preferred (no customs, 2-year warranty)
- CMR only for NAS drives — critical for RAID/ZFS reliability
- DDR5 must be SO-DIMM for MS-01
- NVMe: M.2 2280 PCIe 4.0 (MS-01 has 1x 22110 + 2x 2280 slots)
- Ceph drives: TLC + DRAM. **Avoid QLC** (P3, QVO, Green) and DRAM-less (SN770)
- TB4 cables: passive up to 0.8m, active for longer
- UPS for cluster: ≥900W output, ≥10 min runtime at full load, NUT-compatible
- XG-8-PoE inlet = C14 → need C13 cord (or Schuko→C13 if on existing UPS)

## Order Phasing

1. **Phase 1 — Compute** (~€2,900): 2x MS-01 + 2x RAM + 2x boot drives → bring nodes up standalone
2. **Phase 2 — Network** (~€806): XG-8-PoE + transceivers + cables + TB4 → cluster join
3. **Phase 3 — Ceph OSD** (~€600): 3x SN850X 2TB → Ceph init
4. **Phase 4 — Power safety** (~€246): Eaton 5E + cords → BEFORE Ceph production load

## Files

```
hardware-purchases/
├── CLAUDE.md                                # This file
├── 3-node-ms01-ceph-cluster-cart.md         # Active purchase cart (finalized 2026-05-04)
├── HANDOFF.md                               # Session handoff notes
├── reports/
│   ├── nas-hdd-buying-guide.md              # HDD strategy + cost-per-TB
│   ├── ddr5-ms01-buying-guide.md            # DDR5 compatibility
│   ├── ms01-buying-guide.md                 # MS-01 procurement (new + used)
│   ├── nvme-buying-guide.md                 # NVMe boot + Ceph recommendations
│   └── thunderbolt-ceph-ring-guide.md       # TB4 ring topology + cables + Linux setup
└── research/
    └── price-tracking.md                    # EU prices, sources, marketplaces, purchase log
```

## Decision Log

- **2026-05-04**: Cart finalized. Switched Ceph OSD from 1TB Kingston-mixed plan → 3x symmetric SN850X 2TB. Dropped Pi NUT plan (Reginald already runs NUT for Eaton 3S 850 DIN). Switch chosen: XG-8-PoE for single-box + UniFi UI + form factor next to UCG-Fiber. UPS: Eaton 5E Gen2 1600 (rejected UniFi UPS Tower undersized, UniFi UPS 2U sold out + only 4 outlets).
