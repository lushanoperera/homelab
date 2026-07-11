---
name: homelab-run-and-operate
description: >
  The homelab operate loop — how to actually ship a config change to a self-managed
  Proxmox/Flatcar host and verify it. There is NO build toolchain, NO dev server, NO deploy
  CI here (the GitHub Actions are Claude-review-only) — deploy = edit config → validate →
  rsync/scp → reload → health-check. Use when: "deploy to the homelab", "push this compose /
  Caddyfile / firewall config", "how do I ship to winston / reginald / VM 100 / the Flatcar
  box", "rsync to core@192.168.100.100", "up -d the media stack", "enable the Proxmox
  firewall", "deploy-firewall.sh", "recompile butane / ignition", "spin up a new Flatcar VM",
  "where do secrets live", "what's the SSH into winston", "which host runs what", "SABnzbd is
  an empty shell", "retrigger stuck downloads", "rustfs .env is blank", "is terraform usable
  here". Routes to the per-stack runbook skills. This is homelab-only — for client sites
  (Cloudways/Aruba/Vercel) use the global agency-run-and-operate skill instead.
tools: Bash, Read
---

# Homelab — Run & Operate

**Audience:** an engineer or model that has never touched this lab. Follow the loop, copy the
commands, verify. Every host IP, flag, and path below was read out of the repo on 2026-07-05.

## Read this first — when NOT to use this skill

- **Client / portfolio sites** (WordPress on Cloudways/Aruba/Serverplan, Next.js/Payload on
  Vercel) → use the **global `agency-run-and-operate`** skill. Cloudways-style ops (sshpass,
  lftp FTPS, Varnish/Breeze purge, webroots) **do not apply here** — these are self-managed
  Proxmox/Flatcar hosts with no managed cache layer (`AGENTS.md` "Gotchas", L245–246). No
  client production site runs on this lab.
- **The "is it actually done?" evidence bar** after you deploy → sibling
  **`homelab-validation-and-qa`** (post-deploy verified checklists, negative tests).
- **Deep symptom→fix for a specific stack** → the per-stack runbook skills (table at the
  bottom). This skill *routes* to them; it does not restate them.

## The operate loop (the whole doctrine, verbatim)

There is **no CI deploy pipeline**. The two `.github/workflows/*.yml` are `claude.yml`
(@claude responder) and `claude-code-review.yml` (Claude review on PRs) — **review-only, they
never deploy** (`AGENTS.md` Deployment, L118–120; verified: `ls .github/workflows/`).

```
edit config locally  →  validate syntax  →  rsync/scp to host  →  reload service  →  health-check
```

1. **Validate** — never ship unparsed config (`AGENTS.md` Verification, L236–241):
   - compose: `docker compose -f <file> config --quiet`
   - Caddyfile: `docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`
   - Butane: `--strict` on the butane container (see below)
   - Proxmox firewall: `pve-firewall compile` (done for you by `deploy-firewall.sh`)
2. **shellcheck** every modified `.sh` before committing — **this repo has no CI to catch it**
   (`AGENTS.md`; `.claude/settings.json` autoMode rule).
3. **rsync/scp** to the target, then **reload** the service.
4. **Health-check** with `docker ps` and the per-stack runbook skill.

## SSH matrix (key-based auth; no passwords in the repo or memory)

| Host | SSH target | What it is | Source |
| --- | --- | --- | --- |
| **winston** | `root@192.168.100.38` | Minisforum MS-01, Proxmox VE, SR-IOV GPU; guests VM 100/102, LXC 104 WireGuard / 105 Plex / 106 PDM | `AGENTS.md`, `ops-reference.md` |
| **reginald** | `root@192.168.100.4` | Zimaboard 832, Proxmox VE, ZFS + NFS storage; LXC 120 Technitium DNS, 123 Samba | `AGENTS.md`, `ops-reference.md` |
| **Flatcar VM 100** | `core@192.168.100.100` | Docker host — media stack, Nextcloud, Immich, Traefik, Caddy, CouchDB, Technitium secondary. **All `/srv/docker/*` stacks live here.** | `AGENTS.md`, `ops-reference.md` |
| **PBS** | `root@192.168.100.187` | Proxmox Backup Server (VM on QNAP) | `ops-reference.md` |
| nwlab-thinkpad *(remote)* | `root@10.21.21.99` | nwlab Proxmox host, reached over WireGuard; default target of `deploy-flatcar-vm.sh` | `AGENTS.md` L53 |
| flatcar-nwdesigns *(remote)* | `core@10.21.21.104` | nwlab Docker/Grafana box — **belongs to the sibling `nwlab` repo, out of scope here** | `deploy-proxmox-104.sh` |

