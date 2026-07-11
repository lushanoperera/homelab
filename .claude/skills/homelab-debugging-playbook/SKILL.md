---
name: homelab-debugging-playbook
description: >
  Symptom-to-triage routing layer for THIS homelab's recurring failure shapes (Proxmox winston/reginald,
  Flatcar VM 100 Docker stacks, Technitium DNS cluster, gluetun/ProtonVPN media stack, NFS/ZFS on reginald,
  Caddy/Traefik, UniFi). Start here when something in the lab is broken and you are not sure which runbook
  skill owns it. Triggers — downloads stalled / no VPN port / forwarded port 0 / qBittorrent stuck, container
  can't resolve sibling (getent hosts radarr fails), GPU gone / no /dev/dri / transcoding dead / VFs missing
  after kernel upgrade, NFS stale / hung mount / mnt-media, Seerr 403 invalid csrf token on delete, new
  internal DNS record not resolving, homelab unreachable from macOS after WireGuard app quit / LiveSync down,
  Nextcloud upgrade permission denied for schema public, DNS answers wrong / cluster drift, UniFi API 403 /
  auth weirdness. Keywords: homelab triage, which skill do I use, media stack down, ProtonVPN port forward,
  flatcar, sibling DNS, i915 SR-IOV, NFSv4 stale, Technitium, gluetun, radarr, sonarr, reginald, winston.
---

# Homelab Debugging Playbook (triage & routing layer)

You are debugging the **nwdesigns homelab** (repo `/Users/disconnesso/Documents/Projects/homelab`). This
skill is the **decision tree above** the 13 operational runbook skills. It does **one job**: map a symptom to
its first read-only probe, then hand you off to the skill/rule that owns the fix. It does not restate the
runbooks.

## When to use / when NOT to use

| Situation | Go to |
| --- | --- |
| A lab symptom and you're unsure which runbook owns it | **This skill** — pick the row below, then follow the handoff |
| Generic Proxmox / ZFS / PBS / WireGuard / Docker symptom→fix (not lab-specific topology) | global skill **infra-runbook** |
| You have no reproduction / no sharp feedback loop yet, or you're guessing at causes | global skill **systematic-debugging** (get through its gates first, then come back) |
| "Has this happened before? why is it done this way?" — settled history | sibling **homelab-failure-archaeology**, then global **nwdesigns-failure-archaeology** |
| Kernel upgrade / SR-IOV DKMS build deep dive | sibling **homelab-kernel-gpu-sriov** |
| ZFS tuning, PBS/restic backups, storage capacity | sibling **homelab-storage-and-backup** |

**Do NOT** apply Cloudways/Aruba/managed-host habits here — these are self-managed Proxmox/Flatcar hosts;
deploy = rsync/scp + `docker compose up -d`, no managed cache layer (AGENTS.md "Gotchas"). **Never** flip the
host firewall `enable:` implicitly, `git add -A` (working tree runs chronically dirty), or echo `.env` values.

## Ground rules for every probe

- **Read-only first.** Every "first probe" below is non-mutating. Confirm the symptom before touching anything.
- **SSH targets** (key-auth): `root@192.168.100.38` winston · `root@192.168.100.4` reginald · `core@192.168.100.100` Flatcar VM 100 · `root@192.168.100.187` PBS. (AGENTS.md "Local development".)
- **Flatcar compose is `/opt/bin/docker-compose`** (standalone binary; `/usr` is read-only). Deployed scripts live in `/opt/bin/`; media stack in `/srv/docker/media-stack/`. (AGENTS.md repo→VM path map; flatcar-lessons.md.)
- **Live host versions are unverified from the repo.** AGENTS.md declares winston PVE 9.1.6 / reginald 9.1.5, but a `docs/migrations/pve-9.2-kernel-7-upgrade.md` runbook and memory suggest an upgrade to 9.2.2 / kernel 7.0.2 happened. Confirm with `ssh root@<host> 'pveversion; uname -r'` before making any version-dependent call.

---

## The 10 triage trees

