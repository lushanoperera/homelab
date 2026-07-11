# Proxmox Host Firewall — winston + reginald

Host-level firewall closes the lateral-movement gap from VM 100 (Traefik DMZ,
Cloudflared tunnel, Nextcloud, Immich, Vaultwarden) to the hypervisor
management plane on both nodes and to PBS (.100.187). Per-VM firewall stays
off — multicast/mDNS breakage is documented in `.claude/rules/infra-lessons.md`.

## Files

| Repo path                                 | Authoritative path on host               |
| ----------------------------------------- | ---------------------------------------- |
| `hosts/common/cluster.fw`                 | `/etc/pve/firewall/cluster.fw`           |
| `hosts/winston/firewall/host.fw`          | `/etc/pve/nodes/winston/host.fw`         |
| `hosts/reginald/firewall/host.fw`         | `/etc/pve/nodes/reginald/host.fw`        |

`/etc/pve/` is pmxcfs — lost on bare-metal reinstall (same gap that dropped
vzdump jobs for 5 months in 2025-10). Repo is the DR source of truth.
Standalone (non-clustered) nodes do NOT auto-sync cluster.fw to peers; the
deploy script copies to each host individually.

## Deploy script

```bash
./scripts/hosts/deploy-firewall.sh <winston|reginald> [--enable|--disable|--status]
```

Default action: copy configs + `pve-firewall compile` (no enable change).
`--enable` and `--disable` flip only the host.fw `enable:` line — cluster.fw
stays at whatever the repo committed (always 0 by default).

## Required inbound flows

### Both hosts (admin plane)

| Proto | Port      | Source            |
| ----- | --------- | ----------------- |
| TCP   | 22        | `admin_sources`   |
| TCP   | 8006      | `admin_sources`   |
| TCP   | 3128      | `admin_sources`   |
| TCP   | 5900-5999 | `admin_sources`   |
| ICMP  | echo-req  | any (diagnostics) |

`admin_sources` = `192.168.2.0/24` (Trusted), `192.168.100.106` (PDM),
`192.168.100.38` + `192.168.100.4` (peer hypervisors as literals),
`10.0.0.0/24` (nwlab WG).

Deviation from the original plan text, which included `192.168.100.0/20`.
That /20 contains VM 100 (the stated attack surface), which would let a
compromised VM 100 SSH straight to both hypervisor admin planes — defeating
the threat model. Narrowed deliberately; widen only if a concrete admin
workflow breaks, and document why.

### Reginald only (NFS server)

| Proto   | Port  | Source        |
| ------- | ----- | ------------- |
| TCP     | 2049  | `storage_lan` |
| TCP/UDP | 111   | `storage_lan` |
| TCP     | 20048 | `storage_lan` |

`storage_lan` = `192.168.200.0/24`.

Outbound is ACCEPT on both hosts — egress filtering on a hypervisor is
maintenance pain with no real blast-radius reduction.

## Anti-lockout safeguards (mandatory — do ALL before each enable flip)

1. **Two-level kill switch**. Both `cluster.fw enable: 1` AND host `enable: 1`
   are required for rules to activate. Flipping `cluster.fw` to 0 on either
   host instantly disables the firewall everywhere (on that host). This is
   the primary emergency off switch.
2. **Existing SSH survives rule reload**. Conntrack preserves established
   connections. **Never close the active SSH session during a phase flip** —
   test from a *second* terminal.
3. **Dead-man cron auto-disable**. Install on the target host before the
   enable flip:

   ```
   * * * * * root [ -f /root/.fw-deadman-armed ] && \
     [ $(($(date +%s) - $(stat -c %Y /root/.fw-deadman-armed))) -gt 600 ] && \
     pve-firewall stop && \
     sed -i 's/enable: 1/enable: 0/' /etc/pve/firewall/cluster.fw && \
     rm /root/.fw-deadman-armed
   ```

   Arm with `touch /root/.fw-deadman-armed` immediately before enabling.
   Disarm with `rm /root/.fw-deadman-armed` only after verification passes.
   If anything breaks AND the host is unreachable for 10 minutes, cron
   auto-disables the firewall.
