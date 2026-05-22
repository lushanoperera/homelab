# Blocklist Management — Technitium Cluster

Two-list policy, refreshed every 24h. Replication carries the parsed
blocked-zone tree from QNAP primary to Flatcar + Reginald secondaries — only
the primary downloads list bodies.

## Active lists

| List                                  | URL                                                                | Why                                                                                  |
| ------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| StevenBlack/hosts (unified ads+mal)   | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` | Curated baseline that has held up well — low false-positive rate, broad coverage     |
| Hagezi Pro                            | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt` | Larger pattern set (~265 K entries combined with StevenBlack); Hagezi maintains tiers |

Combined size: ~265 K blocked names. Cache hit + block ratio sit around the
30–45% range depending on time of day.

## Why not pile on more lists

- Each additional list multiplies false-positive risk — and the ones already
  in place cover ad, telemetry, malware, and tracker categories generously.
- Hagezi Ultimate / Threat Intelligence levels start breaking everyday SaaS
  (auth providers, A/B test frameworks, CDN segments). Diagnosing "site X
  doesn't load" gets harder when the blocklist tree is 800 K deep.
- Hagezi tiers above Pro often duplicate StevenBlack entries — extra disk +
  RAM with marginal coverage.

If a request comes in to block a specific domain ("kill all of X"), prefer a
**custom zone** with NXDOMAIN responses over adding another global list.

## Refresh interval

Default `blockListUpdateIntervalHours = 24` is what we run. Verify and adjust
via API (substitute `$TOKEN` from `/api/user/login`):

```bash
# Get current value
curl -sk -G "https://192.168.100.254:5380/api/settings/get" \
    --data-urlencode "token=$TOKEN" \
  | jq '.response.blockListUpdateIntervalHours'

# Force update interval to 24h (if drift detected)
curl -sk -G "https://192.168.100.254:5380/api/settings/set" \
    --data-urlencode "token=$TOKEN" \
    --data-urlencode "blockListUpdateIntervalHours=24"

# Confirm last refresh advanced
curl -sk -G "https://192.168.100.254:5380/api/settings/get" \
    --data-urlencode "token=$TOKEN" \
  | jq '.response.blockListLastUpdatedOn'
```

The setting only needs to be applied on the primary — secondaries inherit it
via cluster replication.

## Manual refresh

UI: Settings → Blocking → "Update Now". API:

```bash
curl -sk -G "https://192.168.100.254:5380/api/settings/forceUpdateBlockLists" \
    --data-urlencode "token=$TOKEN"
```

## Allowlist for false positives

Block-list bypasses live in Zones → "allowed" (built-in zone). Add a single
A or `*` record for the FQDN that needs to slip through. These records
replicate to secondaries.

Avoid editing the source `hosts.txt` files directly — Technitium overwrites
them on every refresh.
