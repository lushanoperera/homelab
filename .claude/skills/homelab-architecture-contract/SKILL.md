---
name: homelab-architecture-contract
description: >-
  The homelab architecture contract — what runs where, WHY, and the invariants
  you must not break. Read this BEFORE changing topology, moving a service between
  hosts, adding a stack, touching the firewall, or reasoning about "where should
  this live". Answers: which lab is this (homelab 192.168.100.0/24 vs office nwlab
  10.21.21.0/24)? why is there no Grafana/Prometheus in this repo? why two reverse
  proxies (Caddy vs Traefik)? why is the per-VM firewall off? why does the working
  tree run dirty? is there a staging environment? why is admin_sources narrowed?
  which images are pinned and why? Triggers — "where does this run / where should
  I put this", "add a new service/stack", "why is observability in nwlab", "move
  Grafana here", "two proxies", "Caddy or Traefik", "which host", "winston vs
  reginald", "is there staging", "why no per-VM firewall", "watchtower pinned",
  "repo vs pmxcfs", "what PVE version are we on", "README says Garage", "MinIO
  migration", "firewall deviation", "admin_sources /20", "homelab invariants",
  "onboarding this repo", "architecture", "topology", "what-runs-where".
---

# Homelab Architecture Contract

This skill is the **contract, rationale, and quirks** for the Proxmox homelab at
`/Users/disconnesso/Documents/Projects/homelab`. It captures WHY things are the
way they are and WHAT you must not break. It deliberately does **not** restate the
full host/VLAN/service tables or the repo→VM path table — **`AGENTS.md` is the
authoritative table source**. When you need an exact IP, port, path, or image tag,
read `AGENTS.md`; when you need to know whether a change is *allowed* and *why*,
read this.

Jargon defined once, at first use. Every fact here was verified read-only against
the repo on 2026-07-05 unless marked `UNVERIFIED`.

---

## When to use this / when NOT

**Use this skill when** you are about to:
- decide where a new service or VM should live, or move an existing one between hosts;
- add/remove a docker-compose stack, or change image-update policy;
- touch the host firewall, VLANs, or reverse-proxy split;
- reconcile a claim in `README.md`/`AGENTS.md` that "feels" out of date;
- onboard to the repo and need the mental model before reading code.

**Do NOT use this skill for — go here instead:**

| You need… | Go to |
|---|---|
| Exact IPs / ports / path-mapping / image tags | `AGENTS.md` (authoritative tables) |
| Which `.env` key lives where, secret locations | sibling skill **homelab-config-and-flags** |
| DNS records, VLAN routing detail, Technitium cluster | sibling skill **homelab-network-and-dns** |
| Deploy a compose change to VM 100 | project skill **deploy-compose** / **container-manage** |
| Proxmox VM/LXC list/start/stop/snapshot | project skill **proxmox-manage** |
| Edge/CrowdSec/Traefik day-2 ops (`cscli`, bouncer) | project skill **traefik-crowdsec** |
| SR-IOV GPU broken after kernel upgrade | project skill **gpu-fix**; `.claude/rules/gpu-sriov-lessons.md` |
| Generic Proxmox/ZFS/PBS/WireGuard/Docker symptom→fix | **global** skill **infra-runbook** |
| Flatcar-specific gotchas (read-only /usr, sysext) | `.claude/rules/flatcar-lessons.md` |
| Multicast/mDNS, KSM, ZFS-scrub, PBS lessons | `.claude/rules/infra-lessons.md` |
| Client-site portfolio architecture (Cloudways/Aruba/Vercel) | **global** skill **agency-architecture-contract** |

This skill holds *only* the homelab-specific contract. It never restates a rule
that a `.claude/rules/*-lessons.md` file or a global skill already owns — it points
at them.

---

## 1. The two-labs boundary (the first question to answer)

There are **two** Proxmox estates. Confusing them is the most common architectural
error. Decide which one you are in before anything else.

