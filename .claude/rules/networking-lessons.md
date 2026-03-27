---
paths:
  - "scripts/network/**"
  - "networking/**"
recall:
  - unifi
  - wifi
  - radio ai
  - mesh
  - channel
---

# Networking Lessons (UniFi / WiFi)

| Topic              | Lesson                                                                                                                                                |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| UniFi API Auth     | CSRF token is INSIDE the JWT payload — decode TOKEN cookie's middle base64 segment → `.csrfToken`. Raw JWT as header = 403.                           |
| UniFi API Write    | `PUT /proxy/network/api/s/{site}/rest/device/{id}` with full `radio_table` array + `X-CSRF-Token` header                                              |
| Radio Table Fields | `radio_table` = config (channel/ht/tx_power), `radio_table_stats` = runtime (cu_total/satisfaction/num_sta). Join by `.radio` (ng=2.4, na=5, 6e=6GHz) |
| TX Power           | `tx_power_mode` = named (auto/medium/high/low/custom), `tx_power` = null unless custom mode                                                           |
| DFS Channels       | UNII-2/2e (ch 52-140) require 60s CAC radar scan (ETSI). AP may fall back to non-DFS if radar detected.                                               |
| Italy Regulatory   | Country code 380: UNII-3 (ch 149+) unavailable in UniFi firmware. Only UNII-1 (36-48) and UNII-2/2e (52-140).                                         |
| Wireless Mesh      | Mesh APs MUST share 5 GHz channel with parent AP — "Channel controlled by uplink AP". Cannot separate without Ethernet.                               |
| Radio AI           | `rest/setting/radio_ai` manages channel optimization. `exclude_devices` takes MAC array. No manual trigger — runs on cron.                            |
| Satisfaction Field | -1 means insufficient samples (display as N/A)                                                                                                        |
| SSO vs Local       | SSO accounts require MFA — create a **local-only admin** (Restrict to Local Access Only) for API automation                                           |

## Script Reference

- **Read-only inventory**: `scripts/network/unifi-inventory.sh` — flags: `--clients`, `--devices`, `--networks`, `--health`, `--wifi`, `--all`, `--json`
- **WiFi optimizer**: `scripts/network/unifi-wifi-optimize.sh` — modes: `--dry-run`, `--apply`, `--rollback`
- **Credentials**: `scripts/network/.env` (copy `.env.example`)
