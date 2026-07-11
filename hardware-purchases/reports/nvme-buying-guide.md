# NVMe Buying Guide — Proxmox HA 3-Node Cluster with Ceph (2026)

## Overview

This guide covers NVMe drive selection for a 3-node Minisforum MS-01 Proxmox cluster with Ceph storage. Each node has:

- **2x M.2 2280 slots** (PCIe 4.0)
- **1x M.2 2242 slot** (PCIe 3.0)

**Total drives needed:**

- 3x boot drives (Proxmox OS) — 256GB
- 3x Ceph OSD/cache drives — 512GB, 1TB, or 2TB

## Why Endurance Matters for Ceph

### Write Endurance (TBW)

Ceph BlueStore uses the OSD drive for:

1. **WAL (Write-Ahead Logging)** — high-frequency small writes
2. **DB (metadata database)** — RocksDB journal writes
3. **Data storage** — primary object storage

These workloads generate sustained write traffic, especially in write-heavy scenarios. An SSD with low TBW will reach end-of-life faster.

### DRAM Cache vs HMB vs DRAM-less

- **DRAM (1GB per 1TB)**: Essential for Ceph OSD duty. Powers the drive's internal cache for fast WAL/DB writes. **Recommended.**
- **HMB (Host Memory Buffer)**: Acceptable fallback if DRAM unavailable; uses system RAM instead.
- **DRAM-less**: Not recommended for Ceph OSDs. Fine for boot-only drives.

### Sequential vs Random Write Speed

Ceph benefits from **sustained random write performance** (small, frequent updates to journal/metadata) more than sequential speed. Random write IOPS and latency matter more than seq MB/s.

---

## Category 1: Boot Drive (Proxmox OS)

### Capacity

**256GB is sufficient** for:

- Proxmox VE OS (~2–3 GB)
- Cluster data, logs, ISOs (~20–30 GB)
- Overhead for wear levelling

### Priority

1. **Reliability** — must not fail; OS breakage = cluster outage
2. **Cost** — boot-only workload is low-stress
3. **Speed** — not critical for boot (PCIe 3.0 or 4.0 both fine)

### Candidates & EU Prices (March 2026)

| Model               | Capacity | Type     | PCIe | TBW   | DRAM      | Seq Write  | EU Price  | Notes                                                                  |
| ------------------- | -------- | -------- | ---- | ----- | --------- | ---------- | --------- | ---------------------------------------------------------------------- |
| **Samsung 980 Pro** | 256GB    | Heatsink | 4.0  | 100\* | Yes (1GB) | 6,900 MB/s | ~€139–160 | Enterprise-grade reliability; overkill for boot but excellent warranty |
| **WD Black SN770**  | 250GB    | No       | 4.0  | 150   | No        | 4,900 MB/s | ~€99      | Budget-friendly; no DRAM OK for boot-only                              |
| **Kingston NV2**    | 256GB    | No       | 4.0  | ~80   | No        | 2,800 MB/s | ~€35–45   | Ultra-budget; acceptable for boot only                                 |
| **Crucial P3**      | 256GB    | No       | 3.0  | ~60   | No        | 3,000 MB/s | ~€50–70   | Budget option; PCIe 3.0 fine for boot                                  |

\*Samsung 980 Pro 256GB TBW not officially published; estimated from 600 TBW @1TB ratio.

**Boot Drive Recommendation:**

- **Value pick**: WD Black SN770 250GB (~€99)
- **Safe pick**: Samsung 980 Pro 256GB (~€150) — if budget permits, excellent warranty peace-of-mind

---

## Category 2: Ceph OSD / Cache Drive

### Capacity Tiers

- **512GB**: Entry-level, good for test/small Ceph clusters
- **1TB**: Sweet spot — cost/capacity/endurance balance
- **2TB**: Premium tier; maximizes storage per node; higher upfront cost

### Priority

1. **Endurance (TBW)** — this is your Ceph WAL/DB drive; write intensity is high
2. **DRAM cache** — critical for BlueStore journal performance
3. **Sustained write speed** — random write IOPS > sequential speed
4. **Cost per TBW** — affects long-term replacement cost

