---
name: quality-manage
description: Quality profile management for Sonarr/Radarr - create, view, apply profiles
allowed-tools: Bash, Read
---

# Quality Profile Management

Manage quality profiles in Sonarr and Radarr for optimal download selection.

## When to Use

- Items stuck because only available in wrong quality
- Setting up new quality preferences
- Applying profiles to existing media
- Debugging why items aren't downloading

## Quality Profile Strategy

**Problem**: Strict 4K-only profiles miss content only available in 1080p.

**Solution**: Tiered profiles that:

1. **Prefer** 4K/2160p when available
2. **Accept** 1080p as fallback
3. **Upgrade** automatically when better quality appears

## Instructions

### Phase 1: View Current Profiles

List all profiles:

```bash
ssh core@192.168.100.100 '/opt/bin/setup-quality-profiles.sh --list'
```

Or manually:

```bash
# Radarr
ssh core@192.168.100.100 'curl -s "http://localhost:7878/api/v3/qualityprofile" -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".[] | {id, name}"'

# Sonarr
ssh core@192.168.100.100 'curl -s "http://localhost:8989/api/v3/qualityprofile" -H "X-Api-Key: $(grep SONARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".[] | {id, name}"'
```

### Phase 2: Create Fallback Profile

Dry run first:

```bash
ssh core@192.168.100.100 '/opt/bin/setup-quality-profiles.sh --dry-run'
```

Create profile:

```bash
ssh core@192.168.100.100 '/opt/bin/setup-quality-profiles.sh'
```

### Phase 3: Apply to Existing Media

Apply to all existing movies and series:

```bash
ssh core@192.168.100.100 '/opt/bin/setup-quality-profiles.sh --apply-to-existing'
```

### Phase 4: Verify Profile

Check a movie's profile:

```bash
ssh core@192.168.100.100 'curl -s "http://localhost:7878/api/v3/movie" -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".[0] | {title, qualityProfileId}"'
```

Check a series' profile:

```bash
ssh core@192.168.100.100 'curl -s "http://localhost:8989/api/v3/series" -H "X-Api-Key: $(grep SONARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".[0] | {title, qualityProfileId}"'
```

### Phase 5: Trigger Upgrades

After changing profiles, search for upgrades:

```bash
# Radarr - search for upgrades
ssh core@192.168.100.100 'curl -s -X POST "http://localhost:7878/api/v3/command" -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" -H "Content-Type: application/json" -d "{\"name\":\"MissingMoviesSearch\"}"'

# Sonarr - search for missing
ssh core@192.168.100.100 'curl -s -X POST "http://localhost:8989/api/v3/command" -H "X-Api-Key: $(grep SONARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" -H "Content-Type: application/json" -d "{\"name\":\"MissingEpisodeSearch\"}"'
```

## Quality Priority (Default Profile)

The "4K with 1080p Fallback" profile prioritizes:

| Priority | Quality      | Notes                      |
| -------- | ------------ | -------------------------- |
| 1        | Remux-2160p  | Best quality, largest size |
| 2        | Bluray-2160p | High quality 4K            |
| 3        | WEB 2160p    | Streaming 4K               |
| 4        | HDTV-2160p   | Broadcast 4K               |
| 5        | Bluray-1080p | Fallback - high quality    |
| 6        | WEBDL-1080p  | Fallback - streaming       |
| 7        | WEBRip-1080p | Fallback                   |
| 8        | HDTV-1080p   | Fallback - broadcast       |

Cutoff: Remux-2160p (stops upgrading when reached)

## Manual Profile Creation

If script fails, create via API:

```bash
# Radarr example
ssh core@192.168.100.100 'curl -s -X POST "http://localhost:7878/api/v3/qualityprofile" \
  -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"4K with 1080p Fallback\",
    \"upgradeAllowed\": true,
    \"cutoff\": 18,
    \"items\": [
      {\"quality\": {\"id\": 18}, \"allowed\": true},
      {\"quality\": {\"id\": 19}, \"allowed\": true},
      {\"quality\": {\"id\": 31}, \"allowed\": true},
      {\"quality\": {\"id\": 7}, \"allowed\": true},
      {\"quality\": {\"id\": 3}, \"allowed\": true}
    ]
  }"'
```

## Troubleshooting

### Profile Not Working

Check quality definitions match:

```bash
ssh core@192.168.100.100 'curl -s "http://localhost:7878/api/v3/qualitydefinition" -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".[] | {id, title}"'
```

### Items Still Stuck

1. Check if profile is assigned:

```bash
ssh core@192.168.100.100 'curl -s "http://localhost:7878/api/v3/movie" -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".[] | select(.hasFile == false) | {title, qualityProfileId, monitored}"'
```

2. Check if item is monitored
3. Run manual search in UI to see available qualities

### Quality IDs Differ

Quality IDs can vary between installations. Get actual IDs:

```bash
ssh core@192.168.100.100 'curl -s "http://localhost:7878/api/v3/qualitydefinition" -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq'
```

## Output Format

```
## Quality Profile Report

### Current Profiles

#### Radarr
| ID | Name | Cutoff |
|----|------|--------|
| 1 | Any | HDTV-720p |
| 2 | 4K with 1080p Fallback | Remux-2160p |

#### Sonarr
| ID | Name | Cutoff |
|----|------|--------|
| 1 | Any | HDTV-720p |
| 2 | 4K with 1080p Fallback | Remux-2160p |

### Action Taken
- Created/Updated profile: [name]
- Applied to: X movies, Y series

### Stuck Items (if any)
| Type | Title | Current Profile | Issue |
|------|-------|-----------------|-------|
| Movie | Example | HD Only | No 1080p releases |
```
