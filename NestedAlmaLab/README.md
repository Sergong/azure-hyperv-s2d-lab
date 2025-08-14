# AlmaLinux Cloud-Init Template for Hyper-V

This project provides a streamlined approach to building and deploying AlmaLinux virtual machines on Hyper-V using Packer templates and cloud-init for configuration management.

## Overview

The cloud-init approach separates template building from VM configuration, allowing you to:

- **Build once**: Create a reusable AlmaLinux template with cloud-init enabled
- **Deploy many**: Deploy multiple VMs with unique configurations (IP addresses, users, SSH keys) without rebuilding templates
- **Scale easily**: Quickly spin up multiple VMs with different network and user configurations
- **Automate fully**: Deploy VMs with static IPs, custom users, and SSH keys automatically

## Features

- ✅ **AlmaLinux 9 Base Template**: Minimal, secure AlmaLinux installation
- ✅ **Cloud-Init Integration**: NoCloud datasource for flexible configuration
- ✅ **Static IP Support**: Configure unique static IPs per VM deployment
- ✅ **User Management**: Create custom users with SSH keys and sudo access
- ✅ **Hyper-V Integration**: Gen1/Gen2 VM support with Hyper-V tools
- ✅ **Security Hardened**: Secure SSH configuration, disabled root login for deployed VMs
- ✅ **Nested Virtualization**: Support for nested virtualization scenarios

## Quick Start

### 1. Prerequisites

- Windows 10/11 or Windows Server with Hyper-V enabled
- PowerShell 5.1 or later
- Packer installed and in PATH
- AlmaLinux 9 ISO downloaded

### 2. Download AlmaLinux ISO

```powershell
# Download AlmaLinux 9 ISO (optional - script can do this)
.\scripts\fetch_iso.ps1
```

### 3. Build the Cloud-Init Template

```powershell
# Build Generation 1 template (recommended)
.\scripts\build-cloudinit-template.ps1 -Generation 1

# Or build Generation 2 template
.\scripts\build-cloudinit-template.ps1 -Generation 2
```

### 4. Deploy VMs with Cloud-Init

```powershell
# Deploy a single test VM
.\scripts\deploy-with-cloudinit.ps1 -VMCount 1 -StartVMs

# Deploy multiple VMs with custom network
.\scripts\deploy-with-cloudinit.ps1 -VMCount 3 -NetworkSubnet '192.168.100' -StartVMs

# Deploy with custom user and SSH key
.\scripts\deploy-with-cloudinit.ps1 -VMCount 2 -Username 'admin' -SSHPublicKeyPath '~\.ssh\id_rsa.pub' -StartVMs
```

## Project Structure

```
NestedAlmaLab/
├── README.md                                    # This documentation
├── scripts/
│   ├── build-cloudinit-template.ps1            # Builds the cloud-init template
│   ├── deploy-with-cloudinit.ps1               # Deploys VMs with cloud-init config
│   ├── deploy-examples.ps1                     # Example deployment scenarios
│   └── fetch_iso.ps1                           # Downloads AlmaLinux ISO
├── templates/
│   └── AlmaLinux/
│       └── hyperv/
│           └── ks-with-cloudinit.cfg            # Kickstart file for cloud-init template
└── output-almalinux-cloudinit/                 # Generated template location (after build)
    └── Virtual Hard Disks/
        └── *.vhdx                               # Template VHDX file
```

## Detailed Usage

### Building the Template

The `build-cloudinit-template.ps1` script creates a reusable AlmaLinux template with cloud-init pre-installed and configured.

#### Basic Build

```powershell
# Build with default settings (Generation 1, default ISO path)
.\scripts\build-cloudinit-template.ps1
```

#### Advanced Build Options

```powershell
# Specify VM generation and ISO path
.\scripts\build-cloudinit-template.ps1 -Generation 2 -ISOPath "D:\ISOs\AlmaLinux-9.iso"

# Force rebuild existing template
.\scripts\build-cloudinit-template.ps1 -Force

# All options combined
.\scripts\build-cloudinit-template.ps1 -Generation 1 -ISOPath "C:\ISOs\AlmaLinux-9-latest-x86_64-dvd.iso" -Force
```

#### What Happens During Build

