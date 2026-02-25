---
paths:
  - "vms/flatcar-media/**"
  - "**/butane/**"
  - "**/ignition/**"
  - "**/docker-compose*"
  - "systemd/**"
---

# Flatcar Lessons

| Issue                        | Solution                                                       |
| ---------------------------- | -------------------------------------------------------------- |
| Network interface naming     | Always use `eth0` (not `ens18`) in Butane configs              |
| Ignition only applies once   | Manual fixes needed for post-boot changes                      |
| Docker Compose location      | `/opt/bin/docker-compose` (standalone binary)                  |
| Watchtower image             | `nickfedor/watchtower` (containrrr discontinued)               |
| VPN secrets                  | Docker secrets in `./secrets/`, not env vars                   |
| Compose .env missing vars    | All vars must be in `.env`; see `.env.example`                 |
| Compose plugin not installed | Flatcar `/usr/lib` is read-only; Butane download fails silently |
| Systemd `\|\| true` syntax   | Use `-` prefix: `ExecStartPre=-/usr/bin/docker ...`           |
| SSH heredoc corrupts shebang | Pipe from local heredoc instead of remote heredoc              |
| Butane → Ignition recompile  | Requires Docker: `docker run --rm -i quay.io/coreos/butane:latest --strict` |
