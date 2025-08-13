# Storage Spaces Direct (S2D) Cluster Setup Script
# Run this script MANUALLY on hyperv-node-0 only
# Prerequisites: Both nodes must have Hyper-V and Failover Clustering installed

param(
    [string]$ClusterName = "S2DCluster",
    [string]$ClusterIP = "10.0.1.100",
    [string[]]$NodeNames = @("hyperv-node-0", "hyperv-node-1")
)

# Ensure running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator. Exiting."
    exit 1
}

# Start logging
Start-Transcript -Path "C:\S2D-Setup-Log.txt" -Append

Write-Host "==========================================="
Write-Host "Storage Spaces Direct Cluster Setup"
Write-Host "==========================================="
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Date: $(Get-Date)"
Write-Host "Cluster Name: $ClusterName"
Write-Host "Cluster IP: $ClusterIP"
Write-Host "Nodes: $($NodeNames -join ', ')"
Write-Host "==========================================="

# Step 1: Verify prerequisites
Write-Host "Step 1: Verifying prerequisites..."

# Check if running on the correct node
if ($env:COMPUTERNAME -ne "hyperv-node-0") {
    Write-Error "This script should only be run on hyperv-node-0. Current computer: $env:COMPUTERNAME"
    Stop-Transcript
    exit 1
}

# Check if required features are installed
$requiredFeatures = @("Hyper-V", "Failover-Clustering", "FS-FileServer")
foreach ($feature in $requiredFeatures) {
    $featureState = Get-WindowsFeature -Name $feature
    if ($featureState.InstallState -ne "Installed") {
        Write-Error "Required feature '$feature' is not installed. Install state: $($featureState.InstallState)"
        Stop-Transcript
        exit 1
    }
Write-Host "✓ Feature '$feature' is installed"
}

# Step 1.5: Create virtual switch for nested VMs (if it doesn't exist)
Write-Host "`nStep 1.5: Setting up virtual switch for nested VMs..."
try {
    $switchName = "InternalLabSwitch"
    $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
    
    if ($existingSwitch) {
        Write-Host "✓ Virtual switch '$switchName' already exists"
        Write-Host "  Switch Type: $($existingSwitch.SwitchType)"
        if ($existingSwitch.NetAdapterInterfaceDescription) {
            Write-Host "  Network Adapter: $($existingSwitch.NetAdapterInterfaceDescription)"
        }
    } else {
        Write-Host "Creating internal virtual switch '$switchName'..."
        
        # Create an internal switch for nested VMs
        # Internal switch allows communication between host and VMs, and between VMs
        New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
        
        # Configure IP address for the switch
        Write-Host "Configuring IP address for virtual switch..."
        $adapter = Get-NetAdapter -Name "vEthernet ($switchName)"
        
        # Remove any existing IP configuration
        Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
        
        # Set static IP for the host side of the switch
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress "192.168.100.1" -PrefixLength 24 -ErrorAction Stop
        
        Write-Host "✓ Virtual switch '$switchName' created successfully"
        Write-Host "  Host IP: 192.168.100.1/24"
        Write-Host "  Nested VMs can use DHCP or static IPs in 192.168.100.0/24 range"
        
        # Optional: Enable NAT for internet access (requires careful consideration in cluster environment)
        try {
            $natName = "InternalLabNAT"
            $existingNAT = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
            if (-not $existingNAT) {
                Write-Host "Creating NAT configuration for internet access..."
                New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix "192.168.100.0/24" | Out-Null
                Write-Host "✓ NAT configuration created - nested VMs will have internet access"
            }
        } catch {
            Write-Warning "Could not create NAT configuration: $($_.Exception.Message)"
            Write-Host "Nested VMs may not have internet access (manual NAT configuration required)"
        }
    }
} catch {
    Write-Warning "Failed to create virtual switch: $($_.Exception.Message)"
    Write-Host "You may need to create the virtual switch manually:"
    Write-Host "  New-VMSwitch -Name 'InternalLabSwitch' -SwitchType Internal"
    Write-Host "  New-NetIPAddress -InterfaceAlias 'vEthernet (InternalLabSwitch)' -IPAddress '192.168.100.1' -PrefixLength 24"
}

# Step 2: Test node connectivity
Write-Host "`nStep 2: Testing node connectivity..."
foreach ($node in $NodeNames) {
    try {
        $result = Test-Connection -ComputerName $node -Count 2 -Quiet -ErrorAction Stop
        if ($result) {
            Write-Host "✓ Node '$node' is accessible"
        } else {
            throw "Ping failed"
        }
    } catch {
        Write-Error "Cannot reach node '$node'. Ensure the node is running and network connectivity exists."
        Write-Host "Troubleshooting steps:"
        Write-Host "  1. Check if the node is powered on"
        Write-Host "  2. Verify network connectivity"
        Write-Host "  3. Check Windows Firewall settings"
        Stop-Transcript
        exit 1
    }
}

