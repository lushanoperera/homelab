# Price Tracking Notes

Last updated: 2026-03-05

## NAS HDDs (4-6TB CMR) — EU Prices March 2026

| Model                        | Capacity | Best Price (EUR) | Source                | EUR/TB    |
| ---------------------------- | -------- | ---------------- | --------------------- | --------- |
| Seagate Ironwolf ST4000VN006 | 4TB      | ~137-153         | idealo.it / Amazon.it | 38.28     |
| Seagate Ironwolf ST6000VN006 | 6TB      | ~197             | idealo.it             | 32.79     |
| WD Red Plus WD40EFPX         | 4TB      | ~159             | Geizhals.de           | 39.75     |
| **WD Red Plus WD60EFPX**     | **6TB**  | **~187**         | **idealo.it**         | **31.18** |
| Toshiba N300 4TB (HDWG440)   | 4TB      | ~155             | Geizhals.de           | 38.73     |
| **Toshiba N300 6TB (bulk)**  | **6TB**  | **~178**         | **Geizhals.de**       | **29.67** |

**Key finding**: 6TB drives at ~€30/TB are significantly better value than 4TB at ~€39/TB (~25% savings per TB).

### Shucking Option

| Model          | Capacity | Price (EUR) | EUR/TB | Notes                                                                                                                                          |
| -------------- | -------- | ----------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| WD My Book 8TB | 8TB      | ~170        | 21.11  | CMR confirmed (2022-2023 teardowns). Verify 2026 batches on r/DataHoarders before buying. Amazon EU for easy returns if SATA port is soldered. |

## DDR5 64GB SO-DIMM for MS-01 — EU Prices March 2026

Target: 3x kits of 2x32GB DDR5-5600 SO-DIMM (one per cluster node, MS-01 uses laptop memory)

**DRAM market warning**: DDR5 prices surged 100-150% since mid-2025 due to AI/HBM capacity diversion at major fabs. Supply may worsen Q2 2026. Buy sooner rather than later if prices are acceptable.

| Model                | Part Number        | EU Price Est.    | CL   | Compatibility                                 |
| -------------------- | ------------------ | ---------------- | ---- | --------------------------------------------- |
| **Crucial 64GB kit** | CT2K32G56C46S5     | ~119+ (Geizhals) | CL46 | Pre-installed in MS-01; best confirmed compat |
| Kingston FURY Impact | KF556S40IBK2-64    | ~200-250 est.    | CL40 | Should work; tighter timings                  |
| G.Skill Ripjaws      | F5-5600S4040A32GX2 | ~250-280 est.    | CL40 | Limited EU stock                              |

**MS-01 compatibility notes**:

- ServeTheHome + Level1Techs confirm DDR5-5600 SO-DIMM works
- Crucial is the safest choice (ships pre-installed in MS-01 units)
- Non-i9 variants may downclock to 5200 MT/s — negligible perf impact
- Max 96GB (2x48GB) on i9-13900H; 64GB (2x32GB) on other CPUs

**Recommendation**: Crucial CT2K32G56C46S5 — best price, best compatibility, widest EU availability.

## MS-01 i9-13900H Units — EU Prices March 2026

Need: 2x MS-01 i9-13900H barebones (for 3-node Proxmox HA cluster)

### New

| Source              | Config              | Price Est. (EUR) | Notes                                                  |
| ------------------- | ------------------- | ---------------- | ------------------------------------------------------ |
| Minisforum Official | Barebones i9-13900H | ~550-650         | Direct from manufacturer, 3-year warranty              |
| Minisforum Official | 32GB + 512GB SSD    | ~800-950         | Configured option — skip if buying RAM/NVMe separately |
| Amazon.it/.de       | Barebones i9-13900H | ~600-750         | Third-party sellers, variable stock                    |
| Geizhals.de         | Barebones i9-13900H | ~550-700         | Cross-EU retailer comparison                           |

### Used

| Platform                    | Expected Price Range (EUR) | Notes                                            |
| --------------------------- | -------------------------- | ------------------------------------------------ |
| eBay.it / eBay.de / eBay.fr | ~400-550 barebones         | Widest EU used market. 30-day buyer guarantee    |
| Subito.it                   | ~350-500                   | Italian classifieds, local pickup possible       |
| Kleinanzeigen.de            | ~400-550                   | German classifieds (formerly eBay Kleinanzeigen) |
| Vinted                      | ~350-500                   | Expanding into electronics in EU                 |
| Facebook Marketplace        | ~350-500                   | No buyer protection — local pickup recommended   |

