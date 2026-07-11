---
name: homelab-firewall-rollout-campaign
description: >-
  Executable battle plan for turning the Proxmox host firewall on winston + reginald
  from staged-untracked (enable:0, nothing live) to Phase B (policy_in: DROP) with
  ZERO lockouts, then committing the live configs back as the DR source of truth.
  Use when: "resume the firewall rollout", "enable the Proxmox firewall", "the firewall
  is staged at enable:0", "flip the host firewall on / to DROP", "Phase A / Phase B",
  "policy_in DROP", "pve-firewall", "host.fw / cluster.fw", "admin_sources", "dead-man
  cron / .fw-deadman-armed", "I locked myself out of Proxmox / SSH is filtered", "break
  glass on winston/reginald", "datacenter kill switch", "deploy-firewall.sh --enable /
  --status / --diff", "close the VM 100 lateral-movement gap". Homelab-only; winston =
  192.168.100.38, reginald = 192.168.100.4.
tools: Bash, Read
---

# Homelab Firewall Rollout Campaign

A multi-day, decision-gated live-network operation. The single biggest risk is **locking
yourself out of both hypervisors**. Read this whole file before touching a host. Every
phase transition is user-confirmed and reversible.

## What this campaign delivers

Take the Proxmox VE host firewall on **winston** (`192.168.100.38`) and **reginald**
(`192.168.100.4`) from its current state — configs written but staged at `enable: 0`,
**nothing live, and the whole plan untracked in git** — to a live default-deny inbound
posture (`policy_in: DROP`) on both hosts, in this order: **reginald first, then winston
24 h later**, with the repo left as the disaster-recovery source of truth.

**Why it exists (threat model):** VM 100 (`192.168.100.100`) runs the internet-facing
surface — Traefik DMZ, Cloudflared tunnel, Nextcloud, Immich, Vaultwarden. Today nothing
stops a compromised VM 100 from moving laterally to either hypervisor's management plane
(SSH :22, PVE webui :8006) or to PBS. The host firewall closes that gap. The UniFi gateway
only filters *between* VLANs; intra-VLAN-100 traffic is wide open until this ships.
[`hosts/firewall.md` L1-7; `AGENTS.md` Security posture]

## When NOT to use this skill (route elsewhere)

| Situation | Use instead |
| --- | --- |
| Generic `pve-firewall` / Proxmox / ZFS / PBS symptom→fix (not this rollout) | global **infra-runbook** |
| How a change gets classified, gated, signed off, promoted to "prod" | global **nwdesigns-change-control** |
| The anatomy of `deploy-firewall.sh` and homelab deploy mechanics generally | sibling **homelab-run-and-operate** |
| Negative-test doctrine, what counts as "verified", acceptance evidence | sibling **homelab-validation-and-qa** |
| WHY the VLAN/IPSET topology and the `admin_sources` deviation are shaped this way | sibling **homelab-architecture-contract** |
| Per-VM firewall, LXC `firewall=1`, outbound filtering | **out of scope — deferred**, see `hosts/firewall.md` "Deferred" |

This skill owns only the *campaign* — the ordered, gated live rollout and its guardrails.

## Glossary (defined once)

- **host.fw** — per-node Proxmox firewall file. Repo: `hosts/<host>/firewall/host.fw`.
  Live: `/etc/pve/nodes/<node>/host.fw`. Holds `enable:`, `policy_in:`, and the node's rules.
- **cluster.fw** — datacenter-wide file (aliases, IPSETs, the `admin_access` group, and the
  master `enable:`). Repo: `hosts/common/cluster.fw`. Live: `/etc/pve/firewall/cluster.fw`.
- **Two-enable rule** — the firewall is live **only when `cluster.fw enable: 1` AND
  `host.fw enable: 1`**. Flipping cluster.fw to 0 disables the firewall on that host
  instantly, regardless of host.fw. This is the primary kill switch.
