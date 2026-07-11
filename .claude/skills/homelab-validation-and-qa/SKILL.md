---
name: homelab-validation-and-qa
description: >
  The homelab's verification doctrine — how to PROVE a change is safe and worked, in a repo with
  ZERO tests and ZERO validation CI. Manual 4-step gate is the only safety net. Use before OR after
  touching any config/script/stack on winston, reginald, or Flatcar VM 100. Triggers — "is this
  safe to deploy", "did the deploy work", "verify the change", "how do I know it's healthy",
  "the compose came up but is it working", "validate this before I scp it", "is the firewall
  actually blocking", "did the backup really run", "confirm the VPN is up", "check DNS on all three
  nodes", "post-deploy health check", "how do I test infra changes here", "there's no CI, how do I
  verify", "shellcheck", "docker compose config", "butane strict", "pve-firewall compile", "negative
  test", "nmap filtered", "prove the blocked path fails", "gluetun VPN IP", "forwarded_port",
  "exportfs", "PBS snapshot verify", "read-only probe first". NOT for generic Proxmox/ZFS/PBS
  symptom→fix (use global infra-runbook) and NOT for client-site/portfolio QA (use global
  agency-validation-and-qa).
---

# Homelab Validation & QA

## What this is / What it is NOT

This repo has **no test toolchain, no lint config, and no validation CI** (verified 2026-07-04:
zero `test/` dirs, no `.shellcheckrc`/eslint/pre-commit, and the only GitHub Actions are
`claude.yml` + `claude-code-review.yml` — Claude review bots, not build/lint/test). **Nothing
automated will catch your mistake.** Verification here is a manual 4-step discipline that you MUST
follow by hand. This skill is that discipline, assembled from the per-subsystem gate skills.

| Use this skill when… | Use instead… |
|---|---|
| Verifying an infra change to homelab (winston/reginald/Flatcar VM 100) is safe + worked | — |
| Generic Proxmox/ZFS/PBS/WireGuard/Docker symptom→fix | global **infra-runbook** |
| Verifying a client WordPress/Next.js deploy, Figma QA, quality-gate scoring | global **agency-validation-and-qa** (different world; borrow only its evidence-standards mindset) |
| The 4-step Verify→Reconcile process shape itself | global **workflow.md** rule |

Global doctrine (quality-gate thresholds, comprehension gate, self-review→Gemini→Codex chain) lives
in the global library — this skill holds **only** the homelab-specific gates, commands, and IPs.

---

## RULE 0 — Read-only probe BEFORE you mutate

Every subsystem has a read-only probe. Gather evidence FIRST, then decide. `.claude/settings.json`
autoMode enforces this: **SSH read commands are auto-safe; every SSH write (compose up/down,
systemctl restart, config write, `--enable`) requires explicit confirmation** — and a defined set of
destructive commands is NEVER auto-approved. The full never-auto-approve list is owned by sibling
**homelab-config-and-flags §5c**; consult it rather than a copy here.

| Subsystem | Read-only probe (safe, no confirmation) |
|---|---|
| Host firewall | `./scripts/hosts/deploy-firewall.sh <host> --status` and `--diff` (repo-vs-host drift) |
| UniFi network | `./scripts/network/unifi-inventory.sh --health\|--clients\|--networks\|--devices\|--wifi` |
| Containers | `ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}"'` |
| Firewall state on host | `pve-firewall status`; `grep -E '^enable:' /etc/pve/firewall/cluster.fw` |
| Backups | global-cite the **backup-status** skill (PBS + Restic + S3 probes) |

Never open with a mutating command. If you cannot name the read-only probe for what you are about
to change, stop and find it.

---

## STEP 1 — Pre-deploy syntax gates (offline, before any scp/rsync)

Run the gate for **every artifact type you touched**. These are ad-hoc (no `.shellcheckrc` — this
repo has no CI, per `.claude/settings.json`). Command bodies are ground-truth from AGENTS.md
Verification, `.claude/rules/ops-reference.md`, and `deployment-lessons.md`.

| Artifact you edited | Gate command (run locally) | Source |
|---|---|---|
| `docker-compose.yml` | `docker compose -f <file> config --quiet` (silent = valid) | deployment-lessons.md |
| Butane `*.bu` | `docker run --rm -i quay.io/coreos/butane:latest --strict < vms/flatcar-media/butane/config.bu > vms/flatcar-media/ignition/config.ign` | ops-reference.md |
| Caddyfile | `docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile` (on the VM) | ops-reference.md |
| Host firewall `*.fw` | `pve-firewall compile` (on the host) | AGENTS.md Verification |
| Any modified `*.sh` | `shellcheck <script>.sh` — **mandatory before commit** | settings.json autoMode |