| | **homelab** (this repo) | **office nwlab** (separate repo) |
|---|---|---|
| Subnet | `192.168.100.0/24` (Infra VLAN 100) | `10.21.21.0/24` |
| Repo | `/Users/disconnesso/Documents/Projects/homelab` | `github.com/lushanoperera/nwlab` (`/Users/disconnesso/Documents/Projects/nwlab`) |
| Hosts | winston `.38`, reginald `.4`, Flatcar VM 100 `.100`, PBS `.187`, QNAP `.254` | thinkpad `10.21.21.99`, flatcar-nwdesigns `10.21.21.104`, VM 103 `10.21.21.103` |
| Link | — | reached from homelab over a **WireGuard** tunnel |

Key homelab hosts (identity + the WHY; exact specs in `AGENTS.md` §Hosts & VMs):
- **winston** `192.168.100.38` — Minisforum MS-01, i9-13900H, 32 GB. Primary Proxmox
  host. Runs the compute-heavy guests and provides **SR-IOV** (Single-Root I/O
  Virtualization — one physical Intel iGPU split into 7 virtual functions/VFs)
  GPU passthrough to VM 100.
- **reginald** `192.168.100.4` — Zimaboard 832 (Intel N3450 Apollo Lake, 8 GB),
  **7× SSD in a ZFS RAIDZ2 pool**. It is the storage/NFS node, deliberately small
  and low-power; ZFS tuning is sized for 8 GB RAM (see `.claude/rules/infra-lessons.md`).
- **Flatcar VM 100** — `core@192.168.100.100`, Flatcar Container Linux, host to
  **~15 docker-compose stacks** (media stack behind gluetun/ProtonVPN, Nextcloud,
  Immich, Vaultwarden, Forgejo, CouchDB, Technitium secondary, Caddy, Traefik+
  CrowdSec+cloudflared, Homepage). This is where "the services" live.
- **PBS** `192.168.100.187` — Proxmox Backup Server (a VM on the QNAP).
- **QNAP TS-251+** `192.168.100.254` — Technitium DNS primary, MinIO S3, PBS VM
  host, and the daily-4 AM Watchtower for QNAP Container Station.

### INVARIANT — observability lives in nwlab, by design

**There is no Grafana or Prometheus stack in this repo, and adding one is a
regression.** Verified: the only repo mentions of "grafana" are in
`docs/sr-iov/gpu-monitoring.md` and `apps/technitium-exporter/README.md` — **no
compose file, no stack**.

The WHY is a documented decision, not an omission. Commit **`0c6f690`
(2026-04-10)** reverted `08e34b3`, which had added Prometheus+Grafana here. From
the commit body: the observability backend belongs in the **nwlab** segment next
to the otel-collector and ntfy on `flatcar-nwdesigns` (`10.21.21.104`). Keeping
them there **avoids shipping per-cron metrics across the WireGuard tunnel and
removes the need to expose `remote_write` to the homelab LAN.** The relocated
`apps/prometheus` + `apps/grafana` stacks live in the sibling **nwlab** repo.

> Grafana at `/opt/grafana` that you may see referenced in memory notes is the
> **nwlab** instance (`grafana.nwlab.nwdesigns.it`), not a homelab service. If a
> task says "deploy a dashboard", it is an **nwlab** task — wrong repo for this skill.

### INVARIANT — no client production sites on homelab, ever

Client hosting is Cloudways / Aruba / Serverplan / Vercel. The homelab hosts only
personal/self-hosted services. For the client-side portfolio contract, see the
global skill **agency-architecture-contract** (one pointer — do not duplicate it here).

---

## 2. Network contract

Full VLAN table is in `AGENTS.md` §Networks. The contract-level facts:

- **7 VLANs** on the UniFi UCG-Fiber gateway (`192.168.1.1`, UniFi OS 10.1):
  Management (1), Trusted (2), Guests (3), IoT (4), Multimedia (5), **Infra (100,
  `192.168.100.0/20`)**, DMZ (7).
