#!/bin/bash

# Flatcar Container Linux VM Deployment Script for Proxmox Homelab
# Automatically deploys Docker-ready VMs with NFS access and Portainer

set -euo pipefail

# Default Configuration
DEFAULT_PROXMOX_HOST="10.21.21.99"
DEFAULT_PROXMOX_USER="root"
DEFAULT_STORAGE="local-lvm"
DEFAULT_MEMORY="4096"
DEFAULT_CORES="2"
DEFAULT_GATEWAY="10.21.21.1"
DEFAULT_DNS1="10.21.21.1"
DEFAULT_DNS2="8.8.8.8"
DEFAULT_NFS_SERVER="192.168.200.4"
DEFAULT_SSH_KEY_FILE="$HOME/.ssh/id_rsa.pub"

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

# Help function
show_help() {
cat << EOF
Flatcar Container Linux VM Deployment Script for Proxmox Homelab

Usage: $0 --vm-id <ID> --vm-ip <IP> [OPTIONS]

Required Arguments:
  --vm-id <ID>          VM ID (e.g., 104)
  --vm-ip <IP>          VM IP address (e.g., 10.21.21.104)

Optional Arguments:
  --vm-name <NAME>      VM name (default: flatcar-<ID>)
  --proxmox-host <IP>   Proxmox host IP (default: $DEFAULT_PROXMOX_HOST)
  --proxmox-user <USER> Proxmox username (default: $DEFAULT_PROXMOX_USER)
  --storage <STORAGE>   Proxmox storage (default: $DEFAULT_STORAGE)
  --memory <MB>         Memory in MB (default: $DEFAULT_MEMORY)
  --cores <N>           CPU cores (default: $DEFAULT_CORES)
  --gateway <IP>        Network gateway (default: $DEFAULT_GATEWAY)
  --dns1 <IP>           Primary DNS (default: $DEFAULT_DNS1)
  --dns2 <IP>           Secondary DNS (default: $DEFAULT_DNS2)
  --nfs-server <IP>     NFS server IP (default: $DEFAULT_NFS_SERVER)
  --ssh-key <FILE>      SSH public key file (default: $DEFAULT_SSH_KEY_FILE)
  --no-portainer        Skip Portainer installation
  --dry-run             Show configuration without deploying
  --help                Show this help

Examples:
  # Basic deployment
  $0 --vm-id 105 --vm-ip 10.21.21.105

  # Custom configuration
  $0 --vm-id 106 --vm-ip 10.21.21.106 --vm-name docker-node-1 --memory 8192 --cores 4

  # Different NFS server
  $0 --vm-id 107 --vm-ip 10.21.21.107 --nfs-server 192.168.1.100

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vm-id)
                VM_ID="$2"
                shift 2
                ;;
            --vm-ip)
                VM_IP="$2"
                shift 2
                ;;
            --vm-name)
                VM_NAME="$2"
                shift 2
                ;;
            --proxmox-host)
                PROXMOX_HOST="$2"
                shift 2
                ;;
            --proxmox-user)
                PROXMOX_USER="$2"
                shift 2
                ;;
            --storage)
                STORAGE="$2"
                shift 2
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --cores)
                CORES="$2"
                shift 2
                ;;
            --gateway)
                GATEWAY="$2"
                shift 2
                ;;
            --dns1)
                DNS1="$2"
                shift 2
                ;;
            --dns2)
                DNS2="$2"
                shift 2
                ;;
            --nfs-server)
                NFS_SERVER="$2"
                shift 2
                ;;
            --ssh-key)
                SSH_KEY_FILE="$2"
                shift 2
                ;;
            --no-portainer)
                NO_PORTAINER=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Check required arguments
    if [[ -z "${VM_ID:-}" ]]; then
        error "VM ID is required. Use --vm-id <ID>"
    fi

    if [[ -z "${VM_IP:-}" ]]; then
        error "VM IP is required. Use --vm-ip <IP>"
    fi

    # Set defaults
    VM_NAME="${VM_NAME:-flatcar-$VM_ID}"
    PROXMOX_HOST="${PROXMOX_HOST:-$DEFAULT_PROXMOX_HOST}"
    PROXMOX_USER="${PROXMOX_USER:-$DEFAULT_PROXMOX_USER}"
    STORAGE="${STORAGE:-$DEFAULT_STORAGE}"
    MEMORY="${MEMORY:-$DEFAULT_MEMORY}"
    CORES="${CORES:-$DEFAULT_CORES}"
    GATEWAY="${GATEWAY:-$DEFAULT_GATEWAY}"
    DNS1="${DNS1:-$DEFAULT_DNS1}"
    DNS2="${DNS2:-$DEFAULT_DNS2}"
    NFS_SERVER="${NFS_SERVER:-$DEFAULT_NFS_SERVER}"
    SSH_KEY_FILE="${SSH_KEY_FILE:-$DEFAULT_SSH_KEY_FILE}"
    NO_PORTAINER="${NO_PORTAINER:-false}"
    DRY_RUN="${DRY_RUN:-false}"

    HOSTNAME="$VM_NAME"
}

