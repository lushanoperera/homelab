# Flatcar Container Linux Homelab Automation

This guide provides three different approaches to automate the deployment of Flatcar Container Linux VMs with Docker, Portainer, and NFS mounts in your Proxmox homelab.

## 🚀 Quick Start Options

Choose the approach that best fits your workflow:

1. **[Bash Script](#bash-script-approach)** - Simple, self-contained, great for ad-hoc deployments
2. **[Ansible Playbook](#ansible-playbook-approach)** - Structured, repeatable, ideal for configuration management
3. **[Terraform](#terraform-approach)** - Infrastructure as Code, perfect for version-controlled infrastructure

## 📋 Prerequisites

All approaches require:
- **Proxmox host** with SSH access
- **SSH key pair** (`~/.ssh/id_rsa.pub` by default)
- **Docker** installed locally (for Butane compilation)
- **NFS server** accessible from your network

### Additional Requirements by Approach:
- **Ansible**: `ansible-core` and `community.docker` collection
- **Terraform**: `terraform` binary and `telmate/proxmox` provider

---

## 🔧 Bash Script Approach

The simplest way to deploy individual VMs quickly.

### Features
- ✅ Single self-contained script
- ✅ Command-line parameter configuration
- ✅ Built-in validation and error handling
- ✅ Dry-run capability
- ✅ Real-time progress feedback

### Usage

```bash
# Basic deployment
./scripts/deploy-flatcar-vm.sh --vm-id 105 --vm-ip 10.21.21.105

# Full configuration
./scripts/deploy-flatcar-vm.sh \
  --vm-id 106 \
  --vm-ip 10.21.21.106 \
  --vm-name docker-node-1 \
  --memory 8192 \
  --cores 4 \
  --nfs-server 192.168.1.100 \
  --proxmox-host 10.21.21.99

# Dry run (show configuration without deploying)
./scripts/deploy-flatcar-vm.sh --vm-id 107 --vm-ip 10.21.21.107 --dry-run

# Deploy without Portainer
./scripts/deploy-flatcar-vm.sh --vm-id 108 --vm-ip 10.21.21.108 --no-portainer
```

### Common Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--vm-id` | VM ID (100-999999) | Required |
| `--vm-ip` | Static IP address | Required |
| `--vm-name` | VM hostname | `flatcar-<ID>` |
| `--memory` | Memory in MB | `4096` |
| `--cores` | CPU cores | `2` |
| `--proxmox-host` | Proxmox host IP | `10.21.21.99` |
| `--nfs-server` | NFS server IP | `192.168.200.4` |
| `--ssh-key` | SSH public key file | `~/.ssh/id_rsa.pub` |

### Examples

```bash
# Development VM
./scripts/deploy-flatcar-vm.sh --vm-id 110 --vm-ip 10.21.21.110 --vm-name dev-docker

# High-memory media server
./scripts/deploy-flatcar-vm.sh \
  --vm-id 120 \
  --vm-ip 10.21.21.120 \
  --vm-name media-server \
  --memory 16384 \
  --cores 8

# Different network configuration
./scripts/deploy-flatcar-vm.sh \
  --vm-id 130 \
  --vm-ip 192.168.1.130 \
  --gateway 192.168.1.1 \
  --dns1 192.168.1.1 \
  --nfs-server 192.168.1.100
```

---

## 🎯 Ansible Playbook Approach

Ideal for managing multiple VMs and maintaining consistent configuration.

### Features
- ✅ Declarative configuration
- ✅ Multi-VM deployment in parallel
- ✅ Template-based customization
- ✅ Idempotent operations
- ✅ Inventory management

### Setup

```bash
# Install Ansible requirements
pip install ansible
ansible-galaxy collection install community.docker

# Verify connectivity
ansible-playbook -i ansible/inventories/homelab.yml ansible/deploy-flatcar-vms.yml --check
```

### Configuration

Edit `ansible/inventories/homelab.yml`:

```yaml
---
all:
  children:
    proxmox:
      hosts:
        proxmox-host:
          ansible_host: 10.21.21.99
          ansible_user: root

          # Define your VMs here
          flatcar_vms:
            - id: 105
              name: "docker-node-1"
              ip: "10.21.21.105"
              memory: 4096
              cores: 2

            - id: 106
              name: "docker-node-2"
              ip: "10.21.21.106"
              memory: 8192
              cores: 4
              enable_portainer: true

            - id: 107
              name: "media-server"
              ip: "10.21.21.107"
              memory: 16384
              cores: 8

          # Global configuration
          vm_defaults:
            storage: local-lvm
            gateway: "10.21.21.1"
            dns1: "10.21.21.1"
            dns2: "8.8.8.8"
            nfs_server: "192.168.200.4"
            enable_portainer: true

# SSH key configuration
ansible_ssh_public_key_file: "~/.ssh/id_rsa.pub"
```

### Deployment

```bash
# Deploy all VMs
ansible-playbook -i ansible/inventories/homelab.yml ansible/deploy-flatcar-vms.yml

# Deploy with custom variables
ansible-playbook -i ansible/inventories/homelab.yml ansible/deploy-flatcar-vms.yml \
  --extra-vars "vm_defaults.nfs_server=192.168.1.100"

# Dry run (check mode)
ansible-playbook -i ansible/inventories/homelab.yml ansible/deploy-flatcar-vms.yml --check

# Deploy specific VMs (tag-based)
ansible-playbook -i ansible/inventories/homelab.yml ansible/deploy-flatcar-vms.yml --limit "vm_id_105,vm_id_106"
```

### Multiple Environment Support

```bash
# Production environment
ansible-playbook -i ansible/inventories/production.yml ansible/deploy-flatcar-vms.yml

# Development environment
ansible-playbook -i ansible/inventories/development.yml ansible/deploy-flatcar-vms.yml
```

---

## 🏗️ Terraform Approach

Best for infrastructure as code and version-controlled deployments.

### Features
- ✅ Infrastructure as Code
- ✅ State management
- ✅ Resource dependencies
- ✅ Plan/apply workflow
- ✅ Modules and reusability

### Setup

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars
cat > terraform.tfvars << EOF
proxmox_password = "your_proxmox_password"
ssh_public_key   = "$(cat ~/.ssh/id_rsa.pub)"

# Customize your VMs
flatcar_vms = {
  "docker-1" = {
    id              = 105
    name            = "flatcar-docker-1"
    ip              = "10.21.21.105"
    memory          = 4096
    cores           = 2
    enable_portainer = true
  }
  "docker-2" = {
    id              = 106
    name            = "flatcar-docker-2"
    ip              = "10.21.21.106"
    memory          = 8192
    cores           = 4
    enable_portainer = true
  }
  "media" = {
    id              = 107
    name            = "media-server"
    ip              = "10.21.21.107"
    memory          = 16384
    cores           = 8
    enable_portainer = true
  }
}
EOF
```

### Deployment

```bash
# Plan deployment
terraform plan

# Apply configuration
terraform apply

# Show current state
terraform show

# Destroy infrastructure
terraform destroy
```

### Advanced Configuration

```bash
# Different environments
terraform workspace new production
terraform workspace new development
terraform workspace select production

# Module-based deployment
terraform apply -var-file="environments/production.tfvars"

# Target specific resources
terraform apply -target="proxmox_vm_qemu.flatcar_vms[\"docker-1\"]"
```

---

## 🔧 Configuration Customization

### Network Configuration

All approaches support customizing network settings:

**Bash Script:**
```bash
--gateway 192.168.1.1 --dns1 192.168.1.1 --dns2 8.8.8.8
```

**Ansible:**
```yaml
vm_defaults:
  gateway: "192.168.1.1"
  dns1: "192.168.1.1"
  dns2: "8.8.8.8"
```

**Terraform:**
```hcl
network_config = {
  gateway = "192.168.1.1"
  dns1    = "192.168.1.1"
  dns2    = "8.8.8.8"
}
```

### NFS Configuration

Modify NFS server and mount options:

**Default NFS Mounts:**
- `/mnt/nfs_shared` ← `192.168.200.4:/rpool/shared`
- `/mnt/nfs_media` ← `192.168.200.4:/rpool/shared/media`

**Custom NFS Server:**
- Bash: `--nfs-server 192.168.1.100`
- Ansible: `vm_defaults.nfs_server: "192.168.1.100"`
- Terraform: `nfs_server = "192.168.1.100"`

### Hardware Configuration

**VM Specifications:**
- Memory: 1GB-64GB (default: 4GB)
- CPU Cores: 1-32 (default: 2)
- Storage: Configurable pool (default: `local-lvm`)

### Portainer Configuration

**Enable/Disable Portainer:**
- Bash: `--no-portainer` flag
- Ansible: `enable_portainer: false` per VM
- Terraform: `enable_portainer = false` per VM

---

## 🔍 Post-Deployment Verification

After deployment, verify your VMs:

```bash
# Test network connectivity
ping 10.21.21.105

# SSH access
ssh core@10.21.21.105

# Check NFS mounts
ssh core@10.21.21.105 'ls -la /mnt/nfs_shared /mnt/nfs_media'

# Verify Docker
ssh core@10.21.21.105 'docker --version'

# Check Portainer (if enabled)
curl -k https://10.21.21.105:9443/api/status

# Verify QEMU Guest Agent
ssh root@10.21.21.99 'qm guest cmd 105 status'
```

## 🚨 Troubleshooting

### Common Issues

**Network Issues:**
```bash
# Check interface name in VM
ssh core@<VM_IP> 'ip addr show'

# Verify network configuration
ssh core@<VM_IP> 'sudo systemctl status systemd-networkd'
```

**NFS Mount Issues:**
```bash
# Check NFS availability
showmount -e 192.168.200.4

# Verify mount status
ssh core@<VM_IP> 'systemctl status mnt-nfs_shared.mount'
```

**Portainer Timeout:**
```bash
# Restart Portainer container
ssh core@<VM_IP> 'docker restart portainer'
```

### Log Analysis

```bash
# Boot logs
ssh core@<VM_IP> 'journalctl -b'

# Network logs
ssh core@<VM_IP> 'sudo journalctl -u systemd-networkd'

# Docker logs
ssh core@<VM_IP> 'journalctl -u docker'

# NFS logs
ssh core@<VM_IP> 'journalctl -u mnt-nfs_shared.mount'
```

---

## 📚 Reference

### File Structure

```
flatcar-deployment/
├── scripts/
│   └── deploy-flatcar-vm.sh           # Bash deployment script
├── ansible/
│   ├── deploy-flatcar-vms.yml         # Main playbook
│   ├── inventories/
│   │   └── homelab.yml                # Inventory example
│   └── roles/flatcar-vm/              # VM deployment role
├── terraform/
│   ├── main.tf                        # Main configuration
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Output definitions
│   └── templates/
│       └── flatcar.bu.tpl             # Butane template
├── configs/
│   └── flatcar-template.bu            # Butane template
└── AUTOMATION.md                      # This guide
```

### Default Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| **Memory** | 4096 MB | RAM allocation |
| **CPU Cores** | 2 | Virtual CPU cores |
| **Storage** | local-lvm | Proxmox storage pool |
| **Network** | vmbr0 | Bridge interface |
| **Gateway** | 10.21.21.1 | Network gateway |
| **DNS** | 10.21.21.1, 8.8.8.8 | DNS servers |
| **NFS Server** | 192.168.200.4 | NFS server IP |

### Supported VM IDs

- **Range:** 100-999999
- **Recommended:** 100-199 for testing, 200+ for production
- **Avoid:** IDs already in use on your Proxmox cluster

---

## 🎉 Quick Deploy Examples

**Single VM for testing:**
```bash
./scripts/deploy-flatcar-vm.sh --vm-id 199 --vm-ip 10.21.21.199
```

**Production cluster with Ansible:**
```bash
# Edit ansible/inventories/production.yml with your VMs
ansible-playbook -i ansible/inventories/production.yml ansible/deploy-flatcar-vms.yml
```

**Infrastructure as Code with Terraform:**
```bash
cd terraform/
terraform plan -out=homelab.tfplan
terraform apply homelab.tfplan
```

Happy Docker homelab automation! 🐳🏠