- Plus a **Storage LAN `192.168.200.0/24`** that is **not a gateway VLAN** — it is
  dedicated NFS/backup traffic that never touches the UCG. winston/reginald/VM 100/
  QNAP each hold a `.200.x` address for this path.
- **DMZ macvlan `192.168.7.119`** is Traefik's public foothold.

> Note the Infra network is declared as a **`/20`** (VLAN 100). This width matters
> for the firewall deviation in §5 — a naïve `192.168.100.0/20` admin allowlist
> would sweep in VM 100.

### Two reverse proxies — the split and the WHY

There are **two** proxies on purpose (`AGENTS.md` §Reverse proxy architecture,
around L195-201). Do not collapse them.

| Proxy | Scope | Cert / entry | Security |
|---|---|---|---|
| **Caddy** | **Internal** LAN only, `*.home.disconnesso.com` (~22 services, 3 site files) | wildcard cert via **Cloudflare DNS challenge** (custom Caddy image with the CF-DNS plugin) | LAN-trust; never internet-exposed |
| **Traefik** | **Public** internet-facing services (`nextcloud`/`immich.lushanoperera.com`) | reached via **Cloudflare Tunnel** + cloudflared → DMZ macvlan `.7.119` | **CrowdSec** + bouncer |

WHY split: the internal proxy needs a wildcard cert but no public exposure and no
IPS overhead; the public proxy needs a hardened, CrowdSec-guarded edge on an
isolated DMZ address. One proxy cannot cleanly be both. **Day-2 edge ops (CrowdSec
decisions, bouncer) → project skill `traefik-crowdsec`.** DNS/VLAN routing detail →
sibling **homelab-network-and-dns**.

---

## 3. Repo is the DR source of truth (the contract that outranks the hosts)

**Deployment model:** there is no CI pipeline. Deploy = `rsync`/`scp` the config to
the target host, then reload the service. The **repo→VM path mapping is declared
authoritative** in `AGENTS.md` (§Repo → VM path mapping, ~L84-98). Read that table
for exact source→destination pairs; do not guess deploy paths.

**The contract:** the repo is the disaster-recovery source of truth, because
**`/etc/pve/` is pmxcfs** (the Proxmox cluster filesystem — a synthetic FUSE
filesystem holding all cluster/firewall config) and **pmxcfs is lost on a
bare-metal reinstall**. Verified in `hosts/firewall.md` L16-17:

> `/etc/pve/` is pmxcfs — lost on bare-metal reinstall (same gap that dropped
> vzdump jobs for 5 months in 2025-10). Repo is the DR source of truth.

That **5-month vzdump-gap** (backup jobs silently absent Oct 2025 → Mar 2026,
because they lived only in pmxcfs and were never committed) is the lesson behind
this rule. **Consequence for you:** anything that lives only on a host and not in
this repo is one reinstall away from gone. This is exactly why the untracked
firewall assets (§5) are a live risk — commit them.

---

## 4. Invariants — do not break these without an explicit decision

| # | Invariant | WHY / source |
|---|---|---|
| I1 | **Per-VM firewall stays OFF.** Host-level Proxmox firewall only. | Enabling `firewall=1` on VM NICs breaks multicast/mDNS discovery (DHCP unicast still works, so it looks fine until discovery fails). `hosts/firewall.md` L5-6; `.claude/rules/infra-lessons.md` rows 23-24,42. |
| I2 | **Single production environment. No staging tier.** The homelab *is* prod. | `AGENTS.md`; validate config offline (compose `config`, `pve-firewall compile`, Butane) before applying — there is no safety net. |
| I3 | **Watchtower auto-updates `:latest`; pinned images are the deliberate exceptions.** | nickfedor/watchtower fork. Pins verified in compose: `traefik:v3.3`, `codeberg.org/forgejo/forgejo:14`, `ghcr.io/dictionarry-hub/profilarr:2.0.6`, Immich **digest-pinned** `postgres:14-vectorchord…@sha256:bcf6…` + `valkey/valkey:9@sha256:3eeb…`. Media containers also carry `watchtower.enable=false` + `scope=weekly` labels. Never "un-pin" one of these to chase latest without a reason. |
| I4 | **Flatcar quirks are load-bearing.** `docker-compose` is `/opt/bin/docker-compose` (a standalone binary), because Flatcar's `/usr` is read-only so the compose *plugin* cannot be installed (Butane download fails silently). | `.claude/rules/flatcar-lessons.md` (owns the full quirk list — sysext mechanism, `-` prefix for optional ExecStartPre, whole-stack recreate when a `network_mode: service:X` provider like gluetun is recreated). Do not restate it; read it. |
| I5 | **The working tree runs chronically dirty** (in-flight migrations parked since ~2026-04-30). **Stage explicit paths — never `git add -A`.** | `AGENTS.md` conventions. `git add -A` would sweep half-finished migrations (rustfs, firewall, hardware-purchases) into a commit. |