**Used buying checklist**: BIOS version (early batches had NVMe issues), physical condition, included accessories, original purchase date.

## NVMe Boot Drives (256GB) — EU Prices March 2026

Need: 3x 256GB M.2 2280 (one per node, Proxmox OS)

| Model           | Capacity | EU Price Est. (EUR) | TBW    | DRAM/HMB  | Notes                           |
| --------------- | -------- | ------------------- | ------ | --------- | ------------------------------- |
| Samsung 980 Pro | 256GB    | ~50-60              | 150 TB | DRAM      | Overkill for boot, but reliable |
| WD Black SN770  | 256GB    | ~35-45              | 200 TB | HMB       | Great value boot drive          |
| Kingston NV2    | 256GB    | ~25-30              | 80 TB  | DRAM-less | Budget. Fine for OS-only        |
| Crucial P3      | 256GB    | ~25-35              | 110 TB | DRAM-less | Budget alternative              |

**Recommendation**: WD SN770 256GB — best reliability-to-price ratio for boot.

## NVMe Ceph/Cache Drives (512GB-2TB) — EU Prices March 2026

Need: 3x drives (one per node, Ceph OSD + WAL/journal). High endurance critical.

### 512GB Tier

| Model                 | EU Price Est. (EUR) | TBW    | DRAM | Seq Write  | Notes                      |
| --------------------- | ------------------- | ------ | ---- | ---------- | -------------------------- |
| Samsung 990 Pro       | ~75-90              | 300 TB | Yes  | 6,900 MB/s | Top tier endurance + speed |
| WD Black SN850X       | ~65-80              | 300 TB | Yes  | 6,600 MB/s | Strong alternative         |
| Crucial T500          | ~55-70              | 300 TB | Yes  | 6,600 MB/s | Best value in tier         |
| SK Hynix P41 Platinum | ~60-75              | 250 TB | Yes  | 5,000 MB/s | Slightly lower TBW         |

### 1TB Tier (Sweet Spot)

| Model                 | EU Price Est. (EUR) | TBW    | DRAM | Seq Write  | Notes               |
| --------------------- | ------------------- | ------ | ---- | ---------- | ------------------- |
| Samsung 990 Pro       | ~100-120            | 600 TB | Yes  | 6,900 MB/s | Premium pick        |
| WD Black SN850X       | ~85-105             | 600 TB | Yes  | 6,600 MB/s | Strong value        |
| Crucial T500          | ~80-100             | 600 TB | Yes  | 6,900 MB/s | Best EUR/TBW        |
| SK Hynix P41 Platinum | ~85-100             | 750 TB | Yes  | 7,000 MB/s | Highest TBW in tier |

### 2TB Tier (Premium)

| Model                 | EU Price Est. (EUR) | TBW      | DRAM | Seq Write  | Notes             |
| --------------------- | ------------------- | -------- | ---- | ---------- | ----------------- |
| Samsung 990 Pro       | ~170-200            | 1,200 TB | Yes  | 6,900 MB/s | Top endurance     |
| WD Black SN850X       | ~150-180            | 1,200 TB | Yes  | 6,600 MB/s | Solid alternative |
| Crucial T500          | ~140-170            | 1,200 TB | Yes  | 6,900 MB/s | Best value at 2TB |
| SK Hynix P41 Platinum | ~150-175            | 1,200 TB | Yes  | 7,000 MB/s | Fast + durable    |

**Decision**: WD Black SN850X 2TB (no heatsink) — ~€230 on Geizhals/Amazon.de, cheapest 2TB with 1,200 TBW + DRAM. 3x drives = ~€690. ~2TB usable with 3-replica Ceph.

## Thunderbolt 4 Cables — EU Prices March 2026

Need: 3x TB4 cables for Ceph ring topology (A↔B, B↔C, C↔A)

| Cable             | Length | Type    | EU Price Est. (EUR) | Notes                               |
| ----------------- | ------ | ------- | ------------------- | ----------------------------------- |
| Cable Matters TB4 | 0.8m   | Passive | ~25-35              | Best value, fine for adjacent nodes |
| Anker TB4         | 0.7m   | Passive | ~25-30              | Good budget option                  |
| Apple TB4 Pro     | 1m     | Active  | ~70-80              | Reliable but pricey                 |
| Apple TB4 Pro     | 1.8m   | Active  | ~80-90              | For spaced-apart nodes              |
| CalDigit TB4      | 0.8m   | Passive | ~30-40              | Premium build quality               |
| Belkin TB4        | 1m     | Active  | ~40-55              | Mid-range active option             |