# Step 3: Check if cluster already exists
Write-Host "`nStep 3: Checking existing cluster configuration..."
try {
    $existingCluster = Get-Cluster -ErrorAction SilentlyContinue
    if ($existingCluster) {
        Write-Warning "Cluster already exists: $($existingCluster.Name)"
        Write-Host "Current cluster nodes:"
        Get-ClusterNode | ForEach-Object { Write-Host "  - $($_.Name): $($_.State)" }
        
        $continue = Read-Host "Do you want to continue and potentially reconfigure? (y/N)"
        if ($continue -ne 'y' -and $continue -ne 'Y') {
            Write-Host "Exiting without changes."
            Stop-Transcript
            exit 0
        }
    }
} catch {
    Write-Host "No existing cluster found. Proceeding with new cluster creation."
}

# Step 4: Validate cluster configuration
Write-Host "`nStep 4: Running cluster validation..."
try {
    Write-Host "This may take several minutes..."
    $validationResult = Test-Cluster -Node $NodeNames -Include "Storage Spaces Direct", "Inventory", "Network", "System Configuration" -ReportName "C:\ClusterValidation"
    
    if ($validationResult) {
        Write-Host "✓ Cluster validation completed. Check C:\ClusterValidation.htm for detailed results."
    }
} catch {
    Write-Warning "Cluster validation encountered issues: $($_.Exception.Message)"
    Write-Host "You may continue, but check the validation report for potential issues."
    
    $continue = Read-Host "Do you want to continue despite validation warnings? (y/N)"
    if ($continue -ne 'y' -and $continue -ne 'Y') {
        Write-Host "Exiting due to validation issues."
        Stop-Transcript
        exit 1
    }
}

# Step 5: Create the failover cluster
Write-Host "`nStep 5: Creating failover cluster..."
try {
    # Check if cluster name is already in use
    try {
        $existingClusterByName = Get-Cluster -Name $ClusterName -ErrorAction Stop
        Write-Error "Cluster name '$ClusterName' is already in use. Choose a different name."
        Stop-Transcript
        exit 1
    } catch {
        # Good - cluster name is available
    }
    
    Write-Host "Creating cluster '$ClusterName' with IP '$ClusterIP'..."
    $cluster = New-Cluster -Name $ClusterName -Node $NodeNames -StaticAddress $ClusterIP -NoStorage -Force
    
    if ($cluster) {
        Write-Host "✓ Failover cluster '$ClusterName' created successfully!"
        Write-Host "Cluster nodes:"
        Get-ClusterNode | ForEach-Object { Write-Host "  - $($_.Name): $($_.State)" }
    }
} catch {
    Write-Error "Failed to create cluster: $($_.Exception.Message)"
    Write-Host "Common issues:"
    Write-Host "  1. IP address $ClusterIP may already be in use"
    Write-Host "  2. DNS resolution issues"
    Write-Host "  3. Windows Firewall blocking cluster communication"
    Write-Host "  4. Insufficient permissions"
    Stop-Transcript
    exit 1
}

# Step 6: Check available storage
Write-Host "`nStep 6: Analyzing available storage..."
try {
    $availableDisks = Get-ClusterAvailableDisk
    if ($availableDisks.Count -eq 0) {
        Write-Warning "No additional storage disks found for S2D."
        Write-Host "This is normal in Azure VMs where S2D uses local storage."
        Write-Host "S2D will use local storage spaces on each node."
    } else {
        Write-Host "Available disks for clustering:"
        $availableDisks | ForEach-Object { Write-Host "  - $($_.Name)" }
    }
    
    # Show physical disks on each node
    foreach ($node in $NodeNames) {
        Write-Host "`nPhysical disks on ${node}:"
        try {
            $disks = Get-PhysicalDisk -CimSession $node | Where-Object { $_.CanPool -eq $true }
            if ($disks) {
                $disks | ForEach-Object { 
                    Write-Host "  - $($_.FriendlyName): $([math]::Round($_.Size/1GB,2)) GB - $($_.MediaType)" 
                }
            } else {
                Write-Host "  - No poolable disks found"
            }
        } catch {
            Write-Warning "Could not query disks on $node`: $($_.Exception.Message)"
        }
    }
} catch {
    Write-Warning "Could not analyze storage: $($_.Exception.Message)"
}