The authoritative **repo → deployed-path** table is in `AGENTS.md` ("Repo → VM path mapping",
L84–98). Consult it before every deploy — deploying to the wrong path silently no-ops.

## Generic stack deploy (any `/srv/docker/<stack>`)

Verbatim from `AGENTS.md` Deployment (L126–129):

```bash
# Example: caddy. Swap the repo dir + remote /srv/docker/<stack>/ per the mapping table.
rsync -az --exclude='.git' --exclude='.env' networking/caddy/ core@192.168.100.100:/srv/docker/caddy/
ssh core@192.168.100.100 'cd /srv/docker/caddy && docker compose up -d'
```

**Flatcar gotcha — the compose binary is not `docker compose`.** The AGENTS.md generic example
writes `docker compose up -d`, but on Flatcar `/usr` is read-only and the compose *plugin is
not installed*. On VM 100 use the standalone binary:

```bash
ssh core@192.168.100.100 'cd /srv/docker/<stack> && /opt/bin/docker-compose up -d'
```

(`.claude/rules/flatcar-lessons.md`, `deployment-lessons.md`; used throughout the
`deploy-compose` skill.)

**Compose mechanics are owned by the `deploy-compose` skill — delegate to it.** It carries the
one rule you must not get wrong:

> **gluetun network-namespace orphaning:** media-stack containers share gluetun's netns via
> `network_mode: service:gluetun`. If gluetun's config (env/ports/image) changed, `up -d` the
> **whole stack** — recreating gluetun alone gives it a new container ID and orphans its
> dependents; a `restart` on them then fails with "No such container".
> (`deploy-compose` skill; `flatcar-lessons.md`.)

### sudo-rsync variant (root-owned stack dirs)

`scp`/`rsync` as `core` works for user-writable paths, but `/srv/docker/immich/` and
`/srv/docker/nextcloud/` are **root-owned** — plain writes there fail
(`deployment-lessons.md`). To push into a root-owned dir:

```bash
rsync -av --rsync-path="sudo rsync" apps/immich/docker-compose.yml \
  core@192.168.100.100:/srv/docker/immich/
```

> UNVERIFIED technique (source: Memory Bank `homelab/session-2026-05-28`, 2026-05-28) — the
> `--rsync-path="sudo rsync"` form appears in no committed script. The repo-documented path is
> plain `rsync`/`scp` as `core` to user-writable dirs. Confirm the target dir's owner with
> `ssh core@192.168.100.100 'ls -ld /srv/docker/immich'` before reaching for sudo.

### Health-poll loop (wait for healthy, don't guess)

The health field the runbook skills read is grounded (`vpn-status`, `container-manage`
skills):

```bash
ssh core@192.168.100.100 'docker inspect -f "{{.State.Health.Status}}" gluetun'
```

Operate pattern — poll until it flips to `healthy` before declaring success:

```bash
until [ "$(ssh core@192.168.100.100 'docker inspect -f "{{.State.Health.Status}}" gluetun')" = healthy ]; do
  sleep 3; done
```

(Loop form from Memory Bank `homelab/session-2026-05-28` — the `docker inspect` command itself
is verified in-repo.) Then hand off to `media-health` / `vpn-status` for the full check.

## Special deploys

### Proxmox host firewall — `scripts/hosts/deploy-firewall.sh`

