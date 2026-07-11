---
name: homelab-kernel-gpu-sriov
description: >-
  Proxmox kernel upgrade + Intel i915 SR-IOV lifecycle for the homelab, spanning
  the winston host AND Flatcar VM 100. Use when upgrading/rebooting a PVE host that
  serves GPU Virtual Functions, or when SR-IOV breaks after a kernel change.
  Symptoms & phrasings: "SR-IOV VFs gone after kernel upgrade", "only i915 PF
  visible", "GPU passthrough dead after reboot", "dkms silently no-oped", "stock
  i915.ko loaded", "unknown parameter max_vfs ignored", "sriov_numvfs is 0", "how
  do I upgrade Proxmox without losing the GPU", "install proxmox kernel 7.0",
  "kernel 7.0 SR-IOV blocked / BUILD_EXCLUSIVE", "proxmox-boot-tool kernel pin",
  "reginald ESP full / No space left on device installing kernel", "pin kernel
  before reboot", "modinfo max_vfs", "i915 VFs on winston". Keywords: proxmox-headers,
  proxmox-default-headers, i915-sriov-dkms, DKMS autoinstall, max_vfs, VF, PF,
  Raptor Lake iGPU, PVE 9.2, kernel 7.0.2-6-pve, legacy GRUB-PC, systemd-boot,
  loader.conf, vzdump PBS.
---

# Homelab Kernel + i915 SR-IOV Upgrade Lifecycle

Wrapper / checklist / failure-modes layer around the **canonical runbook** for
upgrading a Proxmox host that serves GPU SR-IOV Virtual Functions. This is the #1
recurring injury vector in the homelab (two incidents: 2026-04-30 headers-missing
DKMS no-op; reginald ESP full). It does NOT restate the runbook — it points at it
and adds the gates that catch the known failure modes.

**Canonical runbook (READ IT FIRST, follow it step-by-step):**
`docs/migrations/pve-9.2-kernel-7-upgrade.md` (committed `ec4ad3c`, dated 2026-05-22,
includes the executed outcome + 5 mid-flight deviations). This skill is the pre-flight
checklist and the "why did SR-IOV break" decision tree that lives *around* it.

## Jargon (defined once)

- **SR-IOV** — Single-Root I/O Virtualization: one physical Intel iGPU (the **PF**,
  Physical Function) is split into multiple **VF**s (Virtual Functions), each passed
  to a guest. winston exposes **7 VFs** from its Raptor Lake-P iGPU.
- **DKMS** — Dynamic Kernel Module Support: rebuilds out-of-tree modules
  (`i915-sriov-dkms`) against each installed kernel. If the matching kernel
  **headers** are absent, DKMS **silently skips** the build and the stock in-tree
  `i915.ko` (no `max_vfs` param) loads instead → VFs vanish.
- **ESP** — EFI System Partition (`/boot/efi`); holds kernels/initrds. reginald's is
  only **511 MB** and fills up.
- **sysext** — systemd system-extension squashfs; how the patched i915 ships to the
  immutable Flatcar VM (VM 100), a separate mechanism from host DKMS.

## Hosts in scope (topology)

| Host | SSH | Role | GPU |
|---|---|---|---|
| winston | `ssh root@192.168.100.38` | Primary PVE, Raptor Lake iGPU, **7 VFs** | HOST DKMS |
| reginald | `ssh root@192.168.100.4` | Secondary PVE (Zimaboard), ZFS/NFS | none |
| PBS | `ssh root@192.168.100.187` | Proxmox Backup Server (VM on QNAP) | none |
| Flatcar VM 100 | `ssh core@192.168.100.100` | Docker host, consumes a VF via sysext | GUEST sysext |

Live kernel/PVE state is UNVERIFIED from this repo — see Provenance to re-verify.
**As of 2026-07-05**, memory + the runbook outcome record all three hosts on
**PVE 9.2.2 + kernel 7.0.2-6-pve**, winston at **7/7 VFs**, PBS on
`proxmox-backup-server 4.2.0` (executed 2026-05-22/23). **AGENTS.md is STALE** — it
still lists winston 9.1.6 / reginald 9.1.5; trust `pveversion`, not the doc.

## When NOT to use this skill

- GPU is broken **only inside VM 100** (sysext missing/stale) and the host VFs are
  intact → use project skill **`gpu-fix`** (VM-side rebuild/module-swap). But FIRST
  run the one host check below — a dead PF starves every VF.
- Generic Proxmox / ZFS / PBS symptom→fix unrelated to a kernel bump or GPU → global
  skill **`infra-runbook`**.
- Reconstructing "when did this break / what was the incident" narrative → sibling
  project skill **`homelab-failure-archaeology`**.