### Ceph Workload Profile

Ceph OSD typically sees:

- **Small random writes** (4–16KB) at high frequency
- **Moderate sequential writes** during recovery/rebalance
- **Sustained duty cycle** — runs 24/7 in production

**Minimum TBW recommended**: 300 TBW (conservative; 1 DWPD over drive lifetime)

---

## Ceph/Cache Drive Comparison Table

### 512GB Tier

| Model                           | TBW | DRAM | Seq Write  | Rand Write  | EU Price  | Cost/TBW  | Notes                        |
| ------------------------------- | --- | ---- | ---------- | ----------- | --------- | --------- | ---------------------------- |
| **Samsung 990 Pro 512GB**       | 300 | 1GB  | 6,900 MB/s | 1,200K IOPS | €179–199  | €0.60/TBW | Best DRAM; premium endurance |
| **WD Black SN850X 512GB**       | 300 | DRAM | 6,600 MB/s | 900K IOPS   | €170–190  | €0.57/TBW | Excellent balanced performer |
| **Crucial T500 500GB**          | 300 | DRAM | 7,000 MB/s | 1,100K IOPS | €109–130  | €0.36/TBW | Best cost/TBW at this tier   |
| **SK Hynix P41 Platinum 512GB** | —   | DRAM | 6,500 MB/s | 1,000K IOPS | ~€120–140 | —         | Limited availability in EU   |

### 1TB Tier (Recommended)

| Model                         | TBW | DRAM | Seq Write  | Rand Write  | EU Price  | Cost/TBW  | Notes                               |
| ----------------------------- | --- | ---- | ---------- | ----------- | --------- | --------- | ----------------------------------- |
| **Samsung 990 Pro 1TB**       | 600 | 1GB  | 6,900 MB/s | 1,200K IOPS | €175–200  | €0.33/TBW | Premium choice; most reliable       |
| **WD Black SN850X 1TB**       | 600 | DRAM | 6,600 MB/s | 900K IOPS   | ~€189–210 | €0.35/TBW | Strong performer; good availability |
| **Crucial T500 1TB**          | 600 | DRAM | 7,300 MB/s | 1,100K IOPS | €129–150  | €0.22/TBW | **Best cost/TBW value**             |
| **SK Hynix P41 Platinum 1TB** | 750 | DRAM | 6,500 MB/s | 1,000K IOPS | ~€140–160 | €0.19/TBW | Highest endurance; limited EU stock |

### 2TB Tier (Premium)

| Model                         | TBW   | DRAM | Seq Write  | Rand Write  | EU Price  | Cost/TBW  | Notes                           |
| ----------------------------- | ----- | ---- | ---------- | ----------- | --------- | --------- | ------------------------------- |
| **Samsung 990 Pro 2TB**       | 1,200 | 1GB  | 6,900 MB/s | 1,200K IOPS | €233–260  | €0.20/TBW | Enterprise reliability          |
| **WD Black SN850X 2TB**       | 1,200 | DRAM | 6,600 MB/s | 900K IOPS   | €229–250  | €0.19/TBW | Excellent capacity/cost balance |
| **Crucial T500 2TB**          | 1,200 | DRAM | 7,400 MB/s | 1,100K IOPS | €237–260  | €0.20/TBW | **Best overall value at 2TB**   |
| **SK Hynix P41 Platinum 2TB** | 1,200 | DRAM | 6,500 MB/s | 1,000K IOPS | ~€260–300 | €0.22/TBW | High endurance; premium pricing |

