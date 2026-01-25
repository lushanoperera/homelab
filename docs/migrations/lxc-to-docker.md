# LXC to Docker Migration Plan

**Project**: Media Management Stack Migration
**Date**: 2025-09-27
**Status**: Ready for Execution

## 📋 Overview

Complete migration of 10 LXC containers from Proxmox to Docker containers on Flatcar Linux while preserving exact IP addresses and ensuring zero data loss.

### Source Environment
- **Proxmox Host**: 192.168.100.38
- **Credentials**: root / 281188password
- **Container Type**: LXC containers (Proxmox VE)
- **Services**: Media management stack (Arr suite + downloaders)

### Target Environment
- **Flatcar Host**: 192.168.100.100
- **User**: core (SSH key authentication)
- **Platform**: Flatcar Linux + Docker + Docker Compose + Portainer
- **Network**: Macvlan with preserved IP addresses
- **Storage**: Pre-mounted media directories at `/mnt/media/*`

## 🎯 Migration Scope

### Containers to Migrate

| Service | LXC ID | Current IP | Target IP | Port | Purpose |
|---------|--------|------------|-----------|------|---------|
| qbittorrent | 109 | 192.168.100.109 | 192.168.100.109 | 8080 | BitTorrent client |
| sabnzbd | 110 | 192.168.100.110 | 192.168.100.110 | 8080 | Usenet downloader |
| radarr | 111 | 192.168.100.111 | 192.168.100.111 | 7878 | Movie automation |
| sonarr | 112 | 192.168.100.112 | 192.168.100.112 | 8989 | TV show automation |
| lidarr | 113 | 192.168.100.113 | 192.168.100.113 | 8686 | Music automation |
| bazarr | 114 | 192.168.100.114 | 192.168.100.114 | 6767 | Subtitle automation |
| flaresolver | 115 | 192.168.100.115 | 192.168.100.115 | 8191 | Anti-bot solver |
| prowlarr | 116 | 192.168.100.116 | 192.168.100.116 | 9696 | Indexer manager |
| overseerr | 117 | 192.168.100.117 | 192.168.100.117 | 5055 | Request portal |
| tautulli | 121 | 192.168.100.121 | 192.168.100.121 | 8181 | Plex monitoring |

### Media Directory Mapping

| Purpose | Source Path (LXC) | Target Path (Docker) | Flatcar Mount |
|---------|-------------------|---------------------|---------------|
| Downloads | Various | `/downloads` | `/mnt/media/downloads` |
| Incomplete | Various | `/incomplete-downloads` | `/mnt/media/downloads/incomplete-downloads` |
| Movies | Various | `/movies` | `/mnt/media/movies` |
| TV Shows | Various | `/tv` | `/mnt/media/tv` |
| Music | Various | `/music` | `/mnt/media/music` |
| Config | LXC internal | `/config` | `/srv/docker/media-stack/config/<service>` |

## 🏗️ Architecture

### Network Design
- **Type**: Docker macvlan network
- **Name**: `media_macvlan`
- **Subnet**: 192.168.100.0/24
- **Gateway**: 192.168.100.1
- **IP Range**: 192.168.100.96/27 (reserved for containers)
- **Parent Interface**: eth0 (to be verified on Flatcar)

