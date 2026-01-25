output "vm_info" {
  description = "Information about created VMs"
  value = {
    for k, v in proxmox_vm_qemu.flatcar_vms : k => {
      id   = v.vmid
      name = v.name
      ip   = var.flatcar_vms[k].ip
      ssh  = "ssh core@${var.flatcar_vms[k].ip}"
      portainer = var.flatcar_vms[k].enable_portainer ? "https://${var.flatcar_vms[k].ip}:9443" : null
    }
  }
}

output "nfs_mounts" {
  description = "NFS mount information"
  value = {
    server = var.nfs_server
    mounts = [
      "/mnt/nfs_shared (from ${var.nfs_server}:/rpool/shared)",
      "/mnt/nfs_media (from ${var.nfs_server}:/rpool/shared/media)"
    ]
  }
}

output "deployment_summary" {
  description = "Deployment summary"
  value = <<-EOT
    ==========================================
    Flatcar VM Deployment Complete
    ==========================================
    ${join("\n    ", [for k, v in var.flatcar_vms : "${v.name} (${v.id}): ${v.ip} - SSH: ssh core@${v.ip}${v.enable_portainer ? " - Portainer: https://${v.ip}:9443" : ""}"])}

    NFS Mounts (all VMs):
    - /mnt/nfs_shared (from ${var.nfs_server}:/rpool/shared)
    - /mnt/nfs_media (from ${var.nfs_server}:/rpool/shared/media)

    Note: Wait 2-3 minutes for full boot and service startup
    ==========================================
  EOT
}