---
name: homelab-config-and-flags
description: >
  The homelab env-key and feature-switch registry — WHERE every secret and toggle lives and
  what it does, NEVER the values. Use when you need to answer "what env var controls X",
  "where is the Technitium admin password / Immich DB password / UniFi creds / restic S3 key",
  "which .env sets this", "what pins the Immich/Nextcloud version", "how do I turn the firewall
  on", "why won't auto-mode let me run this", "which .env.example do I copy", "what keys go in
  scripts/vms/.env", "rustfs .env is blank", "IMMICH_VERSION default", "NEXTCLOUD_VERSION
  default", "watchtower auto-update vs pinned tag", "settings.json autoMode / never-auto-approve
  list", "conditional rules trigger table". Keywords: env registry, secret location, .env,
  .env.example, restic-env, TUNNEL_TOKEN, CROWDSEC_BOUNCER_API_KEY, POSTGRES_PASSWORD,
  DB_PASSWORD, enable: 0 firewall, deploy-firewall flags, version pin, watchtower, autoMode.
  This skill is a lookup table, not an operations runbook — for DEPLOYING config changes see the
  sibling homelab-run-and-operate; for the global secrets policy see the global rule
  secrets-management.md.
---

# Homelab config & flags registry

This is the **map of every environment key and feature switch** in the homelab repo
(`/Users/disconnesso/Documents/Projects/homelab`): the NAME of each variable, its PURPOSE, and
WHERE it is set. It never contains a single secret value — values live only in gitignored `.env`
files on disk and on the target hosts.

Use this to answer "where does credential/toggle X live?" without grepping blind, and to know
which template to copy when standing up a component.

## When to use this skill — and when NOT to

| You are... | Use |
| --- | --- |
| Looking up which `.env` / key holds a secret or toggle | **this skill** |
| Deciding what to copy/fill when bringing up a stack | **this skill** (§2, §3) |
| Turning the host firewall on/off, reading its stage flag | **this skill** §5 for the flag semantics; then the runbook `hosts/firewall.md` for the rollout |
| Actually deploying/rsyncing config to a host, restarting a service | sibling skill **homelab-run-and-operate** (deploy anatomy, load pattern in context) |
| Asking the general "why plain .env, why no vault" policy question | global rule **`~/.claude/rules/secrets-management.md`** (the authority — do not restate it here) |
| Setting up NEW varlock/rbw secret management | **do not.** This repo migrated OFF varlock/rbw on 2026-05-20. The global `new-project-secrets` skill and any `varlock run --` wrapper are obsolete here (see §6 warnings). |

## 1. Secrets model (project delta only)

The **global policy** — plain gitignored `.env`, no vault at rest, why — is owned by
`~/.claude/rules/secrets-management.md`. Do not restate it. What is **specific to this repo**:

- **One plain `.env` per component**, sitting next to the consumer that sources it. Migrated off
  varlock/rbw on 2026-05-20; the root `.env.schema.bak` and `storage/rustfs/.env.schema.bak` are
  **inert migration leftovers** — ignore them, do not resurrect a schema workflow.
  (Verified on disk 2026-07-04: both `.env.schema.bak` files present.)
- **Load pattern** every script/stack uses:
  ```bash
  set -a; source .env; set +a   # never echo values to logs
  ```
- **Never commit or echo values.** Each committed `.env.example` is the safe template — copy it to
  `.env` and fill in. Deploy scripts rsync with `--exclude='.env'` so the real file never ships in
  a sync (it is placed on the host once, by hand).
- **VM `.env` files are APPEND-ONLY by convention** — add keys, never rewrite the file wholesale
  (avoids clobbering keys other stacks/sessions added out of band).
- **restic env files are `chmod 0600`, deployed manually, and NEVER committed** — there is no
  `restic-env` in git, only `restic-env.example`.

## 2. Repo-side key registry (names + purpose + where set)

Source of truth: `AGENTS.md` §"Credentials" (L146-155), verified 2026-07-04. Values live only in
the sibling gitignored `.env`.

