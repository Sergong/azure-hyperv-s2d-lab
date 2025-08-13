# Simplified Virtual Switch Setup Script for Hyper-V Nested VMs
# This script creates the InternalLabSwitch virtual switch required for nested VM provisioning

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
Write-Host "==========================================="

try {
    # Check if Hyper-V feature is installed
    Write-Host "Checking Hyper-V prerequisites..."
    $hypervFeature = Get-WindowsFeature -Name "Hyper-V"
    if ($hypervFeature.InstallState -ne "Installed") {
        throw "Hyper-V feature is not installed. Please install it first: Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart"
    }
    Write-Host "[OK] Hyper-V feature is installed"

    # Check if virtual switch already exists
    Write-Host "Checking for existing virtual switch..."
    $existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    
    if ($existingSwitch) {
        Write-Host "[OK] Virtual switch '$SwitchName' already exists"
        Write-Host "  Switch Type: $($existingSwitch.SwitchType)"
    } else {
        Write-Host "Creating internal virtual switch '$SwitchName'..."
        $switch = New-VMSwitch -Name $SwitchName -SwitchType Internal
        Write-Host "[OK] Virtual switch created: $($switch.Name)"
        
        Start-Sleep -Seconds 3
        
        Write-Host "Configuring IP address for virtual switch..."
        $adapter = Get-NetAdapter -Name "vEthernet ($SwitchName)"
        
        if ($adapter) {
            Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $HostIP -PrefixLength $PrefixLength -ErrorAction Stop
            Write-Host "[OK] IP address configured: $HostIP/$PrefixLength"
        } else {
            throw "Could not find network adapter for the virtual switch"
        }
    }
    
    # Create NAT configuration (only on hyperv-node-0)
    if ($env:COMPUTERNAME -eq "hyperv-node-0") {
        Write-Host "Checking NAT configuration..."
        $existingNAT = Get-NetNat -Name $NATName -ErrorAction SilentlyContinue
        
        if ($existingNAT) {
            Write-Host "[OK] NAT configuration already exists"
        } else {
            Write-Host "Creating NAT configuration..."
            try {
                $nat = New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix "192.168.100.0/24"
                Write-Host "[OK] NAT configuration created successfully"
            } catch {
                Write-Warning "Could not create NAT configuration: $($_.Exception.Message)"
            }
        }
    }
    
    Write-Host ""
    Write-Host "==========================================="
    Write-Host "SETUP COMPLETE!"
    Write-Host "==========================================="
    Write-Host "[OK] Switch Name: $SwitchName"
    Write-Host "[OK] Host IP: $HostIP/$PrefixLength"
    Write-Host "[OK] VM IP Range: 192.168.100.2 - 192.168.100.254"
    Write-Host ""
    Write-Host "Virtual switch is ready for nested VM provisioning!"
    
} catch {
    Write-Error "Setup failed: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

Write-Host ""
Write-Host "Setup log saved to: C:\VirtualSwitch-Setup-Log.txt"
Stop-Transcript

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
