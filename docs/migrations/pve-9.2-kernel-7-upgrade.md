# PVE 9.2 + Kernel 7.0 Upgrade — winston + reginald

**Created**: 2026-05-22
**Hosts**: winston (primary, GPU SR-IOV) + reginald (secondary, no GPU)
**Target**: PVE 9.2 + kernel 7.0.2-6-pve, SR-IOV intact on winston

---

## Context

Proxmox VE 9.2 released **2026-05-21** with **kernel 7.0** default (PVE 9.1 was 6.17). winston runs Intel Raptor Lake-P iGPU with `i915-sriov-dkms` exposing 7 VFs to LXC 105 (Plex on PF) and (intended) LXC 101/103 + VM 100. A kernel upgrade that loses SR-IOV bricks the media + photo + cloud stack.

### i915-sriov-dkms verdict — READY for kernel 7.0

`strongtz/i915-sriov-dkms` release **2026.05.06** (PR #438 merged 2026-05-02) supports kernel 6.17.x + 7.0.x. Community confirms working on Pentium 8505, i5-1340P (beisser 2026-04-25), Arrow Lake (panji19m 2026-04-28). The previous "BUILD_EXCLUSIVE blocks 7.0" rule was pre-2026.05.06 and is now obsolete.

**Flatcar VM 100 NOT affected** — VM kernel stays 6.12.87 (Flatcar channel); sysext stays on DKMS 2025.07.22 + sed shim.

### Current state (verified 2026-05-22)

| Host | PVE | pve-manager | Running kernel | k7.0 avail | DKMS i915 | SR-IOV |
|---|---|---|---|---|---|---|
| winston | 9.1.0 | 9.1.9 | 6.17.13-6-pve | 7.0.2-6 | 2025.10.10 | 7/7 VFs active |
| reginald | 9.2.0 | 9.1.11 | 6.17.13-6-pve | 7.0.2-6 | n/a | n/a |

---

## Phase 0 — Pre-flight (no downtime)

### 0.1 PBS backups

```bash
# winston — backup ALL guests via PBS UI or:
ssh root@192.168.100.38 'vzdump 100 102 105 106 --storage <pbs-store> --mode snapshot --notes-template "pre-pve92-upgrade {{guestname}}"'

# reginald — empty, snapshot host config
ssh root@192.168.100.4 'tar -czf /root/etc-pve.pre-pve92.tar.gz /etc/pve'
```

### 0.2 Repo docs refreshed (committed before upgrade)

- `.claude/rules/gpu-sriov-lessons.md` — added 2026.05.06 row.
- `.claude/rules/infra-lessons.md` — corrected "7.0 kernel = no SR-IOV" row.
- `docs/sr-iov/proxmox9-migration.md` — appended PVE 9.2 section pointing here.
- This runbook.

Flatcar sysext build (`vms/flatcar-media/sysext/i915-sriov/build.sh`) untouched — Flatcar kernel still 6.12.87.

### 0.3 Stage DKMS package on winston

```bash
ssh root@192.168.100.38
cd /root
wget https://github.com/strongtz/i915-sriov-dkms/releases/download/2026.05.06/i915-sriov-dkms_2026.05.06_amd64.deb
sha256sum i915-sriov-dkms_2026.05.06_amd64.deb  # record
```

### 0.4 Confirm rollback path

```bash
ssh root@192.168.100.38 'proxmox-boot-tool kernel list'  # expect 6.17.13-6 + 7.0.2-6 both present
ssh root@192.168.100.4  'bootctl list | grep -E "title|default"'
```

Keep 6.17.13-6 on both hosts until +14 days post-upgrade.

---

## Phase 1 — Reginald canary (~10 min)

Reginald: no GPU, no VMs. Cleanest signal on PVE 9.2 userspace + kernel 7.0 boot.

### 1.1 Disk cleanup

```bash
ssh root@192.168.100.4
dpkg -l | grep -E 'proxmox-kernel-(6\.8|6\.14|6\.17|7)'
apt purge -y proxmox-kernel-6.8.12-13-pve-signed proxmox-kernel-6.8.12-4-pve-signed
apt purge -y proxmox-kernel-6.14.11-7-pve-signed proxmox-headers-6.14.11-7-pve
bootctl list | grep title  # drop orphan /boot/efi/loader/entries/*.conf
apt autoremove --purge -y && apt clean
df -h / /boot /boot/efi  # target ≥6GB / and ≥3 free ESP slots
```

### 1.2 Full upgrade + kernel 7.0 install

```bash
apt update
apt list --upgradable | tee /tmp/pve92-upgradable.txt
apt full-upgrade -y
apt install -y proxmox-kernel-7.0 proxmox-headers-7.0
dpkg -l | grep -E 'proxmox-(kernel|headers)-7\.0'
```

### 1.3 Pin kernel 7.0 (GRUB-PC — reginald boots legacy CSM)

**Important correction from execution 2026-05-22**: Reginald boots via legacy GRUB-PC (CSM), NOT systemd-boot. `bootctl status` reports "Not booted with EFI". Edits to `/boot/efi/loader/loader.conf` are ignored. Use `proxmox-boot-tool kernel pin` (writes GRUB drop-in at `/etc/default/grub.d/proxmox-kernel-pin.cfg`, runs update-grub).

```bash
proxmox-boot-tool kernel pin 7.0.2-6-pve
grep 'set default' /boot/grub/grub.cfg   # verify points to 7.0.2-6
```

### 1.4 Reboot

```bash
reboot
# ~60s, then from laptop:
ssh root@192.168.100.4 'uname -r && pveversion'  # expect 7.0.2-6-pve + 9.2.x
```

### 1.5 Validate

```bash
ssh root@192.168.100.4 '
  uname -r
  pveversion -v
  systemctl --failed
  journalctl -p err -b | head -50
  zpool status -x 2>/dev/null || echo "no ZFS"
  ip a
'
```

Pass: boot clean, no failed services, NICs up, SSH responsive.

**Rollback**: `sed -i 's|^default .*|default ${MACHINE_ID}-6.17.13-6-pve.conf|' /boot/efi/loader/loader.conf; reboot`

If reginald passes → winston same day. If fails → STOP.

---

## Phase 2 — Winston (~30 min with VM downtime)

### 2.1 Pre-shutdown checks (no downtime)

```bash
ssh root@192.168.100.38
apt update
apt list --upgradable | tee /tmp/pve92-upgradable-winston.txt
ls -la /root/i915-sriov-dkms_2026.05.06_amd64.deb
sha256sum /root/i915-sriov-dkms_2026.05.06_amd64.deb
lspci -nn | grep -iE 'VGA|Display' > /root/pre-upgrade-lspci.txt
dkms status > /root/pre-upgrade-dkms.txt
cat /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs > /root/pre-upgrade-vfs.txt
qm list > /root/pre-upgrade-qm.txt
pct list > /root/pre-upgrade-pct.txt
```

### 2.2 Maintenance window — graceful guest shutdown

```bash
qm shutdown 100   # flatcar-media
qm shutdown 102   # homeassistant
pct shutdown 105  # Plex (PF GPU — must stop before kernel swap)
pct shutdown 106  # PDM
# Plus 101/103 if on winston

while qm list | grep -q running || pct list | grep -q running; do sleep 5; done
qm list && pct list
```

### 2.3 Install PVE 9.2 + kernel 7.0 + new DKMS

```bash
apt full-upgrade -y
apt install -y proxmox-kernel-7.0 proxmox-headers-7.0
ls /lib/modules/7.0.2-6-pve/build/Makefile  # MUST exist before dpkg -i

dkms remove i915-sriov-dkms/2025.10.10 --all 2>/dev/null || true
dpkg -i /root/i915-sriov-dkms_2026.05.06_amd64.deb
dkms status
# Expect installed for BOTH 6.17.13-6-pve and 7.0.2-6-pve

# If 7.0.2-6 missing:
dkms install i915-sriov-dkms/2026.05.06 -k 7.0.2-6-pve
cat /var/lib/dkms/i915-sriov-dkms/2026.05.06/build/make.log  # diagnose
```

**STOP** if DKMS fails 7.0.2-6. Boot back to 6.17.13-6 (still has working module), restart guests.

### 2.4 Pin kernel 7.0 (GRUB)

```bash
proxmox-boot-tool kernel pin 7.0.2-6-pve
proxmox-boot-tool refresh
grep 'set default' /boot/grub/grub.cfg
```

### 2.5 Verify cmdline

```bash
cat /etc/default/grub | grep CMDLINE
# Must contain: intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe
```

### 2.6 Reboot

```bash
sync && reboot
# 90-120s
```

### 2.7 Validate (moment of truth)

```bash
ssh root@192.168.100.38 '
  uname -r
  pveversion
  dkms status
  lsmod | grep -c xe || echo "xe NOT loaded (good)"
  lsmod | grep -E "^i915"
  lspci -nn | grep -iE "VGA|Display|Graphics" | wc -l    # expect 8
  cat /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs   # expect 7
  cat /sys/devices/pci0000:00/0000:00:02.0/sriov_totalvfs # expect 7
  ls -la /dev/dri/
  systemctl --failed
  journalctl -k -b -p err | grep -iE "i915|sriov|vf" | head -30
'
```

Pass (ALL): kernel 7.0.2-6-pve, pve-manager 9.2.x, DKMS 2026.05.06 installed on 7.0.2-6, 8 VGA lines, 7 VFs, /dev/dri card0..7 + renderD128..135, no failed units, no i915/sriov ERRORs.

### 2.8 Start guests

```bash
pct start 105            # Plex
sleep 10
pct start 106            # PDM
pct start 101 || true    # nextcloud
pct start 103 || true    # immich
qm start 102             # HA
sleep 30
qm start 100             # flatcar (heaviest)
qm list && pct list
```

### 2.9 Smoke

- `intel_gpu_top --device /dev/dri/renderD128` shows transcode load
- `ssh core@192.168.100.100 'docker ps --format "{{.Names}}\t{{.Status}}"'` all up/healthy
- `docker exec gluetun wget -qO- https://ipinfo.io/ip` returns Proton egress
- `docker exec gluetun cat /tmp/gluetun/forwarded_port` non-empty
- Homepage loads `https://home.disconnesso.com`
- HA UI loads

---

## Phase 3 — Post-upgrade

### 3.1 Soak (24h)

```bash
ssh root@192.168.100.38 'journalctl -k --since "24h ago" | grep -iE "i915|sriov|drm|gpu" | grep -iE "error|warn|fail" | head'
ssh root@192.168.100.4  'journalctl --since "24h ago" -p err | head -50'
```

### 3.2 Cleanup (+14d only if stable)

```bash
# winston
proxmox-boot-tool kernel unpin
proxmox-boot-tool kernel pin 7.0.2-6-pve
apt purge proxmox-kernel-6.17.13-1-pve-signed proxmox-headers-6.17.13-1-pve

# reginald — keep 6.17.13-6 as one fallback
apt purge proxmox-kernel-6.17.13-1-pve-signed
```

### 3.3 Memory update

`feedback_proxmox_kernel_headers.md` companion: note 2026.05.06 unlocks kernel 7.0.

---

## Rollback

### Reginald (legacy GRUB-PC)
```bash
proxmox-boot-tool kernel pin 6.17.13-6-pve   # writes grub drop-in + runs update-grub
reboot
```

### Winston (GRUB)
```bash
proxmox-boot-tool kernel unpin
proxmox-boot-tool kernel pin 6.17.13-6-pve
proxmox-boot-tool refresh
reboot
```

### Nuclear
Restore VM 100 + 102 + LXC snapshots from PBS.

---

## Out of scope

- LXC 101/103 PF→VF migration (separate task)
- Flatcar sysext bump to DKMS 2026.05.06 (channel still 6.12.87)
- PVE host firewall enable flip (`project_proxmox_firewall_rollout`)

---

## Phase 4 — PBS (proxmox-backup-server) parity bump

PBS (VM on QNAP, 192.168.100.187, 2 GB) is independent of PVE 9.2 but tracks the same kernel/Debian line. Already on PBS 4.x, just a point release + kernel parity.

Pre-state (2026-05-22): PBS 4.0/proxmox-backup-server 4.1.2 on kernel 6.17.9-1-pve. 14 installed kernels (6.8 line + 6.14 line + old 6.17 leftovers).

```bash
ssh root@192.168.100.187
# No active vzdump from clients; proxmox-backup-proxy can stay up during apt.
ps aux | grep -E 'vzdump|proxmox-backup-client' | grep -v grep

# Aggressive old-kernel purge (PBS has no DKMS / no GPU — safe)
DEBIAN_FRONTEND=noninteractive apt purge -y \
  proxmox-kernel-6.8 proxmox-kernel-6.8.12-{9,10,11,13}-pve-signed \
  proxmox-kernel-6.14 proxmox-kernel-6.14.{8-2,11-1,11-4,11-5}-pve-signed \
  proxmox-kernel-6.17.{2-2,4-2}-pve-signed

DEBIAN_FRONTEND=noninteractive apt full-upgrade -y    # pulls PBS 4.2.0 + kernel 6.17.13-11
DEBIAN_FRONTEND=noninteractive apt install -y proxmox-kernel-7.0   # pulls 7.0.2-6
proxmox-boot-tool kernel pin 7.0.2-6-pve

sync && reboot
```

Post-reboot validation:

```bash
ssh root@192.168.100.187 '
  uname -r                                  # expect 7.0.2-6-pve
  proxmox-backup-manager versions | head    # expect 4.2.0 running
  systemctl --failed
'
# From a PVE node
ssh root@192.168.100.38 'pvesm status -storage pbs-backupnas'   # expect active
```

PBS came back on **kernel 7.0.2-6-pve** + **proxmox-backup-server 4.2.0**. PVE storage stayed active across the reboot (PVE-side reconnects automatically when the proxy comes up). One quirk: short post-boot window where SSH was reachable (port 22 open) but `ConnectTimeout=3` was too aggressive — load avg 4.98 at 4 min uptime, indexer/maintenance jobs catching up. Use `ConnectTimeout=10` for PBS post-boot polling.

---

## Outcome (executed 2026-05-22 ~22:00 CEST)

**Result**: SUCCESS. Both hosts on PVE 9.2.2 + kernel 7.0.2-6-pve. SR-IOV intact on winston (7/7 VFs). Total wall time ~50 min including diagnosis of mid-flight deviations.

**Deviations from plan**:

1. **Asset filename**: GitHub release asset is `i915-sriov-dkms_2026.05.06_amd64.deb`, not `_all.deb`. Plan corrected, downloaded SHA `700b95ee06a511ed30b8bfb8fd9023f9ada89786e81cc889cbacc0c3607a47e9`.
2. **Kernel version**: Target was 7.0.0-3 per plan but PVE no-subscription stable already had **7.0.2-6** by 2026-05-22. Used 7.0.2-6 (strictly newer, same major). DKMS builds against both.
3. **Reginald bootloader misidentified**: Plan + repo rules said reginald = systemd-boot. Actual: legacy GRUB-PC (CSM). `bootctl status` returned "Not booted with EFI". loader.conf edits were ignored — first reboot came back on old kernel 6.17.13-6. Fix: `proxmox-boot-tool kernel pin 7.0.2-6-pve` writes a GRUB drop-in that works for both legacy and EFI GRUB. Rules + runbook corrected.
4. **dkms-check-boot.service failed on winston**: `/usr/local/sbin/dkms-kernel-hook` had a broken shebang (`#\!/bin/bash` — backslash escape from a prior heredoc edit). Fixed inline with `sed -i "1c #!/bin/bash"`. Service then active.
5. **6.17.13-11 headers**: `apt full-upgrade` installed kernel 6.17.13-11 but skipped DKMS for it because `proxmox-headers-6.17.13-11-pve` wasn't pulled by metas. Manually installed; DKMS then built 2026.05.06 for it too. Result: DKMS active on all 5 kernels (6.17.13-1, -6, -11, 7.0.0-3, 7.0.2-6).

**Pre-existing issues (not introduced by upgrade)**:

- reginald `openipmi.service` failed — Zimaboard has no IPMI hardware.
- winston systemd ordering-cycle: `nfs-server.service` vs `mnt-nfs_media.mount` (job deleted to break cycle). NFS still works.

**Post-upgrade verification snapshot**:

- winston: kernel 7.0.2-6-pve, pve-manager 9.2.2, xe not loaded, 8 VGA lspci, sriov_numvfs=7, /dev/dri populated (card0..7 + renderD128..135, LXC GID mapping intact), DKMS 2026.05.06 active on 5 kernels.
- reginald: kernel 7.0.2-6-pve, pve-manager 9.2.2, ZFS healthy, LXC 120 Technitium DNS active, no DNS resolution gap (verified `dig @192.168.100.120 home.disconnesso.com` returned 192.168.100.100).
- Flatcar VM 100: 36 containers up, gluetun egress 205.147.16.222, qbit forwarded port 52227, Plex GPU mounted in LXC 105.
- Endpoint smoke: HA=200, nextcloud=302, homepage.home.disconnesso.com=200.

---

## Sources

- https://github.com/strongtz/i915-sriov-dkms/releases/tag/2026.05.06
- https://github.com/strongtz/i915-sriov-dkms/pull/438
- https://github.com/strongtz/i915-sriov-dkms/issues/429
- https://forum.proxmox.com/threads/proxmox-virtual-environment-9-2-available.183741/
- https://forum.proxmox.com/threads/opt-in-linux-7-0-kernel-for-proxmox-ve-9-available-on-test-and-no-subscription.182328/page-3
