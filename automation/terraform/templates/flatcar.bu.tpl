variant: flatcar
version: 1.1.0

passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - $SSH_KEY

storage:
  files:
    - path: /etc/systemd/network/10-static.network
      mode: 0644
      contents:
        inline: |
          [Match]
          Name=eth0
          [Network]
          Address=$VM_IP/24
          Gateway=$GATEWAY
          DNS=$DNS1
          DNS=$DNS2
    - path: /etc/modules-load.d/nfs.conf
      mode: 0644
      contents:
        inline: |
          nfs
          nfsd
    - path: /etc/tmpfiles.d/nfs-mounts.conf
      mode: 0644
      contents:
        inline: |
          d /mnt/nfs_shared 0755 core core -
          d /mnt/nfs_media 0755 core core -

systemd:
  units:
    - name: docker.service
      enabled: true
    - name: qemu-guest-agent.service
      enabled: true
    - name: mnt-nfs_shared.mount
      enabled: true
      contents: |
        [Unit]
        Description=NFS Shared Mount
        After=network-online.target
        [Mount]
        What=$NFS_SERVER:/rpool/shared
        Where=/mnt/nfs_shared
        Type=nfs4
        Options=rw,fsc,noatime,vers=4.2,proto=tcp,rsize=1048576,wsize=1048576,nconnect=8,soft,timeo=100,retrans=5,_netdev
        [Install]
        WantedBy=multi-user.target
    - name: mnt-nfs_media.mount
      enabled: true
      contents: |
        [Unit]
        Description=NFS Media Mount
        After=network-online.target
        [Mount]
        What=$NFS_SERVER:/rpool/shared/media
        Where=/mnt/nfs_media
        Type=nfs4
        Options=rw,fsc,noatime,vers=4.2,proto=tcp,rsize=1048576,wsize=1048576,nconnect=8,soft,timeo=100,retrans=5,_netdev
        [Install]
        WantedBy=multi-user.target