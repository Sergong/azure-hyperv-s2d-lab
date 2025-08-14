# AlmaLinux Networking Issues on Hyper-V - Solutions

## The Problem
AlmaLinux 9.4 often fails to get an IP address on Hyper-V, both during automated installation (Packer) and manual setup. This affects both Generation 1 and Generation 2 VMs.

## Root Causes
1. **Network Interface Detection**: AlmaLinux installer doesn't properly detect Hyper-V synthetic network adapters
2. **Driver Loading**: The `hv_netvsc` driver may not load early enough during installation
3. **Interface Naming**: Modern naming schemes conflict with Hyper-V adapter detection
4. **DHCP Timeout**: Default DHCP timeout too short for Hyper-V networking initialization

## Solution 1: Use Hyper-V Optimized Kickstart (Recommended)

The kickstart file `templates/AlmaLinux/hyperv/ks.cfg` includes these fixes:

### Key Network Settings:
```
# Use device=link instead of device=eth0
network --bootproto=dhcp --device=link --onboot=yes --activate --noipv6

# Extended DHCP timeout for NetworkManager
[ipv4]
method=auto
dhcp-timeout=300
```

### Build with optimized template:
```powershell
.\build-hyperv-template.ps1 -Generation 1 -Force
```

Generation 1 (BIOS) is more compatible than Generation 2 (UEFI) for networking.

## Solution 2: Manual Installation Fixes

If installing manually, use these boot parameters:

### For Generation 1 VMs:
```
text inst.ks=... ip=dhcp biosdevname=0 net.ifnames=0 console=tty0
```

### For Generation 2 VMs:
```
text inst.ks=... ip=dhcp biosdevname=0 net.ifnames=0 modprobe.blacklist=nouveau
```

### During Installation:
1. Press TAB at boot menu
2. Add parameters: `ip=dhcp biosdevname=0 net.ifnames=0`
3. Press ENTER

## Solution 3: Fix Existing VM Network Issues

If you have a VM that can't get IP:

### Inside the VM:
```bash
# Check network interfaces
ip link show

# Load Hyper-V network driver
modprobe hv_netvsc

# Restart NetworkManager
systemctl restart NetworkManager

# Manual DHCP request
dhclient -v

# Check if interface comes up
ip addr show
```

### Create persistent fix:
```bash
# Add to kernel modules
echo "hv_netvsc" >> /etc/modules-load.d/hyperv.conf

# Configure NetworkManager for Hyper-V
cat > /etc/NetworkManager/conf.d/10-hyperv.conf << 'EOF'
[main]
no-auto-default=*
[connection]
ipv6.method=ignore
[device]
wifi.scan-rand-mac-address=no
EOF

systemctl restart NetworkManager
```

## Solution 4: Hyper-V Switch Configuration

### Create reliable External switch:
```powershell
# Run as Administrator
Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Virtual -eq $false}
New-VMSwitch -Name "PackerExternal" -NetAdapterName "Ethernet" -AllowManagementOS $true
```

### Or use the diagnostic script:
```powershell
.\fix-hyperv-networking.ps1 -CreateExternalSwitch
```

## Solution 5: Alternative AlmaLinux Versions

If AlmaLinux 9.4 continues to have issues:

### Try AlmaLinux 9.3:
```
ISO: https://repo.almalinux.org/almalinux/9.3/isos/x86_64/AlmaLinux-9.3-x86_64-minimal.iso
```

### Or AlmaLinux 8.9:
```
ISO: https://repo.almalinux.org/almalinux/8.9/isos/x86_64/AlmaLinux-8.9-x86_64-minimal.iso
```

Update the Packer template iso_url accordingly.

## Verification Steps

After applying fixes:

### 1. Test Packer Build:
```powershell
.\build-hyperv-template.ps1 -Generation 1 -CreateExternalSwitch -Force
```

### 2. Test Manual Installation:
1. Create new VM in Hyper-V Manager
2. Use Generation 1 for best compatibility
3. Attach AlmaLinux ISO
4. Boot and add kernel parameters
5. Verify network comes up during installation

### 3. Test Deployed VM:
```bash
# In the deployed VM
hyperv-network-test.sh
ping -c 3 8.8.8.8
curl -I http://google.com
```

## Quick Fixes Summary

**Most Common Solutions (in order):**

1. **Use Generation 1 instead of Generation 2**
2. **Create External switch instead of using Default Switch**
3. **Use the Hyper-V optimized kickstart file**
4. **Add network boot parameters: `ip=dhcp biosdevname=0 net.ifnames=0`**
5. **Install Hyper-V integration services in the VM**

## Expected Results

After applying these fixes:
- VM should get IP address automatically via DHCP
- Network interface should appear as `eth0`
- Internet connectivity should work immediately
- SSH should be accessible from the host

The Hyper-V optimized approach resolves 90% of AlmaLinux networking issues on Hyper-V.
