---
name: homelab-storage-and-backup
description: >-
  The homelab's storage + backup DESIGN and WHY layer — reginald ZFS on a
  7-drive RAIDZ2 Zimaboard, NFS over the storage LAN, PBS on QNAP, restic to
  S3, and the MinIO→Garage→RustFS migration saga. Read this BEFORE touching a
  disk, dataset, export, backup job, or S3 endpoint on the homelab. Triggers —
  "ZFS pool SUSPENDED", "zpool scrub before disk swap", "hot-swap a drive",
  "replace a failing SSD / sdg errors", "ARC too big / RAM pressure on
  reginald", "tune ZFS on the Zimaboard", "NFS stale file handle",
  "mnt-media.mount", "media not showing in Plex/Sonarr", "why is NFS on
  192.168.200.x", "PBS read timeout / activate_storage", "vzdump before kernel
  upgrade", "recreate vzdump jobs after reinstall", "5-month backup gap",
  "restic timer / restic-env", "restic repository", "MinIO vs Garage vs
  RustFS", "resume the RustFS migration", "storage/rustfs .env blank", "S3
  backend for backups", "Samba LXC 123", "TimeMachine share". Use the sibling
  skills backup-status (verify a backup ran) and nfs-check (verify a mount) to
  RUN checks; use THIS skill to understand the design and decide a change.
tools: Bash, Read
---

# Homelab Storage & Backup — Design & Decisions

This is the **design + rationale ("why it is built this way")** layer for storage
and backup on the homelab at `/Users/disconnesso/Documents/Projects/homelab`.
It exists because the person who built this retired; a junior engineer or a
Sonnet-class model must be able to operate it from this file alone.

## When to use this — and when NOT to

| You want to…                                              | Use                                                        |
| --------------------------------------------------------- | ---------------------------------------------------------- |
| Understand *why* ZFS/NFS/PBS/S3 are shaped this way, or decide a storage change | **This skill**                                             |
| **Verify** a backup actually ran (PBS/restic/S3 freshness) | Sibling skill **`backup-status`** (the verification verb)  |
| **Verify** an NFS mount is healthy across the 3 hosts     | Sibling skill **`nfs-check`**                              |
| Look up a `.env` / `restic-env` key name or secret location | Sibling skill **`homelab-config-and-flags`**              |
| Know the evidence bar for calling a backup/restore "done" | Sibling skill **`homelab-validation-and-qa`**             |
| Generic `zpool` / PBS / WireGuard / Docker symptom→fix (not homelab-specific) | Global skill **`infra-runbook`** — do not duplicate it here |
| "Has this storage failure happened before?" narrative     | Global skill **`nwdesigns-failure-archaeology`** (holds the ZFS-SUSPENDED and i915-VF entries) |
| The normative one-line rules (ZFS scrub, PBS, rslave)     | `~/.claude/rules/infrastructure.md` + repo `.claude/rules/infra-lessons.md` |

**Do NOT** put generic ZFS/PBS command syntax here — that lives in `infra-runbook`
and the rules files. This skill holds only the homelab-specific topology, the
hardware constraints that make generic defaults wrong, and the migration state.

Live-state claims are marked **UNVERIFIED** with the read-only command to confirm
them. The repo is READ-ONLY ground truth; the running lab may have drifted.

---

## 0. Storage & backup topology (the delta facts)

Jargon, defined once:
- **reginald** — the secondary Proxmox host (Zimaboard 832, Celeron N3450,
  **8 GB soldered LPDDR4**), the ZFS + NFS file server. `192.168.100.4` (Infra)
  / `192.168.200.4` (Storage LAN).
- **winston** — primary Proxmox host (Minisforum MS-01, 32 GB). NFS *client*.
- **Flatcar VM 100** — `core@192.168.100.100`, the Docker host. NFS *client*.
- **Storage LAN** — `192.168.200.0/24`, a dedicated NIC segment with **no VLAN on
  the UniFi gateway**. All NFS + backup bulk traffic rides here to keep it off the
  Infra LAN (`192.168.100.0/24`).
- **PBS** — Proxmox Backup Server, a VM running *on the QNAP NAS* at
  `192.168.100.187` (web UI `:8007`). Backs up whole VMs/LXCs via `vzdump`.
- **QNAP TS-251+** — `192.168.100.254` / `.200.254`. Hosts PBS, the S3 service, and
  is the DNS primary.