**Read-only by default. It never flips `enable:` without an explicit flag** (script header,
verified `head -60 scripts/hosts/deploy-firewall.sh`). Targets: `winston`→`root@192.168.100.38`,
`reginald`→`root@192.168.100.4`.

**Flag surface (single home = sibling `homelab-config-and-flags` §5b — do not re-copy the table here).**
Operationally, `<host>` = copy+compile only (no `enable:` change); `--status`/`--diff` are read-only;
`--enable`/`--disable` are the only live-traffic changes and are gated. Consult §5b for the full flag
semantics before invoking.

Before ever running `--enable`, follow the full runbook `hosts/firewall.md` (log-first → drop,
30-min dwell, dead-man cron, **reginald first then winston 24h later**, physical-console
pre-flight). See the **Open threads** ledger — this rollout is **DEFERRED**, and the runbook +
configs are currently **untracked** (must be committed first).

### Butane → Ignition (Flatcar declarative config)

Recompile after editing any `*.bu` (`ops-reference.md` L82; `flatcar-lessons.md`):

```bash
docker run --rm -i quay.io/coreos/butane:latest --strict \
  < vms/flatcar-media/butane/config.bu > vms/flatcar-media/ignition/config.ign
```

Ignition **only applies at first boot** — post-boot changes are manual. Use `eth0`, never
`ens18`, in Butane (`flatcar-lessons.md`).

### New Flatcar VM — `scripts/vms/deploy-flatcar-vm.sh`

```bash
./scripts/vms/deploy-flatcar-vm.sh --vm-id 105 --vm-ip 10.21.21.105   # the script's own example
```

**CAVEAT — do not copy the example blindly.** Its `DEFAULT_PROXMOX_HOST` is `10.21.21.99` (the
**nwlab** thinkpad) and the example `--vm-ip 10.21.21.105` is on the **nwlab** subnet. In the
**homelab** (`192.168.100.0/x`) subnet, **105 is the Plex LXC on winston** — reusing that ID
here would collide. For a homelab VM you must pass `--proxmox-host 192.168.100.38` and a free
`192.168.100.x` IP/ID. (Verified: `head -70 scripts/vms/deploy-flatcar-vm.sh`,
`deploy-proxmox-104.sh` uses `PROXMOX_HOST=10.21.21.99`, `AGENTS.md` LXC 105 = Plex.)

`qm destroy` inside the script is destructive — the autoMode rules never auto-approve it.

## Ops conventions (non-negotiable)

- **Secrets** live in **plain gitignored `.env`** next to each consumer (migrated off
  varlock/rbw 2026-05-20; `.env.schema.bak` is inert). Load with
  `set -a; source .env; set +a` (`AGENTS.md` L167). **Never commit or echo `.env` values.**
  Key-name registry is the table in `AGENTS.md` "Credentials" (L146–162) — this skill does not
  duplicate it. `restic-env` files are `chmod 0600`, deployed manually, never committed.
- **Commits:** Conventional Commits (`feat:`/`fix:`/`docs:`); AI commits end with a brief
  *why & how* (`AGENTS.md` Gotchas).
- **Stage explicit paths — never `git add -A`.** The tree runs chronically dirty (in-flight
  MinIO→RustFS, firewall staging, hardware planning) (`AGENTS.md` Gotchas).
- **shellcheck before commit** — no CI safety net.
- autoMode (`.claude/settings.json`): SSH *reads* are safe; SSH *writes* need confirmation. The
  full never-auto-approve list is owned by sibling **homelab-config-and-flags §5c** — consult it
  rather than relying on a copy here.

## Open operational threads (resume pointers)