- **Phase A** — `enable: 1` + `policy_in: ACCEPT` + `log_level_in: info`. Firewall loaded
  and logging, but nothing is dropped. A safe observation window ("log-first").
- **Phase B** — `policy_in: DROP`. Default-deny inbound; only the explicit ACCEPT rules pass.
  This is the actual security outcome.
- **Dwell** — a mandatory wait under a new policy (30 min per phase; 24 h between reginald-B
  and winston) while you watch logs for unexpected traffic before committing further.
- **Dead-man cron** — a root cron line that auto-disables the firewall if `/root/.fw-deadman-armed`
  is older than 600 s. Arm (`touch`) immediately before an enable flip; disarm (`rm`) only after
  verification passes. This is your lockout insurance.
- **pmxcfs** — the `/etc/pve` cluster filesystem. **Lost on bare-metal reinstall** — the same
  gap that silently killed vzdump for 5 months (Oct 2025–Mar 2026). That is why committing the
  repo copy is not optional. [`hosts/firewall.md` L16-18; `infra-lessons.md` PBS section]
- **admin_sources** — the IPSET of who may reach the admin plane (see Invariant #4).
- **standalone nodes** — winston and reginald are **not clustered**. cluster.fw does **not**
  auto-sync between them; the deploy script copies it to each host separately.

## Current state (as of 2026-07-05)

| Fact | Value | Verify (read-only) |
| --- | --- | --- |
| Plan + configs + script | Present in working tree, **git status `??` (untracked)** | `git status --porcelain hosts/ scripts/hosts/deploy-firewall.sh` |
| `cluster.fw` master enable | `enable: 0` (repo) | `grep '^enable:' hosts/common/cluster.fw` |
| `host.fw` (both) | `enable: 0`, `policy_in: ACCEPT`, `log_level_in: info` | `grep -E '^(enable|policy_in):' hosts/*/firewall/host.fw` |
| Live firewall state on hosts | **UNVERIFIED** — never confirmed whether configs were ever copied | `./scripts/hosts/deploy-firewall.sh reginald --status` |
| Documented status | staged at enable:0, **DEFERRED since ~2026-04-30** | `AGENTS.md` Security posture (says "as of 2026-04-20") |
| PVE version | **3-way contradiction, unsettled** (see Phase 1) | `ssh root@<host> 'pveversion; uname -r'` |

Historical resume pointer (memory): global plan `~/.claude/plans/should-i-have-the-typed-moore.md`.
UNVERIFIED and superseded — **`hosts/firewall.md` in this repo is the authoritative runbook.** Do
not act off the old plan file.

## Invariants — never violate these

1. **Never `git add -A`.** The tree is chronically dirty (MinIO→RustFS, hardware research).
   Stage explicit paths only. [`AGENTS.md` Gotchas]
2. **Every enable/policy flip is user-confirmed.** `settings.json` autoMode requires confirmation
   for *all* SSH write commands (config writes, `sed` on host.fw/cluster.fw, `pve-firewall reload`).
   Enable and DROP flips are SSH writes — never auto-approve them.
3. **Never close the active SSH session during a flip.** Conntrack preserves established
   connections across `pve-firewall reload`; a new policy that would block you only bites a
   **fresh** connection. Always verify from a *second* terminal. [`infra-lessons.md`]
4. **`admin_sources` must NOT contain `192.168.100.0/20`.** That /20 contains VM 100 — the exact
   lateral-movement source this firewall blocks. The committed `cluster.fw` deliberately narrows
   it to Trusted VLAN + PDM + WG + literal peer IPs. Widen only if a concrete admin workflow
   breaks, and document why. [`cluster.fw` L23-35]
5. **No explicit catch-all `IN DROP` in host.fw.** An explicit drop rule fires *before* `policy_in`
   evaluates, so it would silently turn Phase A into Phase B and destroy the log-first dwell. Deny
   happens at the `policy_in` layer only. [`host.fw` comments; `hosts/firewall.md` R3v]
6. **Per-VM / LXC firewall stays OFF.** `firewall=1` on a VM NIC breaks multicast/mDNS. Host-level
   filtering is the whole design. [`hosts/firewall.md` L5-7; `infra-lessons.md`]
7. **`deploy-firewall.sh` never flips `enable:` without `--enable`/`--disable`.** Copy+compile is
   the default. This is deliberate — do not add implicit enabling.
8. **The deploy script's `safety_check` refuses to clobber a live Phase B with a staged Phase A**
   (`policy_in: DROP` remote vs `ACCEPT` repo) unless you pass `--force`. Do not `--force` past it
   without understanding you are reverting Phase B.

## Phase 0 — Commit gate (DR protection FIRST) 🔴 do before anything live

The entire rollout plan is untracked. A bare-metal reinstall today — the exact scenario
`hosts/firewall.md` warns about — would lose it. **Commit before you touch a host.**

**Human decision required first (laptop-IP hardcode):** `cluster.fw` has a placeholder for your
laptop's literal IP as a belt-and-braces admin source. Resolve it now.

Ranked options:

| # | Approach | Tradeoff | Evidence |
| --- | --- | --- | --- |
| 1 ✅ | Add your current laptop IP as a literal in `[IPSET admin_sources]` alongside `192.168.2.0/24` | Survives VLAN-routing hiccups; must update if DHCP moves you | `cluster.fw` L37-39; `hosts/firewall.md` safeguard #4 |
| 2 | Rely on `192.168.2.0/24` (Trusted) range only, skip the literal | One fewer thing to maintain; **loses the belt-and-braces layer** if inter-VLAN routing is the thing that breaks | — |
| 3 | Reserve a static DHCP lease for the laptop, then hardcode that | Most robust; extra UniFi step now | — |

Get the literal to add, run **on the laptop**:
```bash
ip route get 192.168.100.4 | awk '{print $7}'   # → your source IP toward reginald
```
Edit `hosts/common/cluster.fw`, add the literal under `[IPSET admin_sources]` (e.g. `192.168.2.47`).

Then stage EXPLICIT paths and commit:
```bash
cd /Users/disconnesso/Documents/Projects/homelab
git add hosts/firewall.md hosts/common/cluster.fw \
        hosts/winston/firewall/host.fw hosts/reginald/firewall/host.fw \
        scripts/hosts/deploy-firewall.sh
git status --porcelain hosts/ scripts/hosts/deploy-firewall.sh   # confirm ONLY these are staged
git commit    # Conventional Commit, e.g.:
# feat(firewall): track staged Proxmox host firewall rollout (enable:0)
#
# Why: plan+configs+script were untracked; pmxcfs is lost on reinstall so the
# repo copy is the only DR source. How: staged explicit firewall paths, added
# laptop literal to admin_sources; still enable:0, nothing flipped live.
```

**Gate — PROCEED only if:** `git status` shows the five firewall paths staged and nothing else;
the commit lands; `cluster.fw` still shows `enable: 0` and both `host.fw` still `enable: 0`.
**ABORT if:** anything unrelated got staged (`git restore --staged <path>` and redo) — you must
not sweep in the RustFS/hardware WIP.

## Phase 1 — Ground-truth gate (READ-ONLY)

Confirm reality before planning any flip. **No writes in this phase.**

```bash
# Repo-vs-host drift and current live enable/policy state (read-only)
./scripts/hosts/deploy-firewall.sh reginald --status
./scripts/hosts/deploy-firewall.sh winston  --status
./scripts/hosts/deploy-firewall.sh reginald --diff
./scripts/hosts/deploy-firewall.sh winston  --diff

# Settle the PVE version contradiction (three-way, unsettled):
#   AGENTS.md: winston 9.1.6 / reginald 9.1.5
#   host READMEs: both 9.1.6
#   memory (UNVERIFIED): both PVE 9.2.2, kernel 7.0.2-6-pve after 2026-05-22/23 upgrade
ssh root@192.168.100.4  'pveversion; uname -r'
ssh root@192.168.100.38 'pveversion; uname -r'
```

**Expected observations & what they mean:**

| Observation | Meaning → action |
| --- | --- |
| `--status`: cluster.fw & host.fw both `enable: 0` | Clean starting line → proceed |
| `--status`: any `enable: 1` present | **Firewall is already partly live** — STOP, reconcile with STATE.md/history before flipping anything |
| `--status`: "deadman armed" | A prior aborted run left it armed → investigate, `rm /root/.fw-deadman-armed` only after you understand why |
| `--diff`: empty | Host already matches repo → configs were deployed before |
| `--diff`: non-empty | Drift — Phase 3 `deploy` (copy+compile) reconciles it; note the drift in STATE.md |
| `pveversion` differs from AGENTS.md | **Update `AGENTS.md` + `hosts/<host>/README.md`** to the real version (separate docs commit) before proceeding |

**Gate — PROCEED only if** live state is understood and any doc/version drift is recorded (fix docs
now or log it in STATE.md). **ABORT if** `--status` shows an unexpected live-enabled firewall you
cannot explain — that means someone was mid-rollout; do not double-drive it.

## Phase 2 — Pre-flight gate (HUMAN-ONLY, at the physical hosts)

An AI/agent **must stop here and hand off to a human**. These steps need physical presence and
cannot be safely automated. Complete the checklist from `hosts/firewall.md` "Pre-flight":

- [ ] Paper/second-device printout of the recovery commands (below) — if your laptop SSH is what
      breaks, blind recovery needs commands in eyeball range.
- [ ] **Two** SSH terminals open per host, both verified working.
- [ ] **Console verified**: walk to the box, confirm HDMI output + USB keyboard, save a logged-in
      session. Winston = Minisforum MS-01; reginald = Zimaboard 832. Both physically accessible.
- [ ] Laptop IP confirmed present in committed `admin_sources` (Phase 0).
- [ ] **Break-glass ladder rehearsed** — prove the datacenter kill switch works on a throwaway
      host or dry-read it, ordered by preference:

  | Rank | Method | Independent? |
  | --- | --- | --- |
  | 1 | Wait for dead-man cron (≤10 min if armed + unreachable) | yes |
  | 2 | Physical console → kill switch (below) | yes |
  | 3 | Second held-open SSH (conntrack survives) → `pve-firewall stop` | yes, if session alive |
  | 4 | Out-of-band via nwlab WG (`10.0.0.0/24`) | only if tunnel up |
  | 5 | PDM webui | **NO — PDM is LXC 106; if admin plane is cut PDM is blind. Never rely on it.** |

  **Datacenter kill switch** (memorise / print — instantly disables FW on that host, run per host):
  ```bash
  pve-firewall stop
  sed -i 's/enable: 1/enable: 0/' /etc/pve/firewall/cluster.fw
  ```

- [ ] Dead-man cron line installed on the target host (arm/disarm is per-phase in Phase 3):
  ```
  * * * * * root [ -f /root/.fw-deadman-armed ] && \
    [ $(($(date +%s) - $(stat -c %Y /root/.fw-deadman-armed))) -gt 600 ] && \
    pve-firewall stop && \
    sed -i 's/enable: 1/enable: 0/' /etc/pve/firewall/cluster.fw && \
    rm /root/.fw-deadman-armed
  ```
  Confirm it's there: `ssh root@<host> grep fw-deadman /etc/crontab`

**Gate — PROCEED only if** every box is ticked and the kill switch is proven reachable. **ABORT if**
console output cannot be confirmed on either box — without console you have no independent recovery.

## Phase 3 — Reginald Phase A (log-first, ACCEPT + log)

Reginald first: smallest blast radius (no VMs; only LXC 120 DNS + LXC 123 Samba, whose traffic
terminates in guest veths, not on the hypervisor). Follow `hosts/firewall.md` steps **R0–R5**;
the load-bearing gate is R3/R3v.

```bash
# R0 — stage configs (copy + compile, enable stays 0). Confirmed SSH write.
./scripts/hosts/deploy-firewall.sh reginald

# R1 — simulate BEFORE any flip (must all resolve ACCEPT):
ssh root@192.168.100.4 pve-firewall compile          # 0 errors REQUIRED
ssh root@192.168.100.4 pve-firewall simulate --from <laptop_ip>     --to 192.168.100.4:22   --protocol tcp
ssh root@192.168.100.4 pve-firewall simulate --from 192.168.100.106 --to 192.168.100.4:8006 --protocol tcp
ssh root@192.168.100.4 pve-firewall simulate --from 192.168.200.100 --to 192.168.200.4:2049 --protocol tcp  # NFS

# R2 — arm the dead-man IMMEDIATELY before enabling:
ssh root@192.168.100.4 touch /root/.fw-deadman-armed

# R3 — make it live. BOTH enables required (two-enable rule). Do it by hand on the host,
#      NOT via `deploy-firewall.sh --enable` (see WRONG PATHS #1). Still policy_in: ACCEPT.
ssh root@192.168.100.4 'sed -i "s/^enable:.*/enable: 1/" /etc/pve/firewall/cluster.fw \
                                       /etc/pve/nodes/reginald/host.fw && pve-firewall reload'
```

**R3v — verify from a FRESH SSH session** (not the one held open), then **dwell 30 min** tailing logs:
```bash
ssh root@192.168.100.4 hostname                                   # admin SSH still works
ssh root@192.168.100.106 'ssh root@192.168.100.4 hostname'        # via PDM jump
ssh core@192.168.100.100 'ls /mnt/media /mnt/ncdata /mnt/immich'  # NFS from Flatcar
dig @192.168.100.120 google.com +short                           # LXC 120 DNS
ssh root@192.168.100.4 tail -n 100 /var/log/pve-firewall.log     # watch 30 min for surprises
```

**Expected observations & meaning:**

| Observation | Meaning → action |
| --- | --- |
| `compile` = 0 errors, all `simulate` = ACCEPT | Safe to flip → R2/R3 |
| any `simulate` = DROP/REJECT | **DO NOT FLIP** — a needed source is missing from `admin_sources`/`storage_lan`. Fix the repo config, redeploy, re-simulate |
| after R3, fresh SSH works, NFS/DNS green, log shows only known traffic | Phase A healthy → R4/R5, then Phase B |
| fresh SSH **fails** | Lockout starting → do NOT panic-close the held session; use it or the kill switch; dead-man auto-recovers in ≤10 min |
| log shows unexpected legit traffic (some client you forgot) | Add an ACCEPT rule in the repo host.fw, redeploy, before Phase B — this is exactly what the dwell is for |

```bash
# R4 — verification passed: disarm. R5 — re-arm before Phase B.
ssh root@192.168.100.4 rm /root/.fw-deadman-armed
ssh root@192.168.100.4 touch /root/.fw-deadman-armed
```

**Gate — PROCEED to Phase 4 only if** Phase A dwelled 30 min clean and R5 re-armed. **ABORT/ROLLBACK
if** anything broke: `pve-firewall stop` on the host, then the Rollback command (bottom) resets both
enables to 0. Fix the config in the repo, recommit, restart at R0.

## Phase 4 — Reginald Phase B (policy_in: DROP) + negative tests

Follow `hosts/firewall.md` **R6–R7**.

```bash
# R6 — flip reginald host.fw to DROP and reload (dead-man still armed from R5):
ssh root@192.168.100.4 'sed -i "s/^policy_in:.*/policy_in: DROP/" /etc/pve/nodes/reginald/host.fw \
                                       && pve-firewall reload'
```

**Verify (fresh session) — positive AND negative. Negative tests are mandatory** (they prove the
policy is actually effective; doctrine in sibling **homelab-validation-and-qa**):
```bash
# POSITIVE — these MUST still work:
ssh root@192.168.100.4 hostname
ssh core@192.168.100.100 'ls /mnt/media'                         # NFS
dig @192.168.100.120 google.com +short                           # DNS
smbclient -L //192.168.100.123 -N                                # Samba (LXC 123)
ssh root@192.168.100.4 iptables -L PVEFW-HOST-IN -nvx | head -40 # allows >0, DROP counter >0

# NEGATIVE — from a host on a VLAN NOT in admin_sources (IoT .4.x / Guests .3.x / DMZ .7.x),
# these MUST show "filtered" (they showed OPEN in Phase A — that is not a failure then):
nmap -Pn -p 22,8006 192.168.100.4    # → filtered
```

**Expected observations & meaning:**

| Observation | Meaning → action |
| --- | --- |
| positive all green, `nmap` = **filtered**, DROP counter climbing | Phase B effective → **dwell 24 h**, then R7 disarm |
| `nmap` shows **open** after R6 | policy_in did not take — recheck `host.fw policy_in: DROP` and that cluster.fw enable:1; do not proceed to winston |
| a positive check fails | a legit source is being dropped — add its ACCEPT rule in repo, redeploy, re-verify (or rollback if you can't fix fast) |

```bash
# R7 — after 24 h clean: ssh root@192.168.100.4 rm /root/.fw-deadman-armed   # reginald DONE
```

**Gate — PROCEED to winston only after** reginald has been stable under DROP for **24 h**
(positive green, negative filtered). Update STATE.md with the dwell-start timestamp so the wait
survives a session boundary. **ABORT/ROLLBACK** with the bottom command if DROP breaks anything.

## Phase 5 — Winston Phase A → B (same pattern, extra verifications)

Repeat Phases 3–4 for winston (`root@192.168.100.38`, node `winston`) — steps **W0–W7**, identical
structure. `--from` for the NFS simulate is N/A (winston isn't the NFS server); keep the SSH/8006
simulates. Winston carries the real production surface, so add these **winston-specific** checks at
W3v and after W6:

```bash
curl -I https://nextcloud.lushanoperera.com        # → 200 OK (Cloudflare Tunnel → Traefik path intact)
curl -I http://192.168.4.102:8123                  # Home Assistant (VM 102) reachable
# LXCs 104 (WireGuard) / 105 (Plex) / 106 (PDM): start/stop/console via PDM webui
ssh root@192.168.100.38 'vzdump 106 --storage pbs-backupnas --mode snapshot --remove 0'  # PBS path works
```

**Expected observations & meaning:**

| Observation | Meaning → action |
| --- | --- |
| `curl -I nextcloud` = 200 | public ingress unaffected by the new host policy → good |
| `curl` hangs / 5xx | the DMZ/tunnel path is being filtered — check that Traefik's flows aren't caught; rollback if unresolved |
| `vzdump 106` completes | PBS backup path (Storage LAN) still open → good |
| `vzdump` errors on storage | PBS/Storage-LAN flow blocked — verify `pbs_host`/storage_lan rules before continuing |

**Gate — campaign COMPLETE when** winston is stable under DROP (positive green, negative filtered,
Nextcloud 200, vzdump ok). Then do Phase 6.

## Phase 6 — Reconcile & commit live configs (graduate to DR truth)

Per `hosts/firewall.md` "Post" + "Deferred". The final live state is `cluster.fw enable: 1` and both
`host.fw` `enable: 1` + `policy_in: DROP`. Bring the repo to match so it is the true DR source:

```bash
./scripts/hosts/deploy-firewall.sh winston  --diff   # should be empty EXCEPT the enable/policy you flipped live
./scripts/hosts/deploy-firewall.sh reginald --diff
# Update the repo copies to the live values (enable:1, policy_in: DROP), then:
git add hosts/common/cluster.fw hosts/winston/firewall/host.fw hosts/reginald/firewall/host.fw \
        hosts/firewall.md .claude/rules/infra-lessons.md
git commit   # docs: firewall live on both hosts (Phase B DROP); record dwell surprises
```
Also update `AGENTS.md` "Security posture" (was "staged at enable:0 as of 2026-04-20") and add any
dwell surprises to `.claude/rules/infra-lessons.md` "Proxmox Host Firewall".

## FENCED WRONG PATHS — do not re-walk these

1. **`deploy-firewall.sh --enable` does NOT make the firewall live, and re-running plain `deploy`
   after go-live silently disables it.** `--enable` copies configs (including `cluster.fw` at
   `enable: 0`) then flips only `host.fw` — so the two-enable rule is unmet and the firewall stays
   off. Worse: after you've flipped `cluster.fw enable: 1` live, a later `deploy` re-copies the
   repo's `enable: 0` cluster.fw and kills the firewall (fail-open, not a lockout, but a silent
   security regression). `safety_check` only guards Phase-B→A host.fw clobber, **not** cluster.fw
   enable. → Flip both enables **by hand on the host** (Phase 3 R3); don't re-run `deploy` after
   cluster.fw is live. [`deploy-firewall.sh` `deploy()`/`flip_enable()`/`safety_check()`]
2. **Putting `192.168.100.0/20` in `admin_sources`** (the original plan text). It contains VM 100 —
   the attack source — so it would let a compromised VM 100 SSH straight to both admin planes,
   defeating the entire threat model. Deliberately removed. [`cluster.fw` L23-29] (Invariant #4)
3. **Adding an explicit catch-all `IN DROP` to host.fw** to "be safe" during Phase A. It fires
   before `policy_in`, so it silently converts Phase A into Phase B and destroys the log-first
   dwell. Deny only at `policy_in`. [`host.fw` comment] (Invariant #5)
4. **Testing the new policy from the SAME SSH session you flipped from.** Conntrack keeps it alive,
   so it "works" even when a new connection would be blocked — masking a real lockout. Always test
   from a fresh second terminal. (Invariant #3)
5. **Reading the Phase-A `nmap` as a failure.** In Phase A (`policy_in: ACCEPT`) ports 22/8006 show
   **open**, not filtered — correct. "filtered" is only expected after the Phase B DROP flip.
6. **Enabling per-VM / LXC `firewall=1`.** Breaks multicast/mDNS discovery. Host-level FW only.
   (Invariant #6)
7. **Enabling outbound/egress filtering on the hypervisor.** Rejected: maintenance pain, no real
   blast-radius reduction (root already owns the box if the attacker is there). Outbound stays
   ACCEPT. [`hosts/firewall.md` L63-64]
8. **Treating PDM webui as break-glass.** PDM is LXC 106 on winston — if the admin plane is cut,
   PDM is blind too. It is rank 5 / non-independent. (Phase 2 ladder)
9. **`git add -A`.** Sweeps in unrelated RustFS/hardware WIP. Explicit paths only. (Invariant #1)

## STATE ledger — survive multi-day dwells

This repo has no STATE.md. **Create one so the 30-min and 24-h dwells survive session boundaries**
(you cannot hold a session open for 24 h). The skill folder is read-only for writes other than this
file; the operator creates the ledger at the repo root (or `hosts/firewall-STATE.md`). Template:

```markdown
# Firewall Rollout — STATE ledger
Last updated: <ISO8601> by <who/agent>

Current phase: <0..6>
Reginald: <staged | Phase A armed HH:MM | Phase A clean | Phase B armed HH:MM | Phase B DONE>
Winston:  <not started | ...>
Dead-man armed on: <host | none>
Dwell clock: reginald-B started <ISO8601>, 24 h elapses at <ISO8601>

## Evidence (paste command outputs)
- R1 compile/simulate: <...>
- R3v verification + 30-min log tail: <...>
- R6 nmap negative test: <...>

## Deviations from hosts/firewall.md
- <e.g. added client X ACCEPT rule after Phase-A log surprise>
```

Read this ledger FIRST when resuming. Update it after **every** gate.

## Promotion / change control

Each phase transition is a high-risk production change on live infrastructure. Classification,
approval, and sign-off doctrine lives in global **nwdesigns-change-control** — apply it; do not
restate it here. Homelab-specific deltas:

- There is **no CI**. Verification is the 4-step manual chain in `AGENTS.md` "Verification"
  (syntax validate → `shellcheck` → SSH apply/test → health check) plus this campaign's per-gate
  positive **and** negative tests (sibling **homelab-validation-and-qa**).
- `settings.json` autoMode makes every SSH write (enable/policy flip, reload) a **confirmed** step —
  the human is the change-approval gate; there is no auto-merge path.
- A candidate config graduates to "production DR truth" only at **Phase 6**, when the live
  `enable: 1` + `policy_in: DROP` values are committed back to the repo. Until then the repo staying
  at `enable: 0` is intentional (fail-safe if someone redeploys mid-rollout).

## Success = measurable

Done when ALL hold:
- [ ] Reginald AND winston: `cluster.fw enable: 1` + `host.fw enable: 1` + `policy_in: DROP` live.
- [ ] Positive checks green on both: admin SSH, PVE :8006, PDM jump, NFS (reginald), DNS, Samba,
      `curl -I https://nextcloud.lushanoperera.com` = 200, `vzdump 106` completes.
- [ ] Negative check on both: `nmap -Pn -p 22,8006 <host>` from a non-admin VLAN → **filtered**.
- [ ] Reginald ran ≥24 h under DROP before winston started; each phase dwelled ≥30 min.
- [ ] Dead-man disarmed on both; no `/root/.fw-deadman-armed` left behind.
- [ ] Repo committed with the live configs (Phase 0 initial + Phase 6 final); `--diff` clean.
- [ ] `AGENTS.md` Security posture + `infra-lessons.md` updated; STATE.md reflects completion.

## Open work as of 2026-07-05

- **Everything.** The campaign has not started: plan is untracked (Phase 0 not done), nothing is
  live on either host, and it's been DEFERRED since ~2026-04-30.
- **PVE version contradiction unsettled** (AGENTS.md vs host READMEs vs memory's 9.2.2/kernel-7).
  Settle in Phase 1 and fix the docs.
- **Live host firewall state UNVERIFIED** — no confirmation the configs were ever copied to
  `/etc/pve`. First real action is Phase 1 `--status`/`--diff` (read-only).

## Rollback (any point, either host)

```bash
ssh root@<host> 'pve-firewall stop; sed -i "s/enable: 1/enable: 0/" \
  /etc/pve/nodes/<node>/host.fw /etc/pve/firewall/cluster.fw'
```
Instantly fail-open. Then fix the repo config, recommit, restart from the failed phase's R0/W0.

## Provenance and maintenance

Re-verify volatile claims READ-ONLY before acting:
- Untracked/staged state: `cd /Users/disconnesso/Documents/Projects/homelab && git status --porcelain hosts/ scripts/hosts/deploy-firewall.sh`
- Repo config values: `grep -E '^(enable|policy_in):' hosts/common/cluster.fw hosts/*/firewall/host.fw`
- Deploy script flags/safety: `sed -n '1,20p;79,130p' scripts/hosts/deploy-firewall.sh`
- Live firewall + deadman state: `./scripts/hosts/deploy-firewall.sh reginald --status && ./scripts/hosts/deploy-firewall.sh winston --status`
- Repo-vs-host drift: `./scripts/hosts/deploy-firewall.sh <host> --diff`
- PVE versions (settles the contradiction): `ssh root@192.168.100.4 'pveversion; uname -r'` and `ssh root@192.168.100.38 'pveversion; uname -r'`
- Documented status: `AGENTS.md` "Security posture"; full runbook `hosts/firewall.md`; lessons `.claude/rules/infra-lessons.md` "Proxmox Host Firewall".
- autoMode confirmation rules: `.claude/settings.json`.
