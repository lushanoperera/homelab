# LXC 123 - Samba File Server (Reginald)

Rebuilt from Ubuntu 20.04 → Debian 12 → dist-upgraded to Debian 13 (Trixie). Samba 4.22, Cockpit 337 (core only — 45Drives file-sharing plugin dropped, no Trixie packages available). Shares managed via smb.conf.

## Specs

| Setting      | Value                             |
| ------------ | --------------------------------- |
| VMID         | 123                               |
| Hostname     | fileserver                        |
| IP (Infra)   | 192.168.100.123/24                |
| IP (Storage) | 192.168.200.123/24                |
| Gateway      | 192.168.100.1                     |
| Memory       | 384 MB                            |
| Cores        | 1                                 |
| Disk         | 6 GB (local-lvm)                  |
| OS           | Debian 13 (Trixie)                |
| Type         | Privileged (ZFS mount needed)     |
| Tags         | cockpit, samba, fileserver        |
| Features     | nesting=1 (required for nftables) |

## Installation

### Create LXC (temporary VMID 124 until cutover)

```bash
# On Reginald
pct create 124 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname fileserver \
  --memory 384 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.100.124/24,gw=192.168.100.1 \
  --net1 name=eth1,bridge=vmbr1,ip=192.168.200.124/24 \
  --storage local-lvm \
  --rootfs local-lvm:6 \
  --unprivileged 0 \
  --tags cockpit,samba,fileserver \
  --onboot 0 \
  --start 0
```

### Add ZFS passthrough

Append to `/etc/pve/lxc/124.conf`:

```
mp0: /rpool/shared,mp=/rpool/shared
```

### Install packages

```bash
pct start 124
pct exec 124 -- bash -c '
  apt update && apt install -y samba avahi-daemon wsdd2 nftables curl
'
```

### Create Samba users

```bash
pct exec 124 -- bash -c '
  useradd -M -s /usr/sbin/nologin mediauser
  useradd -M -s /usr/sbin/nologin lushano
  smbpasswd -a mediauser
  smbpasswd -a lushano
'
```

### Install Cockpit

```bash
pct exec 124 -- bash -c '
  apt install -y cockpit
'
```

Cockpit is socket-activated — zero resources when idle, starts on-demand at port 9090.

**Note:** 45Drives `cockpit-file-sharing` and `cockpit-identities` were used on Debian 12 but dropped during the Trixie upgrade — 45Drives has no Trixie packages. Cockpit core (system, storage, networking, packagekit) works fine. Shares are managed via `smb.conf` or CLI.

## Samba Configuration

Write to `/etc/samba/smb.conf`:

```ini
[global]
   workgroup = WORKGROUP
   server string = Homelab File Server
   security = user
   map to guest = never

   # Performance
   server multi channel support = yes
   aio read size = 1
   aio write size = 1

   # Logging
   log file = /var/log/samba/log.%m
   max log size = 1000
   log level = 1

   # Disable printing
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes

   # Disable NetBIOS (connect by IP/DNS, not broadcast)
   disable netbios = yes
   smb ports = 445

[Media]
   path = /rpool/shared/media
   browseable = yes
   read only = no
   valid users = mediauser lushano
   create mask = 0664
   directory mask = 0775

[Lushano]
   path = /rpool/shared/lushano
   browseable = yes
   read only = no
   valid users = lushano
   force user = lushano
   create mask = 0644
   directory mask = 0755

   # macOS compatibility (fruit VFS)
   vfs objects = catia fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:nfs_aces = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
```

Enable and validate:

```bash
systemctl enable --now smbd
testparm -s
```

**Note:** Cockpit's file-sharing plugin can also modify smb.conf via the web UI.

## Network Discovery

### Avahi (macOS Finder auto-discovery)

Write `/etc/avahi/services/smb.service`:

```xml
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h (Samba)</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
</service-group>
```

```bash
systemctl enable --now avahi-daemon
```

### wsdd2 (Windows Network discovery)

```bash
systemctl enable --now wsdd2
```

## Firewall (nftables)

Write `/etc/nftables.conf`:

```nft
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Established/related
        ct state established,related accept

        # Loopback
        iif lo accept

        # ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH (management from Infra VLAN)
        tcp dport 22 ip saddr 192.168.100.0/20 accept

        # SMB (Infra + Storage + Trusted VLANs)
        tcp dport 445 ip saddr { 192.168.2.0/24, 192.168.100.0/20, 192.168.200.0/24 } accept

        # Cockpit web UI (Infra + Trusted VLANs)
        tcp dport 9090 ip saddr { 192.168.2.0/24, 192.168.100.0/20 } accept

        # Avahi mDNS (Infra + Storage + Trusted VLANs)
        udp dport 5353 ip saddr { 192.168.2.0/24, 192.168.100.0/20, 192.168.200.0/24 } accept

        # wsdd2 WS-Discovery (Infra + Storage + Trusted VLANs)
        udp dport 3702 ip saddr { 192.168.2.0/24, 192.168.100.0/20, 192.168.200.0/24 } accept

        # Log + drop
        log prefix "[nftables-drop] " limit rate 5/minute
        drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

```bash
systemctl enable --now nftables
```

## Web UIs

| Service | URL                                              |
| ------- | ------------------------------------------------ |
| Cockpit | https://192.168.100.123:9090                     |
| Cockpit | https://cockpit.home.disconnesso.com (via Caddy) |

## Cutover from old LXC 123

```bash
# After validating shares and Cockpit on .124 IPs:
pct stop 123
pct set 124 --net0 name=eth0,bridge=vmbr0,ip=192.168.100.123/24,gw=192.168.100.1
pct set 124 --net1 name=eth1,bridge=vmbr1,ip=192.168.200.123/24
pct set 124 --onboot 1
pct reboot 124

# Verify with .123 IPs from all client types
# Verify Cockpit at https://192.168.100.123:9090
```

## Verification

1. `testparm -s` — validate smb.conf syntax
2. `smbclient -L //192.168.100.123 -U lushano` — list shares
3. Mount from macOS (Finder Cmd+K → `smb://192.168.100.123/Lushano`)
4. Mount from Windows (`\\192.168.100.123\Media`)
5. Create/delete test files on each share from each client
6. `smbstatus` — confirm active sessions
7. `nft list ruleset` — confirm firewall rules loaded
8. Verify macOS Finder auto-discovers the server (Avahi)
9. Verify Windows Network shows the server (wsdd2)
10. Access Cockpit at https://192.168.100.123:9090
11. `systemctl list-units --type=service --state=running` — only expected services

## Rollback

Restore old LXC 123 from PBS backup:

```bash
# Stop new container
pct stop 124

# Restore original
pct restore 123 <PBS_BACKUP_PATH> --storage local-lvm
pct start 123
```
