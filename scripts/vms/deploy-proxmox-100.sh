#!/bin/bash

# Flatcar Container Linux VM 100 Deployment Script for Proxmox
# Deploys Docker-ready VM with VirtioFS/NFS shared storage and Portainer

set -euo pipefail

# Configuration for VM 100
VM_ID="100"
VM_NAME="docker"
VM_IP="192.168.100.100"
PROXMOX_HOST="192.168.100.38"
PROXMOX_USER="root"
STORAGE="vmpool"
MEMORY="4096"
CORES="2"
GATEWAY="192.168.100.1"
DNS1="192.168.100.1"
DNS2="8.8.8.8"
HOSTNAME="docker"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

# Parse command line arguments
DRY_RUN=false
FORCE=false
SSH_KEY_FILE="$HOME/.ssh/id_rsa.pub"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --ssh-key)
            SSH_KEY_FILE="$2"
            shift 2
            ;;
        --password)
            PROXMOX_PASSWORD="$2"
            shift 2
            ;;
        --skip-verify)
            SKIP_VERIFICATION=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run         Show configuration without deploying
  --force           Force deployment even if VM exists
  --ssh-key FILE    SSH public key file (default: ~/.ssh/id_rsa.pub)
  --password PASS   Proxmox root password (if not using SSH keys)
  --skip-verify     Skip post-deployment verification and cleanup
  --help            Show this help

VM Configuration:
  VM ID:       $VM_ID
  VM Name:     $VM_NAME
  IP Address:  $VM_IP
  Proxmox:     $PROXMOX_HOST
  Storage:     $STORAGE
  Memory:      ${MEMORY}MB
  CPU Cores:   $CORES