Butane `--strict` fails on warnings, not just errors — treat any output as a stop.
Invalid YAML that reaches the VM can orphan a whole stack (gluetun `network_mode: service:X`
dependents) — validate BEFORE scp, never after.

---

## STEP 2 — Post-deploy health evidence (never trust `up -d` exit 0)

`docker compose up -d` returning 0 means "container started", NOT "service healthy". You must poll.

```bash
# 1. Snapshot: are the containers even up?
ssh core@192.168.100.100 'docker ps --format "table {{.Names}}\t{{.Status}}"'

# 2. Health poll — repeat until "healthy" (do NOT assume from exit 0)
ssh core@192.168.100.100 "docker inspect -f '{{.State.Health.Status}}' <container>"
```

Then run the **per-subsystem gate skill** for whatever you touched (cite by name — do not re-inline
their command bodies here; they are the maintained homes):

| You changed… | Run gate skill | The evidence it must show |
|---|---|---|
| Media stack / gluetun | **media-health**, **vpn-status** | containers up + gluetun VPN proof pair (below) |
| NFS mounts/exports | **nfs-check** | `exportfs -v` on reginald + `mount -t nfs4` on Flatcar both consistent |
| Any backup path | **backup-status** | PBS snapshots listed, restic repo check passes, S3 reachable (see STEP 4) |
| UniFi / WiFi | **network-diagnostics** | health/clients/devices from `unifi-inventory.sh` |

### gluetun VPN proof pair (both must pass — one alone is not proof)

```bash
ssh core@192.168.100.100 'docker exec gluetun wget -qO- https://ipinfo.io/ip'      # must show VPN IP, NOT your WAN IP
ssh core@192.168.100.100 'docker exec gluetun cat /tmp/gluetun/forwarded_port'     # must be NON-EMPTY
```

An empty `forwarded_port` or a residential-looking IP = torrent traffic is exposed / port-forward
dead. Both green = VPN + PF verified.

### DNS triple-dig (all three cluster nodes — a change to one must not silently break replication)

```bash
dig @192.168.100.254 google.com +short   # QNAP primary
dig @192.168.100.100 google.com +short   # Flatcar secondary
dig @192.168.100.120 google.com +short   # reginald secondary (LXC 120)
```

---

## STEP 3 — NEGATIVE testing (a security control is verified only when the blocked path FAILS)

This is the firewall runbook's discipline (`hosts/firewall.md` §Verification), generalized: a
control that ALLOWS is only half-proven. You must also prove it DENIES. "It let me in" is not
evidence the firewall works — "it let me in AND kept the other guy out" is.

### Firewall negative tests — these MUST fail (from a source NOT in `admin_sources`: IoT .4.x, Guests .3.x, DMZ .7.x)

```bash
nmap -Pn -p 22,8006 192.168.100.38   # winston  → must show FILTERED
nmap -Pn -p 22,8006 192.168.100.4    # reginald → must show FILTERED
```

If those show `open`, Phase B DROP is not effective — the control is NOT verified regardless of what
the positive tests say.

### winston end-to-end chain probes (after the firewall is live — prove the good path still works)

```bash
curl -I https://nextcloud.lushanoperera.com    # 200 OK = CF Tunnel → Traefik → CrowdSec → Nextcloud chain intact
ssh root@192.168.100.38 'vzdump 106 --storage pbs-backupnas --mode snapshot --remove 0'   # PBS path reachable; --remove 0 = no-remove test backup
```

Always run negative + positive tests from a **fresh** SSH session — conntrack keeps your old session
alive across `pve-firewall reload`, so the old terminal is a false positive.

> Full anti-lockout ladder (dead-man cron, physical-console break-glass, datacenter kill switch,
> `pve-firewall stop` + `enable: 1`→`0`) lives in **`hosts/firewall.md`** — do not attempt a live
> firewall flip without it open. The rollout is DEFERRED (staged `enable: 0` as of 2026-04-20);
> resuming it is a change-control decision, not a QA task.

---

## STEP 4 — "Backup verified" means EVIDENCE, not a timer that exists

