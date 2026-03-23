---
name: media-remove
description: Remove a movie or TV series from Seerr, Sonarr/Radarr, qBittorrent, and reginald files
tools: Bash, Read
---

# Media Removal

Completely remove a movie or TV series from the entire media stack.

## When to Use

- User wants to delete a title from all services
- Cleaning up unwanted downloads
- Removing content that was requested by mistake

## Prerequisites

- SSH access to Flatcar VM (`core@192.168.100.100`) and reginald (`root@192.168.100.4`)
- `/srv/docker/media-stack/.env` with `SONARR_API_KEY`, `RADARR_API_KEY`, `SEERR_API_KEY`

## Instructions

### Phase 1: Identify the Title

Determine if it's a **movie** (Radarr) or **TV series** (Sonarr), then get the ID.

**For movies:**

```bash
ssh core@192.168.100.100 'source /srv/docker/media-stack/.env && \
  curl -sf -H "X-Api-Key: $RADARR_API_KEY" http://localhost:7878/api/v3/movie | \
  jq ".[] | select(.title | test(\"SEARCH_TERM\"; \"i\")) | {id, title, path, tmdbId}"'
```

**For TV series:**

```bash
ssh core@192.168.100.100 'source /srv/docker/media-stack/.env && \
  curl -sf -H "X-Api-Key: $SONARR_API_KEY" http://localhost:8989/api/v3/series | \
  jq ".[] | select(.title | test(\"SEARCH_TERM\"; \"i\")) | {id, title, path, tvdbId}"'
```

Note the `id`, `tmdbId`/`tvdbId`, and `path`.

### Phase 2: Delete from Seerr

**IMPORTANT**: Seerr DELETE requires XSRF-TOKEN cookie+header dance.

Find the Seerr media entry (movies use `tmdbId`, TV uses `tvdbId`):

```bash
ssh core@192.168.100.100 'source /srv/docker/media-stack/.env && \
  curl -sf -H "X-Api-Key: $SEERR_API_KEY" "http://localhost:5055/api/v1/request?take=100" | \
  jq ".results[] | select(.media.tmdbId == TMDB_ID) | {id, mediaId: .media.id}"'
```

Delete the **media entry** (cascades to requests):

```bash
ssh core@192.168.100.100 'source /srv/docker/media-stack/.env && \
  CJ=$(mktemp) && \
  curl -sf -c "$CJ" -H "X-Api-Key: $SEERR_API_KEY" "http://localhost:5055/api/v1/status" > /dev/null && \
  XSRF=$(grep XSRF-TOKEN "$CJ" | awk "{print \$NF}") && \
  curl -X DELETE -b "$CJ" -H "X-Api-Key: $SEERR_API_KEY" -H "x-xsrf-token: $XSRF" \
    "http://localhost:5055/api/v1/media/MEDIA_ID" -w "\nHTTP %{http_code}\n" 2>/dev/null && \
  rm -f "$CJ"'
```

Expected: HTTP 204.

If Seerr has no request for this title, skip to Phase 3.

### Phase 3: Delete from qBittorrent

qBittorrent runs inside gluetun — must use `docker exec gluetun`:

```bash
# Find matching torrents
ssh core@192.168.100.100 'docker exec gluetun wget -qO- "http://localhost:8080/api/v2/torrents/info" | \
  jq ".[] | select(.name | test(\"SEARCH_PATTERN\"; \"i\")) | {hash, name, state, size}"'
```

Use dots in the pattern for flexible matching (e.g., `days.of.thunder` matches "Days of Thunder" and "Days.of.Thunder").

```bash
# Delete torrents + downloaded data (pipe-separate multiple hashes)
ssh core@192.168.100.100 'docker exec gluetun wget -qO- \
  --post-data="hashes=HASH1|HASH2&deleteFiles=true" "http://localhost:8080/api/v2/torrents/delete"'
```

If no torrents found, skip.

### Phase 4: Delete from Sonarr/Radarr

**Movies (Radarr):**

```bash
ssh core@192.168.100.100 'source /srv/docker/media-stack/.env && \
  curl -sf -X DELETE -H "X-Api-Key: $RADARR_API_KEY" \
  "http://localhost:7878/api/v3/movie/MOVIE_ID?deleteFiles=true" -w "\nHTTP %{http_code}\n"'
```

**TV Series (Sonarr):**

```bash
ssh core@192.168.100.100 'source /srv/docker/media-stack/.env && \
  curl -sf -X DELETE -H "X-Api-Key: $SONARR_API_KEY" \
  "http://localhost:8989/api/v3/series/SERIES_ID?deleteFiles=true" -w "\nHTTP %{http_code}\n"'
```

Expected: HTTP 200. `deleteFiles=true` removes files through the NFS mount chain.

### Phase 5: Verify on Reginald

```bash
# Movies
ssh root@192.168.100.4 'ls /media/movies/ | grep -i "TITLE" || echo "Clean"'

# TV
ssh root@192.168.100.4 'ls /media/tv/ | grep -i "TITLE" || echo "Clean"'
```

If files remain, manually remove:

```bash
ssh root@192.168.100.4 'rm -rf "/media/movies/FOLDER_NAME"'
# or
ssh root@192.168.100.4 'rm -rf "/media/tv/FOLDER_NAME"'
```

### Phase 6: Final Verification

Run all three checks — all should return 0:

```bash
# Radarr/Sonarr
ssh core@192.168.100.100 'source /srv/docker/media-stack/.env && \
  curl -sf -H "X-Api-Key: $RADARR_API_KEY" http://localhost:7878/api/v3/movie | \
  jq "[.[] | select(.title | test(\"SEARCH_TERM\"; \"i\"))] | length"'

# qBittorrent
ssh core@192.168.100.100 'docker exec gluetun wget -qO- "http://localhost:8080/api/v2/torrents/info" | \
  jq "[.[] | select(.name | test(\"SEARCH_PATTERN\"; \"i\"))] | length"'

# Reginald filesystem
ssh root@192.168.100.4 'ls /media/movies/ /media/tv/ 2>/dev/null | grep -i "TITLE" | wc -l'
```

## Output Format

```
## Media Removal Report

| Service | Action | Status |
|---------|--------|--------|
| Seerr | Deleted media MEDIA_ID | Done / Not found |
| qBittorrent | Deleted N torrents (X GB) | Done / Not found |
| Radarr/Sonarr | Deleted ID with files | Done |
| Reginald | Files verified removed | Clean |
```

## Gotchas

- **Seerr CSRF**: Always do the cookie+XSRF-TOKEN dance. Plain DELETE returns 403.
- **Italian titles**: Search with alternation `english|italian` pattern.
- **qBittorrent network**: Always `docker exec gluetun`, never `curl localhost:8080` from host.
- **Delete order matters**: Seerr → qBittorrent → Radarr/Sonarr → verify reginald.