| Secret file (next to its consumer) | Key names | Purpose |
| --- | --- | --- |
| `.env` (repo root) | `WINSTON_IP`, `REGINALD_IP`, `PBS_PASSWORD`, `API_TOKEN` | Proxmox host IPs + PBS / Proxmox API creds for `scripts/`. **Root `.env` is read-denied to agents by design — never try to cat it.** |
| `scripts/network/.env` | `UNIFI_HOST`, `UNIFI_USER`, `UNIFI_PASS` | UniFi controller API (unifi-inventory.sh) |
| `scripts/vms/.env` | `SEERR_API_KEY`, `SONARR_API_KEY`, `RADARR_API_KEY`, `SEERR_URL`, `SONARR_URL`, `RADARR_URL`, `QBITTORRENT_URL` | *arr / media-automation API access |
| `networking/cloudflare-tunnel/.env` | `TUNNEL_TOKEN` | cloudflared tunnel |
| `networking/traefik/.env` | `CROWDSEC_BOUNCER_API_KEY`, `TUNNEL_TOKEN` | Traefik ↔ CrowdSec bouncer + tunnel (CrowdSec = the IP-reputation firewall in front of public services) |
| `apps/immich/.env` | `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE_NAME`, `IMMICH_VERSION`, `IMMICH_MACHINE_LEARNING_HARDWARE_ACCELERATION`, `TZ` | Immich photo stack — DB creds + version pin + ML accel toggle |
| `apps/nextcloud/.env` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `NEXTCLOUD_VERSION`, `NEXTCLOUD_TRUSTED_DOMAINS`, `NEXTCLOUD_URL`, `TZ` | Nextcloud stack — DB creds + version pin + trusted-domain allowlist |
| `apps/<app>/restic-env` (per node; `chmod 0600`; **never committed**) | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `UPLOAD_LOCATION`, `DB_DATA_LOCATION`, `RESTIC_COMPRESSION` | S3 (restic) backup of the app's data + DB dump path |

**restic nodes on disk** (committed templates, verified 2026-07-04): `apps/nextcloud/restic-env.example`,
`apps/immich/restic-env.example`, `apps/technitium/restic-env.example`. So the three
restic-backed components are Nextcloud, Immich, and Technitium.

> **`POSTGRES_USER` ≠ the DB owner.** Nextcloud's real DB user is `oc_nextcloud`, not the
> compose `POSTGRES_USER=nextcloud` — this bit a 32→33 upgrade. Check `occ config:system:get dbuser`
> before touching schema ownership. (See homelab failure history / global infra-runbook.)

## 3. The 8 `.env.example` templates whose keys AGENTS.md does NOT enumerate

These committed templates exist on disk (verified 2026-07-04) but their key lists are **not**
transcribed into AGENTS.md, and every `.env*` file in this repo is **read-denied to agents by a
permission hook** — so this skill cannot list their keys without inventing them. To see the keys,
a human opens the template directly (agents cannot):

- `apps/couchdb/.env.example` — CouchDB (Obsidian LiveSync backend)
- `apps/forgejo/.env.example` — Forgejo private Git server
- `dns/technitium/.env.example` — Technitium DNS (repo-side; the **admin password** lives in the
  deployed `/srv/docker/dns/.env`, see §4)
- `homepage/.env.example` — Homepage dashboard (widget API keys)
- `networking/caddy/.env.example` — Caddy internal reverse proxy (Cloudflare DNS-challenge token)
- `networking/traefik/crowdsec/.env.example` — CrowdSec engine
- `storage/rustfs/.env.example` — RustFS S3 (see §6 — **values were BLANKED**, repopulate before use)
- `vms/flatcar-media/.env.example` — Flatcar media-stack compose env

Plus the 7 already-enumerated templates (root, `scripts/network`, `scripts/vms`,
`networking/cloudflare-tunnel`, `networking/traefik`, `apps/immich`, `apps/nextcloud`) = **15
committed `.env.example` files total** (verified 2026-07-04; ignore the copies under
`.claude/worktrees/{keen-fox-mws7,agents-guide}/` — stale leftover worktrees).