---

## 5. Deliberate deviations (looks wrong, is intentional — leave it)

**D1 — `admin_sources` narrowed from the original plan.** The firewall plan text
listed `192.168.100.0/20` in the `admin_sources` IPSET for break-glass host-to-host
admin. That was **deliberately narrowed**. Verbatim from `hosts/common/cluster.fw`
(and echoed in `hosts/firewall.md` L47-50):

> DEVIATION FROM PLAN: the plan lists `192.168.100.0/20` in admin_sources … That
> /20 contains VM 100 (192.168.100.100) — the exact lateral-movement source this
> firewall is designed to block. Including it would let a compromised VM 100 SSH
> straight to both hypervisor mgmt planes, defeating the stated threat model.
> Narrowed to trusted + PDM + WG + literal peer IPs. Widen only if a specific
> workflow breaks; document the reason.

So `admin_sources` = Trusted VLAN `192.168.2.0/24` + PDM `.100.106` + peer host IPs
(`.38`, `.4`) + nwlab WG `10.0.0.0/24`, **not** the `/20`. If an admin flow breaks,
widen surgically and document — do not restore the `/20`.

> **Firewall status:** staged at `enable: 0` on both hosts as of 2026-04-20;
> rollout **DEFERRED**. The entire plan (`hosts/firewall.md`, `hosts/common/`,
> `hosts/{winston,reginald}/firewall/`, `scripts/hosts/deploy-firewall.sh`) is
> **untracked** (`git status` `??`) — per §3 that means a reinstall would lose it.
> **Commit the firewall assets before any rollout.** The deploy script never flips
> `enable:` without an explicit `--enable`/`--disable` flag; `--status`/`--diff` are
> read-only. Live enable state is `UNVERIFIED` → `./scripts/hosts/deploy-firewall.sh <host> --status`.

**D2 — MinIO→Garage is DEPRECATED, superseded by MinIO→RustFS.** `docs/migrations/
minio-to-garage.md` still opens "Recommendation: Migrate to Garage" but carries a
header banner: **DEPRECATED 2026-04-10, superseded by `minio-to-rustfs.md`**
(RustFS chosen for memory safety, Apache 2.0, active upstream, MinIO drop-in
compat; **alpha-stage risk accepted, single-node**). Do not execute the Garage
plan. `storage/garage/` and `scripts/migrations/minio-to-garage/` are archived; the
RustFS migration (`docs/migrations/minio-to-rustfs.md`, `storage/rustfs/`,
`scripts/migrations/minio-to-rustfs/`) is the live target and is **untracked WIP**.

> The `storage/rustfs/.env` is blanked (all 3 values empty from the secrets
> migration) and must be repopulated before RustFS use — see sibling
> **homelab-config-and-flags**.

---

## 6. Known doc contradictions — fix these when you touch the area

These are real and will mislead a reader who trusts the doc. Record live truth,
verify before acting.

**C1 — PVE version is inconsistent across three sources.**