# Validate configuration
validate_config() {
    info "Validating configuration..."

    # Check SSH key file
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        error "SSH key file not found: $SSH_KEY_FILE"
    fi

    # Check VM ID format
    if ! [[ "$VM_ID" =~ ^[0-9]+$ ]] || [[ "$VM_ID" -lt 100 ]] || [[ "$VM_ID" -gt 999999 ]]; then
        error "VM ID must be a number between 100 and 999999"
    fi

    # Check IP format
    if ! [[ "$VM_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error "Invalid IP address format: $VM_IP"
    fi

    # Test Proxmox connectivity
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$PROXMOX_USER@$PROXMOX_HOST" "echo 'Connection test'" >/dev/null 2>&1; then
        error "Cannot connect to Proxmox host $PROXMOX_HOST as $PROXMOX_USER"
    fi

    info "Configuration validated successfully"
}

# Show configuration
show_config() {
    info "Deployment Configuration:"
    echo "=========================================="
    echo "VM ID:          $VM_ID"
    echo "VM Name:        $VM_NAME"
    echo "VM IP:          $VM_IP"
    echo "Proxmox Host:   $PROXMOX_HOST"
    echo "Storage:        $STORAGE"
    echo "Memory:         ${MEMORY}MB"
    echo "CPU Cores:      $CORES"
    echo "Gateway:        $GATEWAY"
    echo "DNS Servers:    $DNS1, $DNS2"
    echo "NFS Server:     $NFS_SERVER"
    echo "SSH Key:        $SSH_KEY_FILE"
    echo "Portainer:      $([[ "$NO_PORTAINER" == "true" ]] && echo "Disabled" || echo "Enabled")"
    echo "=========================================="
}

# Generate Butane configuration
generate_butane_config() {
    local ssh_key
    ssh_key=$(cat "$SSH_KEY_FILE")

    local temp_dir
    temp_dir=$(mktemp -d)
    local butane_file="$temp_dir/flatcar-$VM_ID.bu"
    local ignition_file="$temp_dir/flatcar-$VM_ID.ign"

    log "Generating Butane configuration..."

    # Create Butane config by substituting variables in template
    envsubst << 'EOF' > "$butane_file"
variant: flatcar
version: 1.1.0

passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - $SSH_KEY

storage:
  files:
    # Static network configuration
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

    # NFS client configuration
    - path: /etc/modules-load.d/nfs.conf
      mode: 0644
      contents:
        inline: |
          nfs
          nfsd
          rpcsec_gss_krb5

    # Create NFS mount points
    - path: /etc/tmpfiles.d/nfs-mounts.conf
      mode: 0644
      contents:
        inline: |
          d /mnt/nfs_shared 0755 core core -
          d /mnt/nfs_media 0755 core core -

    # Portainer Docker Compose
    - path: /opt/portainer/docker-compose.yml
      mode: 0644
      contents:
        inline: |
          version: '3.8'
          services:
            portainer:
              image: portainer/portainer-ce:2.20.3
              container_name: portainer
              restart: unless-stopped
              ports:
                - "8000:8000"
                - "9443:9443"
              volumes:
                - portainer_data:/data
                - /var/run/docker.sock:/var/run/docker.sock
                - /mnt/nfs_shared:/mnt/nfs_shared:ro
                - /mnt/nfs_media:/mnt/nfs_media:ro
              security_opt:
                - no-new-privileges:true
          volumes:
            portainer_data:
              driver: local

    # Docker Compose binary
    - path: /opt/bin/docker-compose
      mode: 0755
      contents:
        source: https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64

systemd:
  units:
    # Enable Docker service
    - name: docker.service
      enabled: true

    # NFS mount for shared directory
    - name: mnt-nfs_shared.mount
      enabled: true
      contents: |
        [Unit]
        Description=NFS Shared Mount
        After=network-online.target
        Wants=network-online.target

        [Mount]
        What=$NFS_SERVER:/rpool/shared
        Where=/mnt/nfs_shared
        Type=nfs4
        Options=rw,fsc,noatime,vers=4.2,proto=tcp,rsize=1048576,wsize=1048576,nconnect=8,soft,timeo=100,retrans=5,_netdev

        [Install]
        WantedBy=multi-user.target

    # NFS mount for media directory
    - name: mnt-nfs_media.mount
      enabled: true
      contents: |
        [Unit]
        Description=NFS Media Mount
        After=network-online.target
        Wants=network-online.target

        [Mount]
        What=$NFS_SERVER:/rpool/shared/media
        Where=/mnt/nfs_media
        Type=nfs4
        Options=rw,fsc,noatime,vers=4.2,proto=tcp,rsize=1048576,wsize=1048576,nconnect=8,soft,timeo=100,retrans=5,_netdev

        [Install]
        WantedBy=multi-user.target

    # NFS automount for shared directory
    - name: mnt-nfs_shared.automount
      enabled: true
      contents: |
        [Unit]
        Description=NFS Shared Automount
        Before=local-fs.target

        [Automount]
        Where=/mnt/nfs_shared
        TimeoutIdleSec=10

        [Install]
        WantedBy=multi-user.target

    # NFS automount for media directory
    - name: mnt-nfs_media.automount
      enabled: true
      contents: |
        [Unit]
        Description=NFS Media Automount
        Before=local-fs.target

        [Automount]
        Where=/mnt/nfs_media
        TimeoutIdleSec=10

        [Install]
        WantedBy=multi-user.target

    # Enable QEMU Guest Agent
    - name: qemu-guest-agent.service
      enabled: true

    # Create Portainer directory
    - name: create-portainer-dir.service
      enabled: true
      contents: |
        [Unit]
        Description=Create Portainer directory
        Before=portainer-compose.service

        [Service]
        Type=oneshot
        ExecStart=/usr/bin/mkdir -p /opt/portainer
        RemainAfterExit=true

        [Install]
        WantedBy=multi-user.target

    # Portainer deployment service
    - name: portainer-compose.service
      enabled: true
      contents: |
        [Unit]
        Description=Deploy Portainer via Docker Compose
        Requires=docker.service create-portainer-dir.service mnt-nfs_shared.mount mnt-nfs_media.mount
        After=docker.service create-portainer-dir.service mnt-nfs_shared.mount mnt-nfs_media.mount
        Wants=network-online.target
        After=network-online.target

        [Service]
        Type=oneshot
        WorkingDirectory=/opt/portainer
        ExecStart=/opt/bin/docker-compose up -d
        ExecStop=/opt/bin/docker-compose down
        TimeoutStartSec=300
        RemainAfterExit=true

        [Install]
        WantedBy=multi-user.target

    # Set hostname
    - name: set-hostname.service
      enabled: true
      contents: |
        [Unit]
        Description=Set hostname
        Before=systemd-hostnamed.service

        [Service]
        Type=oneshot
        ExecStart=/usr/bin/hostnamectl set-hostname $HOSTNAME
        RemainAfterExit=true

        [Install]
        WantedBy=multi-user.target
EOF

    # Set variables for envsubst
    export SSH_KEY="$ssh_key"
    export VM_IP="$VM_IP"
    export GATEWAY="$GATEWAY"
    export DNS1="$DNS1"
    export DNS2="$DNS2"
    export NFS_SERVER="$NFS_SERVER"
    export HOSTNAME="$HOSTNAME"

    # Generate final config
    envsubst < "$butane_file" > "${butane_file}.tmp"
    mv "${butane_file}.tmp" "$butane_file"

    log "Compiling Butane to Ignition..."

    # Compile to Ignition
    if ! docker run --rm -i quay.io/coreos/butane:latest --strict < "$butane_file" > "$ignition_file" 2>/dev/null; then
        error "Failed to compile Butane configuration"
    fi

    # Store file paths globally
    BUTANE_CONFIG_FILE="$butane_file"
    IGNITION_CONFIG_FILE="$ignition_file"

    log "Configuration generated: $ignition_file"
}

# Deploy VM to Proxmox
deploy_vm() {
    log "Starting deployment to Proxmox host $PROXMOX_HOST"

    # Upload Ignition configuration
    log "Uploading Ignition configuration..."
    ssh "$PROXMOX_USER@$PROXMOX_HOST" "mkdir -p /var/lib/vz/snippets && pvesm set local --content images,iso,rootdir,backup,snippets || true"
    scp "$IGNITION_CONFIG_FILE" "$PROXMOX_USER@$PROXMOX_HOST:/var/lib/vz/snippets/flatcar-$VM_ID.ign"

    # Execute deployment on Proxmox
    log "Executing VM deployment..."
    ssh "$PROXMOX_USER@$PROXMOX_HOST" << EOF
set -euo pipefail

# Change to ISO directory
cd /var/lib/vz/template/iso

# Download Flatcar image if not present
if [[ ! -f "flatcar_production_qemu_image.img" ]]; then
    echo "Downloading Flatcar Stable KVM image..."
    curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2
    curl -O https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2.DIGESTS

    echo "Verifying image integrity..."
    grep flatcar_production_qemu_image.img.bz2 flatcar_production_qemu_image.img.bz2.DIGESTS | awk '{print \$4 "  flatcar_production_qemu_image.img.bz2"}' | sha256sum --check - || true

    echo "Extracting image..."
    bunzip2 flatcar_production_qemu_image.img.bz2
else
    echo "Flatcar image already exists"
fi

# Destroy existing VM if present
echo "Destroying existing VM $VM_ID if it exists..."
if qm status $VM_ID >/dev/null 2>&1; then
    qm stop $VM_ID || true
    sleep 5
    qm destroy $VM_ID || true
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
    --vga serial0

# Import disk image
echo "Importing disk image..."
qm importdisk $VM_ID flatcar_production_qemu_image.img $STORAGE

# Configure storage
echo "Configuring storage..."
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VM_ID-disk-1
qm set $VM_ID --boot c --bootdisk scsi0

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
    echo "VM ID:       $VM_ID"
    echo "VM Name:     $VM_NAME"
    echo "IP Address:  $VM_IP"
    echo "SSH Access:  ssh core@$VM_IP"
    if [[ "$NO_PORTAINER" != "true" ]]; then
        echo "Portainer:   https://$VM_IP:9443"
    fi
    echo "NFS Mounts:"
    echo "  - /mnt/nfs_shared (from $NFS_SERVER:/rpool/shared)"
    echo "  - /mnt/nfs_media (from $NFS_SERVER:/rpool/shared/media)"
    echo "=========================================="
    echo ""

    warn "Wait 2-3 minutes for full boot and service startup"

    if [[ "$NO_PORTAINER" != "true" ]]; then
        warn "Access Portainer within 5 minutes to avoid timeout"
    fi
}

# Cleanup temporary files
cleanup() {
    if [[ -n "${IGNITION_CONFIG_FILE:-}" ]] && [[ -f "$IGNITION_CONFIG_FILE" ]]; then
        rm -rf "$(dirname "$IGNITION_CONFIG_FILE")"
        log "Temporary files cleaned up"
    fi
}

# Main execution
main() {
    # Parse arguments
    parse_args "$@"

    # Show configuration
    show_config

    # If dry run, exit here
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run mode - configuration shown above, no deployment performed"
        exit 0
    fi

    # Validate configuration
    validate_config

    # Generate configuration
    generate_butane_config

    # Deploy VM
    deploy_vm

    # Cleanup
    trap cleanup EXIT

    log "Deployment completed successfully!"
}

# Execute main function
main "$@"