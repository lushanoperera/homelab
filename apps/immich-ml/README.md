# Immich ML — LXC 107 on winston

Immich machine learning (CLIP smart search, face detection) runs alone in LXC 107
(`immich-ml`, 192.168.100.107). The rest of Immich stays on Flatcar VM 100 and reaches the
ML service over HTTP at `http://192.168.100.107:3003` (`IMMICH_MACHINE_LEARNING_URL` in
`apps/immich/docker-compose.yml`).

## Why

The iGPU on VM 100 depended on a patched i915 SR-IOV sysext. Every Flatcar kernel auto-update
broke it (2026-03-16, 05-12, 07-09, 08-13), and Immich + Nextcloud refused to start because
their compose files bound `/dev/dri`. LXC 107 shares the host PF render node the same way
Plex LXC 105 does: host driver, no VF, no rebuild after a kernel update.

## Layout

| Item | Value |
| --- | --- |
| CT | 107, unprivileged, nesting + keyctl, 4 cores, 6 G RAM, rootfs `local-lvm:32` |
| GPU | `dev0 /dev/dri/by-path/pci-0000:00:02.0-render,gid=104`, `dev1 ...-card,gid=44` |
| Stack | `/srv/docker/immich-ml/` (compose + `.env`) |
| Image | `immich-machine-learning:${IMMICH_VERSION}-openvino` |
| Cache | Docker volume `immich-ml_immich-model-cache` (~500 MB, re-downloadable) |
| Backup | winston 04:00 vzdump job (CT snapshot). No restic — nothing stateful |

Create the CT: `ssh root@192.168.100.38 'bash -s' < scripts/hosts/create-immich-ml-lxc.sh`.

## Deploy

```bash
rsync -az --exclude='.env' apps/immich-ml/ root@192.168.100.107:/srv/docker/immich-ml/
ssh root@192.168.100.107 'cd /srv/docker/immich-ml && docker compose up -d'
```

`.env` holds only `IMMICH_VERSION` (keep it equal to VM 100's `/srv/docker/immich/.env`).

## Update

```bash
ssh root@192.168.100.107 'cd /srv/docker/immich-ml && docker compose pull && docker compose up -d'
```

Update ML and server together — Immich requires matching versions.

## Verify

```bash
curl -s http://192.168.100.107:3003/ping                       # pong
ssh root@192.168.100.107 'docker logs immich_machine_learning 2>&1 | grep -i provider'
# must list OpenVINOExecutionProvider
ssh root@192.168.100.38 'intel_gpu_top -s 1000 -o - | head'    # Render/3D load during a Smart Search job
```

If the `-openvino` image fails to start, switch the tag to the base image (drop `-openvino`).
ML then runs on CPU.
