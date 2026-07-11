# 3-Node MS-01 Proxmox + Ceph Cluster — Purchase Cart

**Date:** 2026-05-04
**Goal:** Expand homelab from 1x MS-01 to 3-node Proxmox VE cluster with Ceph storage.
**Existing assets (NOT in cart):** 1x MS-01 i9-13900H, 64GB RAM, 970 EVO Plus 250GB boot, 970 EVO Plus VM drive.

---

## Compute

| Item | Qty | Unit € | Total € | Notes |
|---|---|---|---|---|
| Minisforum MS-01 i9-13900H barebone | 2 | 700 | 1,400 | Verify SKU = i9-13900H w/ vPro |
| Crucial DDR5 64GB kit (2x32) 5600 SODIMM CT2K32G56C46S5 | 2 | 650 | 1,300 | Match existing node RAM |

**Subtotal: €2,700**

---

## Storage — Boot (2 new nodes)

| Item | Qty | Unit € | Total € | Notes |
|---|---|---|---|---|
| Samsung 970 EVO Plus 250GB (used) | 2 | 100 | 200 | Check SMART hours/wear before install. Boot only — Ceph holds VM data |

**Subtotal: €200**

---

## Storage — Ceph OSD (1 per node, consumer TLC, NO QLC)

| Item | Qty | Unit € | Total € | Notes |
|---|---|---|---|---|
| WD Black SN850X 2TB (no heatsink) | 3 | 200 | 600 | TLC + DRAM, 1200 TBW. Replica 3/2 = ~1.7 TB usable |

**Subtotal: €600**

**Decision rationale:** Forum evidence (Proxmox community, 7-year run on consumer NVMe) + UPS protection (clean shutdown covers PLP gap) + homelab write rate (~5-30 TB/year per OSD) makes consumer TLC viable. Avoid QLC (P3, QVO, Green) and DRAM-less drives (SN770).

**Future expansion:** MS-01 has 3 M.2 slots. Boot + 1 OSD = 2 used. Add 2nd OSD per node later when cluster fills → 6x 2TB = ~3.4 TB usable.

---

## Networking

| Item | Qty | Unit € | Total € | Notes |
|---|---|---|---|---|
| UniFi USW-Pro-XG-8-PoE | 1 | 538.80 | 538.80 | EU UniFi store, VAT incl. 8x 10GbE RJ45 PoE++ |
| Mikrotik S+RJ10 10GBASE-T SFP+ transceiver | 3 | 50 | 150 | MS-01 SFP+ slot → switch RJ45 |
| Lenovo TB4 cable 0.7m 4X91K16968 | 4 | 21.86 | 87.44 | 3 for ring + 1 spare. Test 40Gbps before deploy |
| Cat6a patch cable 1m | 6 | 5 | 30 | 3x SFP+ runs + 3x 2.5GbE corosync |

**Subtotal: €806.24**

---

## Power Protection

| Item | Qty | Unit € | Total € | Notes |
|---|---|---|---|---|
| Eaton 5E Gen2 1600 (1600VA / 900W line-interactive) | 1 | 220 | 220 | USB for NUT integration. Sized for ~480W cluster + headroom = ~12 min runtime |
| C13 power cord 1.5m | 2 | 8 | 16 | MS-01 spares |
| Schuko → C13 power cord 1.5m | 1 | 10 | 10 | For XG-8-PoE on existing Eaton 3S 850 DIN |

**Subtotal: €246**

**Existing UPS:** Eaton 3S 850 DIN (850 VA / 510 W, 4x Schuko, USB HID, monitored via NUT on Reginald — `0463:ffff` MGE). Currently powers UCG-Fiber + Reginald + storage switch (~70W load → 20-30 min runtime). After cluster: **add XG-8-PoE** to this UPS (needs Schuko-to-C13 cord ~€10) — load becomes ~95W, runtime still safe. Do NOT put MS-01 nodes here (would push past 510W rating).

---

## GRAND TOTAL

| Section | € |
|---|---|
| Compute | 2,700.00 |
| Boot storage | 200.00 |
| Ceph OSD | 600.00 |
| Networking | 806.24 |
| Power | 246.00 |
| **TOTAL** | **€4,552.24** |

---

## Network Topology Per MS-01

| Link | Speed | Switch | Role |
|---|---|---|---|
| TB4 mesh (full ring) | 40 Gbps | none — direct cable | Ceph **cluster network** (OSD↔OSD replication) |
| SFP+ via 10GBASE-T transceiver | 10 Gbps | XG-8-PoE | Ceph **public network** + VM traffic + mgmt (VLAN trunk) |
| 2.5GbE Cat6 (port 1) | 2.5 Gbps | XG-8-PoE | Corosync ring0 (dedicated VLAN) |
| 2.5GbE Cat6 (port 2) | 2.5 Gbps | XG-8-PoE | Corosync ring1 (redundant — optional, free) |

