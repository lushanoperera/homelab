# Encrypted DNS clients — DoH via dns.home.disconnesso.com

LAN-only DoH endpoint. The wildcard `*.home.disconnesso.com` cert (Caddy +
Cloudflare DNS-01) terminates at Caddy on Flatcar VM 100; Caddy proxies to
the Technitium primary on `192.168.100.254:53443/dns-query`.

Not exposed via Cloudflare Tunnel. Clients only reach it from the Trusted
VLAN (192.168.2.0/24), Multimedia, IoT, or any segment with LAN routing.
Over WAN/cellular, DoH fails by design.

## Test from a workstation

```bash
# RFC 8484 GET — base64url of a wire-format query for example.com A
Q=$(printf '\x00\x00\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01' \
    | base64 | tr '+/' '-_' | tr -d '=')
curl -sf -H 'accept: application/dns-message' \
    "https://dns.home.disconnesso.com/dns-query?dns=$Q" | xxd | head
```

Expect a binary DNS response (xxd renders it). Failures usually mean Caddy
isn't proxying (`docker exec caddy caddy validate ... && caddy reload ...`)
or the client isn't on a LAN-reachable segment.

## Android (Private DNS)

Settings → Network & Internet → Private DNS → "Private DNS provider
hostname" → `dns.home.disconnesso.com`. Android probes the hostname; if it
fails to find a working DoT/DoH responder it silently falls back. Verify by
killing Wi-Fi briefly and re-joining — under "Private DNS mode" you should
see `dns.home.disconnesso.com` listed.

Verify resolution path:

```text
chrome://net-export   # capture on phone, look for "secureDNS" field == "tls"
```

## iOS / macOS (Encrypted DNS configuration profile)

Apple's Private Relay does **not** cover homelab DoH — install a profile.
Save the following as `homelab-dns.mobileconfig` and AirDrop / email to the
device, then accept the profile in Settings → General → VPN & Device
Management.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadDisplayName</key><string>Homelab DoH</string>
  <key>PayloadIdentifier</key><string>com.disconnesso.dns.doh</string>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadUUID</key><string>9E3F2C18-3B8C-4D7B-A2FD-2DB6B6D5DE01</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadDisplayName</key><string>Homelab Encrypted DNS</string>
      <key>PayloadIdentifier</key><string>com.disconnesso.dns.doh.payload</string>
      <key>PayloadType</key><string>com.apple.dnsSettings.managed</string>
      <key>PayloadUUID</key><string>4F4C4C7A-7E5C-46A3-9F8B-1A0D9B0F4A2A</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>DNSSettings</key>
      <dict>
        <key>DNSProtocol</key><string>HTTPS</string>
        <key>ServerURL</key><string>https://dns.home.disconnesso.com/dns-query</string>
      </dict>
      <!-- Optional: restrict to home Wi-Fi SSIDs only -->
      <!--
      <key>OnDemandRules</key>
      <array>
        <dict>
          <key>Action</key><string>Connect</string>
          <key>SSIDMatch</key><array><string>YourHomeSSID</string></array>
        </dict>
        <dict><key>Action</key><string>Disconnect</string></dict>
      </array>
      -->
    </dict>
  </array>
</dict>
</plist>
```

Regenerate the two `PayloadUUID` values with `uuidgen` if you publish the
file anywhere. Apple ties the profile identity to those UUIDs — reusing them
across deploys means later installs upgrade the existing profile rather
than installing a second one.

## Apply Caddy change

```bash
scp networking/caddy/sites/infrastructure.caddy \
    core@192.168.100.100:/srv/docker/caddy/sites/infrastructure.caddy
ssh core@192.168.100.100 \
    'docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
    && docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile'
```
