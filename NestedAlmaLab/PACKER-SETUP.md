# AlmaLinux Packer Template Setup Guide

This guide shows you how to use Packer to build reusable AlmaLinux VM templates for your Hyper-V lab, eliminating the need for custom ISOs and manual kickstart processes.

## Why Use Packer?

✅ **Completely automated** - no manual intervention required  
✅ **Reliable and repeatable** - same result every time  
✅ **Industry standard** - used by major cloud providers  
✅ **Fast deployment** - VMs boot in seconds from template  
✅ **Version controlled** - templates as code  
✅ **No ISO complexity** - handles all the ISO creation challenges automatically  

## Prerequisites

- Windows Server with Hyper-V enabled
- Administrator privileges
- Internet connectivity for ISO download
- At least 10GB free disk space

## Quick Start

### 1. Install Packer (if not already installed)

```powershell
# Option 1: Using winget (Windows 10/11)
winget install HashiCorp.Packer

# Option 2: Automated installation via script
.\build-template-with-packer.ps1 -InstallPacker

# Option 3: Manual download from https://www.packer.io/downloads
```

### 2. Build Your Template

```powershell
# Build a comprehensive template with all lab tools
.\build-template-with-packer.ps1 -KickstartVersion v2 -Generation 2

# Or build minimal template
.\build-template-with-packer.ps1 -KickstartVersion v1 -Generation 1
```

**What happens during build:**
- Downloads AlmaLinux ISO (cached for future builds)
- Creates temporary Hyper-V VM
- Performs automated installation using kickstart
- Installs Docker, development tools, etc.
- Cleans up and prepares template
- Exports ready-to-use VHDX template

**Build time:** 15-30 minutes (depending on internet speed)

### 3. Deploy VMs from Template

```powershell
# Deploy 3 VMs and start them immediately
.\deploy-from-template.ps1 -VMCount 3 -VMPrefix "Lab" -StartVMs

# Deploy VMs without starting
.\deploy-from-template.ps1 -VMCount 2 -VMPrefix "Test"
```

**Deployment time:** 30-60 seconds per VM (just copying template)

## Template Features

### What's Included in the Template

- **Base OS:** AlmaLinux 9 with latest updates
- **Container Platform:** Docker + Docker Compose
- **Development Tools:** 
  - Git, Vim, Python3, Node.js, Go, Rust
  - Ansible core for automation
  - Development Tools group (gcc, make, etc.)
- **Network Tools:** curl, wget, tcpdump, nmap, bind-utils
- **Monitoring:** htop, tree, tmux
- **Pre-configured Users:**
  - `root` / `alma123!`
  - `labuser` / `labpass123!` (sudo access)
- **Services:** SSH enabled, firewall configured
- **Nested Virtualization:** Enabled where supported

### Template Benefits

- **Instant Boot:** VMs start in seconds (no OS installation)
- **Consistent Environment:** All VMs identical and predictable
- **Pre-configured:** SSH, firewall, users all ready
- **Development Ready:** All tools pre-installed
- **Lab Optimized:** Passwords, sudo access, useful aliases

## File Structure

```
NestedAlmaLab/
├── packer/
│   ├── almalinux.pkr.hcl          # Main Packer template
│   └── variables.pkrvars.hcl      # Generated variables file
├── templates/AlmaLinux/
│   └── packer/
│       └── ks.cfg                 # Packer-optimized kickstart
└── scripts/
    ├── build-template-with-packer.ps1  # Template builder
    └── deploy-from-template.ps1         # VM deployment
```

## Advanced Usage

### Custom Template Configuration

Edit `NestedAlmaLab/packer/almalinux.pkr.hcl` to customize:

```hcl
# Change VM specifications
variable "vm_memory" {
  default = 4096  # 4GB RAM
}

variable "vm_disk_size" {
  default = 51200  # 50GB disk
}

# Change output location
variable "output_directory" {
  default = "D:\\Templates"
}
```

### Build Different Variants

```powershell
# Build Gen 1 template for older hardware
.\build-template-with-packer.ps1 -Generation 1

# Build with custom output location
.\build-template-with-packer.ps1 -OutputPath "D:\MyTemplates"

# Force rebuild without prompts
.\build-template-with-packer.ps1 -Force
```

### Deploy Custom VM Configurations

```powershell
# Deploy with more memory
.\deploy-from-template.ps1 -Memory 4GB -VMCount 2

# Deploy to custom location
.\deploy-from-template.ps1 -VMPath "D:\VMs" -VHDPath "D:\VMs\Disks"

# Deploy with custom switch
.\deploy-from-template.ps1 -SwitchName "LabSwitch"
```

## Troubleshooting

### Common Issues

**Packer not found:**
```powershell
# Install Packer automatically
.\build-template-with-packer.ps1 -InstallPacker
```

**Hyper-V permissions:**
- Run PowerShell as Administrator
- Ensure Hyper-V is enabled
- Check user has Hyper-V Administrator rights

**Network issues during build:**
- Check Windows Firewall (Packer needs to serve HTTP)
- Verify internet connectivity
- Try different mirror URLs in template

**Build fails:**
- Check disk space in output directory
- Verify Hyper-V is working: `Get-VM`
- Check Packer logs for specific errors

### Validation Commands

```powershell
# Check Packer installation
packer version

# Validate template
packer validate NestedAlmaLab/packer/almalinux.pkr.hcl

# Check template files
Get-ChildItem "C:\Packer\Output" -Filter "*.vhdx"

# Test deployed VMs
Get-VM Lab-* | Get-VMNetworkAdapter | Select Name, IPAddresses
```

## Migration from Custom ISO Approach

If you were previously using custom ISO scripts:

1. **Stop using:** `create-custom-iso.ps1` and `create-custom-iso-alternative.ps1`
2. **Start using:** `build-template-with-packer.ps1` (one-time template creation)
3. **Deploy VMs with:** `deploy-from-template.ps1` (fast VM creation)

### Benefits of Migration

| Custom ISO Approach | Packer Template Approach |
|---------------------|-------------------------|
| ❌ Error-prone ISO creation | ✅ Reliable automated builds |
| ❌ Tool compatibility issues | ✅ Industry-standard tooling |
| ❌ Manual boot parameters | ✅ Ready-to-use VMs |
| ❌ 15+ minutes per VM | ✅ 1 minute per VM |
| ❌ Requires ISO tools | ✅ Only needs Packer |

## Example Workflow

```powershell
# 1. One-time template build (15-30 minutes)
.\build-template-with-packer.ps1 -KickstartVersion v2 -InstallPacker

# 2. Deploy lab VMs instantly (1-2 minutes total)
.\deploy-from-template.ps1 -VMCount 5 -VMPrefix "Workshop" -StartVMs

# 3. Access VMs immediately via SSH
# All VMs boot in seconds and are ready for use!
```

## Next Steps

After your VMs are deployed from the template:
- VMs boot in seconds (no OS installation wait)
- SSH access immediately available
- Docker ready for container workflows
- All development tools pre-installed
- Consistent environment across all VMs

This approach eliminates all the complexity and reliability issues of custom ISO creation while providing much faster deployment and a better user experience.