4. **Hardcode laptop IP** inside `cluster.fw [IPSET admin_sources]` alongside
   the `192.168.2.0/24` range. On the laptop:
   `ip route get 192.168.100.4 | awk '{print $7}'` — add that literal IP.
   Even if VLAN routing hiccups, the literal still matches.
5. **Compile + simulate** before any enable flip:

   ```
   pve-firewall compile                                            # 0 errors required
   pve-firewall simulate --from <laptop_ip> --to <host_ip>:22 --protocol tcp
   pve-firewall simulate --from 192.168.100.106 --to <host_ip>:8006 --protocol tcp
   pve-firewall simulate --from 192.168.200.100 --to 192.168.200.4:2049 --protocol tcp   # reginald only
   ```
6. **Console fallback**.
   - Winston: Minisforum MS-01 → HDMI + USB keyboard, physically accessible.
   - Reginald: Zimaboard 832 → HDMI + USB keyboard, physically accessible.
   - Out-of-band SSH via nwlab WG (10.0.0.0/24) if local network is the problem.
7. **Printed runbook** (paper or second device) with the recovery commands
   below. If the laptop's primary SSH is the thing that breaks, blind recovery
   needs the commands in eyeball range.

## Rollout order — reginald first

Reginald has the smaller blast radius: no VMs, only two LXCs (DNS + Samba)
that don't terminate on the hypervisor. Winston follows after 24 h of
reginald stability.

### Pre-flight (once, before touching either host)

- [ ] Paper/second-device printout of recovery commands.
- [ ] Two SSH terminals open per host, both verified working.
- [ ] Console access verified — walk to the box, confirm HDMI output, save
      the session.
- [ ] Laptop IP hardcoded in `admin_sources` in the committed `cluster.fw`.
- [ ] `deploy-firewall.sh <host>` — configs copied + compiled clean.

### Reginald

| Step | Action                                                                                 |
| ---- | -------------------------------------------------------------------------------------- |
| R0   | `./scripts/hosts/deploy-firewall.sh reginald` — configs staged, enable: 0, compiled.   |
| R1   | `ssh root@192.168.100.4 pve-firewall simulate ...` — SSH, 8006, NFS all ACCEPT.        |
| R2   | `ssh root@192.168.100.4 touch /root/.fw-deadman-armed` + install cron line.            |
| R3   | Flip `cluster.fw enable: 1` AND reginald `host.fw enable: 1` (still policy_in: ACCEPT).|
| R3v  | Verify from a **fresh** SSH terminal (see "Verification" below). Dwell 30 min. Tail `/var/log/pve-firewall.log` and look for unexpected traffic — **this dwell only works because there is no explicit catch-all `IN DROP` rule**. Explicit drop rules fire before `policy_in` evaluates, so adding one turns Phase A into Phase B silently. Leave it off until R6. |
| R4   | `ssh root@192.168.100.4 rm /root/.fw-deadman-armed` — disarm.                          |
| R5   | Re-arm: `ssh root@192.168.100.4 touch /root/.fw-deadman-armed`.                        |
| R6   | Flip reginald `host.fw policy_in: DROP`, reload: `pve-firewall reload`. Dwell 30 min.  |
| R7   | Disarm: `rm /root/.fw-deadman-armed`. Reginald done.                                   |

Wait 24 h for reginald to stay stable under DROP before starting winston.

### Winston

Same pattern as R0-R7. Additional verifications listed below.

### Post

- Commit final working configs back to the repo (they should already match).
- Update `.claude/rules/infra-lessons.md` and `CLAUDE.md` Security posture
  with any surprises observed during dwell.

## Verification