Each row: **symptom → first read-only probe → owning skill/rule → fix pattern.** Run the probe, confirm, then
open the owning skill/rule for the full runbook. Do not fix from this table alone when a runbook skill exists.

### 1. Downloads stalled / no VPN port / forwarded port is 0

- **Probe (read-only):**
  ```bash
  ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port'
  # 0 or empty = ProtonVPN NAT-PMP port-forward died (recvfrom: connection refused on UDP 5351)
  ```
- **Owner:** project skill **vpn-status** (verify), then **media-health** for the whole stack.
- **Fix pattern:** ProtonVPN NAT-PMP can die silently and gluetun loops without re-acquiring — no native healthcheck. Re-sync the port with `/opt/bin/qbt-port-sync.sh`; the standing watcher is `/opt/bin/gluetun-pf-watch.sh` (systemd 5-min timer: restarts gluetun + deps `qbittorrent prowlarr sabnzbd` after 2 consecutive `port=0` reads, 1800s cooldown). **Gluetun recreate/restart orphans its dependents** — always restart the deps too, never gluetun alone (flatcar-lessons.md "Gluetun restart stuns deps" / "NAT-PMP can die silent"). qBittorrent API only answers from **inside** the gluetun namespace: `docker exec gluetun wget -qO- ...`, not `curl localhost` from the host (media-api-lessons.md).
- **If requests are stuck but VPN is healthy:** project skill **retrigger-downloads** / `/opt/bin/retrigger-missing-downloads.sh [--dry-run]`.

### 2. Container can't resolve a sibling (`getent hosts radarr` fails)

- **Probe (read-only):**
  ```bash
  ssh core@192.168.100.100 'docker exec <container> getent hosts radarr'   # empty = broken embedded DNS
  ssh core@192.168.100.100 'docker inspect <container> --format "{{json .HostConfig.Binds}}" | grep resolv.conf'
  ```
- **Owner:** rule **media-api-lessons.md** (Profilarr V2 row).
- **Fix pattern:** A `/srv/docker/resolv.conf` **bind-mount overrides Docker's embedded DNS at 127.0.0.11**, so sibling container names (radarr, sonarr) stop resolving. **Drop the resolv.conf bind** from that service's compose — embedded DNS handles siblings and forwards external upstream. (This is the Profilarr fix; dropped in commit `a4a82d6`, 2026-05-27.)

### 3. GPU / VFs gone in VM 100 (no `/dev/dri`, transcoding dead, "VFs missing after kernel upgrade")

- **Probe — CHECK THE HOST FIRST, not the VM.** The classic is a silent DKMS no-op on winston after a kernel bump:
  ```bash
  ssh root@192.168.100.38 'dkms status'                 # must list the RUNNING kernel; if only old kernel → headers missing
  ssh root@192.168.100.38 'uname -r; ls /lib/modules/$(uname -r)/updates/dkms/i915.ko'
  ssh root@192.168.100.38 'modinfo /lib/modules/$(uname -r)/updates/dkms/i915.ko | grep max_vfs'  # no max_vfs = stock i915 loaded
  ssh root@192.168.100.38 'dmesg | grep -i "max_vfs"'   # "unknown parameter max_vfs ignored" = stock module
  ```
- **Owner:** project skill **gpu-fix** (VM-side rebuild/sysext/module swap); rules **gpu-sriov-lessons.md** + **infra-lessons.md** (host DKMS). Deep build issues → sibling **homelab-kernel-gpu-sriov**.
- **Fix pattern:** If `dkms status` doesn't list the running kernel, `proxmox-headers-<ver>-pve` was not installed in the same transaction as the kernel → DKMS silently skipped rebuild → stock `i915.ko` with no `max_vfs`. Install `proxmox-default-headers` + matching per-version headers, `dkms autoinstall -k <ver>-pve`, re-check `modinfo ... | grep max_vfs`, reboot → VFs return. **Host DKMS on kernel 7.0 needs `i915-sriov-dkms` `2026.05.06`** (PR #438); the old `BUILD_EXCLUSIVE`/xe workaround is obsolete. **Only after the host is healthy**, work the Flatcar guest with gpu-fix (sysext rebuild + `insmod` + `verify-gpu.sh`, expect 7/7). Flatcar guest DKMS is a separate pin: `2025.07.22` + nocache shim (kernel 6.12.87; `DRM_GPUVM` disabled) — do not confuse it with the host version.

