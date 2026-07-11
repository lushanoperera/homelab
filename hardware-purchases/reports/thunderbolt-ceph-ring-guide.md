# Thunderbolt 4 Ring Network for Ceph Replication (2026)

A practical guide to building a dedicated 40 Gbps Thunderbolt 4 cluster network across 3 Minisforum MS-01 Proxmox nodes for high-speed OSD replication in Ceph, achieving 16x throughput over 2.5GbE.

## 1. Why Thunderbolt 4 for Ceph

### Performance Gap

- **2.5GbE**: 312 MB/s maximum throughput, shared across all traffic (clients + replication)
- **Thunderbolt 4**: 40 Gbps (~5 GB/s) bidirectional per link, dedicated link
- **Improvement**: 16x faster than saturated 2.5GbE
- **Real-world speeds**: Community reports 18.5–26 Gbps sustained on TB4 ring networks

### Ceph Architecture

Ceph separates two networks:

1. **public_network**: Client I/O (VMs accessing RBD, CephFS mounts)
2. **cluster_network**: OSD replication and heartbeat traffic

The Thunderbolt ring becomes the cluster_network, keeping 2.5GbE for public traffic and management. This separation yields significant rebalance/recovery performance gains.

### Topology Advantages

- **Ring topology**: Point-to-point Thunderbolt links, no switch needed
- **High availability**: Any single link failure still leaves 2 paths for redundancy
- **Low latency**: Direct copper connections vs. switched fabric (sub-millisecond ping times possible)
- **Cost-effective**: $10–60 per cable vs. $200+ SFP+ dacs or switches
- **No extra hardware**: Uses native TB4 ports on MS-01

## 2. Ring Topology Diagram

```
        ┌─────────────────────────────┐
        │    Winston (Node A)         │
        │  192.168.100.38  TB0: .1    │
        │                             │
    TB0 │                         │ TB1
        │                             │
        └─────────────────────────────┘
              ↑                    ↓
           40 Gbps              40 Gbps
              ↑                    ↓
        ┌─────────────────────────────┐
        │    Reginald (Node B)        │
        │  192.168.100.4   TB0: .2    │
        │  TB1: .6                    │
        │                             │
    TB0 │                         │ TB1
        │                             │
        └─────────────────────────────┘
              ↑                    ↓
           40 Gbps              40 Gbps
              ↓                    ↑
        ┌─────────────────────────────┐
        │   PBS / Third Node (Node C) │
        │  192.168.100.187 TB0: .5    │
        │  (or Immich LXC if used)    │
        │                             │
    TB1 │                         │ TB0
        │                             │
        └─────────────────────────────┘

Legend:
TB0/TB1   = Thunderbolt port 0 and port 1
A ↔ B = passive or short active cable
Each node has 2 TB ports; forms complete ring
All 3 links active = 6 parallel Ceph replication paths
```

**IP Addressing Scheme**:

- **A↔B link**: 10.10.10.0/30 (A: .1, B: .2)
- **B↔C link**: 10.10.10.4/30 (B: .5, C: .6)
- **C↔A link**: 10.10.10.8/30 (C: .9, A: .10)

## 3. Thunderbolt 4 Cables: Types & EU Pricing

### Passive vs. Active

| Type        | Max Length | Technology                  | Cost (EU) | Use Case                               |
| ----------- | ---------- | --------------------------- | --------- | -------------------------------------- |
| **Passive** | 0.8 m      | Pure copper, no electronics | €15–30    | Adjacent nodes (same rack)             |
| **Active**  | 2.0 m      | Retimer chips boost signal  | €40–80    | Spaced nodes (different shelves/rooms) |
| **Active**  | 3.0 m      | Apple only; most expensive  | €80–120   | Very long runs                         |

### Recommended EU Cables (March 2026)