| Source | winston | reginald |
|---|---|---|
| `AGENTS.md` L24-25, L46-47 | PVE **9.1.6** | PVE **9.1.5** |
| `hosts/winston/README.md` L10 / `hosts/reginald/README.md` L12 | PVE **9.1.6**, kernel 6.17.13-1 | PVE **9.1.6**, kernel 6.17.9-1 |
| Memory (KG/MB, verified 2026-05-22/23) | PVE **9.2.2**, kernel **7.0.2-6-pve** | PVE **9.2.2**, kernel **7.0.2-6** |

**Live truth (best available):** both hosts + PBS were upgraded to **PVE 9.2.2 /
kernel 7.0.2-6-pve** on 2026-05-22/23 (SR-IOV unblocked once i915-sriov-dkms added
7.0 support). The committed runbook `docs/migrations/pve-9.2-kernel-7-upgrade.md`
corroborates the upgrade happened, but **neither `AGENTS.md` nor the host READMEs
were updated** — they still show 9.1.x. Treat repo version strings as **stale**.
`UNVERIFIED` against a live host from this read-only session →
**verify: `ssh root@<host> 'pveversion; uname -r'`** (winston `.38`, reginald `.4`,
PBS `.187`) before relying on a version, and update the three repo sources to match.

**C2 — `README.md` is stale.** It still describes the S3 layer as "MinIO → Garage
migration" (L13, L113-114, L186-187, L220, L228) — superseded by RustFS per D2. It
also **omits Forgejo, RustFS, Profilarr, and the firewall runbook** entirely.
`AGENTS.md` is current; `README.md` is not — prefer `AGENTS.md`, and correct
`README.md` when you touch storage/services docs.

---

## Provenance and maintenance

Every non-live fact above was read from the repo on 2026-07-05. Re-verify volatile
claims read-only:

```bash
cd /Users/disconnesso/Documents/Projects/homelab

# PVE/kernel live truth (C1) — repo strings are stale
ssh root@192.168.100.38 'pveversion; uname -r'   # winston
ssh root@192.168.100.4  'pveversion; uname -r'   # reginald
ssh root@192.168.100.187 'pveversion; uname -r'  # PBS

# Firewall live enable state + repo-vs-host drift (D1, §5) — read-only
./scripts/hosts/deploy-firewall.sh winston  --status
./scripts/hosts/deploy-firewall.sh reginald --status
./scripts/hosts/deploy-firewall.sh winston  --diff

# No Grafana/Prometheus stack exists here (§1 invariant)
grep -rl grafana --include='*.yml' --include='*.yaml' .   # expect: no compose hits

# Image pins are still pinned (I3)
grep -rniE 'image:.*(traefik|forgejo|profilarr|postgres|valkey)' \
  networking/traefik apps/forgejo apps/immich vms/flatcar-media

# admin_sources deviation still narrowed, not /20 (D1)
sed -n '/IPSET admin_sources/,/IPSET storage_lan/p' hosts/common/cluster.fw

# Untracked firewall + migration WIP still uncommitted (§3, §5)
git status --porcelain

# Doc-contradiction sources (C1, C2)
grep -niE '9\.1\.[0-9]|9\.2\.[0-9]' AGENTS.md hosts/winston/README.md hosts/reginald/README.md
grep -niE 'garage|rustfs|forgejo|profilarr' README.md
```

Cross-references (read, do not duplicate): sibling **homelab-config-and-flags**
(env/secret registry), sibling **homelab-network-and-dns** (DNS/VLAN detail);
project skills **deploy-compose**, **container-manage**, **proxmox-manage**,
**traefik-crowdsec**, **gpu-fix**; repo `.claude/rules/infra-lessons.md` +
`flatcar-lessons.md` + `gpu-sriov-lessons.md`; global skills **infra-runbook**
(generic Proxmox/ZFS/PBS/WireGuard/Docker) and **agency-architecture-contract**
(client portfolio side). `AGENTS.md` remains the authoritative table source for all
exact IPs, ports, paths, and image tags.
