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

## Prowlarr behind gluetun (2026-08-10)

Prowlarr, qBittorrent, sabnzbd, and flaresolverr all share gluetun's network namespace. Two
failure modes follow from that, and both look like an application bug.

**1 — The gluetun firewall drops LAN traffic.** `FIREWALL_OUTBOUND_SUBNETS` is empty and the
compose file sets no `FIREWALL` variable. The bridge `172.23.0.0/16` is directly connected and
passes. The LAN `192.168.100.0/20` is not, so it is dropped.

| Direction | Address | Works |
| --- | --- | --- |
| prowlarr → *arr | `http://sonarr:8989` (container name) | yes |
| prowlarr → *arr | `http://192.168.100.100:8989` (LAN IP) | **no — times out** |
| *arr → prowlarr | `http://192.168.100.100:9696` | yes, gluetun publishes 9696 |
| *arr → prowlarr | `http://gluetun:9696` | **no — `FIREWALL_INPUT_PORTS` is empty** |

Symptom: health message "All applications are unavailable due to failures for more than 6 hours",
with `Http request timed out` in the log. Fix the application `baseUrl` to a container name. Leave
`prowlarrUrl` on the LAN IP. Adding the LAN to `FIREWALL_OUTBOUND_SUBNETS` also works, but it needs
a full-stack recreate and it opens LAN egress from inside the tunnel.

**2 — FlareSolverr must share the same exit IP.** Cloudflare binds the `cf_clearance` cookie to the
IP that solved the challenge. With flaresolverr on the bridge it egressed via the home WAN while
prowlarr egressed via the VPN, so every solved cookie was rejected. The logs are misleading:
flaresolverr prints `Challenge solved!` and prowlarr still reports
`blocked by CloudFlare Protection`. Compare the two IPs before believing either:

```bash
docker exec flaresolverr curl -s https://ipinfo.io/ip   # must equal the next line
docker exec gluetun wget -qO- https://ipinfo.io/ip
```

Moving a container into the namespace needs three edits beyond `network_mode: "service:gluetun"`:
drop `hostname:` (Docker rejects it with a shared namespace), move `ports:` to gluetun, and drop
any `/etc/resolv.conf` bind (namespace members resolve through gluetun at `127.0.0.1`; a LAN
resolver there leaks DNS outside the tunnel). Prowlarr then reaches it at `http://localhost:8191`,
never `http://flaresolverr:8191`.

### Prowlarr API gotchas

| Issue | Solution |
| --- | --- |
| `apiKey` returns as `********` | The applications API masks it. Read the real key from each app (`docker exec sonarr sed -n "s\|.*<ApiKey>\(.*\)</ApiKey>.*\|\1\|p" /config/config.xml`) and include it in the PUT, or the stored key is at risk |
| PUT an indexer returns 400 | Prowlarr validates on save. A live-unreachable indexer blocks its own config change. Use `?forceSave=true` |
| No `-P` in busybox grep | The linuxserver images ship busybox. Use `sed -n "s\|...\|\1\|p"`, not `grep -oP` |
| Errors right after restoring the app link | `429 TooManyRequests` and `Should be unique` are first-sync churn. Retest before chasing them |

CAUTION: Any gluetun recreate re-runs NAT-PMP and changes the forwarded port. Run
`/opt/bin/qbt-port-sync.sh` afterward. qBittorrent does not follow the new port on its own.

### A gluetun restart strands namespace members, and the healthcheck cannot see it (2026-08-18)

Gluetun restarted and flaresolverr kept running inside the namespace gluetun abandoned. Docker
still reported `healthy` for 5 days. The container's healthcheck curls `localhost:8191` from
*inside* its own namespace, where loopback keeps working, so the probe can never detect this.
Autoheal never fired. Meanwhile flaresolverr had no route out, and prowlarr got
`Connection refused (localhost:8191)`.

`HostConfig.NetworkMode` is the *configured* parent, not the live one — it still matched gluetun's
ID, so the usual namespace check passed while the container was stranded. Probe across the
namespace boundary instead, because only that distinguishes the two states:

```bash
docker exec gluetun wget -qO- --timeout=6 http://localhost:8191/   # authoritative
docker exec flaresolverr curl -fs http://localhost:8191/health     # lies when stranded
```

Fix: `docker-compose up -d --force-recreate flaresolverr`. Prowlarr, qBittorrent, and sabnzbd
survived the same restart, so treat the blast radius as per-container, not all-or-nothing.

### FlareSolverr needs Chromium-sized memory

An interactive Cloudflare challenge (ilcorsaroblu.org) died at `mem_limit: 256m` with the 64 MB
default `/dev/shm`:

```
Error solving the challenge. Message: tab crashed (chrome=148.0.7778.178)
```

`mem_limit: 1g` plus `shm_size: 1gb` fixes it. EZTV's lighter challenge always fit in 256m, so the
limit looks adequate until a harder tracker arrives.