### 4. NFS stale / hung mount (`/mnt/media` unresponsive, media stack can't read files)

- **Probe (read-only):**
  ```bash
  ssh core@192.168.100.100 'systemctl status mnt-media.mount --no-pager; mount | grep /mnt/media'
  ssh root@192.168.100.4 'exportfs -v'                          # reginald = NFS server (storage LAN .200.4)
  ssh root@192.168.100.4 'zfs list -o name,mountpoint,mounted | grep media'
  ```
- **Owner:** project skill **nfs-check**; rules **nfs-zfs-lessons.md** + **network-services.md**.
- **Fix pattern:** For a stale mount on Flatcar: `ssh core@192.168.100.100 'sudo systemctl restart mnt-media.mount'` (network-services.md). Recurring shape: **NFSv4 stale sessions on old IPs** — clients holding sessions on now-unauthorized IPs poison new mounts; stop the media containers, remount clean (nfs-zfs-lessons.md). Server-side partial-stale handles: `exportfs -ra` on reginald, then restart containers. NFS traffic rides the **storage LAN (192.168.200.x)**, separate from Infra (.100.x) — check the right subnet. (Mount-propagation/rslave tuning: UNVERIFIED against repo — memory/history only, do not assert without checking the live systemd unit.)

### 5. Seerr API 403 "invalid csrf token" on a mutation (delete/PUT/POST)

- **Probe (read-only):** confirm the endpoint is a mutation and that a plain `X-Api-Key`-only call returns 403.
- **Owner:** rule **media-api-lessons.md** (Seerr API); project skill **media-remove** wraps the full cascade.
- **Fix pattern — double-submit cookie dance (mandatory for every mutating Seerr call):**
  ```bash
  source /srv/docker/media-stack/.env         # SEERR_API_KEY etc.
  curl -s -c /tmp/seerr.cookies -H "X-Api-Key: $SEERR_API_KEY" "$SEERR_URL/api/v1/status" > /dev/null
  XSRF=$(grep XSRF-TOKEN /tmp/seerr.cookies | awk '{print $NF}')
  curl -s -b /tmp/seerr.cookies -H "x-xsrf-token: $XSRF" -H "X-Api-Key: $SEERR_API_KEY" -X DELETE "$SEERR_URL/api/v1/media/{id}"
  ```
  GET `/api/v1/status` first to seed the XSRF-TOKEN cookie, then send it as **both** cookie jar and `x-xsrf-token` header alongside `X-Api-Key`. **Delete the MEDIA entry (`/api/v1/media/{id}`), not the request** — deleting media cascades to associated requests; deleting the request can orphan media. Removal order across the stack: Seerr → qBittorrent → Sonarr/Radarr (`deleteFiles=true`) → verify on reginald (media-api-lessons.md).

### 6. New internal DNS record "not resolving" (created via Cloudflare, points at RFC1918)

- **Probe (read-only):**
  ```bash
  dig @1.1.1.1 <name> +short         # empty right after creating an RFC1918-pointing record = expected hold
  ```
- **Owner:** sibling **homelab-network-and-dns §4** (Cloudflare RFC1918 playbook) — the design home for this fact.
- **Fix pattern (one line — full runbook in the owner):** it's a **known non-incident** — Cloudflare's silent ~60-min RFC1918 validation hold; **wait 60+ min, do not open a ticket or build a workaround.** See network-and-dns §4 for the rationale (and why the `nwlab.nwdesigns.it` zero-cost secondary zone exists).

### 7. Homelab unreachable from macOS after the WireGuard app quit (LiveSync / SSH to .100.x dead)

