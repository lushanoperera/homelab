#!/usr/bin/env python3
"""Tiny Prometheus exporter for Technitium DNS.

Scrapes /api/dashboard/stats/get on the configured Technitium host once per
scrape and exposes the result in Prometheus text exposition format on
LISTEN_PORT (default 9628).

Env:
    TECHNITIUM_HOST       default https://192.168.100.254:5380
    TECHNITIUM_USER       default admin
    TECHNITIUM_PASS       required
    LISTEN_PORT           default 9628
    SCRAPE_TIMEOUT        default 5 (seconds)

No external deps — stdlib only. Re-login on every scrape so an admin password
rotation is picked up at next scrape, not at restart.
"""

from __future__ import annotations

import json
import os
import ssl
import sys
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("TECHNITIUM_HOST", "https://192.168.100.254:5380").rstrip("/")
USER = os.environ.get("TECHNITIUM_USER", "admin")
PASS = os.environ.get("TECHNITIUM_PASS") or sys.exit("TECHNITIUM_PASS required")
PORT = int(os.environ.get("LISTEN_PORT", "9628"))
TIMEOUT = float(os.environ.get("SCRAPE_TIMEOUT", "5"))

# Technitium serves self-signed cert on 5380 https — skip verify (LAN).
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE


def _get(path: str, **params) -> dict:
    url = f"{HOST}{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=TIMEOUT, context=_SSL_CTX) as resp:
        return json.loads(resp.read().decode())


def _login() -> str:
    data = _get("/api/user/login", user=USER, pass_=PASS, includeInfo="false")
    # Technitium expects pass — urlencode of "pass" key, not python kw.
    if data.get("status") != "ok":
        # Retry with the real key name (python kw collision workaround)
        url = f"{HOST}/api/user/login?{urllib.parse.urlencode({'user': USER, 'pass': PASS, 'includeInfo': 'false'})}"
        with urllib.request.urlopen(url, timeout=TIMEOUT, context=_SSL_CTX) as r:
            data = json.loads(r.read())
    if data.get("status") != "ok" or not data.get("token"):
        raise RuntimeError(f"login failed: {data}")
    return data["token"]


def _stats(token: str, window: str = "lastHour") -> dict:
    out = _get("/api/dashboard/stats/get", token=token, type=window)
    if out.get("status") != "ok":
        raise RuntimeError(f"stats failed: {out}")
    return out.get("response", out)


def _labels(labels: dict | None) -> str:
    if not labels:
        return ""
    return "{" + ",".join(f'{k}="{v}"' for k, v in labels.items()) + "}"


def _header(name: str, help_text: str, mtype: str) -> str:
    return f"# HELP {name} {help_text}\n# TYPE {name} {mtype}\n"


# Stat key in Technitium API → (metric name, help, type)
_METRICS = [
    (
        "totalQueries",
        "technitium_queries_total",
        "Total DNS queries handled",
        "counter",
    ),
    (
        "totalBlocked",
        "technitium_queries_blocked",
        "DNS queries blocked by blocklists",
        "counter",
    ),
    (
        "totalCached",
        "technitium_queries_cached",
        "Queries served from cache",
        "counter",
    ),
    (
        "totalNoError",
        "technitium_queries_no_error",
        "Queries that returned NOERROR",
        "counter",
    ),
    (
        "totalServerFailure",
        "technitium_queries_server_failure",
        "Queries that returned SERVFAIL",
        "counter",
    ),
    (
        "totalNxDomain",
        "technitium_queries_nx_domain",
        "Queries that returned NXDOMAIN",
        "counter",
    ),
    (
        "totalClients",
        "technitium_clients_unique",
        "Unique client IPs observed",
        "gauge",
    ),
]


def _render() -> str:
    body: list[str] = []
    body.append(
        _header(
            "technitium_up",
            "Whether the exporter scraped the API successfully",
            "gauge",
        )
    )

    try:
        token = _login()
        h = _stats(token, "lastHour")
        d = _stats(token, "lastDay")
    except Exception:  # noqa: BLE001
        body.append(f"technitium_up 0\n")
        return "".join(body)

    body.append("technitium_up 1\n")

    # Emit one HELP/TYPE per metric, then samples for each window label.
    for stat_key, metric, help_text, mtype in _METRICS:
        body.append(_header(metric, help_text, mtype))
        for window, src in (("1h", h), ("1d", d)):
            body.append(
                f"{metric}{_labels({'window': window})} {_safe(src, stat_key)}\n"
            )
    return "".join(body)


def _safe(d: dict, key: str, default: int = 0):
    v = (
        d.get("stats", {}).get(key)
        if isinstance(d.get("stats"), dict)
        else d.get(key, default)
    )
    return v if isinstance(v, (int, float)) else default


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path != "/metrics":
            self.send_error(404, "use /metrics")
            return
        body = _render().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # silence access log
        return


if __name__ == "__main__":
    print(f"technitium-exporter listening on :{PORT}, scraping {HOST}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