| Thread | State (as of 2026-07-05) | Resume pointer |
| --- | --- | --- |
| **Proxmox host firewall rollout** | **DEFERRED.** Configs staged at `enable: 0`; runbook `hosts/firewall.md`, staged `hosts/{common,winston,reginald}/…`, and `scripts/hosts/deploy-firewall.sh` are **all untracked (`git status` `??`)** — a bare-metal reinstall would lose them. | **Commit the plan + configs first.** Then read `hosts/firewall.md`, run `deploy-firewall.sh reginald --status`/`--diff` (read-only) to check drift, reginald first. Memory: `project_proxmox_firewall_rollout.md`. |
| **SABnzbd / Usenet** | SABnzbd runs as an **empty shell** behind gluetun on host `:8081` (in the media stack). No Usenet provider, no indexer, not wired into the *arrs. | Add provider + indexer + categories (movies/tv/music) → add SABnzbd as a download client in Sonarr/Radarr (priority 1) → run `/opt/bin/retrigger-missing-downloads.sh` for the ~24 stuck requests (skill `retrigger-downloads`). UNVERIFIED count (KG `UsenetIntegration`). |
| **rustfs `.env` blank** | `storage/rustfs/.env` values were **blanked** during the secrets migration (vault folder was empty) — RustFS unusable until repopulated. | Repopulate the `.env` before any RustFS deploy. Memory: `project_secrets_migration_off_rbw` (2026-05-20). |
| **MinIO → RustFS migration** | Scripts + doc exist **uncommitted** in the working tree; the older MinIO→Garage path is DEPRECATED. | `scripts/migrations/minio-to-rustfs/` (and `…/minio-to-garage/` marked deprecated). Commit + finish, or leave parked. |
| **Terraform** | `automation/terraform/` pins `telmate/proxmox` **2.9.14** vs live PVE 9.x — **very likely broken**, untouched since Jan. | **Ansible is the live IaC path** (`automation/ansible/deploy-flatcar-vms.yml` + `flatcar-vm` role, inventory targets `10.21.21.99`). Prefer Ansible; treat terraform as rotten until re-pinned. |

## Where this skill routes (operational verbs)

Keep-as-is; cross-ref, don't restate:

| Need | Skill |
| --- | --- |
| Deploy a compose change (netns-safe recreation) | `deploy-compose` |
| Restart / logs / update a single container | `container-manage` |
| VM/LXC list, start, stop, snapshot, migrate | `proxmox-manage` |
| SR-IOV GPU broken after kernel bump | `gpu-fix` |
| Traefik / CrowdSec edge ops | `traefik-crowdsec` |
| Remove a movie/series everywhere | `media-remove` |
| Sonarr/Radarr quality profiles | `quality-manage` |
| Retrigger stuck Seerr requests | `retrigger-downloads` |
| Post-deploy health (stack / NFS / VPN / backups) | `media-health`, `nfs-check`, `vpn-status`, `backup-status`, and sibling `homelab-validation-and-qa` |

Generic symptom→fix for Proxmox/ZFS/PBS/WireGuard/Docker lives in the **global `infra-runbook`**
and **global `nwdesigns-failure-archaeology`** skills — go there for cause/cure; stay here for
homelab topology, IPs, and paths. Deploy lessons: `.claude/rules/deployment-lessons.md`,
`.claude/rules/flatcar-lessons.md`, `.claude/rules/ops-reference.md`.

## Provenance and maintenance

Re-verify volatile claims read-only (repo is the source of truth; live host state needs SSH):

```bash
# SSH matrix, path table, deploy commands, conventions
sed -n '84,180p;230,255p' AGENTS.md
# firewall script flags (none/--enable/--disable/--status/--diff)
head -60 scripts/hosts/deploy-firewall.sh
# new-VM script defaults + example (nwlab subnet caveat)
head -70 scripts/vms/deploy-flatcar-vm.sh
# workflows are review-only; scripts inventory
ls .github/workflows/ && ls scripts/*/
# firewall assets still untracked?
git status --short hosts/ scripts/hosts/deploy-firewall.sh
# terraform provider pin vs live PVE
grep -rn 'telmate/proxmox' automation/terraform/
```

Live-state (SSH, mutating nothing): `deploy-firewall.sh <host> --status`,
`ssh <host> 'pveversion; uname -r'`, `ssh core@192.168.100.100 'docker ps'`.
Marked UNVERIFIED above: the `--rsync-path="sudo rsync"` form, the health-poll `until` loop,
and the ~24 stuck-request count (all from Memory Bank/KG, 2026-05, not committed to this repo).
