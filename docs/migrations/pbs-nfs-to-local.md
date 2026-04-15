# PBS: NFS datastores → local virtio disks

**Date:** 2026-04-15
**Host:** PBS VM on QNAP (192.168.100.187)
**Outcome:** partial — fresh empty local datastores, NFS legacy kept alongside for ~90 d.

## Problem

Reginald CT 120 vzdump jobs failing daily at 08:00 CET at the
`activate_storage` step with `error fetching datastores - 500 read timeout`
(Apr 2–15). PBS ran both datastores (`pbs-backups`, `nwlab-backup`) over NFS
back to the same QNAP box that hosts the VM — every datastore-listing API
call walked `.chunks/` over the NFS stack, routinely exceeding PVE's 10 s
activate-storage budget after any idle period.

## Plan as designed

Give PBS two local virtio-scsi disks (vdb 768 GB, vdc 250 GB) on QNAP
storage, rsync both datastores onto them (`-aHAX`), repoint `datastore.cfg`
paths, validate, drop NFS after a 7-day retention window. Same physical
spindles, no NFS hop, chunk hashes byte-identical so verify stays valid.

## What actually happened

Phases 0–2 (folders, disk attach, mkfs/mount) ran clean.

Phase 3 (rsync) collapsed. Measured throughput:

| Test | Rate |
|---|---|
| Serial rsync, all workers on `.chunks/` | ~2.5 MB/s |
| 16-way parallel rsync (split by first hex char) | ~1 MB/s total (worse) |
| Raw NFS `dd` on a 3.2 MB chunk (cold) | 1.6 MB/s |
| Local ext4 direct write, 200 MB | 15.5 MB/s |
| PBS→QNAP ping (steady state) | 0.26 ms |

Root cause: PBS chunk stores are metadata-bound (65 536 shards, ~2 M files,
most 1–4 MB). Every file is an NFS roundtrip × several ops. Parallelism
didn't help — the source is one physical QNAP disk pool, so 16 concurrent
readers compete for head seeks, and effective parallelism was <2×.
Projection at observed rate: 24–48 h for the 169 GB homelab store alone,
blocking backups the whole time.

## Decision

Swapped strategy to **cut over to empty local datastores**, keeping the old
NFS-backed ones alongside under new names for historical restores:

```text
pbs-backups           /mnt/pbs-local/homelab   (new, local vdb 755 G)
nwlab-backup          /mnt/pbs-local/nwlab     (new, local vdc 246 G)
pbs-backups-legacy    /mnt/pbs-backups         (old, NFS, read-only by convention)
nwlab-backup-legacy   /mnt/nwlab-backup        (old, NFS, read-only by convention)
```

Datastore names `pbs-backups` / `nwlab-backup` stay on the new local disks,
so winston/reginald/nwlab-thinkpad PVE storage entries (`pbs-backupnas`
→ datastore `pbs-backups`) need **zero reconfiguration**. The `*-legacy`
datastores stay mounted so the UI can still browse historical snapshots;
they'll age out via existing prune/GC schedules and be removed once the
retention window expires (~2026-07).

## Tradeoffs accepted

- **Lost backup history continuity on the primary datastore** — new daily
  chain starts 2026-04-15. Old snapshots only reachable via `*-legacy`.
- **NFS stack is still in the data path for the legacy datastores**, but
  only PBS's own internal scheduled GC/prune touches them; no client
  writes. The original `activate_storage` timeout still applies to the
  legacy datastore listings, but clients don't reference them, so backup
  jobs can't trip on them.
- After ~90 d the legacy datastores get removed, NFS exports dropped, and
  the "same disk on both sides of the network stack" anti-pattern
  disappears for good.

## Validation

| Check | Result |
|---|---|
| `proxmox-backup-manager datastore list` — 4 entries | ✅ |
| reginald `pvesm status --storage pbs-backupnas` | ~3.7 s (was failing 10 s) |
| winston  `pvesm status --storage pbs-backupnas` | ~5.8 s |
| Test vzdump CT 120 (reginald) 1.06 GiB | TASK OK in 11m55s |
| Test vzdump CT 106 (winston) | see section below / follow-up |
| nwlab-thinkpad test vzdump | deferred, run from that host |

Unrelated mail-notification errors (`mail-to-root`: no recipients) surfaced
during the test backups — pre-existing, not blocking.

## Lessons

1. **Do not plan large NFS-based rsync migrations of PBS chunk stores**
   without first measuring sustained read throughput on a representative
   chunk. 1 MB/s catastrophic floor is realistic when source and dest share
   a spindle.
2. **PBS chunk stores tolerate starting over** far better than they
   tolerate a half-copied `.chunks/` tree — chunk hashes are
   content-addressed, so a partial copy is worse than nothing (some
   references, some not). Cutover > migration when the numbers look bad.
3. **Keep `datastore: NAME` stable across migrations.** Clients reference
   datastores by name, not path; renaming sections in `datastore.cfg` is
   how you preserve zero client reconfiguration.
4. **`activate_storage` latency budget is 10 s.** The datastore-listing
   API walks `.chunks/`. If that walk goes over NFS to the same disk
   serving the VM, you will lose the race.

## Follow-ups (not done)

- [ ] Clean-removal of `*-legacy` datastores on 2026-07-15 (after 90 d).
- [ ] Drop `PBS-Backups` and `PBS-nwlab` NFS exports on QNAP after legacy
      removal; reclaim ~222 GB.
- [ ] Decide whether to pre-seed the new datastore with selected recent
      snapshots via `proxmox-backup-client` sync — probably not worth it
      since the new chain will build organically in a few days.
- [ ] Investigate why `cache=none` direct writes to vdb max out at
      15.5 MB/s — if QNAP backend disk is that slow even without NFS,
      the long-term upper bound on backup throughput is low.
