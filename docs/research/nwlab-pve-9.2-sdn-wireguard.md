# Research: nwlab ↔ homelab via PVE 9.2 SDN + WireGuard

> Status: **Phase 0 complete (2026-05-27)** — nwlab on PVE 9.2.2 + kernel 7.0.2-6. Phase 1 (SDN WG fabric cutover) unblocked. No execution this session.
> Date: 2026-05-27
> Related runbook: [docs/migrations/pve-9.2-kernel-7-upgrade.md](../migrations/pve-9.2-kernel-7-upgrade.md)

## Context

Winston + Reginald upgraded to PVE 9.2.2 on 2026-05-22 (kernel 7.0.2-6-pve, SR-IOV intact). PVE 9.2 (released 2026-05-21) introduced a **native WireGuard SDN fabric** plus BGP/EVPN/OSPF improvements and a dry-run mode. The current cross-site link to nwlab-thinkpad (10.21.21.99) is a hand-rolled `wg-quick@wg-nwlab` on winston host with MASQUERADE — functional, but invisible to PDM and not GUI-managed.

User asked whether the 9.2 upgrade unlocks something better. Deliverable is a research report only — **no execution this session**, and nwlab's pending 9.2 upgrade (deferred until on-site visit) is treated as a hard prerequisite for any future migration.

## Current State (verified)

### Hosts

- **winston**: PVE 9.2.2, kernel 7.0.2-6-pve, SR-IOV 7/7 VFs
- **reginald**: PVE 9.2.2, kernel 7.0.2-6-pve (legacy GRUB-PC bootloader)
- **nwlab-thinkpad**: PVE 9.2.2, kernel 7.0.2-6-pve (upgraded on-site 2026-05-27). Single physical NIC (`enp0s31f6` → `vmbr0`). Single flat subnet 10.21.21.0/24. No VLANs, no SDN. ZFS userland 2.4.2-pve1, `zpool storage` feature flags upgraded (no longer importable by ZFS < 2.4). Pre-upgrade PBS snapshots tagged `pre-pve92-kernel70-upgrade` on `pbs-nwlab`
- Hosts are **standalone** — no PVE cluster. PDM (LXC 106) federates them via API tokens

### Cross-site link

- `wg-nwlab` on winston host (NOT inside LXC 104 — LXC 104 is the separate wg-easy remote-access server)
- Overlay: winston `10.0.0.5/32`, nwlab gateway `10.0.0.1/24` (wg-easy on nwlab LXC 100), MTU 1420
- AllowedIPs: `10.0.0.0/24, 10.21.21.0/24`
- Endpoint: `80.210.114.192:51820`
- Routing: PDM has static route `10.21.21.0/24 via 192.168.100.38 (winston)`, both ends MASQUERADE
- Live flows: PDM → nwlab PVE API (10.21.21.99:8006); homelab PBS ↔ nwlab PBS daily backup sync (push 04:00, reverse 21:00)

### SDN state

- `/etc/pve/sdn/` empty on all hosts. VLANs handled by UniFi UCG-Fiber upstream
- No EVPN, no VXLAN, no fabric configured anywhere

## PVE 9.2 SDN + WireGuard — What's Actually New

From Proxmox 9.2 release notes + SDN wiki:

- **WireGuard fabric**: native SDN fabric type. "Encrypted node-to-node tunnels usable as a secure underlay for VXLAN networks, migration networks, and cross-cluster connectivity." Per-node key management automated. **External peers supported** (not only PVE↔PVE)
- **BGP fabric**: eBGP unnumbered (no IPs on fabric links, per-node ASN)
- **EVPN improvements**: multiple controllers per cluster (Inter-AS), IPv6 underlay, route maps / prefix lists for filtering
- **OSPF**: route redistribution (connected/local/kernel/BGP)
- **Dry-run mode**: validate SDN changes before apply — relevant because EVPN/VXLAN misconfig is hard to roll back
- **Resource tree integration**: fabrics surface routes/neighbors/interfaces in GUI; EVPN zones show learned MAC/IP

What did NOT change:

- SDN config lives in `/etc/pve/sdn/` per datacenter. **Standalone hosts each have their own datacenter** — SDN config does NOT auto-replicate between standalone PVE installs. WG fabric still has to be configured on each side, just via the GUI instead of `wg-quick`.
- Cluster formation across WAN remains corosync-latency-bound (≤10ms RTT recommended) — WG fabric doesn't change that physics

## Viable Patterns (ranked by recommendation)

### Pattern A — Replace `wg-nwlab` with SDN WireGuard fabric (recommended next step)

After nwlab is on 9.2, retire the hand-rolled `wg-quick@wg-nwlab` on winston and the wg-easy LXC 100 on nwlab. Define a WireGuard fabric on each datacenter (winston + nwlab) with the other side as an external peer. PDM continues federating both standalone hosts.

**Gains:**

- GUI-managed, visible in PDM resource tree
- Per-node automated key management → no more manual key rotation
- Dry-run before apply
- Same L3 routing as today, no MASQUERADE NAT change required (or move NAT to SDN/firewall layer)

**Costs:**

- Coordinated cutover (both sides must be 9.2)
- PBS sync + PDM federation both ride the existing tunnel — cutover window must coordinate both
- Reginald gains nothing direct (only winston runs the tunnel today)