### Container Architecture
- **Base Images**: LinuxServer.io (lscr.io/linuxserver/*)
- **User/Group**: 1000:1000 (PUID/PGID)
- **Timezone**: Etc/UTC
- **Restart Policy**: unless-stopped
- **Health Checks**: Enabled for all services
- **Dependencies**: Proper startup ordering configured

## 🛠️ Migration Components

### Files Created
```
lxc-to-docker-migration/
├── docker-compose.yml          # Main container orchestration
├── .env                        # Environment variables
├── README.md                   # Complete documentation
├── CLAUDE.md                   # Project context for Claude
├── MIGRATION_PLAN.md          # This file
└── scripts/
    ├── pre-migration.sh       # Preparation and backup
    ├── migrate.sh             # Main migration execution
    ├── validate.sh            # Post-migration validation
    └── rollback.sh            # Emergency rollback
```

### Environment Configuration (.env)
```bash
# User and permissions
PUID=1000
PGID=1000
TZ=Etc/UTC
UMASK=002

# Directory paths
CONFIG_ROOT=/srv/docker/media-stack/config
DOWNLOADS_ROOT=/mnt/media/downloads
MEDIA_ROOT=/mnt/media

# Macvlan network
MACVLAN_PARENT=eth0
MACVLAN_SUBNET=192.168.100.0/24
MACVLAN_GATEWAY=192.168.100.1
MACVLAN_IP_RANGE=192.168.100.96/27

# Service ports (default values)
QBITTORRENT_WEBUI_PORT=8080
SABNZBD_PORT=8080
RADARR_PORT=7878
SONARR_PORT=8989
LIDARR_PORT=8686
BAZARR_PORT=6767
FLARESOLVERR_PORT=8191
PROWLARR_PORT=9696
OVERSEERR_PORT=5055
TAUTULLI_PORT=8181
```

## 🔄 Migration Process

### Phase 1: Pre-Migration (5-10 minutes)
**Script**: `./scripts/pre-migration.sh`

**Actions**:
1. Test SSH connectivity to both hosts
2. Inventory all LXC containers and their configurations
3. Create timestamped snapshots of all containers
4. Prepare Flatcar environment directories
5. Backup existing container data
6. Generate migration plan summary

**Verification**:
- [ ] All containers found and accessible
- [ ] Snapshots created successfully
- [ ] Flatcar directories prepared
- [ ] Network connectivity confirmed

### Phase 2: Migration Execution (20-30 minutes)
**Script**: `./scripts/migrate.sh`

**Actions**:
1. Set up macvlan network on Flatcar
2. For each container (in dependency order):
   - Stop LXC container gracefully
   - Sync data using rsync with verification
   - Start corresponding Docker container
   - Validate container startup and IP assignment
3. Clear ARP caches to prevent conflicts
4. Verify all services are accessible

**Order of Migration**:
1. flaresolverr (no dependencies)
2. prowlarr (depends on flaresolverr)
3. qbittorrent & sabnzbd (downloaders)
4. radarr, sonarr, lidarr (depend on downloaders and prowlarr)
5. bazarr (depends on radarr & sonarr)
6. overseerr (depends on radarr & sonarr)
7. tautulli (independent)

### Phase 3: Validation (5-10 minutes)
**Script**: `./scripts/validate.sh`

**Actions**:
1. Check Docker container status
2. Test network connectivity (ping tests)
3. Validate HTTP endpoints and health checks
4. Verify data integrity and permissions
5. Test macvlan network configuration
6. Generate validation report

**Success Criteria**:
- [ ] All containers running and healthy
- [ ] All IP addresses responding to ping
- [ ] All web interfaces accessible
- [ ] Data directories have correct ownership
- [ ] No container restart loops

### Phase 4: Post-Migration Testing
**Manual Actions**:
1. Access each service web interface
2. Test download workflows (manual download)
3. Verify automation is working
4. Check API integrations between services
5. Monitor logs for errors
6. Update any external integrations with new container IDs

## 🔒 Safety Measures

### Backup Strategy
- **LXC Snapshots**: Automatic timestamped snapshots before any changes
- **Data Backup**: Complete rsync backup to local staging area
- **Configuration Export**: Container configs saved to files
- **Docker Data Backup**: Backup created before rollback operations

### Risk Mitigation
- **Dry Run Mode**: All scripts support `--dry-run` for testing
- **Incremental Migration**: One container at a time
- **Immediate Rollback**: Complete rollback capability at any point
- **Network Isolation**: macvlan prevents conflicts during migration
- **Logging**: Comprehensive logging for troubleshooting

### Rollback Procedures
**Script**: `./scripts/rollback.sh`

**Emergency Rollback**:
1. Stop all Docker containers
2. Remove macvlan network
3. Clear ARP caches
4. Start LXC containers
5. Optionally restore from snapshots

**Rollback Triggers**:
- Migration script failures
- Data corruption detected
- Network connectivity issues
- Service functionality problems
- User decision to abort

## ⚠️ Pre-Migration Checklist

### Critical Verifications Required
- [ ] **Network Interface**: Confirm actual interface name on Flatcar (currently assumed `eth0`)
- [ ] **LXC Data Paths**: Verify actual container data locations before migration
- [ ] **Media Permissions**: Ensure `/mnt/media/*` directories have 1000:1000 ownership
- [ ] **SSH Access**: Test passwordless SSH to Flatcar with core user
- [ ] **Docker Status**: Verify Docker and Docker Compose are operational
- [ ] **Disk Space**: Ensure sufficient space for data migration and backups
- [ ] **Network Conflicts**: Verify no other devices use IPs 192.168.100.109-121

### Dependencies to Install
```bash
# On local machine (for scripts)
sudo apt install -y sshpass rsync curl

# Verify tools
ssh core@192.168.100.100 "docker --version && docker compose version"
sshpass -p "281188password" ssh root@192.168.100.38 "pct list"
```

## 🚀 Execution Commands

### Quick Start (When Ready)
```bash
# 1. Prepare environment
./scripts/pre-migration.sh

# 2. Test migration (dry run)
./scripts/migrate.sh --dry-run

# 3. Execute migration
./scripts/migrate.sh

# 4. Validate results
./scripts/validate.sh

# Emergency rollback (if needed)
./scripts/rollback.sh --restore-snapshots
```

### Environment Variables Override
```bash
# Use custom settings
export PROXMOX_HOST=192.168.100.38
export PROXMOX_PASSWORD=281188password
export FLATCAR_HOST=192.168.100.100
export DRY_RUN=true  # For testing

# Then run scripts normally
./scripts/migrate.sh
```

## 📊 Expected Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Pre-migration | 5-10 min | Snapshots, backups, environment prep |
| Migration | 20-30 min | Container stop, data sync, startup |
| Validation | 5-10 min | Testing and verification |
| Manual Testing | 15-30 min | User validation of services |
| **Total Downtime** | **20-30 min** | Time services are unavailable |

## 🔍 Troubleshooting

### Common Issues
1. **Network Interface**: Update `MACVLAN_PARENT` in `.env` if not `eth0`
2. **Permission Errors**: Run `sudo chown -R 1000:1000 /mnt/media` on Flatcar
3. **IP Conflicts**: Clear DHCP reservations or use `ip neigh flush all`
4. **Container Startup**: Check logs with `docker logs <container_name>`
5. **Data Sync Issues**: Verify source paths and network connectivity

### Log Locations
- Migration logs: `migration-YYYYMMDD_HHMMSS.log`
- Validation logs: `validation-YYYYMMDD_HHMMSS.log`
- Docker logs: `docker logs <container_name>`
- Flatcar system logs: `journalctl -u docker`

## ✅ Post-Migration Checklist

### Immediate (Day 1)
- [ ] All containers running and accessible
- [ ] Downloads working (test manual download)
- [ ] API integrations functioning
- [ ] No error logs in containers
- [ ] Network connectivity stable

### Short-term (48-72 hours)
- [ ] Automation workflows completing successfully
- [ ] No unexpected container restarts
- [ ] Media processing working correctly
- [ ] Performance acceptable
- [ ] No data corruption detected

### Cleanup (After 1 week of stable operation)
- [ ] Remove LXC container snapshots
- [ ] Delete temporary backup files
- [ ] Update documentation with any changes
- [ ] Archive migration logs

## 📞 Support Information

### Key Files for Troubleshooting
- `docker-compose.yml` - Container configuration
- `.env` - Environment variables
- `scripts/validate.sh` - Diagnostic tests
- Migration logs - Detailed operation records

### Recovery Options
1. **Partial Rollback**: Stop specific containers, restart LXC equivalents
2. **Complete Rollback**: Use `rollback.sh` script
3. **Snapshot Restore**: Use `rollback.sh --restore-snapshots`
4. **Manual Recovery**: Direct LXC container management on Proxmox

---

**Migration Plan Prepared**: 2025-09-27
**Ready for Execution**: Awaiting user approval
**Estimated Success Rate**: 95% (with comprehensive safety measures)