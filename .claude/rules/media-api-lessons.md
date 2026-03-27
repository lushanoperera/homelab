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