**Passive (Short Runs)**:
| Model | Length | EU Price | Retailer | Notes |
|-------|--------|----------|----------|-------|
| CalDigit TB4/USB4 | 0.8 m | €60–70 | [CalDigit EU Shop](https://shop.caldigit.com/eu) | Certified, 100W, stock available |
| Belkin Thunderbolt 4 | 0.8 m | €15–30 | [Geizhals.de](https://geizhals.de/thunderbolt-4-usb4-kabel-v97174.html) | Passive, budget-friendly |

**Active (Longer Runs)**:
| Model | Length | EU Price | Retailer | Notes |
|-------|--------|----------|----------|-------|
| CalDigit TB4/USB4 Active | 2.0 m | €80–100 | [CalDigit EU Shop](https://shop.caldigit.com/eu) | Signal boosters, certified |
| Plugable Thunderbolt 4 Active | 2.0 m | €65–80 | Amazon.de | 2m limit at 40 Gbps |
| Apple Thunderbolt Pro (braided) | 1.0 m | €50–60 | [Apple Store EU](https://www.apple.com) | Premium; excellent reliability |

**Budget Estimate (3 cables for ring)**:

- **All passive (0.8 m)**: 3 × €20 = **€60**
- **Mixed (1x passive + 2x active)**: €20 + 2 × €60 = **€140**
- **All active 2m**: 3 × €70 = **€210**

> **Note**: Geizhals.de is Germany's largest price comparison site; use regional filters for Italy, Austria, etc. Direct ship from Amazon.de/Amazon.it often cheaper than other EU retailers.

### Cable Specifications

All TB4 cables are Intel-certified and:

- Support 40 Gbps data transfer
- Support 100W USB Power Delivery (not needed for networking)
- Backwards compatible with TB3, USB4, USB 3.1
- Support 8K display @ 60Hz (irrelevant for networking)

## 4. Network Configuration: Linux Kernel & Modules

### Prerequisites

- **Proxmox VE 8.0+** (kernel 6.2.16-14-pve or higher)
- All three nodes running Debian 12 / Proxmox VE 8+
- Both TB4 ports on each MS-01 physically connected

### Load Kernel Modules

On each node, ensure `thunderbolt` and `thunderbolt-net` modules are loaded at boot:

```bash
# Add to /etc/modules
sudo tee -a /etc/modules > /dev/null <<EOF
thunderbolt
thunderbolt-net
EOF

# Load immediately
sudo modprobe thunderbolt
sudo modprobe thunderbolt-net

# Verify
lsmod | grep thunderbolt
# Output should show thunderbolt and thunderbolt_net
```

### Interface Enumeration

Thunderbolt creates virtual Ethernet interfaces named `thunderboltX`. Check which ports map to which interfaces:

```bash
# List all Thunderbolt interfaces
ip link show | grep thunderbolt

# Each TB port creates one interface. Example:
# 3: thunderbolt0: <BROADCAST,MULTICAST>
# 4: thunderbolt1: <BROADCAST,MULTICAST>
```

> **Important**: TB interface naming is **not stable** — they may renumber on reboot or cable insert order. Use **udev rules** to assign consistent names to physical ports.

### Stable Interface Naming (udev Rules)

Create a udev rule to consistently map physical Thunderbolt ports to interface names:

```bash
# On each node, create /etc/udev/rules.d/99-thunderbolt.rules
sudo tee /etc/udev/rules.d/99-thunderbolt.rules > /dev/null <<'EOF'
# Map physical TB4 ports to stable interface names
# Port 0 → tbert0, Port 1 → tbert1
SUBSYSTEM=="net", KERNEL=="thunderbolt*", ATTR{address}=="*", NAME="tbert%n"
EOF

# Reload udev
sudo udevadm control --reload
sudo udevadm trigger
```

> Verify the mapping by checking `/sys/class/net/tbert*/` after reboot.

## 5. Proxmox Network Configuration

### Step 1: Edit `/etc/network/interfaces` on Winston

```bash
# /etc/network/interfaces on Winston (Node A)

auto lo
iface lo inet loopback

# Management / Public network (2.5GbE)
auto enp11s0
iface enp11s0 inet static
    address 192.168.100.38/24
    gateway 192.168.100.1
    dns-nameservers 8.8.8.8 8.8.4.4

# Thunderbolt 0 → connects to Reginald TB0 (A ↔ B link)
allow-hotplug tbert0
iface tbert0 inet static
    address 10.10.10.1
    netmask 255.255.255.252
    mtu 1500
    # Optional: jumbo frames if needed
    # mtu 9000
    pre-up ip link set $IFACE up

# Thunderbolt 1 → connects to third node C TB0 (C ↔ A link)
allow-hotplug tbert1
iface tbert1 inet static
    address 10.10.10.10
    netmask 255.255.255.252
    mtu 1500
    pre-up ip link set $IFACE up
```

### Step 2: Edit `/etc/network/interfaces` on Reginald

```bash
# /etc/network/interfaces on Reginald (Node B)

auto lo
iface lo inet loopback

# Management / Public network
auto enp11s0
iface enp11s0 inet static
    address 192.168.100.4/24
    gateway 192.168.100.1
    dns-nameservers 8.8.8.8 8.8.4.4

# Thunderbolt 0 → connects to Winston TB0 (A ↔ B link)
allow-hotplug tbert0
iface tbert0 inet static
    address 10.10.10.2
    netmask 255.255.255.252
    mtu 1500
    pre-up ip link set $IFACE up

# Thunderbolt 1 → connects to third node C TB1 (B ↔ C link)
allow-hotplug tbert1
iface tbert1 inet static
    address 10.10.10.5
    netmask 255.255.255.252
    mtu 1500
    pre-up ip link set $IFACE up
```

### Step 3: Edit `/etc/network/interfaces` on Third Node (C)

If using PBS or another node:

```bash
# /etc/network/interfaces on Node C (PBS or Immich LXC host)

auto lo
iface lo inet loopback

auto enp11s0
iface enp11s0 inet static
    address 192.168.100.187/24
    gateway 192.168.100.1

# Thunderbolt 0 → connects to Reginald TB1 (B ↔ C link)
allow-hotplug tbert0
iface tbert0 inet static
    address 10.10.10.6
    netmask 255.255.255.252
    mtu 1500
    pre-up ip link set $IFACE up

# Thunderbolt 1 → connects to Winston TB1 (C ↔ A link)
allow-hotplug tbert1
iface tbert1 inet static
    address 10.10.10.9
    netmask 255.255.255.252
    mtu 1500
    pre-up ip link set $IFACE up
```

### Step 4: Apply Configuration

```bash
# On each node
sudo systemctl restart networking

# Verify interfaces are up
ip addr show | grep -E "tbert|10\.10\.10"

# Test connectivity
ping -c 2 10.10.10.2  # From Winston to Reginald
ping -c 2 10.10.10.6  # From Winston to Node C
```

## 6. Ceph Configuration

### Ceph Ring as cluster_network

Edit `/etc/ceph/ceph.conf` on all nodes (or via Proxmox GUI):

```ini
[global]
# ... existing config ...

# Public network (2.5GbE) — clients talk to OSDs here
public_network = 192.168.100.0/24

# Cluster network (Thunderbolt ring) — OSD replication here
cluster_network = 10.10.10.0/30, 10.10.10.4/30, 10.10.10.8/30

# Or CIDR notation (broader, less precise):
# cluster_network = 10.10.10.0/24
```

> **Why CIDR ranges?** Ceph allows OSDs to bind to any IP in the cluster_network range. Listing all three /30s ensures all links are recognized.

### Proxmox GUI Method

If using Proxmox UI to manage Ceph:

1. **Ceph → Cluster** → Edit cluster
2. Find or add `cluster_network` field
3. Enter: `10.10.10.0/30, 10.10.10.4/30, 10.10.10.8/30`
4. Save and restart Ceph daemons

### Verify Replication Traffic

After rebalancing, check which network OSDs use:

```bash
# On any node
sudo ceph osd dump | grep -A 20 "^osd"

# Look for "cluster_addrs" — should list 10.10.10.x IPs
# Example:
# osd.0 up   in  weight 1.0
#   addrs [v2:192.168.100.38:6802,v1:192.168.100.38:6803/…
#   cluster_addrs [v2:10.10.10.1:6800,…]
```

Monitor replication:

```bash
# Watch recovery/rebalance in real-time
sudo ceph -w

# Check cluster health
sudo ceph health detail
sudo ceph osd pool stats
```

## 7. Optional: Redundant Ring for Corosync (HA)

If running Proxmox HA (high-availability cluster), Corosync can use Thunderbolt as a redundant heartbeat network:

```bash
# Edit /etc/pve/corosync.conf
sudo nano /etc/pve/corosync.conf
```

Add a second interface:

```ini
nodelist {
  node {
    name: winston
    nodeid: 1
    quorum_votes: 1
    ring0_addr: 192.168.100.38
    ring1_addr: 10.10.10.1
  }
  node {
    name: reginald
    nodeid: 2
    quorum_votes: 1
    ring0_addr: 192.168.100.4
    ring1_addr: 10.10.10.2
  }
  # ... etc
}
```

This adds TB ring as secondary heartbeat path, improving quorum stability if 2.5GbE fails.

## 8. Known Issues & Troubleshooting

### Issue 1: Interface Numbering Changes on Reboot

**Symptom**: `tbert0` becomes `tbert1` after reboot; IPs don't come up.

**Root Cause**: Kernel assigns TB interface names based on probe order, not physical port.

**Fix**: Use the udev rule in Section 4, or script interface bring-up order in `/etc/network/interfaces` with `allow-hotplug` + explicit MTU + `pre-up`.

### Issue 2: Thunderbolt Ports Disabled in BIOS

**Symptom**: `lsmod | grep thunderbolt` shows module loaded, but `ip link show | grep thunderbolt` returns nothing.

**Root Cause**: Some MS-01 BIOS versions disable TB ports by default or require Intel certification re-enable.

**Fix**:

1. Update MS-01 BIOS to latest (Minisforum releases updates regularly)
2. Check BIOS setup for "USB4 Controller" or "Thunderbolt" settings; ensure enabled
3. Verify Thunderbolt dock/hub not blocking: plug cable directly into MS-01 USB-C port

**BIOS Update**:

```bash
# Check current BIOS version
sudo dmidecode | grep -i bios
# Download latest from Minisforum.com product page
# Follow their update procedure (usually USB-based)
```

### Issue 3: Slow Transfer Speeds (~1 Gbps instead of 18+ Gbps)

**Symptom**: `iperf3` shows 1–2 Gbps instead of expected 18+ Gbps.

**Common Causes**:

- Cable not fully seated or damaged
- MTU mismatch between endpoints
- Firmware issue with TB port (rare)

**Debug**:

```bash
# Test with iperf3 across TB ring
ssh core@192.168.100.100  # or to another node
iperf3 -s -B 10.10.10.1 &   # server listening on TB interface

# From another node
iperf3 -c 10.10.10.1 -t 30 -R  # test reverse direction

# Expected: >18 Gbps
# Poor result: reseat cables, check MTU (ip link show)
```

### Issue 4: Power Management / Autosuspend

**Symptom**: TB interface goes down after 5–10 minutes of idle time.

**Root Cause**: Kernel autosuspends TB4 ports to save power.

**Fix**: Disable autosuspend for Thunderbolt devices:

```bash
# List Thunderbolt USB devices
lsusb | grep -i thunderbolt

# Disable autosuspend
echo -1 | sudo tee /sys/bus/usb/devices/*/power/autosuspend_delay_ms

# Make permanent (systemd drop-in)
sudo mkdir -p /etc/systemd/system/systemd-udevd.service.d
sudo tee /etc/systemd/system/systemd-udevd.service.d/tb-autosuspend.conf > /dev/null <<'EOF'
[Service]
Environment="SYSTEMD_UDEVD_POWERSAVE=no"
EOF

sudo systemctl daemon-reload
```

### Issue 5: MTU Mismatches in Ceph Traffic

**Symptom**: Ceph rebalance is slow; monitor logs show fragmented packets.

**Recommendation**: Keep MTU 1500 (standard). Test jumbo frames (9000) only if all nodes support it:

```bash
# Test jumbo MTU (9000)
ip link set dev tbert0 mtu 9000

# Run iperf3 again
iperf3 -c 10.10.10.1 -t 10

# If drops increase, revert to 1500
ip link set dev tbert0 mtu 1500
```

## 9. Validation & Performance Testing

### Step 1: Test Connectivity

```bash
# From Winston, ping all TB peers
ping -c 5 10.10.10.2   # Reginald TB0
ping -c 5 10.10.10.6   # Third node TB0
ping -c 5 10.10.10.9   # Third node TB1

# Expected: all replies in <5 ms (often <1 ms)
```

### Step 2: Bandwidth Test (iperf3)

```bash
# Install iperf3 on all nodes
sudo apt update && sudo apt install -y iperf3

# On Reginald, start server on TB interface
ssh root@192.168.100.4
iperf3 -s -B 10.10.10.2 &

# From Winston, test
ssh root@192.168.100.38
iperf3 -c 10.10.10.2 -t 30 -R -P 4

# Expected output: 18–26 Gbps total (4–6 Gbps per thread)
# Example:
# [  5] (sender) Bitrate:  5.27 Gbps
# [  6] (sender) Bitrate:  5.31 Gbps
# ...
# [SUM] (sender) Bitrate:  21.4 Gbps
```

### Step 3: Ceph Rebalance Test

Trigger a deliberate rebalance to saturate the cluster network:

```bash
# Add a dummy pool to stress test
sudo ceph osd pool create test-rb 32

# Monitor traffic
sudo ceph -w

# Watch `recovering` and `backfilling` — should show >10 GB/s throughput
# Check Ceph dashboard for per-OSD replication bandwidth

# Clean up
sudo ceph osd pool delete test-rb test-rb --yes-i-really-mean-it
```

### Step 4: Monitor Ceph Health

```bash
# Full cluster health
sudo ceph health detail

# Per-OSD replication traffic
sudo ceph osd perf

# Example (high-load):
# osd.0  4521 MB/s wr, 2831 MB/s recovery
# osd.1  4389 MB/s wr, 2920 MB/s recovery
# (high numbers = TB ring working as intended)
```

## 10. Lessons & Best Practices

### Deployment Checklist

- [ ] All 3 MS-01 nodes have latest BIOS (check Thunderbolt support)
- [ ] All 6 TB4 ports physically connected with qualified cables
- [ ] Kernel modules `thunderbolt` and `thunderbolt-net` loaded on all nodes
- [ ] Udev rules applied for stable interface naming (`tbert0`, `tbert1`)
- [ ] `/etc/network/interfaces` configured with correct IPs, MTU, hotplug settings
- [ ] Networking restarted and TB interfaces verified up (`ip link show`)
- [ ] Ping tests passed (all 3 nodes can reach all TB neighbors)
- [ ] `ceph.conf` updated with `cluster_network = 10.10.10.0/24`
- [ ] Ceph daemons restarted (if existing cluster)
- [ ] iperf3 bandwidth tests show >18 Gbps per link
- [ ] Ceph rebalance completes without errors; no cluster warnings

### Maintenance

- **Monthly**: Check TB interface status (`ip addr`, `ethtool -i tbert0`)
- **Quarterly**: Reseat TB4 cables; run iperf3 test again
- **Yearly**: Update MS-01 BIOS (Minisforum releases periodic updates)

### Cost & ROI

- **3 × Thunderbolt 4 cables (0.8–2m)**: €60–210
- **vs. 25GbE SFP+ switch + 3 NICs**: €1500+
- **vs. 10GbE SFP+ ring (older)**: €800+
- **Throughput gain**: 16x over 2.5GbE
- **Payback**: Single rebalance on large pool saves hours of time

## References

- [Proxmox Ceph Network Configuration – Proxmox Wiki](https://pve.proxmox.com/wiki/Deploy_Hyper-Converged_Ceph_Cluster)
- [Thunderbolt Networking Setup – Scyto's Gist](https://gist.github.com/scyto/67fdc9a517faefa68f730f82d7fa3570)
- [Proxmox MS-01 Thunderbolt Ring Network – GitHub Gist](https://gist.github.com/volschin/99e4303bfbb912c987d4144d6ca4754d)
- [Thunderbolt Networking on Linux – Christian Kellner](https://christian.kellner.me/2018/05/24/thunderbolt-networking-on-linux/)
- [Active vs. Passive Thunderbolt 4 Cables – Plugable](https://plugable.com/blogs/news/what-s-the-difference-between-active-and-passive-thunderbolt-cables)
- [Linux Kernel Thunderbolt Documentation](https://docs.kernel.org/admin-guide/thunderbolt.html)
- [Proxmox Forum: Ceph Public/Cluster Network Discussion](https://forum.proxmox.com/threads/ceph-public-private-and-what-goes-over-the-network.147567/)
- [Minisforum MS-01 BIOS Updates](https://www.minisforum.com/products/minisforum-ms-01)
- [CalDigit EU Shop – Thunderbolt Cables](https://shop.caldigit.com/eu)
- [Geizhals.de – Thunderbolt Cable Price Comparison](https://geizhals.de/thunderbolt-4-usb4-kabel-v97174.html)
- [Level1Techs Forum: Thunderbolt 4 Ring Network for Ceph](https://forum.level1techs.com/t/thunderbolt-4-based-ring-network-between-intel-nucs-for-ceph-storage-on-proxmox/195285)
- [Proxmox Forum: Intel NUC 13 Pro Thunderbolt Ceph Cluster](https://forum.proxmox.com/threads/intel-nuc-13-pro-thunderbolt-ring-network-ceph-cluster.131107/)
- [StarwindSoftware Blog: Configure Ceph Storage in Proxmox](https://www.starwindsoftware.com/blog/proxmox-ve-configure-a-ceph-storage-cluster/)