- **restic** — file-level dedup backup tool; used for *application data*
  (Nextcloud, Immich, Technitium config) to an S3 bucket. Distinct from PBS.

```
VM/LXC images ──vzdump──▶ PBS (QNAP .187) ──push over WireGuard──▶ nwlab PBS (offsite)
App data (NC/Immich/DNS) ──restic──▶ S3 on QNAP (MinIO .200.210 → RustFS .200.212)
Media/app files ──NFSv4.2 (storage LAN)──▶ reginald ZFS rpool/shared ──▶ winston, Flatcar
```

| Component | Where | Notes |
| --- | --- | --- |
| ZFS pool `rpool` | reginald | 7× SATA SSD **RAIDZ2** (2-disk redundancy) on JMB58x HBA |
| NFS server | reginald `.200.4` | NFSv4.2, storage LAN only |
| PBS datastores `pbs-backups`, `nwlab-backup` | PBS VM `.187` | on **local virtio disks** since 2026-04-15 (was NFS) |
| S3 (active) | QNAP MinIO `.200.210:9000` | buckets `restic-nextcloud`, `restic-immich` |
| S3 (migration target) | QNAP RustFS `.200.212:9000` | **not yet cut over** — see §5 |
| Samba/TimeMachine | reginald LXC 123 | see §6 |

---

## 1. ZFS on reginald — the iron rule, then the tuning

### 1.1 THE IRON RULE (memorize this) — physical storage work

