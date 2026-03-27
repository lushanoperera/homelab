---
paths:
  - "storage/nfs/**"
  - "systemd/*.mount"
  - "**/exports*"
recall:
  - nfs
  - zfs
  - mount
  - exports
  - crossmnt
---

# NFS + ZFS Lessons

| Issue                                   | Solution                                                                         |
| --------------------------------------- | -------------------------------------------------------------------------------- |
| Child datasets invisible via NFS        | Add `crossmnt` to NFS export options                                             |
| ZFS child dataset wrong mountpoint      | Use `zfs inherit mountpoint <dataset>`                                           |
| Empty ZFS child shadowing real data     | Destroy empty dataset, bind mount real dir                                       |
| NFS re-export fails for child mounts    | Mount directly from source, not via relay                                        |
| `soft` mount causes silent failures     | Use `hard` mount option for production data                                      |
| Stale data from aggressive caching      | Reduce `actimeo` from 600 to 60 seconds                                         |
| Data split between parent/child         | Check `zfs get mountpoint` SOURCE is "inherited"                                 |
| Partial stale handles (some paths work) | `exportfs -ra` on server, restart containers                                     |
| Movies in parent ZFS dataset, not child | Bind mount `/rpool/shared/media/movies` -> `/media/movies` via systemd unit with `After=zfs-mount.service` |
| `crossmnt` doesn't traverse bind mounts | Explicit NFS export with own `fsid` required for bind-mounted paths              |
| NFSv4 pseudofilesystem child traversal  | Parent export needs `crossmnt,fsid=N`; `/rpool/shared` with `crossmnt,fsid=7`   |
| NFSv4 stale sessions on old IPs         | Clients with sessions on now-unauthorized IPs poison new mounts; stop containers, remount clean |
| `fsid=0` reserved for NFSv4 pseudo-root | Never use `fsid=0` for regular exports; start at `fsid=1` or higher              |
| fstab bind mount orphaned by ZFS order  | Use systemd mount unit with `After=zfs-mount.service` instead of fstab           |
