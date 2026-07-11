---
name: homelab-network-and-dns
description: >-
  Design + quirk layer for the homelab's DNS, UniFi network, and WireGuard fabric.
  Read this BEFORE touching Technitium, adding a DNS record, editing dns-compose,
  changing UniFi WiFi/channels/VLANs, or debugging the nwlab cross-site tunnel.
  Answers: how is the 3-node Technitium cluster wired and where does each node
  deploy; why does a new Cloudflare A record pointing at a 192.168.x address stay
  broken for an hour; why do cluster node names show a doubled suffix; how do I
  verify DNS is actually up on all three nodes; how do I run the UniFi inventory
  read-only; why does the UniFi API 403 with a valid token; what's the difference
  between LXC 104 WireGuard and the wg-nwlab tunnel; why did VM 100 fall off the
  network at night (IPv6); why is the 5GHz camera-channel test still open; is the
  PVE 9.2 SDN WireGuard fabric happening. Keywords: Technitium, DNS cluster,
  dig, DoH, dns.home.disconnesso.com, PTR / reverse zone, SOA drift, technitium
  exporter, double-suffix bug, catalog zone, Cloudflare RFC1918 60-minute hold,
  nwlab.nwdesigns.it secondary zone, UniFi UCG-Fiber, unifi-inventory.sh,
  CSRF-in-JWT, Radio AI, DFS channel, mesh AP, WireGuard, wg-nwlab, PDM,
  macOS zombie utun4, SDN fabric, IPv6 NDisc gateway loss.
---

# Homelab Network & DNS — design + quirk layer

Runbook voice. Every command is read-only unless flagged **WRITE**. This skill holds
only what is *specific to this homelab*; generic Proxmox/WireGuard/Docker symptom→fix
lives in the global **infra-runbook** skill, and generic homelab incident history in the
global **nwdesigns-failure-archaeology** skill — cross-reference those, do not restate them.

## When to use / when NOT to use

| Situation | Use |
| --- | --- |
| Wiring/deploying a Technitium node, adding a DNS record, DoH/PTR/SOA/backup/exporter work, DNS quirks | **this skill** |
| Cloudflare public-DNS record pointing at an RFC1918 (192.168/10.x) address | **this skill** (§Cloudflare RFC1918) |
| UniFi API auth, WiFi channels/Radio AI, the read-only inventory script | **this skill** (§UniFi) |
| The nwlab cross-site WireGuard tunnel, macOS VPN weirdness, SDN fabric question | **this skill** (§WireGuard) |
| *Interpreting* a WiFi assessment (co-channel, DFS, utilization thresholds) with guided phases | sibling skill **network-diagnostics** (verbs) — this skill is the design context above it |
| Traefik routing / CrowdSec decisions / bouncer at the public edge | sibling skill **traefik-crowdsec** |
| The VLAN table as authority, "what runs where + WHY", two-proxy rationale, firewall rollout | sibling skill **homelab-architecture-contract** |
| Symptom-first triage ("DNS is down", "site unreachable") routed by symptom row | sibling skill **homelab-debugging-playbook** |
| Generic `wg show` / Proxmox / ZFS / Docker symptom→fix | global **infra-runbook** |
| "Have we seen this before / why is it done this way" chronicle | global **nwdesigns-failure-archaeology** |

Detailed quirk tables already live in the auto-loaded rules `.claude/rules/dns-lessons.md`
(touch `dns/**`), `.claude/rules/networking-lessons.md` (touch `scripts/network/**`), and
`.claude/rules/network-services.md`. This skill is the map over them — it tells you *which*
lesson applies and *why the design is what it is*; the rules hold the full detail.

---

## 1. Technitium 3-node DNS cluster contract

Three nodes, native Technitium zone replication (replaced Pi-hole + Nebula Sync in commit
`00ce21f`). **Each node deploys differently — do not assume Docker everywhere.**

| Node FQDN | IP | Role | Deploy | Config source in repo |
| --- | --- | --- | --- | --- |
| `reginald.dns.disconnesso.home.arpa` | `192.168.100.120` | **Primary** (elevated 2026-07-11) | **Native** install in Debian 12 LXC 120 (reginald) — **no compose** | systemd unit `dns.service` (the Technitium installer names it `dns`, not `technitium`) |
| `qnap.dns.disconnesso.home.arpa` | `192.168.100.254` | Secondary | Docker, QNAP Container Station (compose at `/share/CACHEDEV1_DATA/.qpkg/container-station/data/application/technitium/`) | `dns/technitium/docker-compose.yml` |
| `flatcar.dns.disconnesso.home.arpa` | `192.168.100.100` | Secondary | Docker on Flatcar VM 100, path `/srv/docker/dns/` | `vms/flatcar-media/dns-compose.yml` (NOTE: separate file, **not** `docker-compose.yml`) |