1. **Environment Setup**: Verifies Hyper-V, creates PackerInternal switch, configures firewall
2. **Packer Template Generation**: Creates HCL template for building the VM
3. **VM Creation**: Creates VM with specified generation and resources
4. **AlmaLinux Installation**: Boots from ISO and runs automated kickstart installation
5. **Cloud-Init Setup**: Installs and configures cloud-init with NoCloud datasource
6. **SSH Configuration**: Sets up SSH for Packer access during build, configured to be secure post-deployment
7. **Template Finalization**: Cleans up build artifacts, prepares template for cloning

#### Build Output

After successful build, you'll have:
- Template VM in `output-almalinux-cloudinit/`
- VHDX file ready for cloning
- Template configured with cloud-init for flexible deployment

### Deploying VMs

The `deploy-with-cloudinit.ps1` script deploys VMs from the template with cloud-init configuration.

#### Basic Deployment

```powershell
# Deploy single VM with defaults
.\scripts\deploy-with-cloudinit.ps1 -VMCount 1 -StartVMs
```

This creates:
- VM name: `AlmaLinux-CloudInit-01`
- IP: `192.168.1.101/24` (gateway `192.168.1.1`)
- User: `labuser` with default password
- Memory: 2GB, CPUs: 2

#### Network Configuration

```powershell
# Deploy to different network subnet
.\scripts\deploy-with-cloudinit.ps1 -VMCount 3 -NetworkSubnet '10.0.50' -StartVMs

# Custom IP range and switch
.\scripts\deploy-with-cloudinit.ps1 -VMCount 5 -NetworkSubnet '192.168.100' -SwitchName 'Internal' -StartVMs
```

#### User and Authentication

```powershell
# Create VMs with custom user
.\scripts\deploy-with-cloudinit.ps1 -VMCount 2 -Username 'admin' -StartVMs

# Add SSH public key authentication
.\scripts\deploy-with-cloudinit.ps1 -VMCount 1 -Username 'devops' -SSHPublicKeyPath 'C:\Users\me\.ssh\id_rsa.pub' -StartVMs

# Specify custom passwords (will prompt securely)
.\scripts\deploy-with-cloudinit.ps1 -VMCount 1 -Username 'admin' -PromptForPasswords -StartVMs
```

#### Resource Configuration

```powershell
# Deploy with custom resources
.\scripts\deploy-with-cloudinit.ps1 -VMCount 2 -Memory 4096 -CPUs 4 -StartVMs

# All options combined
.\scripts\deploy-with-cloudinit.ps1 `
    -VMCount 3 `
    -NetworkSubnet '172.16.10' `
    -Username 'sysadmin' `
    -SSHPublicKeyPath '~\.ssh\id_ed25519.pub' `
    -Memory 8192 `
    -CPUs 6 `
    -SwitchName 'External' `
    -StartVMs
```

### Deployment Examples

See `scripts\deploy-examples.ps1` for complete example scenarios:

1. **Development Environment**: Single VM with development tools
2. **Testing Cluster**: Multiple VMs on isolated network
3. **Production-like**: Multi-node setup with SSH keys and custom users
4. **Lab Network**: Large subnet with many VMs for training/testing

## Network Configuration

### Default Network Setup

The build process creates a `PackerInternal` switch for template building:
- Internal switch with NAT
- Host adapter IP: `192.168.200.1/24`
- VM build IP: `192.168.200.100/24`

### Deployment Networks

VMs can be deployed to any Hyper-V switch:
- **External**: Connected to physical network
- **Internal**: Host-only network with NAT
- **Private**: VM-to-VM only network

The deployment script configures static IPs automatically:
- IP range: `{NetworkSubnet}.101` to `{NetworkSubnet}.200`
- Gateway: `{NetworkSubnet}.1`
- DNS: `8.8.8.8, 8.8.4.4`

## Cloud-Init Configuration

### User Data

Each deployed VM receives custom cloud-init configuration:

```yaml
#cloud-config
users:
  - name: {username}
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - {ssh-public-key}  # if provided

chpasswd:
  list: |
    root:{root-password}
    {username}:{user-password}
  expire: false

ssh_pwauth: true
disable_root: false  # Allows root login during deployment, can be disabled later
```

### Network Data

Static IP configuration per VM:

```yaml
version: 2
ethernets:
  eth0:
    addresses:
      - {ip-address}/24
    gateway4: {gateway}
    nameservers:
      addresses: [8.8.8.8, 8.8.4.4]
```

### Verification

Check cloud-init status on deployed VMs:

```bash
# SSH into VM
ssh labuser@192.168.1.101

# Check cloud-init status
sudo cloud-init status --long

# View applied configuration
sudo cloud-init query -f yaml

# Check logs
sudo tail -f /var/log/cloud-init.log
```

## Troubleshooting

### Template Build Issues

#### Packer Plugin Errors
```powershell
# Manually initialize plugins
packer init almalinux-cloudinit.pkr.hcl
```

#### SSH Connection Problems
- Check PackerInternal switch is created: `Get-VMSwitch -Name PackerInternal`
- Verify NAT network: `Get-NetNat -Name PackerInternalNAT`  
- Check firewall rules for ports 8080-8090
- Review build logs: `packer-cloudinit-build.log`

#### ISO Download/Path Issues
```powershell
# Download ISO to default location
.\scripts\fetch_iso.ps1

# Or specify custom path
.\scripts\build-cloudinit-template.ps1 -ISOPath "D:\ISOs\AlmaLinux-9.iso"
```

### Deployment Issues

#### Cloud-Init Not Running
```bash
# Force cloud-init to run
sudo cloud-init clean
sudo cloud-init init --local
sudo cloud-init init
```

#### Network Configuration Problems
```bash
# Check NetworkManager status
sudo nmcli connection show
sudo nmcli device status

# Restart networking
sudo systemctl restart NetworkManager
```

#### SSH Access Issues
```bash
# Check SSH service
sudo systemctl status sshd

# View SSH configuration
sudo grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config

# Check cloud-init applied SSH config
sudo grep -A 10 -B 5 "ssh" /var/log/cloud-init.log
```

### Log Files

Key log locations:
- **Build logs**: `packer-cloudinit-build.log` (in project root)
- **Kickstart logs**: `/var/log/anaconda/` (in template)
- **Cloud-init logs**: `/var/log/cloud-init*.log` (in deployed VMs)
- **SSH logs**: `/var/log/secure` (authentication events)

## Advanced Configuration

### Custom Kickstart

Modify `templates/AlmaLinux/hyperv/ks-with-cloudinit.cfg` to:
- Add additional packages
- Change partitioning scheme  
- Modify security settings
- Add custom post-install scripts

### Extended Cloud-Init

Create custom cloud-init modules:
- Software installation
- Configuration management
- Monitoring setup
- Security hardening

### Integration

The cloud-init approach integrates well with:
- **Ansible**: Use cloud-init to bootstrap Ansible connectivity
- **Terraform**: Define infrastructure with Terraform, configure with cloud-init
- **CI/CD**: Automated testing environments with unique configurations
- **Container orchestration**: Kubernetes nodes with cloud-init initialization

## Security Considerations

### Template Security

- Root password set to `packer` during build (changed/disabled in deployed VMs)
- SSH keys cleared from template
- Machine ID reset for unique VM identity
- Build-specific SSH configuration removed

### Deployed VM Security

- Root login disabled by default (configurable)
- Password authentication enabled (can be disabled if using SSH keys)
- Firewall enabled with SSH access
- SELinux enforcing mode
- Regular user with sudo access

### Network Security

- Private/internal switches isolate VMs
- Static IP configuration prevents DHCP conflicts
- Custom DNS configuration (defaults to public DNS)

## Contributing

To extend this project:

1. **New Features**: Add to the deployment or build scripts
2. **Templates**: Create new kickstart configurations
3. **Documentation**: Update this README with new capabilities
4. **Testing**: Validate changes across different Hyper-V versions

## License

This project is provided as-is for educational and development purposes.

---

## Quick Reference

### Common Commands

```powershell
# Build template
.\scripts\build-cloudinit-template.ps1 -Generation 1

# Deploy single VM
.\scripts\deploy-with-cloudinit.ps1 -VMCount 1 -StartVMs

# Deploy cluster
.\scripts\deploy-with-cloudinit.ps1 -VMCount 5 -NetworkSubnet '10.0.100' -StartVMs

# Check VM status
Get-VM AlmaLinux-CloudInit-*

# Connect to VM
ssh labuser@192.168.1.101
```

### File Locations

- **Template VHDX**: `output-almalinux-cloudinit/Virtual Hard Disks/`
- **Build logs**: `packer-cloudinit-build.log`
- **Kickstart**: `templates/AlmaLinux/hyperv/ks-with-cloudinit.cfg`