**Passive vs Active**: Passive cables work up to ~0.8m (nodes must be adjacent). Active cables for 1m+ distances. For a desktop cluster, passive 0.8m is usually sufficient.

**Recommendation**: 3x Cable Matters TB4 0.8m passive (~€75-105 total) if nodes are adjacent. 3x Apple TB4 Pro 1.8m (~€240-270 total) if nodes are spaced apart.

## Price Comparison Tools

| Tool            | URL                 | Best For                                       |
| --------------- | ------------------- | ---------------------------------------------- |
| Keepa           | keepa.com           | Amazon price alerts across EU regions          |
| Geizhals        | geizhals.de         | Cross-EU retailer comparison (Germany-centric) |
| idealo.it       | idealo.it           | Italian market price comparison                |
| Disc Prices     | diskprices.com      | Amazon drive prices by region                  |
| CamelCamelCamel | camelcamelcamel.com | Amazon price history (spot fake discounts)     |

## Seasonal Events to Watch (EU-relevant)

| Event                  | When                 | Where            | Notes                                        |
| ---------------------- | -------------------- | ---------------- | -------------------------------------------- |
| **Amazon Spring Sale** | **March 2026 (NOW)** | **Amazon EU**    | **Check for HDD/RAM deals — sale is active** |
| Amazon Prime Day       | July                 | Amazon EU        | Major discounts on storage/RAM               |
| Black Friday           | Late November        | All EU retailers | Best annual deals typically                  |
| Cyber Monday           | Late November        | All EU retailers | Extension of Black Friday                    |

## Used Marketplace Monitoring

Search terms: "Minisforum MS-01", "MS-01 i9-13900H", "MS-01 barebones"

| Platform             | Region  | Notes                       |
| -------------------- | ------- | --------------------------- |
| eBay.it              | Italy   | Buyer guarantee 30 days     |
| eBay.de              | Germany | Larger market, ships to IT  |
| eBay.fr              | France  | Occasional deals            |
| Subito.it            | Italy   | Local pickup, negotiate     |
| Kleinanzeigen.de     | Germany | Formerly eBay Kleinanzeigen |
| Vinted               | EU-wide | Expanding into electronics  |
| Facebook Marketplace | Local   | No buyer protection         |

**Tip**: Set up saved searches with notifications on eBay.it and eBay.de for "MS-01 i9-13900H" to catch new listings early.

## Price Alert Checklist

### Keepa (Amazon.it + Amazon.de)

Install extension: https://keepa.com/ — track on BOTH Amazon.it and Amazon.de for each item.

| Item              | Search Term                      | Target (EUR) | Qty | Priority               |
| ----------------- | -------------------------------- | ------------ | --- | ---------------------- |
| DDR5 RAM          | Crucial CT2K32G56C46S5           | ≤119/kit     | 3   | URGENT — prices rising |
| NVMe Boot         | WD Blue SN580 250GB              | ≤35          | 2   | Medium                 |
| NVMe Ceph         | Crucial T500 1TB                 | ≤90          | 2   | Medium                 |
| NVMe Ceph (alt)   | WD Black SN850X 1TB              | ≤95          | 2   | Medium                 |
| TB4 Cable (short) | Cable Matters Thunderbolt 4 0.8m | ≤30          | 3   | Low                    |
| TB4 Cable (long)  | Apple Thunderbolt 4 Pro 1.8m     | ≤80          | 3   | Low                    |

Setup per item: Open Amazon page → scroll to Keepa chart → "Track product" → set desired price → tracking duration 365 days.

### eBay Saved Searches (MS-01 only)

| Platform | Search Query                 | Email Alerts |
| -------- | ---------------------------- | ------------ |
| eBay.it  | `Minisforum MS-01 i9-13900H` | ON           |
| eBay.it  | `Minisforum MS-01 barebones` | ON           |
| eBay.de  | `Minisforum MS-01 i9-13900H` | ON           |
| eBay.de  | `Minisforum MS-01 barebones` | ON           |

### Subito.it Alert

Search: "Minisforum MS-01" → tap bell icon on results page to enable push notifications.

## Purchase Log

| Date | Item | Store | Price | Notes            |
| ---- | ---- | ----- | ----- | ---------------- |
| —    | —    | —     | —     | No purchases yet |
