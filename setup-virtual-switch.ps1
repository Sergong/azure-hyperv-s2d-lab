# Virtual Switch Setup Script for Hyper-V Nested VMs
# This script creates the InternalLabSwitch virtual switch required for nested VM provisioning
# Run this on both hyperv-node-0 and hyperv-node-1

param(
    [string]$SwitchName = "InternalLabSwitch",
    [string]$HostIP = "192.168.100.1",
    [int]$PrefixLength = 24,
    [string]$NATName = "InternalLabNAT"
)

# Ensure running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator. Exiting."
    exit 1
}

# Start logging
Start-Transcript -Path "C:\VirtualSwitch-Setup-Log.txt" -Append

Write-Host "==========================================="
Write-Host "Virtual Switch Setup for Nested VMs"
Write-Host "==========================================="
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Date: $(Get-Date)"
Write-Host "Switch Name: $SwitchName"
Write-Host "Host IP: $HostIP/$PrefixLength"
Write-Host "NAT Name: $NATName"
Write-Host "==========================================="

try {
    # Check if Hyper-V feature is installed
    Write-Host "Checking Hyper-V prerequisites..."
    $hypervFeature = Get-WindowsFeature -Name "Hyper-V"
    if ($hypervFeature.InstallState -ne "Installed") {
        Write-Error "Hyper-V feature is not installed. Install state: $($hypervFeature.InstallState)"
        Write-Host "Please install Hyper-V first: Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart"
        Stop-Transcript
        exit 1
    }
    Write-Host "✓ Hyper-V feature is installed"

    # Check if virtual switch already exists
    Write-Host ""
    Write-Host "Checking for existing virtual switch..."
    $existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    
    if ($existingSwitch) {
        Write-Host "✓ Virtual switch '$SwitchName' already exists"
        Write-Host "  Switch Type: $($existingSwitch.SwitchType)"
        Write-Host "  Creation Time: $($existingSwitch.CreationTime)"
        
        if ($existingSwitch.NetAdapterInterfaceDescription) {
            Write-Host "  Network Adapter: $($existingSwitch.NetAdapterInterfaceDescription)"
        }
        
        # Check IP configuration
        $adapter = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction SilentlyContinue
        if ($adapter) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ipConfig) {
                Write-Host "  Current IP: $($ipConfig.IPAddress)/$($ipConfig.PrefixLength)"
                
                if ($ipConfig.IPAddress -eq $HostIP -and $ipConfig.PrefixLength -eq $PrefixLength) {
                    Write-Host "✓ IP configuration is already correct"
                } else {
                    Write-Warning "IP configuration differs from desired settings"
                    $reconfigure = Read-Host "Do you want to reconfigure the IP address? (y/N)"
                    if ($reconfigure -eq 'y' -or $reconfigure -eq 'Y') {
                        Write-Host "Reconfiguring IP address..."
                        Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
                        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $HostIP -PrefixLength $PrefixLength -ErrorAction Stop
                        Write-Host "✓ IP address reconfigured to $HostIP/$PrefixLength"
                    }
                }
            } else {
                Write-Host "No IP address configured, setting up..."
                New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $HostIP -PrefixLength $PrefixLength -ErrorAction Stop
                Write-Host "✓ IP address configured: $HostIP/$PrefixLength"
            }
        }
    } else {
        Write-Host "Creating internal virtual switch '$SwitchName'..."
        
        # Create an internal switch for nested VMs
        $switch = New-VMSwitch -Name $SwitchName -SwitchType Internal
        Write-Host "✓ Virtual switch created: $($switch.Name)"
        
        # Wait a moment for the adapter to be ready
        Start-Sleep -Seconds 3
        
        # Configure IP address for the switch
        Write-Host "Configuring IP address for virtual switch..."
        $adapter = Get-NetAdapter -Name "vEthernet ($SwitchName)"
        
        if ($adapter) {
            # Remove any existing IP configuration
            Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
            
            # Set static IP for the host side of the switch
            New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $HostIP -PrefixLength $PrefixLength -ErrorAction Stop
            
            Write-Host "✓ Virtual switch '$SwitchName' created and configured successfully"
            Write-Host "  Host IP: $HostIP/$PrefixLength"
            Write-Host "  Network Range: 192.168.100.0/24"
        } else {
            throw "Could not find network adapter for the virtual switch"
        }
    }
    
    # Check and create NAT configuration
    Write-Host ""
    Write-Host "Checking NAT configuration..."
    $existingNAT = Get-NetNat -Name $NATName -ErrorAction SilentlyContinue
    
    if ($existingNAT) {
        Write-Host "✓ NAT configuration already exists: $($existingNAT.Name)"
        Write-Host "  Internal Prefix: $($existingNAT.InternalIPInterfaceAddressPrefix)"
    } else {
        # Only create NAT on the primary node to avoid conflicts
        if ($env:COMPUTERNAME -eq "hyperv-node-0") {
            Write-Host "Creating NAT configuration for internet access..."
            try {
                $nat = New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix "192.168.100.0/24"
                Write-Host "✓ NAT configuration created successfully"
                Write-Host "  Name: $($nat.Name)"
                Write-Host "  Internal Prefix: $($nat.InternalIPInterfaceAddressPrefix)"
                Write-Host "  Nested VMs will have internet access through NAT"
            } catch {
                Write-Warning "Could not create NAT configuration: $($_.Exception.Message)"
                Write-Host "This is not critical - nested VMs can still communicate with each other and the host"
            }
        } else {
            Write-Host "Skipping NAT creation on $env:COMPUTERNAME (should only be created on hyperv-node-0)"
        }
    }
    
    # Display final configuration summary
    Write-Host ""
    Write-Host "==========================================="
    Write-Host "VIRTUAL SWITCH SETUP COMPLETE!"
    Write-Host "==========================================="
    
    $finalSwitch = Get-VMSwitch -Name $SwitchName
    Write-Host "✓ Switch Name: $($finalSwitch.Name)"
    Write-Host "✓ Switch Type: $($finalSwitch.SwitchType)"
    Write-Host "✓ Switch ID: $($finalSwitch.Id)"
    
    $finalAdapter = Get-NetAdapter -Name "vEthernet ($SwitchName)"
    $finalIP = Get-NetIPAddress -InterfaceIndex $finalAdapter.InterfaceIndex -AddressFamily IPv4
    Write-Host "✓ Host IP: $($finalIP.IPAddress)/$($finalIP.PrefixLength)"
    
    Write-Host ""
    Write-Host "Nested VM Network Configuration:"
    Write-Host "  - VM Switch: $SwitchName"
    Write-Host "  - Network Range: 192.168.100.0/24"
    Write-Host "  - Host IP: $($finalIP.IPAddress)"
    Write-Host "  - Available VM IPs: 192.168.100.2 - 192.168.100.254"
    Write-Host "  - Gateway (for internet): $($finalIP.IPAddress)"
    Write-Host "  - DNS (for internet): Use host DNS or 8.8.8.8"
    
    $finalNAT = Get-NetNat -Name $NATName -ErrorAction SilentlyContinue
    if ($finalNAT) {
        Write-Host "✓ NAT enabled for internet access"
    } else {
        Write-Host "⚠ NAT not configured - VMs will have limited internet access"
    }
    
    Write-Host ""
    Write-Host "🎉 Virtual switch is ready for nested VM provisioning!"
    
} catch {
    Write-Error "Failed to setup virtual switch: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Troubleshooting steps:"
    Write-Host "1. Ensure Hyper-V is properly installed and enabled"
    Write-Host "2. Check if running as Administrator"
    Write-Host "3. Verify no conflicting network configurations exist"
    Write-Host "4. Check Windows Firewall settings"
    Write-Host ""
    Write-Host "Manual commands to try:"
    Write-Host "  New-VMSwitch -Name '$SwitchName' -SwitchType Internal"
    Write-Host "  New-NetIPAddress -InterfaceAlias 'vEthernet ($SwitchName)' -IPAddress '$HostIP' -PrefixLength $PrefixLength"
    Write-Host "  New-NetNat -Name '$NATName' -InternalIPInterfaceAddressPrefix '192.168.100.0/24'"
    
    Stop-Transcript
    exit 1
}

Write-Host ""
Write-Host "Setup log saved to: C:\VirtualSwitch-Setup-Log.txt"
Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
