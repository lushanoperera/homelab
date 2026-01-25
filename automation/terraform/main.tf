terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_user             = var.proxmox_user
  pm_password         = var.proxmox_password
  pm_tls_insecure     = true
  pm_parallel         = 10
  pm_timeout          = 600
  pm_debug            = true
  pm_log_enable       = true
  pm_log_file         = "terraform-plugin-proxmox.log"
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}

# Template for creating Flatcar VMs
resource "proxmox_vm_qemu" "flatcar_vms" {
  for_each = var.flatcar_vms

  # VM Configuration
  vmid        = each.value.id
  name        = each.value.name
  target_node = var.proxmox_node

  # Hardware Configuration
  memory      = each.value.memory
  cores       = each.value.cores
  sockets     = 1

  # BIOS and Machine Type
  bios        = "ovmf"
  machine     = "q35"

  # Boot Configuration
  boot        = "c"
  bootdisk    = "scsi0"

  # Network Configuration
  network {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  # Serial Console
  serial {
    id   = 0
    type = "socket"
  }

  # VGA Configuration
  vga {
    type = "serial0"
  }

  # EFI Disk
  efidisk {
    storage = var.storage_pool
    format  = "raw"
    size    = "4M"
  }

  # Main OS Disk (will be replaced with Flatcar image)
  disk {
    slot     = 0
    type     = "scsi"
    storage  = var.storage_pool
    size     = "8G"
    iothread = 1
  }

  # Additional QEMU arguments for Ignition
  args = "-fw_cfg name=opt/com.coreos/config,file=/var/lib/vz/snippets/flatcar-${each.value.id}.ign"

  # VM Lifecycle
  onboot     = true
  automatic_reboot = false

  # Wait for VM to be ready
  define_connection_info = true

  # Provisioning with null_resource for Ignition config
  depends_on = [null_resource.ignition_configs]
}

# Generate Ignition configurations
resource "null_resource" "ignition_configs" {
  for_each = var.flatcar_vms

  # Triggers for regenerating configuration
  triggers = {
    vm_config = jsonencode(each.value)
    template  = filebase64sha256("${path.module}/templates/flatcar.bu.tpl")
  }

  # Generate Butane configuration
  provisioner "local-exec" {
    command = <<-EOT
      # Create temporary directory
      TEMP_DIR=$(mktemp -d)

      # Generate Butane config from template
      envsubst < ${path.module}/templates/flatcar.bu.tpl > $TEMP_DIR/flatcar-${each.value.id}.bu

      # Compile to Ignition
      docker run --rm -i -v $TEMP_DIR:/workspace \
        quay.io/coreos/butane:latest --strict /workspace/flatcar-${each.value.id}.bu \
        > $TEMP_DIR/flatcar-${each.value.id}.ign

      # Copy to local directory
      cp $TEMP_DIR/flatcar-${each.value.id}.ign ignition-configs/

      # Cleanup
      rm -rf $TEMP_DIR
    EOT

    environment = {
      VM_ID         = each.value.id
      VM_NAME       = each.value.name
      VM_IP         = each.value.ip
      GATEWAY       = var.network_config.gateway
      DNS1          = var.network_config.dns1
      DNS2          = var.network_config.dns2
      NFS_SERVER    = var.nfs_server
      SSH_KEY       = var.ssh_public_key
      HOSTNAME      = each.value.name
    }
  }

  # Upload Ignition config to Proxmox
  provisioner "local-exec" {
    command = <<-EOT
      scp ignition-configs/flatcar-${each.value.id}.ign \
        ${var.proxmox_user}@${var.proxmox_host}:/var/lib/vz/snippets/
    EOT
  }
}

# Prepare Flatcar image (run once)
resource "null_resource" "flatcar_image" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.proxmox_user
      host     = var.proxmox_host
      password = var.proxmox_password
    }

    inline = [
      "mkdir -p /var/lib/vz/template/iso",
      "mkdir -p /var/lib/vz/snippets",
      "pvesm set local --content images,iso,rootdir,backup,snippets || true",
      "cd /var/lib/vz/template/iso",
      "if [ ! -f flatcar_production_qemu_image.img ]; then",
      "  curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2",
      "  curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2.DIGESTS",
      "  grep flatcar_production_qemu_image.img.bz2 flatcar_production_qemu_image.img.bz2.DIGESTS | awk '{print $4 \"  flatcar_production_qemu_image.img.bz2\"}' | sha256sum --check - || true",
      "  bunzip2 flatcar_production_qemu_image.img.bz2",
      "fi"
    ]
  }
}