After R3 and R6 (and W3 / W6 on winston), run from a **fresh** SSH session:

```bash
# Admin access from laptop
ssh root@192.168.100.4 hostname
ssh root@192.168.100.38 hostname

# Admin access via PDM (nested jump)
ssh root@192.168.100.106 'ssh root@192.168.100.4 hostname'
ssh root@192.168.100.106 'ssh root@192.168.100.38 hostname'

# NFS from Flatcar (reginald only)
ssh core@192.168.100.100 'ls /mnt/media /mnt/ncdata /mnt/immich'

# Internal DNS (reginald LXC 120)
dig @192.168.100.120 google.com +short

# Samba (reginald LXC 123)
smbclient -L //192.168.100.123 -N

# PDM webui shows both hosts green
# Firewall log — look for unexpected drops
ssh root@192.168.100.4 tail -n 100 /var/log/pve-firewall.log
ssh root@192.168.100.38 tail -n 100 /var/log/pve-firewall.log

# Rule counters — allows > 0, DROP > 0 in Phase B
ssh root@<host> iptables -L PVEFW-HOST-IN -nvx | head -40
```

Winston-specific (after W3 / W6):

```bash
curl -I https://nextcloud.lushanoperera.com                   # 200 OK
curl -I http://192.168.4.102:8123                             # HA reachable
# LXCs 104/105/106 — start/stop/console via PDM webui
# PBS test backup
ssh root@192.168.100.38 'vzdump 106 --storage pbs-backupnas --mode snapshot --remove 0'
```

Negative tests — these MUST fail (confirms policy effective):

```bash
# From any VLAN NOT in admin_sources (IoT .4.x, Guests .3.x, DMZ .7.x)
nmap -Pn -p 22,8006 192.168.100.38   # → filtered
nmap -Pn -p 22,8006 192.168.100.4    # → filtered
```

## Break-glass / lockout recovery

Ordered by preference:

1. **Wait for dead-man cron** (≤10 min). Auto-disables if armed + host
   unreachable. Confirm the cron line is installed before arming:
   `ssh root@<host> grep fw-deadman /etc/crontab`.
2. **Physical console**:
   - Winston: Minisforum MS-01 → HDMI + USB keyboard → root login →
     `pve-firewall stop && sed -i 's/enable: 1/enable: 0/' /etc/pve/firewall/cluster.fw`.
   - Reginald: Zimaboard 832 → same commands.
3. **Second SSH session held open** throughout rollout — conntrack preserves
   it across rule changes. From that session: `pve-firewall stop` + edit
   config.
4. **Out-of-band via nwlab WG** (10.0.0.0/24) if `admin_sources` includes it
   and the tunnel is still up. SSH in from nwlab-thinkpad.
5. **PDM webui** — **not independent**. PDM lives in LXC 106, so if admin
   plane is cut PDM may also be blind. Do not rely on it as primary.

### Datacenter-level kill switch

From any working shell on the affected host:

```bash
pve-firewall stop
sed -i 's/enable: 1/enable: 0/' /etc/pve/firewall/cluster.fw
```

This instantly disables the firewall on that host regardless of host.fw
state. On standalone (non-clustered) nodes it does NOT propagate to the peer
— run it on each host separately.

### Rollback

At any point, either host:

```bash
ssh root@<host> 'pve-firewall stop; sed -i "s/enable: 1/enable: 0/" /etc/pve/nodes/<node>/host.fw /etc/pve/firewall/cluster.fw'
```

## Deferred / not in this runbook

- Per-VM firewall re-enable (stays off — multicast/mDNS issue).
- LXC `firewall=1` for LXCs 104/105/106/120 (decide per-guest; LXC 123 Samba
  already has its own nftables).
- Outbound filtering on the hypervisor.
- Datacenter-wide `enable: 1` permanently in `cluster.fw` — staged as 0,
  flipped at rollout time, committed back as 1 once both hosts are stable.
