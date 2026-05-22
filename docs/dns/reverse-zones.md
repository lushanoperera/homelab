# Reverse DNS (PTR) for 192.168.100.0/24

Primary reverse zone `100.168.192.in-addr.arpa` lives on the QNAP Technitium
primary; secondaries replicate it via the existing cluster join.

## Bootstrap

```bash
TECHNITIUM_ADMIN_PASSWORD=... ./scripts/dns/setup-reverse-zone.sh
```

The script:

1. Logs into the Technitium API on `https://192.168.100.254:5380`.
2. Creates `100.168.192.in-addr.arpa` as a Primary zone (idempotent).
3. Best-effort enables the "use reverse zone for updating PTR" setting so
   forward A/AAAA edits also write the matching PTR. If the API key name has
   drifted between Technitium versions, toggle manually in Settings → General.
4. Seeds PTRs for the six pinned hosts from `CLAUDE.md`:

   | Octet | FQDN                                |
   | ----- | ----------------------------------- |
   | .4    | reginald.home.disconnesso.com.      |
   | .38   | winston.home.disconnesso.com.       |
   | .100  | flatcar.home.disconnesso.com.       |
   | .106  | pdm.home.disconnesso.com.           |
   | .187  | pbs.home.disconnesso.com.           |
   | .254  | qnap.home.disconnesso.com.          |

## Adding a static PTR by hand

Either use the UI (Zones → 100.168.192.in-addr.arpa → Add Record → PTR) or
hit the API:

```bash
curl -sSk -G "https://192.168.100.254:5380/api/zones/records/add" \
    --data-urlencode "token=$TOKEN" \
    --data-urlencode "domain=42.100.168.192.in-addr.arpa" \
    --data-urlencode "zone=100.168.192.in-addr.arpa" \
    --data-urlencode "type=PTR" \
    --data-urlencode "ttl=3600" \
    --data-urlencode "ptrName=new-host.home.disconnesso.com."
```

## Auto-PTR behaviour

When the setting is on, creating or editing an A record inside a primary
forward zone (e.g. `home.disconnesso.com`) writes the matching PTR into the
reverse zone — provided the reverse zone exists. Removing the A record
removes the PTR.

It does **not** retroactively create PTRs for existing A records. Use the
script above for the initial seed, then rely on the auto-create going
forward.

## Verify

```bash
dig @192.168.100.254 -x 192.168.100.38 +short   # → winston.home.disconnesso.com.
dig @192.168.100.100 -x 192.168.100.4  +short   # → reginald.home.disconnesso.com.
dig @192.168.100.120 -x 192.168.100.254 +short  # → qnap.home.disconnesso.com.
```

All three should return identical answers (replication is working).