## 4. Deployed-side `.env` locations (on the hosts, not in git)

These live only on the target hosts. **UNVERIFIED from the repo** (memory digest, dated); confirm
by SSHing to the host before acting.

| Host | Path | Holds | Source/date |
| --- | --- | --- | --- |
| Flatcar VM 100 (`core@192.168.100.100`) | `/srv/docker/couchdb/.env` | CouchDB admin | memory 2026-05-20→28 |
| Flatcar VM 100 | `/srv/docker/homepage/.env` | Homepage widget keys | memory 2026-05-28 |
| Flatcar VM 100 | `/srv/docker/media-stack/.env` | *arr / gluetun / qBt keys | memory 2026-05-28 |
| Flatcar VM 100 | `/srv/docker/dns/.env` | **Technitium admin password** | memory 2026-05-20→28 |
| nwlab flatcar-104 (`core@10.21.21.104`, **sibling `nwlab` repo, not this one**) | `/opt/grafana/.env` | Grafana secrets | memory 2026-05-15 |

> nwlab (10.21.21.0/24, Grafana at `/opt/grafana`) is a **separate repo** (`nwlab`), reachable over
> WireGuard. It is out of scope for this repo except that auto-mode trusts its subnet (§5).

## 5. Feature switches & operational flags

### 5a. Container version pins vs. auto-update

- **Watchtower auto-updates everything left on `:latest`.** The media stack
  (`linuxserver/*:latest`, `qmcgaw/gluetun:latest`, seerr, flaresolverr, autoheal) rides watchtower
  (`nickfedor/watchtower` fork; QNAP watchtower runs daily 4 AM). **Pin a tag only when you need to
  freeze a version.**
- **Explicitly pinned** (do NOT expect auto-update): `traefik:v3.3`, `codeberg.org/forgejo/forgejo:14`,
  `couchdb:3`, `postgres:17-alpine`/`redis:7-alpine`/`nginx:alpine` (Nextcloud), Immich
  `postgres`/`valkey` by digest, `ghcr.io/dictionarry-hub/profilarr:2.0.6`, `python:3.12-alpine`.
- **Version toggles via env** (compose reads `${VAR:-default}`, verified in compose files 2026-07-04):
  - `IMMICH_VERSION` → server/ML image, default **`release`** (`apps/immich/docker-compose.yml`)
  - `NEXTCLOUD_VERSION` → `nextcloud-custom:${NEXTCLOUD_VERSION:-33}-fpm`, default **`33`**
    (`apps/nextcloud/docker-compose.yml`)
  - `IMMICH_MACHINE_LEARNING_HARDWARE_ACCELERATION` → GPU/CPU ML accel selector

### 5b. Host firewall stage flag + deploy-script flag semantics

The Proxmox host firewall is **staged at `enable: 0`** (OFF) on winston + reginald as of
2026-04-20 — intra-VLAN-100 traffic is unfiltered until it is flipped. `enable: 0` lives in
`hosts/common/cluster.fw` and `hosts/<host>/firewall/host.fw`.

`scripts/hosts/deploy-firewall.sh <winston|reginald> [flag]` **never flips `enable:` implicitly**
(verified from script header 2026-07-04):

| Flag | Effect |
| --- | --- |
| _(none)_ | Copy `cluster.fw` + `host.fw` to `/etc/pve/...`, run `pve-firewall compile`. Does NOT change enable state. |
| `--status` | Print `pve-firewall status` + current enable flags. **Read-only.** |
| `--diff` | Diff repo vs. remote copies. **Read-only.** |
| `--enable` | After copy+compile, flip `host.fw` enable `0 → 1`. |
| `--disable` | Flip enable `1 → 0` and `pve-firewall stop`. |

**Do not use `--enable` casually** — actual rollout is log-first→drop-later with a 30-min dwell,
dead-man cron auto-disable, and reginald-before-winston ordering. Follow the runbook
`hosts/firewall.md`; this skill only documents the flag surface. The rollout is a DEFERRED project
(UNVERIFIED whether configs were ever copied to hosts — run `deploy-firewall.sh <host> --status`).

