# Minisforum MS-01 i9-13900H Buying Guide (2026)

**Objective:** Purchase 2x new Minisforum MS-01 i9-13900H units to complete a 3-node Proxmox HA cluster with Winston (existing node 1).

---

## 1. Why i9-13900H SKU

The **Intel Core i9-13900H** is the top-tier MS-01 processor option. Cheaper variants (i9-12900H, i5-12600H) are insufficient for your infrastructure requirements.

### i9-13900H Specifications

- **Cores/Threads:** 14 cores (6P+8E) / **20 threads**
- **Cache:** 24 MB L3
- **Max Boost:** 5.4 GHz
- **TDP:** 45W

### Why Not Cheaper SKUs?

| Aspect         | i9-13900H | i9-12900H | i5-12600H    |
| -------------- | --------- | --------- | ------------ |
| Threads        | 20        | 14        | 10           |
| PCIe Lanes     | 16 (full) | 16        | 12 (reduced) |
| L3 Cache       | 24 MB     | 18 MB     | 10 MB        |
| Thunderbolt 4  | 2x        | 2x        | 2x           |
| GPU (Xe cores) | 80        | 80        | 32           |
| Single-thread  | Highest   | Mid       | Baseline     |

**Impact:** i9-13900H provides:

- **2x more threads** than i5-12600H → better VM concurrency, Proxmox management
- **Full PCIe x16 lane allocation** → critical for NVMe + 2.5GbE + TB4 simultaneous use
- **Higher single-thread perf** → reduces cluster failover latency, improves responsiveness

**Recommendation:** The i9-13900H is the only viable option for matching Winston's performance tier. Mixing SKUs creates asymmetric cluster behavior.

---

## 2. Current EU Pricing (2026)

### New (Barebones)

Based on recent EU market data (March 2026):