reginald's pool is a 7-drive RAIDZ2. Any physical intervention (cable swap, disk
pull/replace, HBA port move) while a **scrub** (ZFS's full-pool integrity read) is
running can knock legs offline simultaneously and put the pool in state
`SUSPENDED` — I/O frozen, "permanent data errors" stamped. This actually happened
(the thinkpad USB-mirror hot-swap incident, 2026-05-15). Full write-up lives in
global **`nwdesigns-failure-archaeology`** ("ZFS pool SUSPENDED"); the one-line law
is in `~/.claude/rules/infrastructure.md`.

The procedure — **never skip a step**:

```bash
# 1. PAUSE the scrub BEFORE touching any cable or disk
ssh root@192.168.100.4 'zpool scrub -p rpool'   # -p = pause, not stop
# 2. ...do the physical work...
# 3. If the pool went SUSPENDED, clear it (brings legs back ONLINE):
ssh root@192.168.100.4 'zpool clear rpool'
# 4. Run a FULL scrub and judge errors ONLY after it completes:
ssh root@192.168.100.4 'zpool scrub rpool'
ssh root@192.168.100.4 'zpool status -x'        # "all pools are healthy" = done
```

Why step 4 matters: the error counter from a SUSPENDED event persists as stale
until the next *complete* scrub. Do not declare a disk dead on the strength of
counters left over from the incident.

**`sdg` gotcha:** the ORICO SSD on the JMB58x HBA has recurring READ/CKSUM errors.
Before RMA-ing the drive, **move it to a different JMB58x port** — the controller
port is the more likely fault than the disk (infra-lessons.md, ZFS section).

### 1.2 Why generic ZFS defaults are wrong here

reginald is RAM- and CPU-starved: 8 GB non-upgradable, weak N3450, storage LAN
capped ~280 MB/s (2.5 GbE USB NIC), no SLOG (a **SLOG** = separate fast disk for
the ZFS Intent Log; there isn't one). Generic ZFS assumes a big-RAM server. The
tuning is codified in `scripts/hosts/reginald/zfs-tune.sh` — **hot-applyable,
reversible, idempotent** (commit `976b78e`, 2026-04-14). Run dry-run first:

```bash
ssh root@192.168.100.4 '/root/zfs-tune.sh'          # dry-run (default)
ssh root@192.168.100.4 '/root/zfs-tune.sh --apply'  # commit + persist via initramfs
```

| Setting | Default → tuned | Why (the delta) |
| --- | --- | --- |
| `zfs_arc_max` (ARC = ZFS RAM read cache) | 4 GB → **2.5 GB** | Default 50%-of-RAM starves the page cache + 16 nfsd threads on an 8 GB box |
| `zfs_arc_min` | 1 GB → 512 MB | Lower floor lets the kernel shrink ARC under pressure |
| `zfs_dirty_data_max` | 2 GB → **512 MB** | Wire peaks ~280 MB/s; a 2 GB write buffer = 7 s flush, wastes scarce RAM |
| `vm.dirty_ratio` / `background` | 60/20 → **20/10** | Kernel dirty buffer was double-buffering on top of ZFS's own |
| `autotrim` | off → **on** | All-SSD RAIDZ2 at ~75% full needs TRIM or the SSD FTL degrades |
| compression on media/library/nextcloud | zstd-3 → **lz4** | Those datasets compress ~1.00–1.05×; zstd-3 is pure CPU waste on N3450 |
| `logbias` on sync-NFS datasets | throughput → **latency** | No SLOG → in-pool ZIL via `latency` beats `throughput` for sync writes |
| `primarycache` on media/{movies,tv,music} | all → **metadata** | Plex streams each file once; caching data blocks evicts hot NC/Immich pages |

Left **untouched on purpose:** `immich/database` (already lz4 + 8K recsize +
logbias=latency), `primarycache=all` on immich/library + nextcloud + vaultwarden,
and the `rpool/swap` zvol (kept as an OOM cushion because zram is only ~1.2 GB —
do not remove it just because `0 B used`).

**Diagnosing "reginald is thrashing / low RAM":** check ARC and swap *before*
concluding, using the reginald-specific facts in the infra-lessons.md ZFS table:
`arc_summary` (ghost lists > c_max means don't shrink further), and
`swapon --show` (zram `swap used > 0` is fine if the `rpool/swap` zd0 shows `0 B`).

**Capacity gotcha:** Sonarr/Radarr/Lidarr *hardlink* from `/media/downloads` into
movies/tv/music, so `du` on downloads overstates real usage. `zfs list` USED on
the parent dataset is the truthful number.

### 1.3 Snapshot retention

`zfs-auto-snapshot` retention was cut on the 8 GB box (history phase 6) to stop
snapshot metadata eating ARC/RAM. Confirm current retention live before assuming:

```bash
ssh root@192.168.100.4 'zfs get -r com.sun:auto-snapshot rpool | grep -v @'   # UNVERIFIED
```

---

## 2. NFS design

**All NFS traffic is on the storage LAN (`192.168.200.0/24`) by design** — never
the Infra LAN. reginald exports NFSv4.2 from `192.168.200.4`. Full export layout is
in `.claude/rules/network-services.md` ("NFS Media Storage"); the delta worth
knowing:

- `rpool/shared` — pseudo-root, `crossmnt`, **`fsid=7`**.
- `rpool/shared/media` — `crossmnt`, so child datasets (downloads, music, tv) are
  traversed automatically.
- `rpool/shared/media/movies` — **`fsid=6`, its own separate export** because it is
  a systemd *bind mount* (`media-movies.mount`), and `crossmnt` does **not** cross
  bind mounts. This is the #1 "movies folder empty on the client but tv works"
  cause — the movies export/mount is a separate thing.
- **`fsid` must stay stable.** Changing an fsid mid-life invalidates every client's
  NFSv4 file handles → mass stale-handle errors. Don't renumber exports casually.

**Mount propagation — `rslave`:** Docker bind mounts of NFS paths on Flatcar must
use **`rslave`** propagation, or new NFS sub-mounts stay invisible inside the
container (rprivate hides them). This is the normative row in
`~/.claude/rules/infrastructure.md` ("Docker rprivate hides NFS").

**NFSv4 stale-session lesson & remediation:** after storage maintenance or a
reginald reboot, clients can hold a stale NFSv4 session → "Stale file handle". The
homelab-specific fix order (Flatcar client is a **systemd mount unit**, not fstab):

```bash
# 1. Simplest: restart the Flatcar mount unit
ssh core@192.168.100.100 'sudo systemctl restart mnt-media.mount'
# 2. If still stale, remount the middle client (winston) then reload exports on reginald
ssh root@192.168.100.38 'umount /mnt/nfs_media && mount /mnt/nfs_media'
ssh root@192.168.100.4  'exportfs -ra'
```

To actually *walk* the 3-host mount chain and prove it healthy, use sibling skill
**`nfs-check`** — do not re-derive its checks here.

---

## 3. PBS (Proxmox Backup Server)

PBS is a VM **on the QNAP** at `192.168.100.187`. It stores whole-guest `vzdump`
backups. Two design facts that bit hard in the past:

### 3.1 Datastores are on LOCAL virtio disks now (not NFS)

Until 2026-04-15, PBS datastores lived on NFS back to the *same* QNAP box hosting
the VM. Every datastore-listing API call walked the `.chunks/` tree over NFS,
routinely blowing PVE's **10-second `activate_storage` budget** → daily vzdump
jobs failed with `error fetching datastores - 500 read timeout`. Fix: cut over to
two **local virtio-scsi disks** (`vdb`, `vdc`) as fresh empty datastores, keeping
the old NFS ones as `*-legacy` (read-only, for historical restores). Full write-up:
`docs/migrations/pbs-nfs-to-local.md`. Key lessons carried forward:

- **Keep the `datastore:` NAME stable** (`pbs-backups`, `nwlab-backup`) across any
  migration — clients (winston/reginald PVE storage `pbs-backupnas`) reference
  datastores by *name*, not path, so cutover needed zero client reconfig.
- **Do not plan a large NFS-based rsync of a PBS chunk store.** Chunk stores are
  metadata-bound (~2M files of 1–4 MB); over NFS to a shared spindle you get
  ~1 MB/s. PBS tolerates *starting over* far better than a half-copied `.chunks/`
  tree (content-addressed → partial copy is worse than nothing).
- **Follow-up still open (UNVERIFIED):** the `*-legacy` datastores were slated for
  removal ~2026-07-15 and QNAP NFS exports dropped (reclaim ~222 GB). Confirm
  before assuming they're gone: `ssh root@192.168.100.187 'proxmox-backup-manager datastore list'`.

`pbs-backupnas` can `read timeout` in `pvestatd` when the QNAP is under load, but
vzdump transfers still complete — check `pvesm status` first, don't panic.

### 3.2 vzdump jobs live in pmxcfs → the repo is the DR copy

Backup job definitions live in **pmxcfs** (`/etc/pve/jobs.cfg`, the Proxmox cluster
filesystem). **pmxcfs is NOT preserved on a bare-metal reinstall.** This caused the
**5-month silent backup gap (Oct 2025 – Mar 2026)**: winston was rebuilt, jobs.cfg
was lost, no scheduled backup ran, and nobody noticed until 2026-03-01. The repo is
the disaster-recovery source of truth for these definitions.

After ANY Proxmox host rebuild, verify the jobs exist:

```bash
ssh root@192.168.100.38 'cat /etc/pve/jobs.cfg'
ssh root@192.168.100.38 'pvesh get /cluster/backup'   # expect:
#   winston Job A: VMIDs 103,104,105,106 @ 04:00
#   winston Job B: VMIDs 100,101,102     @ 05:00
#   reginald:      VMID 120              @ 08:00
```

### 3.3 Pre-backup a guest before a kernel upgrade

Before upgrading a Proxmox host kernel (the kernel/SR-IOV runbook is
`docs/migrations/pve-9.2-kernel-7-upgrade.md`), snapshot-backup the guests first:

```bash
vzdump <vmid> --storage pbs-backupnas --mode snapshot --remove 0
```

(`--mode snapshot` = no downtime; `--remove 0` = keep, don't rotate.) This is the
exact form the firewall winston-verification and the kernel runbook both use.
Generic vzdump/PBS command syntax → `infra-runbook`; the DKMS-header trap that
makes kernel upgrades dangerous → `~/.claude/rules/infra-lessons.md` (Proxmox
Kernel Upgrades) and global `nwdesigns-failure-archaeology` ("i915 VFs gone").

---

## 4. restic — application-data backups

restic backs up *application data* to S3, on **systemd timers**, separate from PBS.

- **`restic-env` files live per node at `/etc/restic/<app>.env`, `chmod 0600`,
  deployed manually, NEVER committed.** The committed `apps/*/restic-env.example`
  files are templates only. Key names (`AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, …) are owned by
  sibling skill **`homelab-config-and-flags`** — look them up there, don't restate.
- Repos: `restic-nextcloud` and `restic-immich` on the S3 endpoint (§5), daily
  ~00:00, ~16 MB pack files.
- **Technitium DNS config backup (added phase 7):** `scripts/backup/technitium-config-backup.sh`
  → restic, deployed to `/opt/bin/` on Flatcar + reginald (and a QNAP Container
  Station scheduled task). Env `/etc/restic/technitium.env` (template
  `apps/technitium/restic-env.example`). Per-node snapshots tagged
  `--host technitium-<node>`. Retention **keep-daily 7 / keep-weekly 4 /
  keep-monthly 6**. Systemd unit `technitium-backup.timer` fires **03:30 daily**
  (`Persistent=true`, 600 s jitter). NOTE: the unit's `Description` still says
  "restic → Garage" — that is stale text (Garage was never deployed; see §5), the
  actual target is the S3 endpoint in the env file.

To **verify** restic timers/snapshots/repo health, use sibling **`backup-status`**
(it walks the timers on the LXCs and `restic snapshots` / `restic check`). This
skill only tells you how the backups are *shaped*.

---

## 5. The S3 story — MinIO → Garage (DEAD) → RustFS (in flight)

This is the most confusing area for a newcomer because three S3 backends appear in
the repo. Here is the definitive state as of 2026-07-04:

| Backend | Dir | Status | Endpoint |
| --- | --- | --- | --- |
| **MinIO** | `storage/minio/` | **LIVE / active** — holds real backups | `192.168.200.210:9000` |
| **Garage** | `storage/garage/` | **DEPRECATED 2026-04-10, NEVER DEPLOYED** — reference only | (`.200.211`, unused) |
| **RustFS** | `storage/rustfs/` | **migration target, NOT cut over** | `192.168.200.212:9000` |

**Story:** MinIO is the incumbent S3 on the QNAP. A migration to **Garage** was
planned (40× lower idle RAM) but **abandoned without ever deploying** — superseded
2026-04-10 by **RustFS** (Rust, Apache-2.0, active upstream, MinIO drop-in). The
RustFS choice **accepts alpha-stage risk**: v1.0.0-alpha, run **single-node only**
(distributed/lifecycle/KMS are "Under Testing" upstream), ~0.5× MinIO throughput on
>20 MB objects (fine — restic packs are ~16 MB). Active runbook:
`docs/migrations/minio-to-rustfs.md`. The Garage files (`storage/garage/`,
`scripts/migrations/minio-to-garage/DEPRECATED.md`, `docs/migrations/minio-to-garage.md`)
are retained for comparison — **do not execute them.**

### 5.1 TWO BLOCKERS before you can resume the RustFS migration

1. **The migration is UNCOMMITTED** — a bare-metal reinstall today would lose it.
   Untracked in git (`git status`): `storage/rustfs/`,
   `scripts/migrations/minio-to-rustfs/`, `docs/migrations/minio-to-rustfs.md`,
   and `scripts/migrations/minio-to-garage/DEPRECATED.md`. This is the exact DR
   trap that caused the §3.2 backup gap. **Commit these (stage explicit paths —
   never `git add -A`, the tree runs chronically dirty) before doing migration
   work.**
2. **`storage/rustfs/.env` is BLANKED** — all values were emptied during the
   2026-05-20 move off varlock/rbw, and the vault folder `Homelab/rustfs` was
   found empty. RustFS cannot start until these are repopulated as a plain
   `chmod 0600` `.env`. Key names are in `homelab-config-and-flags`; the secrets
   policy is `~/.claude/rules/secrets-management.md` (plain `.env`, never varlock).

### 5.2 STALE-DOC warning (do not follow blindly)

`storage/rustfs/README.md` and `docs/migrations/minio-to-rustfs.md` were written
*before* the 2026-05-20 secrets migration and still say to launch via
`varlock run -- docker compose up -d` and store keys in Vaultwarden via `rbw`.
**That is obsolete.** Per AGENTS.md and `secrets-management.md`, the homelab uses
plain gitignored `.env` sourced with `set -a; source .env; set +a` — there is no
live varlock/vault dependency. When you resume, translate those runbook steps to
plain `.env`. Also stale: `storage/minio/README.md` still says "being migrated to
Garage" (should read RustFS).

### 5.3 The safety design (why cutover is cautious)

The runbook keeps MinIO running **read-only in parallel for one full 6-month restic
retention cycle** after cutover, with `restic check --read-data-subset` weekly then
monthly, and a mandatory **cold-restore drill** gate before trusting RustFS.
Rollback at any time = flip the `restic-env` endpoint back to `.200.210`; no data
migration needed because MinIO retained everything. Do **not** shortcut the
parallel window — alpha backend, trust nothing.

---

## 6. Samba / TimeMachine LXC

**Samba file server = reginald LXC 123** (confirmed in repo:
`hosts/reginald/lxc-123-samba.md`; AGENTS.md "LXC (reginald): 120 Technitium DNS,
123 Samba"). Debian 13 (Trixie), Samba 4.22, Cockpit (core only — the 45Drives
file-sharing plugin was dropped, no Trixie packages). Shares in `smb.conf`. When the
host firewall eventually goes live, LXC 123 needs the Samba ports opened
(`hosts/firewall.md` §Samba) — that whole rollout is DEFERRED and out of scope here.

⚠ **CONTRADICTION to flag, not resolve:** project memory (incident, ~2026-02)
refers to a **"TimeMachine/Samba LXC 102"** given 256 MB swap to avoid OOM. But the
repo's authoritative AGENTS.md lists **VM 102 = homeassistant**, and the Samba
service is **LXC 123**. These disagree. Treat the "LXC 102 = TimeMachine" +
zero-swap detail as **UNVERIFIED (memory, ~2026-02)** — it may be stale, a
renumbering, or a TimeMachine share that lives inside the Samba LXC 123. Before
acting on anything about a TimeMachine/AFP share or "LXC 102", confirm live:

```bash
ssh root@192.168.100.4  'pct list'                          # what LXCs exist on reginald  (UNVERIFIED)
ssh root@192.168.100.38 'qm list | grep 102; pct list'      # what 102 actually is         (UNVERIFIED)
```

Surface the discrepancy to a human rather than guessing which source wins.

---

## Known contradictions & UNVERIFIED facts (2026-07-04)

| Claim | Conflict / status | Resolve with |
| --- | --- | --- |
| reginald PVE version | AGENTS.md says 9.1.5; `hosts/reginald/README.md` says 9.1.6; memory says 9.2.2 / kernel 7.0.2 | `ssh root@192.168.100.4 'pveversion; uname -r'` |
| PBS `*-legacy` datastores removed | Slated ~2026-07-15; unverified | `ssh root@192.168.100.187 'proxmox-backup-manager datastore list'` |
| RustFS migration state | Runbook exists, NOT executed; env blank; uncommitted | `git status --short storage/rustfs scripts/migrations` |
| "TimeMachine LXC 102" | Contradicts AGENTS.md (VM 102 = homeassistant; Samba = LXC 123) | `pct list` on reginald + `qm list` on winston |
| zfs-auto-snapshot retention | Cut on reginald, current values unverified | `zfs get -r com.sun:auto-snapshot rpool` |
| Stale docs reference varlock/Garage | rustfs README + minio-to-rustfs.md (varlock/rbw); minio README + technitium-backup.service (Garage) | Treat as obsolete; secrets-management.md + §5 are authoritative |

---

## Provenance and maintenance

Re-verify each volatile claim group READ-ONLY (repo is ground truth; live lab may drift):

```bash
# ZFS tuning rationale + iron rule
cd /Users/disconnesso/Documents/Projects/homelab && git show 976b78e --stat && sed -n '/## ZFS Tuning/,$p' .claude/rules/infra-lessons.md

# NFS export/fsid design + mount remediation
sed -n '/## NFS Media Storage/,/## nwlab/p' .claude/rules/network-services.md

# PBS local-disk cutover + pmxcfs DR + backup gap
cat docs/migrations/pbs-nfs-to-local.md; sed -n '/## PBS/,/## Proxmox Kernel/p' .claude/rules/infra-lessons.md

# restic (incl. Technitium backup) — script, unit, retention
cat scripts/backup/technitium-config-backup.sh systemd/technitium-backup.timer

# S3 migration state + TWO blockers (untracked + blank env)
git status --short | grep -E 'rustfs|migrations'; cat scripts/migrations/minio-to-garage/DEPRECATED.md; head -20 storage/garage/README.md

# Samba LXC 123 + the LXC-102 contradiction
grep -n 'LXC (reginald)\|VM 102\|homeassistant' AGENTS.md; head -5 hosts/reginald/lxc-123-samba.md

# Live-state checks referenced above (run against the lab, not the repo)
ssh root@192.168.100.4 'pveversion; zpool status -x; exportfs -v'
ssh root@192.168.100.187 'proxmox-backup-manager datastore list'
```

Owner: nwdesigns agency. If you change storage or backup design, update this file,
AGENTS.md, and the relevant `.claude/rules/` file in the same commit — pmxcfs and
blank envs have burned this lab before.