### 5c. `.claude/settings.json` autoMode rules (verified 2026-07-04)

The harness enforces these when auto-mode runs; know them so you understand what will and won't be
auto-approved:

- **Trusted**: repo `github.com/lushanoperera/homelab`; domains `*.home.disconnesso.com`,
  `*.lushanoperera.com`; subnets `192.168.100.0/20`, `192.168.200.0/24`, `10.21.21.0/24`.
- **SSH read commands are safe** (status, `docker ps`, mount checks, `dig`, curl to internal svc).
- **SSH write commands require confirmation** (`docker compose up/down`, `systemctl restart`, config
  writes, remote destructive ops).
- **NEVER auto-approve**: `rm -rf`, `qm destroy`, `pct destroy`, `zfs destroy`, `systemctl stop` on
  prod services, `docker-compose down` (without explicit request).
- **Deploy pattern**: edit locally → scp/rsync → restart on VM, each step confirmed separately.
- **`shellcheck` all `.sh` before committing** — no CI, shell validation is manual.

### 5d. Conditional-rules trigger table

`.claude/rules/*.md` auto-load by touched-file glob. The full mapping is `AGENTS.md` §"Conditional
rules" (L217-228) — do not duplicate it; consult it when you edit a path and want to know which
lessons file will fire (e.g. touch `apps/immich/**` → `gpu-sriov-lessons.md`; touch `dns/**` →
`dns-lessons.md`).

## 6. Warnings & hygiene flags

- ⚠️ **RustFS `.env` values were BLANKED on 2026-05-20** (the source vault folder was empty). The
  template `storage/rustfs/.env.example` exists but the real `.env` has no valid secrets —
  **repopulate before any RustFS work** or S3 ops will fail silently. (Memory, 2026-05-20;
  RustFS is single-node alpha, replacing the deprecated MinIO→Garage path.)
- ⚠️ **Memory hygiene — literal keys leaked into memory stores.** The KG `homelab` store
  (entity `UsenetIntegration`) and some Memory-Bank session logs (e.g. `homelab/session-2026-05-28`)
  embed **real API keys** (SABnzbd, Prowlarr, Radarr, Sonarr, Seerr, Homepage/Profilarr). LAN-only,
  but treat as **rotate + scrub candidates**. Never copy those values into code, commits, or this
  skill.
- ⚠️ **Leftover `varlock run --` consumers break lazily.** Any script still wrapping in
  `varlock run --` post-migration will fail at run time — swap it to `set -a; source .env; set +a`.
- ⚠️ **`.env.schema` / `.env.schema.bak` are inert.** Do not treat them as an active schema; do not
  reinstate a varlock/rbw workflow.
- **Never `git add -A`** — the working tree runs chronically dirty (firewall staging, MinIO→RustFS
  migration, hardware planning). Stage explicit paths only.

## Provenance and maintenance

Every volatile claim above is re-verifiable READ-ONLY:

- **Repo-side key table & policy** — `AGENTS.md` L137-171 (`sed -n '137,171p' AGENTS.md`).
- **15 `.env.example` + `.env.schema.bak` on disk** — `find . -name '.env.example' -not -path './.claude/worktrees/*' -not -path './.git/*'` and `find . -name '.env.schema.bak'`.
- **restic nodes** — `find . -name 'restic-env.example'`.
- **8 unenumerated templates are unreadable** — by design (`.env*` read-deny hook); open them as a human to see keys.
- **Version-pin defaults** — `grep -n 'VERSION' apps/immich/docker-compose.yml apps/nextcloud/docker-compose.yml`.
- **Firewall flag semantics** — `head -40 scripts/hosts/deploy-firewall.sh`; live stage → `./scripts/hosts/deploy-firewall.sh <host> --status`.
- **autoMode rules** — `cat .claude/settings.json`.
- **Conditional-rules table** — `AGENTS.md` L217-228.
- **Deployed-side `/srv/docker/*/.env` paths & rustfs-blank / memory-leak flags** — UNVERIFIED from repo (memory digest, 2026-05-15→28); confirm by SSH to the host before relying on them.
