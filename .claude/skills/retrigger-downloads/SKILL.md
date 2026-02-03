---
name: retrigger-downloads
description: Retrigger Overseerr requests that are stuck (not downloaded, not in queue)
allowed-tools: Bash, Read
---

# Retrigger Missing Downloads

Find and retrigger Overseerr requests that failed to download.

## When to Use

- After VPN reconnection or port change
- When Overseerr shows pending but nothing downloading
- Periodic cleanup of stuck requests
- After qBittorrent queue was cleared

## Prerequisites

Ensure `/srv/docker/media-stack/.env` exists on Flatcar VM with:

- `OVERSEERR_API_KEY`
- `SONARR_API_KEY`
- `RADARR_API_KEY`

## Instructions

### Phase 1: Dry Run First

Always check what would be retriggered:

```bash
ssh core@192.168.100.100 '/opt/bin/retrigger-missing-downloads.sh --dry-run'
```

This shows:

- Which requests are stuck
- Movies vs TV series
- Why each was skipped (already downloaded, in queue, etc.)

### Phase 2: Execute Retrigger

If dry run looks correct:

```bash
ssh core@192.168.100.100 '/opt/bin/retrigger-missing-downloads.sh'
```

### Phase 3: Verify

After retriggering, check:

```bash
# Check Sonarr queue
ssh core@192.168.100.100 'curl -s "http://localhost:8989/api/v3/queue" -H "X-Api-Key: $(grep SONARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".totalRecords"'

# Check Radarr queue
ssh core@192.168.100.100 'curl -s "http://localhost:7878/api/v3/queue" -H "X-Api-Key: $(grep RADARR_API_KEY /srv/docker/media-stack/.env | cut -d= -f2)" | jq ".totalRecords"'

# Check qBittorrent for new downloads
ssh core@192.168.100.100 'docker exec gluetun wget -qO- "http://localhost:8080/api/v2/torrents/info?filter=downloading" | jq "length"'
```

## Troubleshooting

### Script Not Found

Deploy from homelab repo:

```bash
scp scripts/vms/retrigger-missing-downloads.sh core@192.168.100.100:/opt/bin/
ssh core@192.168.100.100 'chmod +x /opt/bin/retrigger-missing-downloads.sh'
```

### API Key Errors

Check .env file exists:

```bash
ssh core@192.168.100.100 'cat /srv/docker/media-stack/.env | grep -E "API_KEY"'
```

### No Results

If no stuck items found:

1. All requests may already be downloaded
2. Items may be in download queue (check qBittorrent)
3. Overseerr requests may not be approved yet

## Output Format

Report summary:

```
## Retrigger Results

### Dry Run Summary
- Movies checked: X
- Series checked: X
- Movies to retrigger: X
- Series to retrigger: X

### Items Retriggered
| Type | Title | ID | Status |
|------|-------|-----|--------|
| Movie | Example Movie | 123 | Triggered |
| TV | Example Show | 456 | Triggered |

### Notes
- [Any issues or observations]
```