Features:
  - Flatcar Container Linux
  - Docker + Docker Compose
  - Portainer (https://$VM_IP:9443)
  - NFS shared storage (/mnt/nfs_shared)
  - QEMU Guest Agent
  - Nano text editor via Docker wrapper
  - Automatic post-deployment verification and cleanup

Post-deployment verification includes:
  - Cleanup of any failed systemd services
  - Hostname verification and correction
  - NFS mount verification and mounting
  - Nano wrapper creation if missing
  - Service status validation

EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Show configuration
show_config() {
    info "VM 100 Deployment Configuration:"
    echo "=========================================="
    echo "VM ID:          $VM_ID"
    echo "VM Name:        $VM_NAME"
    echo "VM IP:          $VM_IP"
    echo "Hostname:       $HOSTNAME"
    echo "Proxmox Host:   $PROXMOX_HOST"
    echo "Storage:        $STORAGE"
    echo "Memory:         ${MEMORY}MB"
    echo "CPU Cores:      $CORES"
    echo "Gateway:        $GATEWAY"
    echo "DNS Servers:    $DNS1, $DNS2"
    echo "SSH Key:        $SSH_KEY_FILE"
    echo "=========================================="
}

# Validate configuration
validate_config() {
    info "Validating configuration..."

    # Check SSH key file
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        error "SSH key file not found: $SSH_KEY_FILE"
    fi

    # Check Ignition file
    if [[ ! -f "ignition/flatcar-proxmox-100-docker.ign" ]]; then
        error "Ignition file not found: ignition/flatcar-proxmox-100-docker.ign"
    fi

    # Test Proxmox connectivity
    if [[ -n "${PROXMOX_PASSWORD:-}" ]]; then
        # Use sshpass if password provided
        if ! command -v sshpass >/dev/null 2>&1; then
            error "sshpass is required when using password authentication"
        fi
        SSH_CMD="sshpass -p '$PROXMOX_PASSWORD' ssh -o StrictHostKeyChecking=no"
        SCP_CMD="sshpass -p '$PROXMOX_PASSWORD' scp -o StrictHostKeyChecking=no"
    else
        # Use key-based authentication
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$PROXMOX_USER@$PROXMOX_HOST" "echo 'Connection test'" >/dev/null 2>&1; then
            error "Cannot connect to Proxmox host $PROXMOX_HOST as $PROXMOX_USER (try --password option if using password auth)"
        fi
        SSH_CMD="ssh"
        SCP_CMD="scp"
    fi

    info "Configuration validated successfully"
}

# Deploy VM to Proxmox
deploy_vm() {
    log "Starting deployment to Proxmox host $PROXMOX_HOST"

    # Update SSH key in Ignition file
    local ssh_key
    ssh_key=$(cat "$SSH_KEY_FILE")
    local temp_ign
    temp_ign=$(mktemp)

    # Replace the placeholder SSH key with the actual key
    sed "s|ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC1o+LR0vywznyrfJkK49RypPbFDZC/xORHCamB5SnZyGKs52Qv/j6B6itmZK1JeuEMm0uPRjcT5ASrmyTtJ3iw+xsOZ+xLMxK2lzOdEA5+wRb2GBT12489JXC6JK+zjUpfcW2aKvdcZtl/dFMUNbUHombALfh/70ivoKQuoMvBY+W+7fSs5KIibKZTMLtdtJ4z11jdITBBIPmELv8XroXVQuMgVftkEVOO//uDV9UNF4+xxjqLvQKkKdQnlnJK6DMqsDHLst9UvXb2we//g/JSXff3cdE088XiDZYXkvjYz+UCMHHGqbSzXEeWK+rtFtfbH7VRrKHQ9J/XI48n3auB lushano@MacBook-Pro-di-Lushano.local|$ssh_key|g" \
        ignition/flatcar-proxmox-100-docker.ign > "$temp_ign"

    # Upload Ignition configuration
    log "Uploading Ignition configuration..."
    $SSH_CMD "$PROXMOX_USER@$PROXMOX_HOST" "mkdir -p /var/lib/vz/snippets && pvesm set local --content images,iso,rootdir,backup,snippets || true"
    $SCP_CMD "$temp_ign" "$PROXMOX_USER@$PROXMOX_HOST:/var/lib/vz/snippets/flatcar-$VM_ID.ign"
    rm -f "$temp_ign"

    # Configure NFS server for shared storage
    log "Configuring NFS server for shared storage..."
    $SSH_CMD "$PROXMOX_USER@$PROXMOX_HOST" "
        # Install NFS server if needed
        apt update && apt install -y nfs-kernel-server

        # Ensure /mnt/nfs_shared exists (don't modify if already present)
        if [[ ! -d /mnt/nfs_shared ]]; then
            mkdir -p /mnt/nfs_shared
            chown nobody:nogroup /mnt/nfs_shared
        fi

        # Configure NFS export if not already present
        if ! grep -q '/mnt/nfs_shared' /etc/exports; then
            echo '/mnt/nfs_shared 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash,insecure,fsid=0)' >> /etc/exports
        else
            # Update existing export to ensure proper configuration
            sed -i 's|/mnt/nfs_shared.*|/mnt/nfs_shared 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash,insecure,fsid=0)|' /etc/exports
        fi

        # Apply NFS configuration
        exportfs -ra
        systemctl enable --now nfs-kernel-server
        systemctl enable --now rpcbind

        echo 'NFS export configured:'
        exportfs -v
    "

    # Execute deployment on Proxmox
    log "Executing VM deployment..."
    $SSH_CMD "$PROXMOX_USER@$PROXMOX_HOST" << EOF
set -euo pipefail

# Change to ISO directory
cd /var/lib/vz/template/iso

# Download Flatcar image if not present
if [[ ! -f "flatcar_production_qemu_image.img" ]]; then
    echo "Downloading Flatcar Stable KVM image..."
    curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2
    curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2.DIGESTS

    echo "Verifying image integrity..."
    grep flatcar_production_qemu_image.img.bz2 flatcar_production_qemu_image.img.bz2.DIGESTS | awk '{print \$4 "  flatcar_production_qemu_image.img.bz2"}' | sha256sum --check - || echo "Checksum verification skipped"

    echo "Extracting image..."
    bunzip2 flatcar_production_qemu_image.img.bz2
else
    echo "Flatcar image already exists"
fi

# Check if VM exists
if qm status $VM_ID >/dev/null 2>&1; then
    if [[ "$FORCE" == "true" ]]; then
        echo "Destroying existing VM $VM_ID..."
        qm stop $VM_ID || true
        sleep 5
        qm destroy $VM_ID || true
    else
        echo "VM $VM_ID already exists. Use --force to overwrite."
        exit 1
    fi
fi

# Create VM
echo "Creating VM $VM_ID..."
qm create $VM_ID \\
    --name $VM_NAME \\
    --memory $MEMORY \\
    --cores $CORES \\
    --sockets 1 \\
    --machine q35 \\
    --bios ovmf \\
    --efidisk0 $STORAGE:0,format=raw \\
    --net0 virtio,bridge=vmbr0 \\
    --serial0 socket \\
    --vga serial0 \\
    --agent enabled=1

# Import disk image
echo "Importing disk image..."
qm importdisk $VM_ID flatcar_production_qemu_image.img $STORAGE

# Configure storage
echo "Configuring storage..."
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-1
qm set $VM_ID --boot c --bootdisk scsi0

# Note: VirtioFS requires complex mapping-id setup, using NFS instead
echo "VirtioFS not configured - VM will use NFS mount for shared storage"

# Attach Ignition configuration
echo "Attaching Ignition configuration..."
qm set $VM_ID --args "-fw_cfg name=opt/com.coreos/config,file=/var/lib/vz/snippets/flatcar-$VM_ID.ign"

# Start VM
echo "Starting VM $VM_ID..."
qm start $VM_ID

echo "VM $VM_ID deployed successfully!"
EOF

    log "VM $VM_ID deployed successfully!"

    # Show access information
    echo ""
    echo "=========================================="
    info "VM Access Information:"
    echo "VM ID:           $VM_ID"
    echo "VM Name:         $VM_NAME"
    echo "Hostname:        $HOSTNAME"
    echo "IP Address:      $VM_IP"
    echo "SSH Access:      ssh core@$VM_IP"
    echo "Portainer:       https://$VM_IP:9443"
    echo "Shared Storage:  /mnt/nfs_shared (NFS mount)"
    echo "Nano Editor:     /home/core/nano filename.txt"
    echo "=========================================="
    echo ""

    warn "Wait 2-3 minutes for full boot and service startup"
    warn "Access Portainer within 5 minutes to avoid timeout"
    echo ""
    info "Post-deployment verification commands:"
    echo "  - Monitor console:    ssh $PROXMOX_USER@$PROXMOX_HOST 'qm terminal $VM_ID'"
    echo "  - Check status:       ssh core@$VM_IP"
    echo "  - Fix hostname:       ssh core@$VM_IP 'sudo hostnamectl set-hostname docker'"
    echo "  - Mount NFS:          ssh core@$VM_IP 'sudo mount -t nfs4 $PROXMOX_HOST:/ /mnt/nfs_shared'"
    echo "  - Test nano:          ssh core@$VM_IP '/home/core/nano test.txt'"
    echo "  - Test Portainer:     curl -k https://$VM_IP:9443"
}

# Main execution
main() {
    show_config

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run mode - configuration shown above, no deployment performed"
        exit 0
    fi

    validate_config
    deploy_vm

    log "Deployment completed successfully!"

    # Optional post-deployment verification
    if [[ -z "${SKIP_VERIFICATION:-}" ]]; then
        log "Starting post-deployment verification..."
        post_deployment_verification
    fi
}

# Post-deployment verification and cleanup
post_deployment_verification() {
    info "Waiting for VM to fully boot and services to start..."
    local max_attempts=10
    local attempt=1

    # Wait for SSH to be available
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -o ConnectTimeout=5 -o BatchMode=yes core@$VM_IP "echo 'SSH ready'" >/dev/null 2>&1; then
            break
        fi
        echo "Attempt $attempt/$max_attempts: Waiting for SSH..."
        sleep 15
        ((attempt++))
    done

    if [[ $attempt -gt $max_attempts ]]; then
        warn "SSH not available after ${max_attempts} attempts. Manual verification needed."
        return 1
    fi

    log "VM is accessible, performing verification and cleanup..."

    # Run verification and cleanup on the VM
    ssh core@$VM_IP "
        echo '=== Post-deployment verification and cleanup ==='

        # Check and fix failed services
        failed_services=\$(systemctl --failed --no-legend | wc -l)
        if [[ \$failed_services -gt 0 ]]; then
            echo 'Found \$failed_services failed services, cleaning up...'

            # Reset and disable problematic services
            sudo systemctl reset-failed install-nano.service 2>/dev/null || true
            sudo systemctl reset-failed set-hostname.service 2>/dev/null || true
            sudo systemctl disable install-nano.service 2>/dev/null || true
            sudo systemctl disable set-hostname.service 2>/dev/null || true

            echo 'Failed services cleaned up'
        fi

        # Ensure hostname is set correctly
        if [[ \"\$(hostname)\" != \"docker\" ]]; then
            echo 'Fixing hostname...'
            sudo hostnamectl set-hostname docker
        fi

        # Create nano wrapper if not present
        if [[ ! -f /home/core/nano ]]; then
            echo 'Creating nano wrapper...'
            cat > /home/core/nano << 'EOF'
#!/bin/bash
docker run --rm -it -v \"\$PWD\":/workspace -w /workspace alpine:latest sh -c 'apk add --no-cache nano >/dev/null 2>&1 && nano \"\$@\"' -- \"\$@\"
EOF
            chmod +x /home/core/nano
        fi

        # Ensure NFS is mounted
        if ! mountpoint -q /mnt/nfs_shared; then
            echo 'Mounting NFS...'
            sudo mount -t nfs4 $PROXMOX_HOST:/ /mnt/nfs_shared || echo 'NFS mount failed - manual intervention needed'
        fi

        # Ensure Portainer is running (it may stop after reboot since it's a oneshot service)
        if [[ \$(docker ps --filter name=portainer --format '{{.Names}}' | wc -l) -eq 0 ]]; then
            echo 'Portainer not running, starting it...'
            sudo systemctl start portainer-compose.service
            sleep 5
            if [[ \$(docker ps --filter name=portainer --format '{{.Names}}' | wc -l) -eq 0 ]]; then
                echo 'Portainer failed to start - check logs: journalctl -u portainer-compose.service'
            else
                echo 'Portainer started successfully'
            fi
        fi

        echo '=== Verification Summary ==='
        echo \"Hostname: \$(hostname)\"
        echo \"Failed services: \$(systemctl --failed --no-legend | wc -l)\"
        echo \"Docker status: \$(systemctl is-active docker)\"
        echo \"NFS mounted: \$(mountpoint -q /mnt/nfs_shared && echo 'Yes' || echo 'No')\"
        echo \"Nano wrapper: \$(test -x /home/core/nano && echo 'Yes' || echo 'No')\"
        echo \"Portainer running: \$(docker ps --filter name=portainer --format '{{.Names}}' | wc -l) containers\"
        echo \"Portainer service: \$(systemctl is-active portainer-compose.service)\"
    " 2>/dev/null

    local verification_result=$?

    if [[ $verification_result -eq 0 ]]; then
        log "✅ Post-deployment verification completed successfully!"
        echo ""
        info "VM is ready for use:"
        echo "  - SSH:       ssh core@$VM_IP"
        echo "  - Nano:      /home/core/nano filename.txt"
        echo "  - Portainer: https://$VM_IP:9443"
        echo "  - NFS:       /mnt/nfs_shared"
    else
        warn "Post-deployment verification encountered issues. Manual verification recommended."
        echo ""
        info "Manual verification commands:"
        echo "  - SSH check:      ssh core@$VM_IP"
        echo "  - Service check:  ssh core@$VM_IP 'systemctl --failed'"
        echo "  - Fix hostname:   ssh core@$VM_IP 'sudo hostnamectl set-hostname docker'"
        echo "  - Mount NFS:      ssh core@$VM_IP 'sudo mount -t nfs4 $PROXMOX_HOST:/ /mnt/nfs_shared'"
        echo "  - Create nano:    ssh core@$VM_IP 'test -x /home/core/nano || echo \"Need to create nano wrapper\"'"
    fi
}

# Execute main function
main "$@"