**EU Price Sources:** [Geizhals.de](https://geizhals.de) (German/Austrian price comparison), [Crucial EU Store](https://eu.crucial.com), [Samsung EU](https://semiconductor.samsung.com/consumer-storage/internal-ssd/990-pro/), [Western Digital](https://shop.sandisk.com/products/ssd/internal-ssd/wd-black-sn850x-nvme-ssd) (current as of March 2026)

---

## Endurance Analysis: Cost Per TBW

The cost-per-TBW metric shows which drive offers the most writes per euro:

```
Cost per TBW = Drive Price (€) / Total TBW rating

Lower = better long-term value for write-heavy workloads
```

### By Tier:

**512GB:**

- Crucial T500: €0.36/TBW (best)
- WD SN850X: €0.57/TBW
- Samsung 990 Pro: €0.60/TBW

**1TB (Sweet Spot):**

- SK Hynix P41: €0.19/TBW (best, limited availability)
- Crucial T500: €0.22/TBW (best available)
- Samsung 990 Pro: €0.33/TBW
- WD SN850X: €0.35/TBW

**2TB:**

- WD SN850X: €0.19/TBW (best)
- Crucial T500: €0.20/TBW (best, widely available)
- Samsung 990 Pro: €0.20/TBW

**Takeaway:** Crucial T500 dominates cost/TBW across all tiers. Samsung 990 Pro is the premium/enterprise choice with the most DRAM and proven track record in datacenter deployments.

---

## Budget Scenarios: Total Cluster Cost

### Scenario A: Budget Build (Min Ceph capacity)

**Boot:** 3x Kingston NV2 256GB
**Ceph:** 3x Crucial T500 512GB

| Role              | Model              | Qty | Price/unit | Total    |
| ----------------- | ------------------ | --- | ---------- | -------- |
| Boot              | Kingston NV2 256GB | 3   | €40        | €120     |
| Ceph              | Crucial T500 512GB | 3   | €115       | €345     |
| **Cluster Total** |                    |     |            | **€465** |

**Pros:** Lowest upfront cost; adequate for test/small Ceph clusters
**Cons:** Smallest capacity; limited room for growth

---

### Scenario B: Balanced Build (Recommended)

**Boot:** 3x WD Black SN770 250GB
**Ceph:** 3x Crucial T500 1TB

| Role              | Model                | Qty | Price/unit | Total    |
| ----------------- | -------------------- | --- | ---------- | -------- |
| Boot              | WD Black SN770 250GB | 3   | €99        | €297     |
| Ceph              | Crucial T500 1TB     | 3   | €140       | €420     |
| **Cluster Total** |                      |     |            | **€717** |

**Pros:** Excellent cost/capacity balance; 1TB is industry sweet spot; proven boot drive
**Cons:** None; this is the recommended tier

---

### Scenario C: Premium Build (Enterprise-Grade)

**Boot:** 3x Samsung 980 Pro 256GB
**Ceph:** 3x Samsung 990 Pro 1TB

| Role              | Model                 | Qty | Price/unit | Total      |
| ----------------- | --------------------- | --- | ---------- | ---------- |
| Boot              | Samsung 980 Pro 256GB | 3   | €150       | €450       |
| Ceph              | Samsung 990 Pro 1TB   | 3   | €185       | €555       |
| **Cluster Total** |                       |     |            | **€1,005** |

**Pros:** Maximum DRAM, proven enterprise reliability, excellent warranty, superior random write performance
**Cons:** 40% premium over balanced build; overkill for home cluster

---

### Scenario D: Large Capacity Build

**Boot:** 3x WD Black SN770 250GB
**Ceph:** 3x Crucial T500 2TB

| Role              | Model                | Qty | Price/unit | Total      |
| ----------------- | -------------------- | --- | ---------- | ---------- |
| Boot              | WD Black SN770 250GB | 3   | €99        | €297       |
| Ceph              | Crucial T500 2TB     | 3   | €250       | €750       |
| **Cluster Total** |                      |     |            | **€1,047** |

**Pros:** 2TB per node = 6TB total Ceph capacity; excellent cost/TBW; room for growth
**Cons:** Higher upfront cost; overkill unless you need the raw capacity

---

## Regional Availability & Pricing Notes

### Germany (Geizhals.de)

- **Crucial T500 1TB**: €129–150 ✓ (best availability)
- **Samsung 990 Pro 1TB**: €175–200 ✓
- **WD Black SN850X 2TB**: €229–240 ✓

German retailers often have the best EU prices. Use [Geizhals.de](https://geizhals.de) to compare across retailers.

### Italy (Amazon.it, local retailers)

- Prices typically 5–15% higher than Germany due to VAT/logistics
- Check [Amazon.it](https://amazon.it), [Alternate.it](https://alternate.it), local computer shops
- Consider ordering from German retailers for cost savings

### International EU Shipping

- Germany → Italy shipping: €15–25 via DPD/DHL
- Order threshold: €60+ to break even on shipping vs local premium

---

## Specific Recommendations

### Boot Drive: Final Recommendation

**Buy: WD Black SN770 250GB (~€99)**

- Reliable, proven performer in Proxmox deployments
- No DRAM required for boot-only workload
- Best cost/performance ratio
- Widely available across EU retailers

If budget allows and you want peace-of-mind warranty:
**Buy: Samsung 980 Pro 256GB (~€150)**

---

### Ceph OSD Drive: By Capacity

#### 512GB (Entry-level clusters)

**Buy: Crucial T500 512GB (~€115)**

- Best cost/TBW at this tier (€0.36/TBW)
- Adequate endurance for light Ceph workloads
- Consider if you're just testing Ceph or have a small cluster

---

#### 1TB (Recommended)

**Buy: Crucial T500 1TB (~€140)**

- **Best overall value**: €0.22/TBW cost ratio
- 600 TBW is solid endurance
- 1TB is the industry sweet spot for Ceph OSDs
- Excellent random write performance (1,100K IOPS)
- Widely available in EU

**Premium alternative: Samsung 990 Pro 1TB (~€185)**

- If you want maximum DRAM (1GB vs standard), choose Samsung
- Enterprise-grade reliability; used in production datacenters
- Worth the premium if you value redundancy and can afford it

---

#### 2TB (Large capacity / future-proof)

**Buy: Crucial T500 2TB (~€250)**

- Best cost/TBW at 2TB tier (€0.20/TBW)
- Doubles capacity per node (6TB total cluster)
- Same proven random write performance
- Overkill unless you need the capacity now

---

## Ceph Performance Expectations

With the recommended drives (Crucial T500 1TB):

- **OSD write latency**: <5 ms (BlueStore with DRAM cache)
- **Cluster throughput**: 200–400 MB/s (3x 1TB OSDs)
- **IOPS (4K random)**: ~3,000–5,000 per node
- **Drive lifespan**: 5–7 years in production (600 TBW ÷ typical 100 TBW/year)

These are conservative estimates; actual performance depends on Ceph configuration, workload pattern, and network saturation.

---

## Final Shopping Checklist

### For 3-Node Cluster (Balanced Build):

- [ ] 3x WD Black SN770 250GB (boot) — €297 total
- [ ] 3x Crucial T500 1TB (Ceph OSD) — €420 total
- [ ] **Total: €717**
- [ ] Verify form factor: all must fit M.2 2280 slot on Minisforum MS-01

### Ordering Tips

1. **Order together** from German retailer (Geizhals.de) to reduce shipping cost
2. **Check lead times** — some models have 2–4 week delays in March/April
3. **Verify return policy** — buy from retailers with 14+ day returns
4. **Inspect on arrival** — test SMART data immediately after installation
5. **Enable S.M.A.R.T. monitoring** in Proxmox (`pvestat`, `smartctl`)

---

## References

- [Ceph Official Hardware Recommendations](https://docs.ceph.com/en/quincy/start/hardware-recommendations/)
- [Ceph All-NVMe Performance Guide](https://openmetal.io/resources/blog/guide-to-all-nvme-ceph-cluster-performance/)
- [Geizhals EU Price Comparison](https://geizhals.de)
- [Proxmox Storage and NVMe Boot Guide](https://homelab.casaursus.net/ssd-nvme/)
- [Crucial T500 Specifications](https://eu.crucial.com/products/ssd/crucial-t500-ssd-pdp)
- [Samsung 990 Pro Datasheet](https://semiconductor.samsung.com/consumer-storage/internal-ssd/990-pro/)
- [WD Black SN850X Performance Review](https://www.tomshardware.com/reviews/wd-black-sn850x-ssd-review-back-in-black)
- [SK Hynix P41 Platinum Review](https://www.tomshardware.com/reviews/sk-hynix-platinum-p41-ssd-review)

---

**Last Updated:** March 2026
**Region:** EU (Italy focus)
**Cluster:** Minisforum MS-01 x3 with Ceph Storage