- Post-upgrade "is it actually healthy / sign-off checklist" → sibling project skill
  **`homelab-validation-and-qa`**.
- This skill owns ONLY the homelab-specific host+VM coupling, paths, IPs, and the VF
  failure modes. The generic kernel-headers rule is normative in global
  `rules/infrastructure.md` ("Proxmox kernel upgrade w/ DKMS" row) — cited, not copied.

---

## The one check gpu-fix should do first (HOST before VM)

Before rebuilding the sysext inside VM 100, confirm winston is actually serving VFs.
If the host PF is dead (headers missing → stock i915), no amount of VM-side work helps.

```bash
# On winston — is DKMS built for the RUNNING kernel, and does the module carry max_vfs?
ssh root@192.168.100.38 '
  uname -r
  dkms status | grep i915
  modinfo /lib/modules/$(uname -r)/updates/dkms/i915.ko 2>/dev/null | grep max_vfs || echo "NO max_vfs — stock module loaded, VFs will be gone"
  cat /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs   # expect 7
'
```

`sriov_numvfs = 0` or missing `max_vfs` → this is a HOST problem; fix here, not in
`gpu-fix`. (Note the path differs by side: **host** = `/lib/modules/<ver>/updates/dkms/i915.ko`;
**VM 100 sysext** = `/usr/lib/modules/<ver>/updates/i915/i915.ko` — see `gpu-fix`.)

---

## Pre-upgrade gates (do ALL before touching apt)

| # | Gate | Command / check | Why (incident) |
|---|---|---|---|
| 1 | **Back up guests to PBS** | `vzdump 100 102 105 106 --storage <pbs-store> --mode snapshot --notes-template "pre-upgrade {{guestname}}"` (runbook §0.1) | pmxcfs + guests are the only recovery if the host won't boot |
| 2 | **Headers in the SAME apt transaction as the kernel** | `apt install -y proxmox-kernel-7.0 proxmox-headers-7.0` (and `proxmox-default-headers`) | **2026-04-30**: kernel installed without matching headers → DKMS silent no-op → stock i915.ko → VFs gone on reboot |
| 3 | **Check reginald ESP free space** | `df -h /boot/efi` then purge superseded: `apt purge proxmox-kernel-<old>-pve-signed` (runbook §1.1) | reginald ESP is **511 MB**; filled to 100% once → `No space left on device` mid-initrd |
| 4 | **Confirm rollback kernel present** | `proxmox-boot-tool kernel list` — keep the prior kernel until +14d | runbook §0.4 / §3.2 |
| 5 | **DKMS version supports the target kernel** | see version-coupling table below | kernel 7.0 was BUILD_EXCLUSIVE-blocked before DKMS 2026.05.06 |

## Post-install, PRE-reboot gates (moment of truth — do NOT reboot until green)

Run on the host you just ran `apt install` on, BEFORE `reboot`:

```bash
# 1. DKMS must list the NEW kernel
dkms status
# 2. If the new kernel is NOT listed, force it:
dkms autoinstall -k <ver>-pve        # e.g. 7.0.2-6-pve
# 3. HARD GATE — the built module MUST expose max_vfs, or SR-IOV is already dead:
modinfo /lib/modules/<ver>-pve/updates/dkms/i915.ko | grep max_vfs
```

If step 3 prints nothing, **STOP** — do not reboot. Diagnose
`/var/lib/dkms/i915-sriov-dkms/<ver>/build/make.log` (runbook §2.3). Rebooting now
gives you a host with no VFs and a downed media/photo/cloud stack.

winston kernel cmdline must also carry the SR-IOV params (runbook §2.5):
`intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe`.

## Pinning the kernel (BOTH host types)

Always pin with `proxmox-boot-tool`, never by editing `loader.conf`:

```bash
proxmox-boot-tool kernel pin <ver>-pve       # writes /etc/default/grub.d/proxmox-kernel-pin.cfg + update-grub
grep 'set default' /boot/grub/grub.cfg       # verify it points at <ver>-pve
```

**CORRECTION on record (2026-05-22):** reginald boots via **legacy GRUB-PC (CSM)**,
NOT systemd-boot — despite systemd-boot files sitting in its ESP. `bootctl status`
returns *"Not booted with EFI"*. Editing `/boot/efi/loader/loader.conf` `default` is
**silently ignored** there (first reboot came back on the old kernel). `proxmox-boot-tool
kernel pin` writes a GRUB drop-in that works on **both** winston (GRUB-EFI) and reginald
(legacy GRUB-PC). This supersedes any older "reginald = systemd-boot" note.

## Version-coupling history (why the DKMS version matters)