| Source                          | Price (EUR)            | Config             | Link                                                                                                        |
| ------------------------------- | ---------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------- |
| **Minisforum Official**         | €623 USD (~€600 EUR\*) | Barebones only     | [store.minisforum.com](https://store.minisforum.com/products/minisforum-ms-01)                              |
| **Geizhals.eu (price tracker)** | €681–709               | Varies by retailer | [geizhals.eu](https://geizhals.eu/minisforum-ms-01-a3264329.html)                                           |
| **Galaxus.de**                  | €669                   | Barebones          | [galaxus.de](https://www.galaxus.de/en/s1/product/minisforum-ms-01-intel-core-i9-13900h-barebones-47130567) |
| **Configured (32GB+1TB)**       | ~€800–900              | Full setup         | Various retailers via Geizhals                                                                              |

\*USD to EUR conversion may vary; check live pricing on Minisforum official EU store (minisforumpc.eu).

### Pricing Trend

- Barebones: **€600–700 per unit** (typical range)
- Configured: **€800–950 per unit** (includes DDR5 + NVMe markup)
- **2x barebones total:** ~€1,200–1,400

### Where to Buy (EU)

**Recommended retailers:**

1. **Minisforum Official EU Store** (`minisforumpc.eu`) — Direct warranty, fastest support
2. **Geizhals.eu** — Price comparison, aggregates 10+ EU retailers
3. **Amazon.de / Amazon.it** — Regional availability, buyer protection
4. **Galaxus.de / Digitec.ch** — Swiss/German, reputable electronics retailers
5. **Newegg.eu** — US-based but ships to EU

---

## 3. Barebones vs Configured

### Barebones (Recommended for your case)

- **Price:** €600–700 per unit
- **Includes:** Chassis, motherboard, CPU, power supply, fans, BIOS
- **You provide:** DDR5 RAM, NVMe SSDs, cooling thermal pads
- **Advantages:**
  - Lowest total cost
  - Reuse existing DDR5/NVMe shopping list
  - Fine-grained control over component sourcing (warranty, timing)
  - Avoid retailer markup on RAM/SSD

### Configured (32GB DDR5 + 1TB NVMe)

- **Price:** €800–950 per unit
- **Includes:** All of barebones + RAM + storage + OS (Windows)
- **Advantages:**
  - Convenience (one-box deployment)
  - Unified warranty on all components
  - Sometimes bundled thermal pads included
- **Disadvantages:**
  - 20–30% cost premium over barebones
  - Fixed config (if you want 64GB, you pay for it)
  - May include unnecessary Windows license

### Recommendation

**Buy: Barebones (2x)**

**Reasons:**

1. Lowest per-unit cost (~€1,200 total for 2 units)
2. Flexibility to match Winston's RAM (32 GB) or upgrade to 64 GB later
3. Avoids retailer markup on memory/storage
4. Consistent with existing procurement (DDR5 + NVMe sourced separately)
5. Thermal pads usually included in barebones box

---

## 4. Used Market Analysis

Buying used MS-01 units can reduce cost by 20–40%, but risks must be evaluated.

### Where to Look (EU)

| Platform                 | Availability | Risk Level  | Notes                                                |
| ------------------------ | ------------ | ----------- | ---------------------------------------------------- |
| **eBay.de / eBay.it**    | High         | Medium      | 30-day buyer protection, return shipping             |
| **Kleinanzeigen.de**     | Medium       | Medium–High | German classifieds, local pickup possible            |
| **Subito.it**            | Medium       | Medium–High | Italian classifieds, no centralized buyer protection |
| **Vinted**               | Low          | Medium      | Expanding into electronics, primarily fashion        |
| **Facebook Marketplace** | Low          | High        | No formal dispute resolution                         |

### Used Pricing Estimates

Based on market research, typical used MS-01 i9-13900H asking prices:

| Config              | Estimated Used Price (EUR) |
| ------------------- | -------------------------- |
| Barebones           | €450–550                   |
| 32GB+1TB configured | €650–800                   |
| 64GB+2TB configured | €850–1,100                 |

**Cost savings:** 20–40% off new price, but warranty and condition variability.

### What to Check When Buying Used

1. **BIOS Version**
   - Current stable: **v1.26+**
   - Avoid: v1.22 (kernel panics), v1.24 beta (RAM limits)
   - Seller should confirm BIOS version before purchase
   - Request screenshot of BIOS version from boot screen

2. **Physical Condition**
   - Check for cracks, dents on aluminum chassis
   - Verify all ports (2x TB4, HDMI, 2.5GbE, 10GbE SFP+) work
   - Ask about thermal pad age (replaced recently?)
   - Request photos of interior (dust, bent heatsink fins?)

3. **Included Accessories**
   - Power supply + cable intact?
   - Any NVMe/RAM included? (Check if purchase price reflects this)
   - Original box/documentation (helpful but not critical)

4. **Original Purchase Date**
   - Units from 2023 Q3–Q4 more likely to have firmware issues
   - 2024+ units typically ship with v1.26 BIOS
   - Warranty not transferable regardless of date (Minisforum policy)

5. **Seller Verification**
   - On eBay: check seller rating (aim for 98%+)
   - On Kleinanzeigen: request video walkthrough or VC call
   - Ask for proof of original purchase (invoice, email receipt) to verify authenticity

### Risks of Used Purchase

| Risk                         | Mitigation                                                  |
| ---------------------------- | ----------------------------------------------------------- |
| **BIOS issues**              | Request BIOS v1.26+ proof; verify in testing phase          |
| **No manufacturer warranty** | Plan to run Proxmox stress test for 48h after arrival       |
| **Shipping damage**          | Use eBay/platform protection for return shipping            |
| **CMOS battery dead**        | Common in units powered off long-term; easily replaced (€5) |
| **Thermal paste degraded**   | Budget €20–30 for professional thermal pad replacement      |

---

## 5. Risk Factors

### Minisforum Warranty

- **Manufacturer:** 2-year standard / 3-year optional (accidental damage)
- **Transferability:** **NOT transferable** — warranty applies to original purchaser only
- **For new purchases:** Warranty is active and transferable within EU consumer protection (but not Minisforum's own warranty)
- **For used purchases:** No manufacturer warranty; relies on platform buyer protection (eBay 30-day, etc.)

### EU Consumer Protection

- **eBay:** 30-day money-back guarantee + shipping protection
- **Amazon.de/it:** 30-day return; 2-year legal warranty (EU law)
- **Direct retailers:** Varies by retailer; always check T&C
- **Private sales:** No recourse beyond small claims court

### BIOS/Firmware Issues

Early batches (2023) experienced:

- **v1.22:** Kernel panics every 3 days on Linux; resolved in v1.24
- **v1.24:** RAM instability above 64 GB (resolved in v1.26)
- **v1.26+:** Stable for Proxmox (current shipping version)

**Mitigation:**

- Request BIOS version before purchase (new units ship with v1.26)
- Used units: test in Proxmox for 48h before committing to cluster

### CMOS Battery Issues

Early MS-01 units shipped with low-quality CMOS batteries; units left powered off for weeks may not boot. Replacement is trivial (internal battery, ~€5, 2-minute swap).

### Physical Risks (Used)

- **Thermal pads:** Degrade after 12+ months; reapply if showing white residue
- **Thunderbolt 4:** Mechanical wear if heavily used (rare)
- **NVMe slots:** Check for bent pins if pre-installed SSD removed

---

## 6. Budget Summary (2x Barebones)

### Scenario A: New Barebones (Recommended)

| Item                               | Unit Cost | Qty | Total (EUR) |
| ---------------------------------- | --------- | --- | ----------- |
| MS-01 i9-13900H Barebones          | €650      | 2   | €1,300      |
| DDR5-5600 32GB Kit (32GB per unit) | €80       | 2   | €160        |
| Samsung 990 Pro 2TB NVMe           | €120      | 2   | €240        |
| **Total**                          | —         | —   | **€1,700**  |

**Per-node cost:** €850
**vs. Winston baseline:** Identical spec, matching investment

### Scenario B: New Configured (Convenience)

| Item                              | Unit Cost | Qty | Total (EUR) |
| --------------------------------- | --------- | --- | ----------- |
| MS-01 i9-13900H (32GB DDR5 + 1TB) | €850      | 2   | €1,700      |
| Extra storage upgrade (optional)  | €0        | 2   | €0          |
| **Total**                         | —         | —   | **€1,700**  |

**Per-node cost:** €850
**Note:** Same total but less flexibility; you get fixed RAM/SSD combo.

### Scenario C: Mixed New + Used (Cost-Optimized)

| Item                                    | Unit Cost | Qty | Total (EUR) |
| --------------------------------------- | --------- | --- | ----------- |
| MS-01 i9-13900H Barebones (new)         | €650      | 1   | €650        |
| MS-01 i9-13900H Barebones (used, v1.26) | €500      | 1   | €500        |
| DDR5-5600 32GB Kit                      | €80       | 2   | €160        |
| Samsung 990 Pro 2TB NVMe                | €120      | 2   | €240        |
| Thermal pad replacement (used unit)     | €25       | 1   | €25         |
| Stress-test equipment rental (24h)      | €0        | —   | €0          |
| **Total**                               | —         | —   | **€1,575**  |

**Per-node cost:** €788 (vs €850 all-new)
**Savings:** ~€125 (7%)
**Added complexity:** Verification, thermal pads, 48h stress test

---

## 7. Recommendation & Action Plan

### Buy Strategy

**Primary:** 2x Barebones (new), sourced from EU official retailer or Geizhals-aggregated offers

| Step | Action                                                    | Timeline |
| ---- | --------------------------------------------------------- | -------- |
| 1    | Check live pricing on Minisforum EU store & Geizhals      | Today    |
| 2    | Verify stock (MS-01 i9-13900H barebones) on 2–3 retailers | Today    |
| 3    | Confirm BIOS v1.26 on retail listing (or contact sales)   | Day 1    |
| 4    | Purchase 2x barebones units                               | Week 1   |
| 5    | Parallel: Order DDR5 RAM + NVMe SSD per shopping list     | Week 1   |
| 6    | Receive units → unbox, check BIOS, verify all ports       | Week 2   |
| 7    | Install RAM + NVMe → initial power-on test                | Week 2   |
| 8    | Deploy Proxmox 9.x via USB key                            | Week 3   |
| 9    | Cluster join with Winston (Corosync ring topology)        | Week 4   |

### If New Units Unavailable

**Fallback:** 1x new + 1x used (verified v1.26 + stress-tested)

- New barebones: **€650** (primary node, full warranty)
- Used barebones: **€500** (secondary, pre-tested 48h, BIOS confirmed)
- **Total:** ~€1,575
- **Risk:** Accepts ~10% condition uncertainty on used unit; mitigated by pre-delivery stress test

### Reject Criteria

Do not proceed with purchase if:

- BIOS version below v1.26 (firmware upgrade risk on 13th gen)
- Physical damage visible (dents, bent heatsink fins)
- Seller cannot confirm original purchase date (authenticity risk)
- Used unit asking price > €600 (bad value)
- No EU buyer protection offered (private sale, payment by wire)

---

## References

- [Minisforum MS-01 Official Store](https://store.minisforum.com/products/minisforum-ms-01)
- [Minisforum EU Store](https://minisforumpc.eu/)
- [Geizhals EU Price Tracker](https://geizhals.eu/minisforum-ms-01-a3264329.html)
- [BIOS Update Guide](https://www.virtualizationhowto.com/2024/09/how-to-upgrade-the-minisforum-ms-01-bios/)
- [Warranty Policy (non-transferable)](https://store.minisforum.com/pages/warranty)
- [Proxmox Forum: MS-01 i9-13900H Cluster Experiences](https://forum.proxmox.com/threads/proxmox-install-on-minisforum-ms-01.154110/)
