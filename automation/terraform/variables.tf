variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://10.21.21.99:8006/api2/json"
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "proxmox_host" {
  description = "Proxmox host IP for SSH operations"
  type        = string
  default     = "10.21.21.99"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "storage_pool" {
  description = "Proxmox storage pool"
  type        = string
  default     = "local-lvm"
}

variable "network_config" {
  description = "Network configuration"
  type = object({
    gateway = string
    dns1    = string
    dns2    = string
  })
  default = {
    gateway = "10.21.21.1"
    dns1    = "10.21.21.1"
    dns2    = "8.8.8.8"
  }
}

variable "nfs_server" {
  description = "NFS server IP address"
  type        = string
  default     = "192.168.200.4"
}

variable "ssh_public_key" {
  description = "SSH public key for core user"
  type        = string
}

variable "flatcar_vms" {
  description = "Map of Flatcar VMs to create"
  type = map(object({
    id              = number
    name            = string
    ip              = string
    memory          = number
    cores           = number
    enable_portainer = bool
  }))

  default = {
    "vm1" = {
      id              = 105
      name            = "flatcar-docker-1"
      ip              = "10.21.21.105"
      memory          = 4096
      cores           = 2
      enable_portainer = true
    }
    "vm2" = {
      id              = 106
      name            = "flatcar-docker-2"
      ip              = "10.21.21.106"
      memory          = 4096
      cores           = 2
      enable_portainer = true
    }
  }
}