| Target kernel | Where | DKMS version | Note |
|---|---|---|---|
| 7.0.x (PVE 9.2) | winston/reginald/PBS host | **2026.05.06** | PR #438 (merged 2026-05-02) lifted the `BUILD_EXCLUSIVE` block from issue #429. Pre-2026.05.06 rules calling 7.0 "blocked" are OBSOLETE. Asset is `_amd64.deb`, not `_all.deb`. |
| 6.17.x | PVE host | 2025.10.10 | prior host line |
| 6.12.87 | **Flatcar VM 100** (sysext) | **2025.07.22** + `nocache` sed shim | Flatcar channel still ships 6.12.87 |

**Flatcar VM 100 is NOT upgraded by a PVE host kernel bump** — its kernel stays
6.12.87 and its sysext stays on DKMS 2025.07.22. Do not bump it to 2026.03.05.x: that
compat module needs `CONFIG_DRM_GPUVM`, which Flatcar disables (verify:
`zcat /proc/config.gz | grep DRM_GPUVM`). All VM-side sysext rebuild/module-swap/
container re-enable verbs live in project skill **`gpu-fix`** — do not duplicate them here.

## Monitoring SR-IOV (this repo, NOT Grafana)

`intel_gpu_top` does **not** work against VFs (no PMU). Use the repo scripts, which
read debugfs/sysfs (`docs/sr-iov/gpu-monitoring.md`):

```bash
scripts/monitoring/gpu-monitor.sh    # dashboard of PF + all VFs
scripts/monitoring/gpu-watch.sh [interval_seconds]   # live freq/activity watcher
```

Grafana/Prometheus GPU dashboards are an **nwlab** thing (`/opt/grafana` on
flatcar-nwdesigns) — there is no Grafana stack in this repo; do not look for one here.

## Cross-references (do not restate their content)

- `docs/migrations/pve-9.2-kernel-7-upgrade.md` — the canonical step-by-step runbook.
- `.claude/rules/infra-lessons.md` — "Proxmox Kernel Upgrades" + "GPU SR-IOV" gotcha
  rows (headers, ESP, GRUB pin, DRM_GPUVM), auto-loads on `hosts/**`.
- `.claude/rules/gpu-sriov-lessons.md` — DKMS-version-per-kernel table, recovery
  checklist; auto-loads on `vms/flatcar-media/sysext/**`, `apps/{immich,nextcloud}/**`.
- Global `rules/infrastructure.md` — normative "Proxmox kernel upgrade w/ DKMS" row
  (install `proxmox-headers-X` + `proxmox-default-headers`). Cite; it is the rule's home.
- Global skill **`infra-runbook`** — generic Proxmox/ZFS/PBS symptom→fix.
- Project skill **`gpu-fix`** — VM-100 sysext remediation (extend it with a "check the
  host first" pointer to the check above — see Provenance note).
- Sibling project skills **`homelab-failure-archaeology`** (dated incident chronicle)
  and **`homelab-validation-and-qa`** (post-upgrade acceptance/sign-off).

Secrets: PBS/host creds are in the gitignored root `.env` (key names `PBS_PASSWORD`,
`WINSTON_IP`, `REGINALD_IP`, `API_TOKEN`) — never inline values. SSH is key-auth.

## Provenance and maintenance

Every volatile claim above is re-checkable READ-ONLY:

```bash
# Live PVE + kernel + VF state (settles the AGENTS.md 9.1.x staleness):
ssh root@192.168.100.38 'pveversion; uname -r; cat /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs'
ssh root@192.168.100.4  'pveversion; uname -r'
ssh root@192.168.100.187 'proxmox-backup-manager versions | head -1; uname -r'

# Host DKMS / module gate:
ssh root@192.168.100.38 'dkms status | grep i915; modinfo /lib/modules/$(uname -r)/updates/dkms/i915.ko | grep max_vfs'

# Repo ground truth (run in repo root, read-only):
git log --oneline -1 -- docs/migrations/pve-9.2-kernel-7-upgrade.md   # canonical runbook commit
ls scripts/monitoring/gpu-monitor.sh scripts/monitoring/gpu-watch.sh docs/sr-iov/gpu-monitoring.md
cat vms/flatcar-media/sysext/i915-sriov/build.sh   # Flatcar sysext DKMS version

# NOTE: gpu-fix SKILL.md was NOT modified by this authoring pass (writes were scoped to
# this skill folder). Recommended one-line extension to gpu-fix/SKILL.md "When to Use":
# "Before rebuilding the sysext, confirm the HOST is serving VFs — see
#  homelab-kernel-gpu-sriov 'The one check gpu-fix should do first'."
```

Re-verify after any host kernel change; update the "as of 2026-07-05" live-state line
and prod AGENTS.md if `pveversion` disagrees with it.