- **Probe (read-only):**
  ```bash
  ifconfig | grep -A3 utun          # look for a zombie utun with a stale default route
  netstat -rn | grep -E 'utun|0.0.0.0/0|192.168.100'
  ```
- **Owner:** sibling **homelab-network-and-dns §6** (macOS zombie utun4) — the design home for this fact.
- **Fix pattern (one line — full runbook in the owner):** a quit WireGuard app leaves a zombie `utun4` + stale `0.0.0.0/0` route; add a more-specific route (`sudo route add -net 192.168.100.0/24 192.168.2.1`) so it wins. **Not reboot-persistent** (still open). See network-and-dns §6 for the full note (and why the vault's CouchDB LiveSync is never a git-remote problem).

### 8. Nextcloud upgrade fails: "permission denied for schema public"

- **Probe (read-only):**
  ```bash
  ssh core@192.168.100.100 'docker exec -u www-data nextcloud php occ config:system:get dbuser'
  # expect oc_nextcloud, NOT the compose POSTGRES_USER (nextcloud)
  ```
- **Owner:** no repo runbook — app-level DB ownership gotcha.
- **Fix pattern:** Nextcloud's **real DB user is `oc_nextcloud`** (set at install), not the `POSTGRES_USER=nextcloud` in `apps/nextcloud/.env`. PG15+ revokes `CREATE` on `public` from non-owners, so migrations fail. Make `oc_nextcloud` **own the `public` schema** (`ALTER SCHEMA public OWNER TO oc_nextcloud;`). Always check `occ config:system:get dbuser` before touching DB grants. (UNVERIFIED against repo — source: memory `feedback_nextcloud_dbuser`, ~2026-04-01.)

### 9. DNS answers wrong / cluster drift / naming looks doubled

- **Probe (read-only):**
  ```bash
  dig @192.168.100.254 <name> +short   # QNAP primary
  dig @192.168.100.100 <name> +short   # Flatcar secondary
  dig @192.168.100.120 <name> +short   # reginald secondary   — triple-dig, compare answers
  ssh core@192.168.100.100 '/opt/bin/check-cluster-drift.sh'   # SOA serial drift across nodes (exit 1 = drift)
  ```
- **Owner:** rule **dns-lessons.md**; script `scripts/dns/check-cluster-drift.sh` (systemd `dns-drift-check.timer`, 5-min).
- **Fix pattern:** If nodes disagree, `check-cluster-drift.sh` compares SOA serials and writes `dns-cluster.json` for the Homepage widget; exit 1 = serials diverged (replication lag or a node stuck). If cluster-page node names render as `dns.disconnesso.home.arpa.dns.disconnesso.home.arpa`, that's the **known double-suffix bug** — with the current short-suffix config expect **3 distinct nodes**; verify before treating it as live drift. Catalog member-zone records only answer from the cluster subnet — use a **non-catalog zone for client-visible records** (dns-lessons.md).

### 10. UniFi API 403 / auth weirdness (inventory or optimize scripts failing)

- **Probe (read-only):**
  ```bash
  ./scripts/network/unifi-inventory.sh --health          # or --clients|--devices|--networks|--wifi ; --all --json
  ```
- **Owner:** rule **networking-lessons.md**; project skill **network-diagnostics**.
- **Fix pattern:** The **CSRF token is INSIDE the JWT payload**, not a separate header — decode the TOKEN cookie's middle base64 segment → `.csrfToken`, send it as `X-CSRF-Token`. Passing the raw JWT as the header = 403. For automation use a **local-only admin** ("Restrict to Local Access Only") — SSO accounts force MFA and break API login. Credentials in `scripts/network/.env` (`UNIFI_HOST/USER/PASS`). Read-only work stays in `unifi-inventory.sh`; changes go through `unifi-wifi-optimize.sh --dry-run|--apply|--rollback`.

---

## Subsystem → runbook routing table

Once you know the subsystem, this is which of the 13 existing project runbook skills to invoke. This playbook
**routes**; those skills **execute**. Keep them as-is.

| Subsystem | First-line project skill(s) | Owning rule file | Deep-dive sibling / global |
| --- | --- | --- | --- |
| Media stack health (containers/VPN/ports/NFS/disk) | **media-health** | media-api-lessons, flatcar-lessons | — |
| VPN / ProtonVPN port forward | **vpn-status** | flatcar-lessons | — |
| Remove a movie/series everywhere | **media-remove** | media-api-lessons | — |
| Stuck Seerr requests | **retrigger-downloads** | media-api-lessons | — |
| Sonarr/Radarr quality profiles | **quality-manage** | media-api-lessons | — |
| GPU / SR-IOV / transcoding (VM 100) | **gpu-fix** | gpu-sriov-lessons, infra-lessons | **homelab-kernel-gpu-sriov** |
| NFS / ZFS mounts | **nfs-check** | nfs-zfs-lessons, network-services | **homelab-storage-and-backup** |
| DNS cluster (Technitium) | (probe: `check-cluster-drift.sh`) | dns-lessons | — |
| UniFi / WiFi / network | **network-diagnostics** | networking-lessons, network-services | global **infra-runbook** (generic net) |
| Reverse proxy / CrowdSec (public edge) | **traefik-crowdsec** | — | — |
| Compose deploy to VM 100 | **deploy-compose** | deployment-lessons, flatcar-lessons | — |
| Container lifecycle (restart/logs/update) | **container-manage** | deployment-lessons | — |
| Proxmox VM/LXC (list/start/stop/snapshot) | **proxmox-manage** | infra-lessons | global **infra-runbook** |
| PBS / restic / S3 backup health | **backup-status** | infra-lessons | **homelab-storage-and-backup** |
| Host firewall rollout (staged `enable: 0`) | — (follow `hosts/firewall.md`) | infra-lessons | — |
| Kernel upgrade (Proxmox host) | — | infra-lessons | **homelab-kernel-gpu-sriov** |

**Generic** Proxmox/ZFS/PBS/WireGuard/Docker symptom→fix that isn't lab-specific → global **infra-runbook**.
**Process** discipline (no repro, guessing) → global **systematic-debugging**. **History** ("seen before?") →
sibling **homelab-failure-archaeology** → global **nwdesigns-failure-archaeology**.

---

## Provenance and maintenance

Re-verify the volatile claims in this skill with these read-only commands (run from the repo root):

- **Rule files still exist / own these lessons:** `ls .claude/rules/{media-api,gpu-sriov,nfs-zfs,dns,networking,infra,flatcar,deployment}-lessons.md .claude/rules/{network-services,ops-reference}.md`
- **Scripts referenced by the trees exist:** `ls scripts/vms/{qbt-port-sync,gluetun-pf-watch,retrigger-missing-downloads}.sh scripts/dns/check-cluster-drift.sh scripts/network/unifi-inventory.sh scripts/hosts/check-nfs-mounts.sh`
- **Project runbook skills still present:** `ls .claude/skills/` (expect the 13: media-health, vpn-status, media-remove, retrigger-downloads, quality-manage, gpu-fix, nfs-check, network-diagnostics, traefik-crowdsec, deploy-compose, container-manage, proxmox-manage, backup-status)
- **Gluetun / NFS / DNS commands unchanged:** `grep -rn 'forwarded_port\|mnt-media.mount' .claude/rules/network-services.md .claude/rules/ops-reference.md` and `grep -n 'PRIMARY\|SECONDARIES' scripts/dns/check-cluster-drift.sh`
- **Live host versions (trees 3, kernel-dependent):** `ssh root@192.168.100.38 'pveversion; uname -r; dkms status'` — AGENTS.md still says 9.1.6/9.1.5; confirm before any version-specific action (as of 2026-07-05).
- **Repo-UNVERIFIED trees (6 Cloudflare hold, 7 WireGuard zombie, 8 Nextcloud dbuser, rslave note in 4):** sourced from auto-memory, not the repo. Confirm live before acting; promote to a rule file if reproduced on-box.
