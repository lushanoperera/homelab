# LXC 105 (Plex) Dist-Upgrade: Ubuntu 22.04 → 24.04 → 26.04

**Completed**: 2026-04-08
**Duration**: ~45 minutes total (including backups)

## Summary

Sequential LTS upgrade of the only Ubuntu LXC in the homelab. Preserved GPU Physical Function passthrough (iHD driver), NFS media mount, and Plex configuration through both upgrades.

## Upgrade Path

```
Ubuntu 22.04.5 LTS (Jammy) → 24.04 LTS (Noble) → 26.04 LTS (Resolute Raccoon)
```

## What Survived Unchanged

- GPU PF passthrough: card0 + renderD128 with iHD VA-API driver (H264/HEVC/VP9/AV1)
- GIDs: video=44, render=104 (no drift on either upgrade)
- NFS mount: /mnt/media (host-side bindmount, unaffected by in-container upgrade)
- Plex 1.43.0: service, API, and apt repo all working
- LXC config: identical pre/post (verified with diff)

## Key Findings

### do-release-upgrade Quirks

- **24.04 → 26.04 requires `-d` flag**: Standard `do-release-upgrade` says "no development version of an LTS available" even though `--check-dist-upgrade-only` finds 26.04. Using `-d` works.
- **Third-party repos disabled**: `do-release-upgrade` adds `Enabled: no` to DEB822 `.sources` files. Must remove that line to re-enable.

### Apt Format Migration

- 22.04 uses traditional `.list` format: `deb [signed-by=...] https://...`
- 24.04+ uses DEB822 `.sources` format with `Types:`, `URIs:`, `Suites:`, etc.
- Plex signing key location: `/usr/share/keyrings/PlexSign.asc` (not `.gpg`)

### GPU Packages

- `intel-gpu-tools` renamed to `igt-gpu-tools` on 26.04 (transitional package keeps both)
- Core GPU packages (`intel-media-va-driver`, `intel-opencl-icd`, `mesa-va-drivers`, `vainfo`) available on all three releases

### Bash Arithmetic Gotcha

- `((VAR++))` with `set -e` returns exit code 1 when VAR=0 (0 is falsy in bash arithmetic)
- Fix: use `VAR=$((VAR + 1))` instead

## PBS Backup Points

| Snapshot | Notes |
|----------|-------|
| 2026-04-08T06:19:31Z | Pre-upgrade (22.04) |
| 2026-04-08T06:29:42Z | Post-24.04 verified |
| 2026-04-08T07:03:09Z | Post-26.04 verified |

## Scripts

Migration scripts at `scripts/migrations/lxc-105-dist-upgrade/`:
- `upgrade.sh` — 6-phase orchestrator (runs on winston as root)
- `verify.sh` — 15-check verification (OS, GPU, GIDs, NFS, Plex)

## Rollback

Restore from any PBS snapshot:
```bash
pct restore 105 pbs-backupnas:backup/ct/105/<timestamp> --storage vmpool --force
```
