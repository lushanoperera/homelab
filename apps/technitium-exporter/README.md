# Technitium Prometheus Exporter

Tiny stdlib-only Python exporter that scrapes the QNAP Technitium primary
(`https://192.168.100.254:5380/api/dashboard/stats/get`) and exposes
`/metrics` on `:9628`. Deployed as a sidecar on Flatcar VM 100.

## Deploy

```bash
ssh core@192.168.100.100 'mkdir -p /srv/docker/technitium-exporter'
rsync -av apps/technitium-exporter/{docker-compose.yml,exporter.py,README.md} \
    core@192.168.100.100:/srv/docker/technitium-exporter/

# Reuse the same TECHNITIUM_ADMIN_PASSWORD that DNS compose uses.
ssh core@192.168.100.100 \
    'grep -q TECHNITIUM_ADMIN_PASSWORD /srv/docker/technitium-exporter/.env 2>/dev/null \
    || (echo TECHNITIUM_ADMIN_PASSWORD=$(grep TECHNITIUM_ADMIN_PASSWORD /srv/docker/dns/.env | cut -d= -f2-) \
        > /srv/docker/technitium-exporter/.env)'

ssh core@192.168.100.100 \
    'cd /srv/docker/technitium-exporter && /opt/bin/docker-compose up -d'
```

## Hook into Prometheus

Append to `/opt/grafana/prometheus/prometheus.yml` on Flatcar (see
`reference_flatcar_grafana.md`):

```yaml
  - job_name: technitium
    static_configs:
      - targets: ["technitium-exporter:9628"]
        labels:
          node: qnap-primary
```

Reload Prometheus:

```bash
ssh core@192.168.100.100 \
    'docker exec prometheus kill -HUP 1'
```

## Verify

```bash
ssh core@192.168.100.100 'curl -s http://localhost:9628/metrics | head -20'
ssh core@192.168.100.100 'curl -s http://localhost:9090/api/v1/targets | jq ".data.activeTargets[] | select(.labels.job==\"technitium\")"'
```

Import `grafana-dashboard.json` into Grafana (Dashboards → New → Import).
