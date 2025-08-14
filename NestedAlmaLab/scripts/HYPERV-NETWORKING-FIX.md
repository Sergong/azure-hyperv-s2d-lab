# Fixing Packer Hyper-V "Error getting host adapter ip address: No ip address"

This error is one of the most common issues when using Packer with Hyper-V. Here are the proven solutions:

## Root Cause
Packer needs to:
1. Create an HTTP server to serve kickstart files to the VM
2. Detect the host IP address that the VM can reach to download the kickstart
3. The VM gets an IP from the Hyper-V switch's DHCP and needs to reach the host

The error occurs when Packer cannot determine which host network adapter IP to use for the HTTP server.

## Solution 1: Create a Dedicated External Switch (Recommended)

**On your Windows Hyper-V host, run this in PowerShell as Administrator:**

```powershell
# List physical network adapters
Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Virtual -eq $false}

# Create external switch (replace "Ethernet" with your adapter name)
New-VMSwitch -Name "PackerExternal" -NetAdapterName "Ethernet" -AllowManagementOS $true
```

**Then update your Packer template to use this switch:**

In `almalinux-fixed.pkr.hcl`, change:
```hcl
source "hyperv-iso" "almalinux" {
  switch_name = "PackerExternal"  # Change from "Default Switch"
  # ... rest of config
}
```

## Solution 2: Fix Default Switch Issues

**Method A: Reset Default Switch**
```powershell
# As Administrator
Remove-VMSwitch "Default Switch" -Force
# Restart Hyper-V service or reboot
# Default Switch will be recreated automatically
```

**Method B: Restart Hyper-V Services**
```powershell
# As Administrator
Restart-Service vmms
Restart-Service HvHost
```

## Solution 3: Use Internal Switch with Static IP

Create an internal switch and configure it manually:

```powershell
# Create internal switch
New-VMSwitch -Name "PackerInternal" -SwitchType Internal

# Configure host adapter IP
$adapter = Get-NetAdapter | Where-Object {$_.Name -match "PackerInternal"}
New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress "192.168.99.1" -PrefixLength 24
```

Update Packer template:
```hcl
source "hyperv-iso" "almalinux" {
  switch_name = "PackerInternal"
  # ... rest of config
}
```

## Solution 4: Windows Firewall Rules

Add firewall exceptions for Packer's HTTP server:

```powershell
# Allow Packer HTTP server ports
New-NetFirewallRule -DisplayName "Packer HTTP Server" -Direction Inbound -Protocol TCP -LocalPort 8080-8090 -Action Allow
```

## Solution 5: Alternative Packer Configuration

Create a more robust template that handles networking better:

```hcl
packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "~> 1"
    }
  }
}

variable "kickstart_version" {
  type    = string
  default = "v2"
}

source "hyperv-iso" "almalinux" {
  # ISO Configuration
  iso_url      = "https://repo.almalinux.org/almalinux/9.4/isos/x86_64/AlmaLinux-9.4-x86_64-minimal.iso"
  iso_checksum = "file:https://repo.almalinux.org/almalinux/9.4/isos/x86_64/CHECKSUM"
  
  # VM Configuration
  vm_name       = "almalinux-9.4-template"
  generation    = 2
  guest_additions_mode = "disable"
  
  # Hardware
  cpus      = 2
  memory    = 2048
  disk_size = 20480
  
  # Network - Try multiple approaches
  switch_name              = "Default Switch"  # or "PackerExternal"
  enable_mac_spoofing      = true
  enable_dynamic_memory    = false
  enable_secure_boot       = false
  
  # HTTP Server for Kickstart
  http_directory = "kickstart"
  http_port_min  = 8080
  http_port_max  = 8090
  
  # Boot Configuration
  boot_wait = "3s"
  boot_command = [
    "<tab>",
    " inst.text",
    " inst.ks=http://{{.HTTPIP}}:{{.HTTPPort}}/kickstart-${var.kickstart_version}.cfg",
    " biosdevname=0",
    " net.ifnames=0",
    "<enter>"
  ]
  
  # SSH Configuration
  ssh_username     = "root"
  ssh_password     = "packer"
  ssh_timeout     = "30m"
  ssh_handshake_attempts = 100
  
  # Shutdown
  shutdown_command = "systemctl poweroff"
  shutdown_timeout = "5m"
}

build {
  sources = ["source.hyperv-iso.almalinux"]
  
  provisioner "shell" {
    inline = [
      "echo 'Template build completed successfully'"
    ]
  }
}
```

## Quick Test Commands

**To test if your current setup works, run these on Windows:**

```powershell
# Check Default Switch and its IP
Get-VMSwitch "Default Switch"
Get-NetAdapter | Where-Object {$_.Name -match "Default"} | Get-NetIPAddress -AddressFamily IPv4

# Test if Packer can detect the IP
packer console almalinux-fixed.pkr.hcl
# In console: {{.HTTPIP}}
```

## Immediate Next Steps

1. **On your Windows machine**, run the diagnostic script I created: `fix-hyperv-networking.ps1`
2. If Default Switch has issues, create an External switch: `fix-hyperv-networking.ps1 -CreateExternalSwitch`
3. Update your Packer template to use the working switch
4. Retry the build

The key insight is that Packer's auto-detection of host IP is fragile with Hyper-V's Default Switch. Using a dedicated External or Internal switch with known networking usually resolves this issue.

Would you like me to create an updated Packer template that uses one of these more reliable networking approaches?