# Step 7: Enable Storage Spaces Direct
Write-Host "`nStep 7: Enabling Storage Spaces Direct..."
try {
    Write-Host "Enabling S2D... This may take several minutes."
    Enable-ClusterS2D -Confirm:$false -Verbose
    
    Write-Host "✓ Storage Spaces Direct enabled successfully!"
    
    # Show S2D status
    Write-Host "`nS2D Cluster Information:"
    $s2dCluster = Get-ClusterS2D
    Write-Host "  State: $($s2dCluster.State)"
    Write-Host "  Cache State: $($s2dCluster.CacheState)"
    
} catch {
    Write-Error "Failed to enable Storage Spaces Direct: $($_.Exception.Message)"
    Write-Host "Common issues:"
    Write-Host "  1. Insufficient storage devices"
    Write-Host "  2. Storage devices already in use"
    Write-Host "  3. Hardware compatibility issues"
    Write-Host "  4. Previous S2D configuration conflicts"
    
    # Try to get more details
    try {
        Write-Host "`nDetailed S2D status:"
        Get-ClusterS2D | Format-List
    } catch {
        Write-Host "Could not retrieve detailed S2D status."
    }
    
    Stop-Transcript
    exit 1
}

# Step 8: Create storage tier and volume (if possible)
Write-Host "`nStep 8: Setting up storage tiers and volumes..."
try {
    # Wait a moment for S2D to stabilize
    Start-Sleep -Seconds 10
    
    # Check storage pool
    $storagePool = Get-StoragePool -FriendlyName "S2D on $ClusterName" -ErrorAction SilentlyContinue
    if ($storagePool) {
        Write-Host "✓ S2D storage pool found: $($storagePool.FriendlyName)"
        Write-Host "  Total Size: $([math]::Round($storagePool.Size/1GB,2)) GB"
        Write-Host "  Available: $([math]::Round($storagePool.AllocatedSize/1GB,2)) GB"
        
        # Create a simple volume for demonstration
        try {
            Write-Host "Creating demo volume 'S2D-Volume01'..."
            $volume = New-Volume -StoragePoolFriendlyName $storagePool.FriendlyName -FriendlyName "S2D-Volume01" -FileSystem NTFS -Size 100GB -ErrorAction SilentlyContinue
            if ($volume) {
                Write-Host "✓ Demo volume created: $($volume.DriveLetter): $([math]::Round($volume.SizeRemaining/1GB,2)) GB available"
            }
        } catch {
            Write-Warning "Could not create demo volume: $($_.Exception.Message)"
            Write-Host "You can create volumes manually later using Failover Cluster Manager or PowerShell."
        }
    } else {
        Write-Warning "S2D storage pool not found. This may be normal during initial setup."
    }
} catch {
    Write-Warning "Could not configure storage tiers: $($_.Exception.Message)"
}

# Step 9: Summary and next steps
Write-Host "`n==========================================="
Write-Host "SETUP COMPLETE!"
Write-Host "==========================================="

try {
    $cluster = Get-Cluster
    Write-Host "✓ Cluster Name: $($cluster.Name)"
    Write-Host "✓ Cluster IP: $($cluster.Cluster)"
    
    Write-Host "`nCluster Nodes:"
    Get-ClusterNode | ForEach-Object { 
        Write-Host "  - $($_.Name): $($_.State)" 
    }
    
    Write-Host "`nS2D Status:"
    $s2d = Get-ClusterS2D
    Write-Host "  State: $($s2d.State)"
    Write-Host "  Cache State: $($s2d.CacheState)"
    
    if ($s2d.State -eq "Enabled") {
        Write-Host "`n🎉 SUCCESS: Storage Spaces Direct cluster is ready!"
        Write-Host "`nNext steps:"
        Write-Host "1. Open Failover Cluster Manager to manage the cluster"
        Write-Host "2. Create additional volumes as needed"
        Write-Host "3. Deploy VMs on the S2D storage"
        Write-Host "4. Configure cluster networks if needed"
        Write-Host "`nUseful commands:"
        Write-Host "  Get-ClusterNode                    # Show cluster nodes"
        Write-Host "  Get-ClusterS2D                     # Show S2D status"  
        Write-Host "  Get-StoragePool                    # Show storage pools"
        Write-Host "  Get-Volume                         # Show volumes"
        Write-Host "  New-Volume -StoragePoolFriendlyName 'S2D on $ClusterName' -FriendlyName 'MyVolume' -Size 500GB -FileSystem NTFS"
    }
    
} catch {
    Write-Warning "Could not retrieve final cluster status: $($_.Exception.Message)"
}

Write-Host "`nSetup log saved to: C:\S2D-Setup-Log.txt"
Write-Host "Cluster validation report: C:\ClusterValidation.htm"

Stop-Transcript

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