**2026-07-11 elevation:** reginald promoted via `/api/admin/cluster/secondary/promote`
(after upgrading it 14.3→15.4 — promote/join fail cross-version with "DNS Server config
version not supported"; QNAP + Flatcar containers were pulled to latest for the same reason).
QNAP re-joined as secondary via `/api/admin/cluster/initJoin`. The non-catalog zone
`home.disconnesso.com` does NOT ride the catalog — it was moved by zone export/import and
lives only on the primary (.120); other nodes resolve it via the public Cloudflare copy.

Ground truth (verified 2026-07-11): both compose files pin `technitium/dns-server:latest`,
share `DNS_SERVER_DOMAIN=dns.disconnesso.home.arpa`, and read the admin password from env key
**`TECHNITIUM_ADMIN_PASSWORD`**. On Flatcar it lives in `/srv/docker/dns/.env` (root 0600 —
was missing until re-created 2026-07-11); on QNAP the value is inline in the Container
Station compose. **Never** put the value in a skill, rule, or commit.

The QNAP node binds DNS to the management IP on purpose: `192.168.100.254:53:53` (not
`0.0.0.0:53`) to dodge a port-53 clash with QNAP's dnsmasq.

### Deploy a Flatcar-secondary change (WRITE — follow the compose skill)
Use the sibling **deploy-compose** skill for the full rsync→recreate→health-poll loop. In short:
edit `vms/flatcar-media/dns-compose.yml` → `docker run --rm quay.io/coreos/butane` is N/A here,
just validate with `docker compose -f dns-compose.yml config --quiet` → rsync to
`/srv/docker/dns/` → `cd /srv/docker/dns && /opt/bin/docker-compose -f dns-compose.yml up -d`.
Flatcar has no compose plugin — the binary is `/opt/bin/docker-compose`.

### Triple-dig verification (do this after ANY DNS change)
```bash
dig @192.168.100.120 google.com +short   # Reginald primary
dig @192.168.100.254 google.com +short   # QNAP secondary
dig @192.168.100.100 google.com +short   # Flatcar secondary
```
All three must answer.

**UniFi Content Filtering vs Technitium (resolved 2026-07-11):** UniFi CyberSecure
"Content Filter" entries (FAMILY level, added ~2025-07) DNAT'd all port 53 from VLANs
2/3/4/5/7 to the gateway's own coredns:1053 → dnscrypt-proxy (Cloudflare/Google) — so
those VLANs never reached Technitium despite DHCP handing out all three node IPs, and
digs from the Mac were silently answered by the gateway (masked blocking during the
health check; a dig against a bogus IP like `dig @198.51.100.99 x.com` answering =
intercept active). Fixed by DELETING the Content Filter entries for Trusted/Guests/IoT/
Multimedia (UI refuses plain disable: "Filtering must be enabled when Ad Block is
disabled" — delete the entry instead). DMZ keeps its filter deliberately. Enforcement
state visible on the gateway: `ssh root@192.168.1.1 'ipset list dnsfilter'` (members =
filtered subnets). Residual gap: hardcoded-DNS clients + browser DoH now bypass
Technitium — optional follow-ups: per-VLAN DNAT :53 → 192.168.100.120 (Settings →
Routing → NAT), block outbound 853. The compose healthcheck alone is NOT proof: Technitium fails-soft —
the web UI on :5380 can be up while the :53 binding silently failed. That is why the
healthcheck probes both ports (`</dev/tcp/localhost/53 && </dev/tcp/localhost/5380`) and why
you still dig all three externally.

### SOA drift check (are the secondaries in sync?)
`scripts/dns/check-cluster-drift.sh` compares the SOA serial across all three nodes and
writes `/srv/docker/homepage/data/dns-cluster.json` for the Homepage widget. Reads
`TECHNITIUM_ADMIN_PASSWORD` from `/etc/dns-drift.env` on the host. **NOT currently deployed**
(verified 2026-07-11: no `dns-drift-check.timer` on VM 100, no `/etc/dns-drift.env`) — treat
as available tooling, not a running monitor. Note: `home.disconnesso.com` now lives only on
the primary; the cluster-replicated zone to compare is `dns.disconnesso.home.arpa` (catalog
zones answer only from 192.168.100.0/24).

## 2. Technitium hardening deltas (the phase-7 burst, 2026-05)

Six features were added in one hardening burst. Each has a committed doc — read it before
operating that feature.

| Delta | What / where | Doc |
| --- | --- | --- |
| **DoH endpoint** | `https://dns.home.disconnesso.com/dns-query` → Caddy on VM 100 → Technitium primary `192.168.100.120:443` (re-pointed + repaired 2026-07-11: Technitium 15.x web-console port no longer serves `/dns-query`, so the DoH optional protocol was enabled with self-signed cert `/etc/dns/doh.pfx` on the primary). **LAN-only**, not exposed via Cloudflare Tunnel. Caddy MUST use `tls_insecure_skip_verify` (self-signed backend). Block is in `networking/caddy/sites/infrastructure.caddy`. | `docs/dns/encrypted-dns-clients.md` |
| **Reverse PTR zone** | `100.168.192.in-addr.arpa` (Primary) for 192.168.100.0/24. Idempotent seeder `scripts/dns/setup-reverse-zone.sh`. **Gotcha:** the zone does NOT auto-spawn — the "auto-create PTR" toggle only writes into an *existing* reverse zone, so create the zone first. | `docs/dns/reverse-zones.md` |
| **SOA drift check** | §1 above — `scripts/dns/check-cluster-drift.sh` + systemd timer. | — |
| **restic config backup** | **DORMANT** (verified 2026-07-11: no live timer anywhere; Garage target never deployed). Script `scripts/backup/technitium-config-backup.sh` + units exist; env template retargeted to MinIO `.210`. Create the `technitium-config` bucket before activating. | `docs/dns/backup.md` |
| **Prometheus exporter** | Sidecar `apps/technitium-exporter/` (`python:3.12-alpine`, stdlib only, 64 MB). Scrapes the reginald primary API (`.120`), exposes `/metrics` on `127.0.0.1:9628`. **Not running on VM 100** (verified 2026-07-11) — deploy on demand to `/srv/docker/technitium-exporter/`; reuses `TECHNITIUM_ADMIN_PASSWORD`. | `apps/technitium-exporter/README.md` |
| **Blocklist mgmt** | StevenBlack/hosts + Hagezi Pro (~265K entries). | `docs/dns/blocklist-management.md` |

**Exporter → Grafana caveat (open inconsistency):** `grafana-dashboard.json` ships in
`apps/technitium-exporter/`, but the Grafana/Prometheus stack was **reverted off homelab VM 100**
(commit `0c6f690`, 2026-04-10) and relocated to the sibling **nwlab** host `flatcar-nwdesigns`
(`10.21.21.104`, `/opt/grafana`) [memory: reference_flatcar_grafana, 2026-05-15]. The exporter
README still says "append to `/opt/grafana/prometheus/prometheus.yml` on Flatcar" and binds the
exporter to `127.0.0.1:9628` — which a Prometheus on nwlab could not reach. **Before wiring the
exporter into Prometheus, confirm which host actually runs Prometheus today** and whether the
loopback bind needs to change. Do not assume the README is current.

### DNS quirk index (full detail in `.claude/rules/dns-lessons.md`)
- **Double-suffix bug:** if the cluster UI shows names like
  `dns.disconnesso.home.arpa.dns.disconnesso.home.arpa`, that is the known double-suffix bug.
  With the current short-suffix config expect **3 distinct nodes** — verify in the UI before
  treating a naming oddity as a live fault.
- **Catalog member zones are subnet-gated:** A records added to a `catalog:` member zone answer
  only queries from 192.168.100.0/24, not from other VLANs — `overrideCatalogQueryAccess=true`
  did NOT unlock external clients (observed 2026-05-23). For client-visible records use a
  **non-catalog** zone.
- **API login key is literally `pass`:** `urlencode({'pass': ...})`; `pass_=` fails.
- **Cluster-dashboard "token missing":** cross-node UI navigation needs the client to resolve
  `<node>.dns.disconnesso.home.arpa` and hold a session for that node — add `/etc/hosts` entries.
  Queries/replication/blocklists are unaffected; only the UI drilldown breaks.

## 3. Special zone — `nwlab.nwdesigns.it` kept on homelab DNS

**UNVERIFIED against repo** (no repo config found for this zone; source: memory dynamic_profile,
decision on record **2026-04-11**). The homelab Technitium cluster holds `nwlab.nwdesigns.it` as a
**zero-cost secondary resolution path** for the office. Rationale: the office's authoritative DNS
is a managed service with **no admin access**, so a secondary here is the only lever available.
Treat as a deliberate standing decision — do not "clean up" this zone as stray.

## 4. Cloudflare RFC1918 playbook — the 60-minute silent hold

**Symptom:** you create a *public* Cloudflare A record that points at a private
(RFC1918: `192.168.x.x` / `10.x.x.x`) address, and it appears "filtered" / doesn't resolve.

**This is not a bug and not a filter to fight.** Cloudflare applies a silent **~60-minute
validation hold** on new records pointing at RFC1918 space; it resolves itself.

**Playbook:** create the record → **wait 60+ minutes** → re-test. Do **not** open a Cloudflare
ticket, do **not** build a workaround, do **not** flip proxy settings hunting for it.
[source: memory incident, 2026-04-11]

## 5. UniFi network

- **Gateway:** UCG-Fiber at `192.168.1.1`, UniFi OS **10.1** (as of 2026-07-04), **7 VLANs**.
  The authoritative VLAN table + subnet map is in the sibling **homelab-architecture-contract**
  skill / `AGENTS.md` — do not duplicate it here; go there when you need the numbers.

### Read-only inventory (safe to run anytime)
```bash
./scripts/network/unifi-inventory.sh --health     # gateway + networks UP?
./scripts/network/unifi-inventory.sh --clients     # active clients
./scripts/network/unifi-inventory.sh --devices     # UniFi devices
./scripts/network/unifi-inventory.sh --networks    # VLAN config
./scripts/network/unifi-inventory.sh --wifi        # radio details + channel assessment
./scripts/network/unifi-inventory.sh --all --json  # everything, raw JSON
```
Every flag above is **read-only** (verified in the script header, 2026-07-04). Credentials come
from `scripts/network/.env` (keys `UNIFI_HOST` / `UNIFI_USER` / `UNIFI_PASS`; copy `.env.example`).
For guided interpretation of `--wifi` output (co-channel, DFS, utilization thresholds), hand off
to the sibling **network-diagnostics** skill.

### CSRF-in-JWT — why the API 403s with a "valid" token
UniFi OS puts the CSRF token **inside the JWT payload**, not in a separate header. Sending the raw
`TOKEN` cookie as a header = **403**. You must: grab the `TOKEN` cookie → base64-decode its middle
segment → read `.csrfToken` → send it as `X-CSRF-Token`. Both `unifi-inventory.sh` and
`test-5ghz-channel.sh` already implement this decode. For automation use a **local-only admin**
(Restrict to Local Access Only) — SSO accounts force MFA. Writes go to
`PUT /proxy/network/api/s/{site}/rest/device/{id}` with the full `radio_table` array.

### WiFi work history (context for any channel/radio change)
Committed on `main`: 6GHz management + band-steering + Radio AI exclusion (`2eb6cb2`), then a
follow-up scoping Radio-AI rollback removal to excluded APs only (`c261ac0`). Regulatory reality
for Italy (country code 380): only UNII-1 (ch 36–48) and UNII-2/2e (ch 52–140, DFS with 60 s CAC);
**UNII-3 (ch 149+) is unavailable** in UniFi firmware here. Mesh APs are locked to their parent's
5 GHz channel — the **Camera AP is meshed to Salotto**, so it cannot take an independent channel
without Ethernet backhaul.

### OPEN THREAD — 5GHz camera-channel test (not finished)
- Script `scripts/network/test-5ghz-channel.sh` (**untracked** — `git status` shows `??`,
  verified 2026-07-04) sets a 5 GHz channel on the Camera AP, waits for the DFS CAC scan, and
  checks whether the channel was actually adopted (exit 0 adopted / 1 fell back).
- Branch `autoresearch/camera-5ghz-channel` exists but is **stale** — it points at `c261ac0` and
  is **0 commits ahead of main** (verified 2026-07-04). The work never landed on the branch.
- Because the Camera AP is mesh-locked to Salotto's channel (above), independently pinning its
  channel may be futile without Ethernet. Treat this as unresolved; do not present the script's
  result as a settled config. If you resume it, commit the untracked script first (a bare-metal
  reinstall would lose it).

## 6. WireGuard — two tunnels, don't conflate them

There are **two separate** WireGuard setups on winston. Confusing them is the classic mistake:

| Tunnel | Where | Purpose |
| --- | --- | --- |
| **LXC 104** | winston container | Personal / remote-access WG server (wg-easy style). **Not** the site link. |
| **`wg-nwlab`** | winston **host** (`wg-quick@wg-nwlab`, `/etc/wireguard/wg-nwlab.conf`) | Site-to-site to the office **nwlab** |

**Cross-site path (nwlab federation):**
`PDM (LXC 106, .100.106)` → winston MASQUERADE (`10.0.0.5`) → `wg-nwlab` tunnel → nwlab wg-easy →
`nwlab-thinkpad (10.21.21.99)`. Overlay: winston `10.0.0.5/32`, nwlab gateway `10.0.0.1/24`,
AllowedIPs `10.0.0.0/24, 10.21.21.0/24`, MTU 1420. PDM has a static route
`10.21.21.0/24 via 192.168.100.38`; both ends MASQUERADE. Only three flows ride it today: PBS sync
push 04:00, PBS sync reverse 21:00, and PDM → nwlab PVE API `10.21.21.99:8006`. Debug generically
with `wg show` (see global **infra-runbook**).

### macOS zombie utun4 (OPEN, cosmetic)
After the macOS WireGuard app quits, an orphaned `utun4` + stale `0.0.0.0/0` route can block
LiveSync to the LAN. **Workaround** (more-specific route wins):
```bash
sudo route add -net 192.168.100.0/24 192.168.2.1   # WRITE — adjust gateway to your LAN
```
**Not reboot-persistent** — needs a LaunchDaemon or config fix for a permanent solution. Still open.
[source: memory KG WireGuardZombieBug, 2026-03-03]

### PVE 9.2 SDN WireGuard fabric — researched and DEFERRED
Do **not** migrate the hand-rolled tunnel to the PVE 9.2 native SDN WireGuard fabric. Decision on
record **2026-05-27** (commit `104b5c2`, research doc `docs/research/nwlab-pve-9.2-sdn-wireguard.md`):
current `wg-quick` tunnel is ~30 lines, reboot-survivable, debuggable in 5 s, and all three live
flows are pure L3/NAT-tolerant. Phase-1 gains are cosmetic (GUI mgmt, key rotation); costs are real
(coordinated two-datacenter cutover, PBS-sync window risk, a documented SDN-vs-WG boot-order MAC
race). **Revisit only** if: a VM needs same-L2 as a winston VM, a 3rd remote site is added, a new
service won't NAT cleanly, or compliance demands logged key rotation. Until a trigger fires, the
research doc is forward-looking reference only.

## 7. IPv6 NDisc gateway-loss fix (phase 5) — pointer
**Symptom:** VM 100 became unreachable from *other VLANs* at night while same-subnet hosts
(winston) still reached it. **Root cause:** `systemd-networkd` marked `eth0` Failed on an IPv6
Router-Advertisement (NDisc) timeout and flushed *all* routes — including the IPv4 default gateway.
**Fix (committed `1b8dae1`)** in `vms/flatcar-media/butane/flatcar-proxmox-100-docker.bu`, eth0
stanza: `IPv6AcceptRA=no` (static-only network) + `KeepConfiguration=static` (don't drop routes on
transient failure). If you regenerate the Ignition, keep these two lines.

---

## Provenance and maintenance
Read-only re-verify commands, grouped by volatile claim. Run before trusting a stale-looking fact.

```bash
cd /Users/disconnesso/Documents/Projects/homelab

# Cluster contract (nodes, images, env key, deploy paths)
cat dns/technitium/docker-compose.yml vms/flatcar-media/dns-compose.yml
grep -n "Node\|Primary\|Secondary\|Native" AGENTS.md

# Hardening deltas exist + doc locations
ls apps/technitium-exporter/ scripts/dns/ docs/dns/
grep -rn "tls_insecure_skip_verify\|dns-query" networking/caddy/sites/infrastructure.caddy

# UniFi inventory flags are read-only; gateway/OS/VLAN facts
sed -n '1,60p' scripts/network/unifi-inventory.sh
grep -niE "UCG-Fiber|UniFi OS|VLAN" README.md AGENTS.md

# 5GHz thread still open (script untracked, branch stale)
git status --short scripts/network/test-5ghz-channel.sh
git log --oneline -1 autoresearch/camera-5ghz-channel   # expect c261ac0 == main

# WireGuard SDN deferral + IPv6 fix still in place
git show 104b5c2 --stat
grep -n "IPv6AcceptRA\|KeepConfiguration" vms/flatcar-media/butane/flatcar-proxmox-100-docker.bu

# Live DNS state (needs LAN access; SSH/dig are read-only)
dig @192.168.100.254 google.com +short
dig @192.168.100.100 google.com +short
dig @192.168.100.120 google.com +short
```

Live-state claims (which host runs Prometheus today; whether `nwlab.nwdesigns.it` zone still
exists; UniFi OS version) are memory- or LAN-sourced and marked inline — verify on the wire before
acting, never from this file alone.