**TB4 ring:** 3 cables, full mesh. Each node uses 2 of 3 TB4 ports. Configure FRR + OpenFabric routing per Proxmox wiki "Full Mesh Network for Ceph Server".

**XG-8-PoE port allocation (8 ports):**
- 3x ports → MS-01 SFP+ (via 10GBASE-T transceivers)
- 3x ports → MS-01 2.5GbE corosync ring0
- 1x port → Zimaboard (existing NAS, 1GbE)
- 1x port → QNAP NAS (1GbE)
- = 8/8 used. Ring1 corosync would need a 9th port — defer or use UCG-Fiber free port if available.

**Storage LAN (192.168.200.0/24):** keep existing unmanaged 8-port 2.5GbE switch. 4 used → 6 used after cluster (3x MS-01 added). 2 ports spare. Unchanged.

---

## Verification Before Order

- [ ] MS-01 SKU confirmed: i9-13900H, vPro (IPMI-equivalent)
- [ ] Crucial DDR5 SODIMM compatibility list checked vs Minisforum QVL
- [ ] SN850X 2TB stock + price verified (varies €180-220)
- [ ] XG-8-PoE uplink port type (2x SFP28 25G uplinks may allow direct DAC for 2 of 3 MS-01, saving ~€100 in transceivers)
- [ ] TB4 cable counterfeit risk — order 4, test 40Gbps with `iperf3` before committing to ring
- [ ] Eaton 5E NUT compatibility confirmed (Network UPS Tools driver list)

---

## Order Phasing

1. **Phase 1 — Build nodes** (~€2,900): 2x MS-01 + 2x RAM + 2x boot drives
2. **Phase 2 — Network fabric** (~€806): XG-8-PoE + transceivers + cables + TB4
3. **Phase 3 — Ceph OSD** (~€600): 3x SN850X 2TB
4. **Phase 4 — Power safety** (~€236): UPS + cords (BEFORE first cluster boot)

---

## Removed From Initial eBay Cart

- ❌ WD_BLACK SN850X 1TB ×2 — boot covered by 970 EVO; 2TB version better for OSD
- ❌ Crucial DDR5 64GB (gblmarket) — listing unavailable
- ❌ Enterprise PM9A3/Micron 7450 — overkill for homelab + UPS-protected. Saves ~€240

---

## Existing Assets Inventory

| Item | Location | Role after upgrade |
|---|---|---|
| MS-01 #1 (i9-13900H, 64GB RAM) | current node | Ceph cluster member node 1 |
| Samsung 970 EVO Plus 250GB | MS-01 #1 | Boot (keep) |
| Samsung 970 EVO Plus (VM drive) | MS-01 #1 | Migrate VMs to Ceph, then: local fast scratch OR optional 2nd OSD on node 1 |
| Eaton 3S Mini 36W UPS | rack | Gateway/modem/cams only — NOT cluster |
| 8-port unmanaged 2.5GbE switch | rack | Storage LAN 192.168.200.0/24 (keep) |
| UCG-Fiber gateway | rack | WAN + existing VLANs (keep) |
| Zimaboard + 7 SSDs | NAS role | Keep until 10GbE NAS upgrade |
| QNAP NAS | rack | Keep |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| TB4 cable counterfeit (€21 sus) | Order 4, iperf3 test, swap if <25 Gbps |
| Used 970 EVO failure | Boot only — rebuild = 30 min + PBS restore |
| Consumer NVMe wear under Ceph | Replica 3/2, monitor SMART, replace 5-7y |
| Single corosync ring (no ring1 if XG-8-PoE saturated) | Add ring1 via UCG-Fiber port if available, else accept switch SPOF |
| Power loss → Ceph corruption | UPS + NUT graceful shutdown order: VMs → Ceph stop → nodes off |
| MS-01 firmware bugs (TB4, SR-IOV) | Update BIOS before cluster config |

---

## Reference Links (verify before purchase)

- Minisforum MS-01 specs: https://minisforumpc.com/products/ms-01
- Proxmox TB4 mesh: https://pve.proxmox.com/wiki/Full_Mesh_Network_for_Ceph_Server
- Ceph hardware recommendations: https://docs.ceph.com/en/latest/start/hardware-recommendations/
- UniFi XG-8-PoE: https://eu.store.ui.com/eu/en/category/switching-pro/products/usw-pro-xg-8-poe
- NUT compatible UPS list: https://networkupstools.org/stable-hcl.html