### Pattern B — Stack VXLAN zone over the WG fabric (L2 stretch, optional Phase 2)

Adds a VXLAN zone on top of the WG fabric so VMs on nwlab and homelab can share a Layer-2 broadcast domain. MTU planning: WG = 1420 → VXLAN MTU 1370 (50-byte VXLAN overhead).

**When this is worth it:**

- You want a VM on nwlab to live on the same subnet as a VM on winston (e.g. for migration testing, shared services without NAT, identical IP plan)
- L3 routing today already does everything the user needs → **skip unless a concrete use case appears**

**Forum-documented gotcha:** PVE SDN does not wait for WireGuard to come up at boot — race condition can leak MAC addresses during reboot. Mitigation = systemd ordering, well-known issue.

### Pattern C — Cluster across the WAN (NOT recommended)

A 3-host cluster (winston + reginald + nwlab) over WG fabric. Theoretically possible. Practically: corosync requires sub-10ms RTT; a WAN tunnel with home-broadband jitter will cause cluster instability and fencing surprises. PDM federation already gives the centralized-management benefit without the corosync risk. **Explicitly de-scope.**

## Recommendation

**Phase 0 (DONE 2026-05-27):** nwlab-thinkpad upgraded on-site to PVE 9.2.2 + kernel 7.0.2-6. proxmox-ve meta 9.0.0 → 9.2.0, ZFS 2.3.4 → 2.4.2, Ceph 19.2.3-pve2 → -pve4, Corosync 3.1.9 → 3.1.10, FRR 10.3 → 10.6. All 5 guests rebooted clean, WG handshakes green, idle ~8.2 W. Pre-upgrade snapshots `pre-pve92-kernel70-upgrade` retained on `pbs-nwlab`. 6.17.13-11 kept as GRUB fallback.

**Phase 1 (unblocked, ready when scheduled):** Implement Pattern A — migrate `wg-nwlab` to SDN WireGuard fabric. Keep MASQUERADE/routing identical so PDM federation and PBS backup sync don't notice. Validate with dry-run, cut over in a maintenance window, verify PBS push job + PDM reachability post-cutover.

**Phase 2 (optional, only if needed):** Layer a VXLAN zone on the WG fabric if a real cross-site L2 use case appears. Plan MTU = 1370. Address the boot-time race with systemd ordering.

**De-scope:** PVE clustering across the WAN.

## Critical Files / Pointers (for the future implementation)

- `docs/migrations/pve-9.2-kernel-7-upgrade.md` — Phase 0 runbook (reuse for nwlab)
- `/etc/wireguard/wg-nwlab.conf` on winston — current tunnel config to map onto fabric
- `/etc/pve/sdn/` on each host — where future fabric/zone YAML will live
- PDM LXC 106 routing config — static route `10.21.21.0/24 via 192.168.100.38` may need update if fabric moves the overlay subnet
- nwlab PBS push job (04:00 daily) + reverse sync (21:00) — both ride the tunnel and must survive cutover
- `.claude/rules/infra-lessons.md` — capture WG-fabric lessons here post-rollout

No files to be modified this session — research only.

## Verification (deferred to Phase 1 execution)

After Phase 1 cutover:

1. `wg show` on both hosts → handshake recent, transfer counters incrementing
2. `pvesh get /cluster/sdn/fabrics` → fabric reported healthy on both datacenters
3. PDM web UI: nwlab-thinkpad shown reachable, no token errors
4. PBS: trigger `proxmox-backup-manager sync-job run home-backup` manually, confirm success
5. `ping -M do -s 1392 10.21.21.99` from winston → confirm MTU sane (1420 WG MTU - 28 ICMP/IP)
6. Reboot winston → tunnel re-establishes on its own, PBS sync survives (boot-order race check)

## References

- [Proxmox VE 9.2 release announcement](https://proxmox.com/en/about/company-details/press-releases/proxmox-virtual-environment-9-2) — official 2026-05-21
- [Proxmox VE Roadmap](https://pve.proxmox.com/wiki/Roadmap) — 9.2 changelog
- [Software-Defined Network wiki](https://pve.proxmox.com/wiki/Software-Defined_Network) — zone types + fabric reference
- [SDN docs (HTML)](https://pve.proxmox.com/pve-docs/chapter-pvesdn.html)
- [VXLAN over WireGuard with OPNsense (buffashe blog, 2026-05)](https://blog.buffashe.com/en/2026/05/proxmox-vxlan-over-wireguard-opnsense/)
- [PVE 9.2 forum announcement thread](https://forum.proxmox.com/threads/proxmox-virtual-environment-9-2-available.183742/)
- [DATAZONE: PVE 9.2 — DLB, WireGuard SDN & Kernel 7.0](https://datazone.de/en/aktuelles/proxmox-ve-9-2-release/)
- Forum: [VXLAN over WireGuard cluster](https://forum.proxmox.com/threads/proxmox-cluster-over-2-sites-using-vxlan-over-wireguard.157400/), [boot-time race](https://forum.proxmox.com/threads/how-to-create-a-lan-over-wireguard-for-a-proxmox-cluster-that-encrypts-cluster-traffic-sdn-vxlan-traffic-without-mac-address-leakage.169522/)
