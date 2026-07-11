---
name: homelab-failure-archaeology
description: >-
  The homelab settled-battles chronicle — check here FIRST when a symptom feels
  familiar or someone asks "has this broken before?", "is this a known issue?",
  "why is it done this way?", "did we already try X?", "what did we abandon?",
  "past incident", "post-mortem", "history of winston/reginald/flatcar". Covers
  homelab-SPECIFIC incidents (2026-02 → 2026-06): SR-IOV VFs gone after a kernel
  upgrade, DKMS silently no-op, kernel 7.0 BUILD_EXCLUSIVE blocker, reginald ESP
  full mid kernel install + the "reginald is legacy-GRUB not systemd-boot"
  correction, ZFS pool SUSPENDED during a hot-swap mid-scrub, Nextcloud
  "permission denied for schema public" (oc_nextcloud), the 5-month PBS vzdump
  gap, LXC 102 zero-swap OOM, gluetun NAT-PMP dead port-forward, Profilarr V2
  deploy issues. Also indexes the 10 .claude/rules/*-lessons.md files (the raw
  archaeology), the reverted/abandoned decisions with WHY (Prometheus+Grafana
  ejected to nwlab, Profilarr homepage widget dropped, resolv.conf bind dropped,
  SDN WireGuard deferred, NordVPN→ProtonVPN, Pi-hole→Technitium, Kido→Vercel+Neon,
  MinIO→Garage→RustFS), and the stale git branches. Keywords: known issue,
  regression, we tried this, why not X, reverted, deprecated, dead branch,
  kernel upgrade broke, VFs disappeared, pool suspended, backup gap.
---

# Homelab Failure Archaeology

The **chronicle of settled battles** for `Documents/Projects/homelab` (Proxmox
hosts winston + reginald, Flatcar VM 100 Docker stacks, Technitium DNS, PBS,
S3, plus the remote **nwlab** thinkpad over WireGuard). Read this to answer
*"has this happened before / why is it done this way / what did we abandon and
why"* — **not** to fix a live outage.

**Jargon, defined once:**
- **SR-IOV** — hardware feature that splits one Intel iGPU into virtual
  functions (**VFs**) so VMs/LXCs each get a slice for transcoding.
- **DKMS** — Dynamic Kernel Module Support; rebuilds out-of-tree drivers (here
  `i915-sriov-dkms`) whenever the kernel changes. **Silently no-ops if the
  matching kernel headers are absent** — the root of most SR-IOV injuries.
- **ESP** — EFI System Partition; the small boot partition where kernels land.
- **pmxcfs** — Proxmox cluster filesystem at `/etc/pve/`; **NOT captured by
  vzdump/PBS**, lost on a bare-metal reinstall.
- **NAT-PMP** — the port-mapping protocol gluetun uses to ask ProtonVPN for a
  forwarded port for qBittorrent.

## When NOT to use this skill — route elsewhere

| You actually want… | Go to |
|---|---|
| To FIX something broken right now (live triage) | sibling **homelab-debugging-playbook** + runbook skills (`media-health`, `vpn-status`, `backup-status`, `nfs-check`, `gpu-fix`) |
| The step-by-step kernel / GPU / SR-IOV upgrade runbook | sibling **homelab-kernel-gpu-sriov** + `gpu-fix` skill + `docs/migrations/pve-9.2-kernel-7-upgrade.md` |
| Generic Proxmox / ZFS / PBS / WireGuard / Docker symptom→fix (any project) | global **infra-runbook** |
| Debugging *process* discipline (reproduce → root cause → test) | global **systematic-debugging** |
| Whether a symptom hit a **client site** (WordPress/Cloudways/Aruba) or the portfolio | global **nwdesigns-failure-archaeology** (also holds this repo's ZFS-SUSPENDED and i915-VF entries — see Cross-references) |
| The **normative rule** itself (the current do/don't) | the owning `.claude/rules/*.md` file — indexed below |

This skill holds only homelab-specific *history*. It never restates a gotcha
that already lives in a rules table; it **indexes** those and adds the
memory-only incidents + cross-incident synthesis.

---

## 1. Index of the raw archaeology — the 10 `.claude/rules/*.md` files

These auto-load when you touch matching paths. They ARE the symptom→fix tables;
this skill points at them, never copies them. (Verify: `ls .claude/rules/`.)

| Rules file | Battles it owns (one-line hooks) |
|---|---|
| `infra-lessons.md` | Proxmox networking (VLAN 0-rx, mDNS/multicast); host firewall (both-enables kill switch, dead-man cron, conntrack survives reload); **PBS 5-month vzdump gap Oct 2025–Mar 2026** (§PBS/Vzdump — the pmxcfs-DR archetype); **kernel-upgrade DKMS/headers/ESP/legacy-GRUB table**; GPU SR-IOV sysext + unprivileged-LXC 3-layer fix; **reginald ZFS tuning for the 8 GB Zimaboard** (ARC 2.5 GB, lz4-not-zstd, primarycache=metadata, ORICO-on-JMB58x flakiness) |
| `gpu-sriov-lessons.md` | Build/deploy of the i915 sysext (kvmgt linker, `insmod` not `modprobe`, stock-i915-after-update); GPU consumer containers (Immich/Nextcloud); **the 7-step "GPU broken after kernel update" recovery checklist** |
| `flatcar-lessons.md` | `eth0` not `ens18`; Ignition-applies-once; `/opt/bin/docker-compose`; **gluetun recreate orphans deps** (always `up -d` whole stack); **gluetun `restart` stuns deps** (2026-05-20, 60s dead); **gluetun NAT-PMP dies silent** (2026-05-19, 41h before noticed); Redis maxmemory < mem_limit |
| `deployment-lessons.md` | Compose→Flatcar (namespace orphaning, `restart` vs `up -d`, validate YAML first); Nextcloud config-key names (`overwritehost` breaks multi-domain); watchtower scope |
| `media-api-lessons.md` | Seerr XSRF cookie dance; qBit via `docker exec gluetun`; Radarr/Sonarr `deleteFiles` NFS chain; **media-removal order**; **Profilarr V2** (`:2.0.6` bare semver, 512m min, sibling-DNS bind drop, arr-sync UI-only); Plex 1.40 legacy-agent removal |
| `dns-lessons.md` | Technitium cluster-join (domain URL not IP); silent port-53 fail-soft; **catalog member zones invisible cross-VLAN** (2026-05-23); double-suffix FQDN bug; exporter duplicate-HELP scrape rejection |
| `networking-lessons.md` | UniFi CSRF-inside-JWT; radio_table vs radio_table_stats; DFS CAC; **Italy country-code 380 blocks UNII-3**; mesh must share 5 GHz with parent; local-admin-not-SSO for API |
| `nfs-zfs-lessons.md` | `crossmnt` for child datasets; `hard` not `soft`; `actimeo=60`; bind-mount needs own `fsid`; `fsid=0` reserved; NFSv4 stale sessions poison new mounts |
| `network-services.md` | Service→backend map; reginald NFSv4.2 export layout (movies bind-mount own fsid); nwlab WG tunnel path; backup flow (VM→PBS→nwlab push; LXC→NFS→Restic→S3) |
| `ops-reference.md` | SSH targets; Flatcar/app/proxy quick commands; Ignition recompile; Caddy `reload` vs recreate |

---

## 2. Memory-only incidents the repo never captured

Each: symptom → root cause → evidence → fix → status → date. **Source = auto-memory,
not the repo** — marked UNVERIFIED against live hosts; re-verify commands in
Provenance. Where a *general* rule already exists in a rules table, this records
only the **specific dated incident** the table omits.

### 2.1 winston SR-IOV VFs vanished after 6.17.13-1 → 6.17.13-6
- **Symptom:** after routine kernel-point-release reboot, only the i915 **PF**
  (physical function) visible; VM 100 GPU passthrough dead, no VFs.
- **Root cause:** `proxmox-headers-6.17.13-6-pve` not installed → DKMS rebuild
  **silently no-oped** → stock `i915.ko` loaded (no `max_vfs` param).
- **Evidence:** `dkms status` listed only the *old* kernel; `dmesg` showed
  `unknown parameter 'max_vfs' ignored`.
- **Fix:** install `proxmox-default-headers` + matching per-version headers →
  `dkms autoinstall -k <ver>-pve` → `modinfo …/updates/dkms/i915.ko | grep max_vfs`
  → reboot → 8 VFs restored.
- **Status:** RESOLVED 2026-04-30. Promoted to **global** `rules/infrastructure.md`;
  the generalized rule is `infra-lessons.md` §Proxmox Kernel Upgrades. The **dated
  winston incident** itself is memory-only.
- **Source:** `feedback_proxmox_kernel_headers` + MB `homelab/session-2026-04-30`.

### 2.2 Kernel 7.0 BUILD_EXCLUSIVE blocker → strongtz#438 unblock
- **Symptom:** i915-sriov-dkms refused to build on kernel 7.0 (`BUILD_EXCLUSIVE`,
  upstream issue **strongtz#429**), blocking the whole PVE 9.2 upgrade.
- **Interim:** both hosts pinned to **6.17.13-6** on 2026-04-30.
- **Resolution arc:** DKMS release **2026.05.06** (PR **#438**, merged 2026-05-02)
  added 7.0 support → winston verified PVE 9.2.2 + 7.0.2-6-pve with 7/7 VFs →
  **reginald + PBS (.187)** upgraded/rebooted to 7.0.2-6 on **2026-05-22/23**.
- **Status:** RESOLVED. Runbook `docs/migrations/pve-9.2-kernel-7-upgrade.md`
  (verified present; header dated 2026-05-22, hosts winston+reginald). Note:
  that doc's state table still says winston `PVE 9.1.0` **as of 2026-05-22** — a
  point-in-time snapshot, not proof of today's version (see Open questions).
- **Source:** runbook doc + `feedback_proxmox_kernel_headers` update.

### 2.3 reginald ESP full mid kernel-install + the legacy-GRUB correction
- **Symptom:** `No space left on device` writing a new kernel to reginald's
  **511 MB ESP at 100%** during the upgrade.
- **Fix:** purge superseded kernels (~190 MB freed) + `apt --fix-broken install`.
- **The correction (why this matters):** reginald was *believed* to be
  systemd-boot. **That earlier note was WRONG** — reginald (Zimaboard, CSM) boots
  **legacy GRUB-PC**; `bootctl status` says "Not booted with EFI", and edits to
  `/boot/efi/loader/loader.conf` are silently ignored. The corrected pinning
  procedure (`proxmox-boot-tool kernel pin`, works on both hosts) now lives in
  `infra-lessons.md` §Proxmox Kernel Upgrades — but that file still carries a
  fossil row header **"ESP capacity on systemd-boot hosts"** describing reginald;
  treat the header as stale wording, the body (legacy-GRUB) as truth.
- **Status:** RESOLVED 2026-04-30 (correction confirmed 2026-05-22).
- **Source:** MB `homelab/session-2026-04-30`; `feedback_proxmox_kernel_headers`.

### 2.4 ZFS pool SUSPENDED during a hot-swap mid-scrub (nwlab thinkpad)
- **Symptom:** USB-cable swap on a Sharkoon enclosure (mirror `sdb`+`sdc`) at
  **79% scrub** → both legs vanished at once → pool **SUSPENDED**, ~8314
  in-flight IO errors stamped "permanent data errors" in
  `/storage/homelab-sync/.chunks/`.
- **Root cause:** hot-swapping a **single-cable USB mirror mid-scrub** takes both
  legs offline simultaneously.
- **Fix:** `zpool clear` → pool ONLINE 0/0/0 (error count persists until the next
  full scrub completes).
- **Rule promoted:** `zpool scrub -p <pool>` (pause) before **any** physical
  storage work; resume/clear after.
- **Status:** RESOLVED 2026-05-15. This is on the **nwlab thinkpad**, not
  winston/reginald, so it is absent from this repo's rules (which cover only
  reginald's raidz2 tuning). Also held in **global** `nwdesigns-failure-archaeology`
  + `rules/infrastructure.md` — cross-ref, don't duplicate.
- **Source:** `feedback_zfs_hotswap_pause_scrub`.

### 2.5 Nextcloud 32→33: "permission denied for schema public"
- **Root cause:** Nextcloud's real DB user is **`oc_nextcloud`**, not the compose
  `POSTGRES_USER=nextcloud`; PostgreSQL 15+ revokes `CREATE` on `public` from
  non-owners, so the migration can't create tables.
- **Fix:** make `oc_nextcloud` own the `public` schema; always check
  `occ config:system:get dbuser` before a major upgrade.
- **Status:** RESOLVED ~2026-04-01. `deployment-lessons.md` covers Nextcloud
  config-key names but **not** this schema-ownership trap — memory-only here;
  also global `feedback_nextcloud_dbuser`.
- **Source:** `feedback_nextcloud_dbuser`.

### 2.6 The 5-month PBS vzdump gap (Oct 2025 – Mar 2026) — the pmxcfs-DR archetype
- **Fully documented in the repo already** (`infra-lessons.md` §PBS/Vzdump): a
  winston rebuild dropped `/etc/pve/jobs.cfg`; because pmxcfs is not backed up,
  **no scheduled backups ran for ~5 months**, recreated 2026-03-01.
- **Why it's here:** it is the *archetype* of the recurring "pmxcfs is not in any
  backup" pattern that also threatens the **untracked firewall plan** (`hosts/`,
  `scripts/hosts/deploy-firewall.sh` are `??` in git — verified) and the
  untracked rustfs/hardware-purchases trees. The repo is the DR source of truth;
  a reinstall today loses anything not committed. **Index-only — not re-encoded.**

### 2.7 "LXC 102" (TimeMachine/Samba) zero-swap = OOM risk — CONTRADICTS AGENTS.md
- **Symptom:** container configured with 0 swap → OOM exposure under memory
  pressure.
- **Fix:** added **256 MB swap** during the Feb-2026 resource-optimization pass
  (alongside `KSM_THRES_COEF=95`, zram `lzo-rle` — zstd unsupported in the VM
  kernel).
- ⚠️ **CONTRADICTION — do not treat "LXC 102 = TimeMachine/Samba" as settled.**
  The authoritative AGENTS.md lists **VM 102 = homeassistant** and the Samba
  service as **LXC 123** (on reginald) — so the memory's "LXC 102 = Samba" ID is
  wrong, stale, or a renumbering. The **resolution owner is sibling
  homelab-storage-and-backup §6**, which surfaces this same conflict per
  standards.md's contradiction-stop rule; defer to it. Confirm live before acting:
  `ssh root@192.168.100.4 'pct list'` (reginald LXCs) and
  `ssh root@192.168.100.38 'qm list | grep 102'` (what 102 actually is).
- **Status:** the *zero-swap → add-256MB-swap* fix is RESOLVED ~2026-02, but the
  **container identity is UNVERIFIED / contradicted** (see above). Not in repo
  rules (which hold KSM/balloon *host* tuning, not per-LXC swap); memory-only
  (KG `homelab` store `LXC102ZeroSwap`).

---

## 3. Reverted / abandoned decisions — with WHY (git-verified)

All hashes and dates verified via `git log`. When you're tempted to re-add one of
these, this is why it left.

| Decision | Verdict + WHY | Evidence |
|---|---|---|
| **Prometheus + Grafana in homelab** | **Reverted in 12 minutes.** Added `08e34b3` (2026-04-10 22:57) → reverted `0c6f690` (2026-04-10 23:09). Blog-publisher/observability belongs in the **nwlab** segment next to otel-collector/ntfy on flatcar-104 (10.21.21.104) — avoids shipping per-cron metrics across the WG tunnel and exposing `remote_write` to the homelab LAN. | `git show 0c6f690` |
| **Profilarr Homepage widget** | Dropped `00d05f2` (2026-05-27) — **not yet supported upstream.** | commit msg |
| **resolv.conf bind on profilarr** | Dropped `a4a82d6` (2026-05-27) — the bind overrode Docker's embedded 127.0.0.11 resolver, breaking sibling-container DNS (`getent hosts radarr` failed). Embedded DNS handles siblings. Also in `media-api-lessons.md`. | commit msg |
| **SDN WireGuard fabric (Phase 1)** | **Deferred** `104b5c2` (2026-05-27) — research done (`7f217a5`, `docs/research/nwlab-pve-9.2-sdn-wireguard.md`) but the current tunnel was judged adequate; docs-only decision. | commit msg |
| **NordVPN** | Archived → **ProtonVPN/gluetun** (with NAT-PMP port-forwarding). `docs/migrations/nordvpn-fixes-ARCHIVED.md` (verified present). | file |
| **Pi-hole + Nebula Sync** | Replaced by the **3-node Technitium** cluster with native zone replication (AGENTS.md §DNS). | AGENTS.md |
| **Kido self-hosting** | Removed from VM 100 `0f74f44` (2026-03-07) — **migrated off-prem to Vercel + Neon.** | commit msg |
| **MinIO → Garage** | **Deprecated 2026-04-10, never deployed.** Superseded by **MinIO → RustFS** (alpha risk accepted for memory-safety + Apache-2.0 + MinIO drop-in). Both `docs/migrations/minio-to-garage.md` (DEPRECATED banner) and `scripts/migrations/minio-to-garage/DEPRECATED.md` verified. RustFS `.env` is still **blanked** — repopulate before use. | file headers |

---

## 4. Stale git branches — work landed elsewhere or parked untracked

All three local non-`main` branches are **0 commits ahead of main** (verified
`git rev-list --count main..<branch>`). Do not resurrect scope from a branch
name — check what actually shipped.

| Branch | Points at | Reality |
|---|---|---|
| `autoresearch/camera-5ghz-channel` | `c261ac0` (2026-03-26) | 0 ahead. The 5 GHz-channel work exists as an **untracked** `scripts/network/test-5ghz-channel.sh`, not on this branch. |
| `docs-agents-guide` | `c261ac0` | 0 ahead. The AGENTS.md standardization actually landed on **main** (`51a6110`, 2026-06-22). Worktree dir `.claude/worktrees/agents-guide/` still on disk. |
| `worktree-keen-fox-mws7` | `e2c294d` (2026-03-18) | 0 ahead. Leftover Claude worktree; dir `.claude/worktrees/keen-fox-mws7/` still on disk. |
| `origin/add-claude-github-actions-1776891479459` | `b6d1d96` | Merged via PR #1 (`a6b3055`, the repo's **only** merge commit). Safe to delete. |

---

## 5. Cross-incident synthesis

**Kernel upgrades are the #1 recurring injury vector.** Every serious homelab
outage in this chronicle traces back to a kernel change: winston's VFs vanishing
(§2.1), the 7.0 BUILD_EXCLUSIVE block (§2.2), reginald's ESP filling mid-install
(§2.3), plus the Flatcar `DRM_GPUVM` / `__copy_from_user_inatomic_nocache`
blockers in `gpu-sriov-lessons.md`. The single mechanism underneath most of them:
**DKMS silently no-ops when the matching headers are missing**, so SR-IOV dies on
the *next* boot with no error at upgrade time. That is why the discipline is
front-loaded — install `proxmox-default-headers` + per-version headers *in the
same transaction* as the kernel, verify `dkms status` lists the new kernel and
`modinfo … | grep max_vfs` **before** rebooting, and pin the known-good kernel.
The runbook lives in `infra-lessons.md` §Proxmox Kernel Upgrades, the recovery in
`gpu-sriov-lessons.md`, and the how-to in sibling **homelab-kernel-gpu-sriov** +
the `gpu-fix` skill. Treat any `apt` kernel bump on winston as a change that can
brick the media/photo/cloud stack.

**Observability keeps trying to enter this repo and keeps being ejected to
nwlab.** Prometheus + Grafana were added and reverted **12 minutes later**
(`08e34b3`→`0c6f690`), relocated to flatcar-104 in the nwlab segment. Grafana
runs at `/opt/grafana` on flatcar-nwdesigns with **zero representation in this
repo** (no compose, no doc — a deliberate boundary, not a gap to fill here). The
*only* metrics component that stayed is the Technitium Prometheus **exporter
sidecar**, because it is DNS-cluster-local and doesn't cross the tunnel. The
settled rule: cross-service metrics live in **nwlab** next to otel-collector/ntfy;
do not reintroduce a homelab-LAN Prometheus or a `remote_write` path across the
WireGuard tunnel. If you find yourself adding Grafana here, you are re-fighting a
lost battle — send it to the `nwlab` repo instead.

---

## Cross-references

- **Global `nwdesigns-failure-archaeology`** already holds this repo's
  **ZFS pool SUSPENDED** (§2.4) and **i915 VFs gone after kernel upgrade** (§2.1)
  as portfolio entries. Link **both directions**: that skill = the portfolio
  chronicle; this skill = the host-specific detail (thinkpad enclosure, chunk
  paths, winston kernel versions). Don't duplicate the shared entries.
- **Siblings** (same homelab skill family): **homelab-debugging-playbook** (live
  triage) and **homelab-kernel-gpu-sriov** (the upgrade runbook). `gpu-fix` skill
  = remediation owner for SR-IOV recovery.
- **Global `infra-runbook`** = generic Proxmox/ZFS/PBS/WireGuard/Docker
  symptom→fix; **`systematic-debugging`** = process gates.
- **Normative rules** = the 10 `.claude/rules/*.md` files (§1). This chronicle
  never overrides them; on any conflict, the rules file and AGENTS.md win.

## Open questions (unverified live state)

- **PVE/kernel version drift:** AGENTS.md still lists winston 9.1.6 / reginald
  9.1.5, but the kernel-7 runbook + memory say both (and PBS) reached 7.0.2-6 by
  2026-05-23. Neither AGENTS.md nor the host READMEs were updated. Verify before
  relying on either: `ssh root@192.168.100.38 'pveversion; uname -r'` (and `.4`,
  `.187`).
- **RustFS `.env` blanked** during the secrets migration — repopulate before use.
- **Firewall plan still untracked** (`git status` shows `hosts/`, `scripts/hosts/`
  as `??`) — a bare-metal reinstall would lose it (the §2.6 pattern).

## Provenance and maintenance

Read-only re-verify commands (run from repo root; nothing here mutates state):

```bash
# §1 the 10 rules files still exist
ls .claude/rules/

# §2.2/2.3 kernel runbook + host state snapshot
sed -n '1,30p' docs/migrations/pve-9.2-kernel-7-upgrade.md
# live host versions (SSH, read-only) — settles the version-drift Open question
for h in 192.168.100.38 192.168.100.4 192.168.100.187; do ssh root@$h 'pveversion; uname -r'; done

# §3 reverted-decision hashes + dates
for h in 08e34b3 0c6f690 00d05f2 104b5c2 a4a82d6 0f74f44; do git log -1 --format='%h %ci %s' $h; done
ls docs/migrations/nordvpn-fixes-ARCHIVED.md \
   docs/migrations/minio-to-garage.md scripts/migrations/minio-to-garage/DEPRECATED.md

# §4 stale branches are still 0-ahead
for b in autoresearch/camera-5ghz-channel docs-agents-guide worktree-keen-fox-mws7; do \
  echo -n "$b ahead: "; git rev-list --count main..$b; done

# §2.6 / Open questions — firewall plan tracked yet?
git status --short hosts/ scripts/hosts/
```

Memory-sourced incidents (§2) are point-in-time from `~/Obsidian/Brain/auto-memory/`
and the Knowledge Graph — mine those for updates; never make them a use-time
dependency. **Never put secrets in this file** — credential *locations* only
(`.env` key names live in AGENTS.md §Credentials; VM per-stack `.env` under
`/srv/docker/<stack>/`).

_Last verified against disk: 2026-07-04._
