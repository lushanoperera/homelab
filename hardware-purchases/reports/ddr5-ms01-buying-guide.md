# DDR5 SO-DIMM Buying Guide for MS-01 (2026)

## MS-01 Memory Specifications

- **Form factor**: SO-DIMM (laptop memory) — desktop DIMMs will NOT fit
- **Standard**: DDR5-5600 (native speed)
- **Slots**: 2x SO-DIMM
- **Max capacity**: 96GB (2x48GB) on i9-13900H; 64GB (2x32GB) on other CPUs
- **Non-i9 note**: May downclock to DDR5-5200 MT/s — negligible performance impact for homelab workloads

## Confirmed Compatible Kits

Sources: ServeTheHome review, Level1Techs forum, Minisforum community.

| Model                | Part Number        | Speed | CL  | Confirmed By                 |
| -------------------- | ------------------ | ----- | --- | ---------------------------- |
| **Crucial 64GB kit** | CT2K32G56C46S5     | 5600  | 46  | Ships pre-installed in MS-01 |
| Kingston FURY Impact | KF556S40IBK2-64    | 5600  | 40  | STH community                |
| G.Skill Ripjaws      | F5-5600S4040A32GX2 | 5600  | 40  | Level1Techs forum            |

## DRAM Market Context (March 2026)

DDR5 prices have surged **100-150%** since mid-2025. Root cause: major DRAM fabs (Samsung, SK Hynix, Micron) shifted capacity to HBM production for AI accelerators (H100/H200/B100), reducing DDR5 consumer supply.

**Timing advice**:

- Prices unlikely to drop before Q3 2026 at earliest
- Supply may worsen Q2 2026 as HBM3e ramps
- If current prices are acceptable, buy now rather than wait
- Amazon Spring Sale (March 2026) may have brief dips — set Keepa alerts

## EU Price Comparison (March 2026)

| Model                | EU Price Est. | Where to Buy                     | Notes                         |
| -------------------- | ------------- | -------------------------------- | ----------------------------- |
| **Crucial 64GB kit** | **~119+ EUR** | **Geizhals.de, Amazon.de/.it**   | **Best value + safest pick**  |
| Kingston FURY Impact | ~200-250 EUR  | Amazon.de, Geizhals.de           | Tighter CL40 timings          |
| G.Skill Ripjaws      | ~250-280 EUR  | Limited EU stock; check Geizhals | Premium; limited availability |

## Recommendation

**Buy: Crucial CT2K32G56C46S5 (2x32GB DDR5-5600 CL46)**

Reasons:

1. **Proven compatibility** — ships pre-installed in MS-01 units, zero risk
2. **Best EU price** — ~119 EUR vs 200+ EUR for alternatives
3. **Wide availability** — stocked by Amazon.de, Amazon.it, and German retailers via Geizhals
4. **Good enough timings** — CL46 vs CL40 is ~5% theoretical bandwidth difference, imperceptible for VMs/containers

The ~80-160 EUR premium for Kingston/G.Skill buys marginally tighter timings with no real-world benefit for Proxmox/VM workloads.

## Where to Buy (Priority Order)

1. **Geizhals.de** — compare prices across EU retailers, many ship to Italy
2. **Amazon.de** — often cheaper than .it for RAM, free shipping above threshold
3. **Amazon.it** — local option, faster delivery
4. **idealo.it** — Italian price comparison as backup

## References

- ServeTheHome MS-01 review (DDR5-5600 SO-DIMM confirmed)
- Level1Techs forum MS-01 threads (community compatibility reports)
- Geizhals.de DDR5 SO-DIMM price tracking
- TrendForce DRAM market reports (HBM capacity analysis)
