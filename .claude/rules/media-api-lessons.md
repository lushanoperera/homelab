---
paths:
  - "vms/flatcar-media/**"
  - "scripts/vms/**"
  - "apps/**"
recall:
  - seerr
  - sonarr
  - radarr
  - qbittorrent
  - gluetun
  - arr api
---

# Media Stack API Lessons

## Seerr API

| Issue | Solution |
| --- | --- |
| DELETE returns 403 "invalid csrf token" | Seerr requires XSRF-TOKEN cookie+header dance. First GET `/api/v1/status` with `-c cookiejar` to obtain cookies, then pass `-b cookiejar -H "x-xsrf-token: $XSRF"` on DELETE |
| Movies vs TV use different ID fields | Movies: `tmdbId` in Seerr media object. TV: `tvdbId` in Seerr media object |
| Deleting a request vs deleting media | Delete the **media** entry (`/api/v1/media/{id}`) — cascades to associated requests. Deleting just the request may leave orphan media |
| Finding media for a title | Seerr doesn't search by name. Get TMDB/TVDB ID from Radarr/Sonarr first, then filter Seerr requests: `.results[] | select(.media.tmdbId == ID)` |

## qBittorrent API

| Issue | Solution |
| --- | --- |
| API calls fail from Flatcar host | qBittorrent shares gluetun's network namespace. Must use `docker exec gluetun wget -qO-` not `curl localhost:8080` from host |
| Deleting multiple torrents | Pipe-separate hashes: `hashes=HASH1\|HASH2&deleteFiles=true` via `--post-data` to `/api/v2/torrents/delete` |
| Torrent name matching | Names may use dots, spaces, or mixed case. Use regex: `test("title.pattern"; "i")` in jq |

## Radarr / Sonarr API

| Issue | Solution |
| --- | --- |
| `deleteFiles=true` on DELETE | Removes files through NFS mount chain. `/movies/` or `/tv/` (container path) → `/mnt/media/` (Flatcar) → `/media/` (reginald ZFS). Usually works, but verify on reginald afterward |
| Italian vs English titles | Radarr `.title` is usually English. Search with alternation: `test("english\|italian"; "i")` |
| API key sourcing | Always `source /srv/docker/media-stack/.env` first. Keys: `SONARR_API_KEY`, `RADARR_API_KEY`, `SEERR_API_KEY` |

## Media Removal Order

Always remove in this order to prevent re-requests or orphan data:

1. **Seerr** (media entry) — prevents re-requesting
2. **qBittorrent** (torrents + files) — stops active downloads, removes incomplete files
3. **Sonarr/Radarr** (with `deleteFiles=true`) — removes from library + deletes completed files via NFS
4. **Verify on reginald** — belt-and-suspenders check, manual `rm -rf` if needed

## Profilarr V2 API

| Issue | Solution |
| --- | --- |
| Image tag format | `ghcr.io/dictionarry-hub/profilarr:2.0.6` — bare semver, NOT `v2.0.6` (GitHub releases use v-prefix, registry strips it) |
| OOM on default mem_limit | 256m kills profilarr in seconds (exit 137). Needs 512m minimum (~350MiB at idle) |
| Parser healthcheck | Parser image lacks curl. Use `wget --spider /health` (returns `{"status":"healthy"}`; `/` is 404) |
| Sibling DNS broken | `/srv/docker/resolv.conf` bind overrides Docker embedded DNS at 127.0.0.11 → sibling container names (radarr, sonarr) don't resolve. Drop the bind for profilarr; embedded DNS handles siblings + forwards external upstream |
| API auth header | `X-API-Key: <key>` on `/api/v1/*` — key generated in Settings → API Keys (after first admin login, no key by default) |
| Arr sync via API | NOT exposed in v2.0.6 OpenAPI. `/api/v1/arr` is GET-only. Sync must be triggered via UI form actions (SvelteKit routes blocked by CSRF for X-API-Key auth) |
| Database add via API | POST `/api/v1/databases` works. Required: `name`, `repository_url`. Default branch may differ — Dumpstarr is `stable`, Dictionarry is `main` |
| Sync trigger via API | POST `/api/v1/databases/{id}/sync` returns `{"jobId": N}`. Poll `/api/v1/jobs/{id}` for `status: "success"` + `result.status: "skipped"` / `"completed"` |

## Seerr Anime Routing

Single Sonarr instance handles both Western TV + anime via per-series-type config in Seerr:

```bash
# CSRF dance required (mandatory for all PUT/POST)
curl -s -c /tmp/seerr.cookies -H "X-Api-Key: $SK" http://localhost:5055/api/v1/status > /dev/null
XSRF=$(grep XSRF-TOKEN /tmp/seerr.cookies | awk '{print $NF}')

# PUT /api/v1/settings/sonarr/0 with anime fields:
# activeProfileId/activeProfileName/activeDirectory     → Western TV (e.g. TV 1080p, /tv)
# activeAnimeProfileId/Name/Directory + animeSeriesType=anime + animeTags=[<anime-tag-id>]
```

Seerr auto-detects anime by TMDB keyword 210024 and routes to the anime block.

## Plex Modern (1.40+) Legacy Agent Removal

| Issue | Solution |
| --- | --- |
| HAMA agent missing from dropdown | Plex removed legacy plug-in support in PMS 1.40.x. HAMA / AniDB / TVDB-bundle no longer load. Built-in Plex Series + Plex Personal Media only |
| Anime metadata fallback | Plex Series agent now handles anime via TVDB ordering — covers ~90% of mainstream catalog. For misses, force-match via folder suffix `[tvdbid-{TvdbId}]` (Sonarr Anime series folder format does this automatically) |
| Jellyfin escape hatch | Still supports proper AniDB plugin. Can run alongside Plex on same `/mnt/media/anime` NFS if Plex Series proves insufficient |