### Italian indexers

Prowlarr carries 8 `it-IT` definitions. Seven are private (invite or account). **Il Corsaro Blu**
(`ilcorsaroblu.org`) is the only semi-private one and needs a username and password, stored in
Prowlarr runtime config — never in this repo, which is public. It sits behind Cloudflare, so it
requires the flaresolverr tag.

An Italian tracker does NOT fix the Italian-title problem below. Its results carry the Italian
title too, so Radarr rejects them the same way.

## Radarr / Sonarr API

| Issue | Solution |
| --- | --- |
| `deleteFiles=true` on DELETE | Removes files through NFS mount chain. `/movies/` or `/tv/` (container path) → `/mnt/media/` (Flatcar) → `/media/` (reginald ZFS). Usually works, but verify on reginald afterward |
| Italian vs English titles | Radarr `.title` is usually English. Search with alternation: `test("english\|italian"; "i")` |
| API key sourcing | Always `source /srv/docker/media-stack/.env` first. Keys: `SONARR_API_KEY`, `RADARR_API_KEY`, `SEERR_API_KEY` |

## Italian audio — Radarr profile 8 "1080p Balanced ITA" (2026-08-04)

Movies downloaded English-only from 2026-06-03. Cause: Profilarr imported the Dictionarry
"1080p Balanced" profile (id 7) on 2026-05-27, and Seerr defaulted to it. Before that, profile 6
(`Language: Italian`) produced ITA+ENG grabs. Profile 7 is English-by-construction.

Profile 8 is a clone of 7 with the Italian-hostile parts neutralized. Never edit profile 7 — a
Profilarr sync restores it. Point Seerr at 8 instead.

| Blocker in profile 7 | Change in profile 8 | Why it matters for Italian |
| --- | --- | --- |
| CF `Not Original or English` = -999999 | 0 | Rejects every Italian dub outright |
| CF `Banned Dual Audio Groups` = -999999 | 0 | Regex `\bDual[ ._-]?(Audio)?\b` hits ITA-ENG releases |
| CF `x265` / `h265` = -999999 | 0 | MIRCrew / V3SP4EV3R releases are mostly x265 |
| CF `Release Group (Missing)` = -999999 | 0 | Italian releases often have no parseable group |
| CF `Italian Audio` (id 108, new) | **+900000** | Must exceed the English ceiling of ~861000 |
| `minFormatScore` 200000 | **500000** | Junk floor — see below |
| `cutoffFormatScore` 1000000 | 900000 | Any Italian grab meets cutoff and stops upgrading |

Scoring rationale: profile 7 puts every quality in ONE group (id 1001), so quality comparison always
ties and **custom format score alone ranks releases**. Its tier CFs (up to 861000) are curated
English release-group lists that Italian releases never match, so an Italian release scores 0 on the
ladder. Hence the flat +900000 bonus.

**Gotcha — `allowed: false` is ignored inside a quality group.** Setting `allowed: false` on SDTV /
DVD / 480p / 576p *inside* group 1001 does nothing; a DVD-rip still got grabbed (score 1100400).
The qualities must be moved OUT of the group into top-level items with `allowed: false`. Verify with:

```bash
curl -s -H "X-Api-Key: $RADARR_API_KEY" http://localhost:7878/api/v3/qualityprofile/8 \
  | jq -r '.items[]|if .quality then "TOP \(.allowed)\t\(.quality.name)" else "GRP \(.items|map(.quality.name)|join(","))" end'
```

Excluding SD is what keeps an Italian DVD rip from displacing an English 1080p file. Result:
Italian wins at 720p and above, English remains the fallback below that.

**Side effect — a 720p release can outrank a 1080p one (observed 2026-08-18 on *Twins*).** Because
one group flattens quality, an Italian release that also matches a tier format wins on score alone:

| Release | Score |
| --- | --- |
| `Twins 1988 720p ITA ENG BluRay x265 AAC V3SP4EV3R` | **1440200** |
| `Twins 1988 BDMux ITA ENG 10bit 1080p x265 Paso77` | 900000 |

Radarr grabbed the 720p. Check the resolution of the winner before accepting an automatic grab on
this profile. To remove the trap for good, split 720p and 1080p into separate groups the way Sonarr
profile 9 does — resolution then ranks first and Italian still wins inside each resolution.

**`minFormatScore` is the junk filter — do not set it to 0.** Dictionarry uses it to reject releases
that match no tier format. With the floor at 0, a cam rip mislabeled as HDTV-1080p
(`Spider-Man: Brand New Day 2026.1080p.HQ Pre.Multi`, score 200) passed and was queued for grab.
500000 is the correct floor:

| Release | Score | Verdict |
| --- | --- | --- |
| Italian, any allowed quality | 900000+ | pass |
| English 1080p WEB-DL | ~860000 | pass |
| English 720p Bluray (lowest legit tier) | 540000 | pass |
| Cam / telesync / "HQ Pre" junk | 0–400 | **reject** |
| English HDTV with no tier match | 40000–80000 | reject (matches profile 7 behavior) |

### Italian sources

`ilCorSaRoNeRo` and `MIRCrew` indexers are dead in Prowlarr ("Indexers have no definition"). Their
definitions were dropped upstream and no public Italian replacement exists — every `it-IT` option
left is private or semi-private. **This does not matter**: MIRCrew ITA-ENG releases are indexed on
The Pirate Bay, which is healthy and is where the working grabs come from.

Known limit: Radarr searches the TMDb title and its alternate titles. Films listed on trackers under
an Italian-only title (for example `Un Film Minecraft` for *A Minecraft Movie*) are unreachable,
because TMDb carries no Italian alternate title for them. Add one on TMDb to fix a specific film.

### Bazarr subtitles

Language profile 3 `Italiano + English` is the movie default (`movie_default_enabled: true`). It
applies to newly added movies only — existing movies need an explicit assignment:

```bash
curl -s -X POST -H "X-API-KEY: $BAZARR_API_KEY" \
  "http://localhost:6767/api/movies?radarrid=<radarrId>&profileid=3"
```

CAUTION: Do not mass-assign the whole library. Only `opensubtitlescom` is enabled, and a free
OpenSubtitles account allows about 20 downloads per day.

## Italian audio — Sonarr profile 9 "TV 1080p ITA" (2026-08-04)

Sonarr needs a different fix from Radarr. **Sonarr v4 has no language field on a quality profile**,
so the language preference can only come from a custom format.

Sonarr was never Italian, and Profilarr is not the cause here. Three separate blockers:

| Blocker | Fix in profile 9 |
| --- | --- |
| All 9 series sat on profile 1 `Any`, whose cutoff is **SDTV** | Series moved to profile 9 |
| Profile 8 `TV 1080p` disallows **HDTV-1080p** | Profile 9 allows it — see below |
| CF `x265 (HD)` = -10000 | 0 |
| No language preference existed | New CF `Italian Audio` (id 96) at **+2000** |

Profile 1's `SDTV` cutoff makes Sonarr refuse every upgrade. The rejection reads
`Existing file meets cutoff: SDTV`. Any series left on `Any` will never improve.

**The HDTV-1080p trap.** Italian releases usually carry no source tag
(`Severance.S02E05.1080p.ENG.ITA.H264-TheBlackKing.mkv`), so Sonarr parses them as **HDTV-1080p**,
not WEBDL-1080p. The Profilarr `TV 1080p` profile disallows HDTV-1080p, so every such release is
rejected as `HDTV-1080p is not wanted in profile`. Profile 9 puts HDTV-1080p in the top group.

Quality ladder in profile 9, lowest first. SD is excluded, so an Italian SD rip cannot displace an
HD file:

```
(disallowed) Unknown, Raw-HD, Remux, all 2160p, SDTV, DVD, Bluray-480p/576p, WEB 480p
  group 1002 "HD 720p"   [HDTV-720p, WEBRip-720p, WEBDL-720p, Bluray-720p]
  group 1001 "HD 1080p"  [HDTV-1080p, WEBRip-1080p, WEBDL-1080p, Bluray-1080p]   <- cutoff
```

Unlike Radarr, resolution is NOT flattened into one group. Sonarr ranks quality first, then custom
format score, so grouping by resolution keeps Italian winning **within** a resolution without
letting a 720p release outrank a 1080p one. TRaSH tier formats here (`WEB Tier 01` = 1700) are
resolution-agnostic, so one flat group would cause resolution regressions.

Scoring: best English observed = **1831** (`WEB Tier 01` 1700 + service 75 + audio). Italian at 2000
wins. `cutoffFormatScore` = 2000, so any Italian grab meets cutoff and stops upgrading, while an
English-only episode stays below cutoff and keeps looking for Italian.

Sonarr's other -10000 formats are safe for Italian: `Bad Multis` only matches `\bJOiNED\b`, and the
`LQ` formats are specific bad-group lists.

**Gotcha — creating a custom format silently edits every existing profile.** Sonarr auto-adds the
new format at score 0 to all profiles. Cloning a profile and then appending the format produces a
DUPLICATE `formatItems` entry for the same `format` id (one at 0, one at your score). Deduplicate:

```bash
jq '.formatItems = (.formatItems | group_by(.format) | map(max_by(.score)))'
# verify: dupes must be 0
curl -s -H "X-Api-Key: $SONARR_API_KEY" http://localhost:8989/api/v3/qualityprofile/9 \
  | jq '(.formatItems|length) - ([.formatItems[].format]|unique|length)'
```

Anime profile 7 is deliberately untouched — Seerr still routes anime to it via `animeTags`.

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
