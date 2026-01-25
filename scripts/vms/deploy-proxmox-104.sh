#!/bin/bash

# Flatcar Container Linux Proxmox VM 104 Deployment Script
# This script deploys a Flatcar VM with Portainer and Docker Compose on Proxmox

set -euo pipefail

# Configuration
VM_ID="104"
VM_NAME="flatcar-portainer-104"
VM_MEMORY="4096"
VM_CORES="2"
VM_IP="10.21.21.104"
PROXMOX_HOST="10.21.21.99"
PROXMOX_USER="root"
STORAGE="local-lvm"  # Change this to match your Proxmox storage

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if Ignition config exists
if [[ ! -f "ignition/flatcar-proxmox-104-portainer.ign" ]]; then
    error "Ignition configuration not found. Please run the Butane compilation first."
    exit 1
fi

log "Starting Flatcar deployment to Proxmox host $PROXMOX_HOST"

# Step 1: Prepare Proxmox and upload Ignition configuration
log "Preparing Proxmox directories and uploading Ignition configuration..."
ssh $PROXMOX_USER@$PROXMOX_HOST "mkdir -p /var/lib/vz/snippets && pvesm set local --content images,iso,rootdir,backup,snippets || true"
scp ignition/flatcar-proxmox-104-portainer.ign $PROXMOX_USER@$PROXMOX_HOST:/var/lib/vz/snippets/flatcar-104.ign

# Step 2: Execute deployment commands on Proxmox
log "Executing deployment commands on Proxmox host..."

ssh $PROXMOX_USER@$PROXMOX_HOST << EOF
set -euo pipefail

echo "Changing to ISO directory..."
cd /var/lib/vz/template/iso

echo "Downloading Flatcar Stable KVM image..."
if [[ ! -f "flatcar_production_qemu_image.img" ]]; then
    curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2
    curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2.DIGESTS

    echo "Verifying image integrity..."
    grep flatcar_production_qemu_image.img.bz2 flatcar_production_qemu_image.img.bz2.DIGESTS | awk '{print \$4 "  flatcar_production_qemu_image.img.bz2"}' | sha256sum --check -

    echo "Extracting image..."
    bunzip2 flatcar_production_qemu_image.img.bz2
else
    echo "Flatcar image already exists, skipping download."
fi

echo "Destroying existing VM $VM_ID if it exists..."
if qm status $VM_ID >/dev/null 2>&1; then
    qm stop $VM_ID || true
    sleep 5
    qm destroy $VM_ID || true
fi

echo "Creating VM $VM_ID..."
qm create $VM_ID \\
    --name $VM_NAME \\
    --memory $VM_MEMORY \\
    --cores $VM_CORES \\
    --sockets 1 \\
    --machine q35 \\
    --bios ovmf \\
    --efidisk0 $STORAGE:0,format=raw \\
    --net0 virtio,bridge=vmbr0 \\
    --serial0 socket \\
    --vga serial0

echo "Importing disk image..."
qm importdisk $VM_ID flatcar_production_qemu_image.img $STORAGE

echo "Configuring storage..."
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-0
qm set $VM_ID --boot c --bootdisk scsi0

echo "Attaching Ignition configuration..."
qm set $VM_ID --args "-fw_cfg name=opt/com.coreos/config,file=/var/lib/vz/snippets/flatcar-104.ign"

echo "Starting VM $VM_ID..."
qm start $VM_ID

echo "VM $VM_ID started successfully!"
echo "You can monitor the console with: qm monitor $VM_ID"
echo "Once booted, Portainer will be available at: https://$VM_IP:9443"
echo ""
echo "Initial login steps for Portainer:"
echo "1. Browse to https://$VM_IP:9443"
echo "2. Accept the self-signed certificate warning"
echo "3. Create your admin user account"
echo "4. Choose 'Docker' as the environment to manage"
echo ""
echo "SSH access: ssh core@$VM_IP"
EOF

log "Deployment completed! VM $VM_ID should be starting up."
log "Portainer will be available at: https://$VM_IP:9443"
log "SSH access: ssh core@$VM_IP"

# Step 3: Wait for VM to be accessible and perform verification
log "Waiting for VM to boot and become accessible..."
log "You can monitor the boot process with: ssh $PROXMOX_USER@$PROXMOX_HOST 'qm monitor $VM_ID'"

echo ""
echo "=== Deployment Summary ==="
echo "VM ID: $VM_ID"
echo "VM Name: $VM_NAME"
echo "IP Address: $VM_IP"
echo "Memory: ${VM_MEMORY}MB"
echo "CPU Cores: $VM_CORES"
echo "Proxmox Host: $PROXMOX_HOST"
echo ""
echo "Services:"
echo "- Portainer: https://$VM_IP:9443"
echo "- SSH: ssh core@$VM_IP"
echo ""
echo "Next Steps:"
echo "1. Wait 3-5 minutes for full boot and service startup"
echo "2. Access Portainer web interface"
echo "3. Configure Portainer admin user"
echo "4. Verify Docker and containers are running"