**The cautionary tale:** `/etc/pve/jobs.cfg` lives in pmxcfs and is NOT preserved on bare-metal
reinstall. When winston was rebuilt, the vzdump jobs vanished and **no scheduled backups ran for ~5
months (Oct 2025 – Mar 2026)** — the timers "existed" in everyone's memory but nothing was actually
backing up. A green cron line is not evidence.

Backup is verified only with **positive evidence of a recent successful run + restorable target**:

| Claim | Evidence required |
|---|---|
| PBS backups working | Run **backup-status** skill → PBS snapshots listed with recent timestamps; `pvesh get /cluster/backup` shows the jobs exist; `pvesh get /nodes/<node>/tasks --typefilter vzdump --limit 5` shows recent OK |
| Restic → S3 working | **backup-status** → restic repo check passes |
| S3 target reachable | **backup-status** → MinIO/RustFS reachable on Storage LAN (.200.x, separate from Infra .100.x) |

Never report "backups are fine" from timer/cron existence alone.

---

## The offline-CI-able gap (flag honestly)

Three of the STEP 1 gates need **no live host** and could run in CI on every PR, but currently do
not (only Claude-review workflows exist):

- `docker compose config --quiet` on every changed compose file
- `butane --strict` on every changed `*.bu`
- `shellcheck` on every changed `*.sh`

Butane/compose/shellcheck are pure-offline validators. If asked to "add CI" or "why do mistakes slip
through", this is the honest answer: the offline gates are run by hand today and a pre-commit hook or
a lint-only GitHub Action would close the gap. (Caddyfile validate and `pve-firewall compile` need a
live target, so they stay manual.) See `homelab-docs` digest §6/§9 for the full docs-gap list.

---

## Verified-done checklist (paste into your reconcile note)

```
[ ] STEP 0  Ran the read-only probe for this subsystem BEFORE mutating
[ ] STEP 1  Ran the syntax gate for EVERY artifact type touched (compose/butane/caddy/fw/shellcheck)
[ ] STEP 1  shellcheck clean on every modified .sh
[ ] STEP 2  docker ps shows containers up on the target
[ ] STEP 2  Health-polled docker inspect until 'healthy' (did NOT assume from up -d)
[ ] STEP 2  Ran the per-subsystem gate skill (media-health / vpn-status / nfs-check / backup-status / network-diagnostics)
[ ] STEP 2  (VPN) gluetun proof pair: VPN IP shown + forwarded_port non-empty
[ ] STEP 2  (DNS) triple-dig @.254/@.100/@.120 all resolve
[ ] STEP 3  (Security) negative test: blocked path FAILS (nmap filtered) from a non-admin source
[ ] STEP 3  (Firewall) winston chain probe 200 OK + PBS no-remove test backup, from a FRESH session
[ ] STEP 4  (Backup) positive evidence of a recent successful run, NOT just a timer
```

---

## Provenance and maintenance

Re-verify volatile claims read-only (repo is READ-ONLY reference; run from repo root):

```bash
# No tests / no lint CI still true?
find . -type d \( -name test -o -name tests -o -name __tests__ -o -name spec \) -not -path '*/.git/*'; \
  find . -maxdepth 3 \( -name '.shellcheckrc' -o -name '.eslintrc*' -o -name '.pre-commit-config.yaml' \); \
  ls .github/workflows/                              # expect: nothing, nothing, only claude*.yml

# 4-step doctrine + gate commands unchanged?
sed -n '/## Verification/,$p' AGENTS.md; grep -nE 'config --quiet|butane|caddy validate|inspect|forwarded_port' .claude/rules/ops-reference.md .claude/rules/deployment-lessons.md

# Firewall negative tests + winston chain probes unchanged?
sed -n '/## Verification/,/## Break-glass/p' hosts/firewall.md

# deploy-firewall.sh read-only flags unchanged?
grep -nE '\-\-status|\-\-diff|\-\-enable|\-\-disable' scripts/hosts/deploy-firewall.sh

# autoMode SSH-write/shellcheck rules unchanged?
grep -nE 'SSH|shellcheck|Never auto-approve' .claude/settings.json

# Per-subsystem gate skills still present?
ls .claude/skills/{backup-status,media-health,nfs-check,vpn-status,network-diagnostics}/SKILL.md
```

Volatile facts date-stamped **(as of 2026-07-04)**: firewall staged `enable: 0` / rollout DEFERRED;
PVE versions and live host state are UNVERIFIED from the repo — confirm on the host before acting.
The 5-month backup gap (Oct 2025 – Mar 2026) is settled history from `infra-lessons.md`.
