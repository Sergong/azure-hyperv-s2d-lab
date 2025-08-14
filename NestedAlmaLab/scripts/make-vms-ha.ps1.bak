# Make VMs Highly Available Script
#
# This script converts standalone VMs into highly available clustered VMs
# by adding them to the existing failover cluster and configuring them
# for automatic failover between cluster nodes.
#
# PREREQUISITES:
# - Failover cluster must be running and healthy
# - Storage Spaces Direct (S2D) must be configured
# - VMs must exist and be accessible from both cluster nodes
# - PowerShell remoting must be configured between cluster nodes
#
# FEATURES:
# - Detects existing failover cluster automatically
# - Moves VM files to shared cluster storage (CSV)
# - Adds VMs to cluster as highly available resources
# - Configures automatic failover policies
# - Sets up VM monitoring and health checks
# - Provides detailed progress and error reporting
# - Supports both individual VMs and batch operations
#
# USAGE:
#   .\make-vms-ha.ps1                          # Make all VMs HA based on config
#   .\make-vms-ha.ps1 -VMNames "VM1","VM2"     # Make specific VMs HA
#   .\make-vms-ha.ps1 -WhatIf                  # Preview changes without applying
#

param(
    [Parameter(Mandatory=$false)]
    [string[]]$VMNames = @(),
    
    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Load configuration from YAML file (same as other scripts)
function ConvertFrom-Yaml {
    param([string]$YamlContent)
    
    $config = @{}
    $lines = $YamlContent -split "`n" | Where-Object { $_ -match '^\s*\w+:' }
    
    foreach ($line in $lines) {
        if ($line -match '^\s*([^:]+):\s*"?([^"]+)"?\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            
            if ($value -match '^\d+$') {
                $config[$key] = [int]$value
            }
            elseif ($value -match '^(\d+)(GB|MB|KB)$') {
                $size = [int]$matches[1]
                $unit = $matches[2]
                switch ($unit) {
                    "KB" { $config[$key] = $size * 1KB }
                    "MB" { $config[$key] = $size * 1MB }
                    "GB" { $config[$key] = $size * 1GB }
                }
            }
            else {
                $config[$key] = $value
            }
        }
    }
    return $config
}

# Function to validate cluster readiness
function Test-ClusterReadiness {
    param([string]$ClusterName)
    
    Write-Host "Validating cluster readiness..." -ForegroundColor Yellow
    
    try {
        # Check if failover clustering feature is installed
        $fcFeature = Get-WindowsFeature -Name "Failover-Clustering" -ErrorAction Stop
        if ($fcFeature.InstallState -ne "Installed") {
            throw "Failover Clustering feature is not installed"
        }
        
        # Get cluster information
        if ([string]::IsNullOrEmpty($ClusterName)) {
            $cluster = Get-Cluster -ErrorAction Stop
            $ClusterName = $cluster.Name
        } else {
            $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
        }
        
        Write-Host "  ✓ Found cluster: $($cluster.Name)" -ForegroundColor Green
        Write-Host "  ✓ Cluster nodes: $($cluster.ClusterNodes -join ', ')" -ForegroundColor Green
        
        # Check cluster health
        $clusterHealth = Get-ClusterNode | Where-Object { $_.State -ne "Up" }
        if ($clusterHealth.Count -gt 0) {
            Write-Warning "Some cluster nodes are not in 'Up' state:"
            $clusterHealth | ForEach-Object { Write-Warning "  - $($_.Name): $($_.State)" }
        }
        
        # Check for CSV volumes
        $csvVolumes = Get-ClusterSharedVolume -ErrorAction Stop
        if ($csvVolumes.Count -eq 0) {
            throw "No Cluster Shared Volumes (CSV) found. S2D storage may not be configured."
        }
        
        Write-Host "  ✓ Found $($csvVolumes.Count) CSV volume(s):" -ForegroundColor Green
        foreach ($csv in $csvVolumes) {
            Write-Host "    - $($csv.Name): $($csv.SharedVolumeInfo.FriendlyVolumeName)" -ForegroundColor Green
        }
        
        return @{
            ClusterName = $ClusterName
            CSVVolumes = $csvVolumes
            IsReady = $true
        }
        
    } catch {
        Write-Error "Cluster validation failed: $($_.Exception.Message)"
        return @{ IsReady = $false }
    }
}

# Function to move VM to CSV storage
function Move-VMToCSV {
    param(
        [string]$VMName,
        [object]$CSVVolume,
        [switch]$WhatIf
    )
    
    Write-Host "  Moving VM storage to CSV..." -ForegroundColor Yellow
    
    try {
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        $csvPath = $CSVVolume.SharedVolumeInfo.FriendlyVolumeName
        
        # Create VM directory on CSV
        $vmCsvPath = Join-Path $csvPath "VMs\$VMName"
        
        if ($WhatIf) {
            Write-Host "    [WHATIF] Would create directory: $vmCsvPath" -ForegroundColor Magenta
            Write-Host "    [WHATIF] Would move VM files to CSV storage" -ForegroundColor Magenta
            return $vmCsvPath
        }
        
        if (-not (Test-Path $vmCsvPath)) {
            New-Item -ItemType Directory -Path $vmCsvPath -Force | Out-Null
            Write-Host "    ✓ Created VM directory on CSV: $vmCsvPath" -ForegroundColor Green
        }
        
        # Get current VM files
        $vmFiles = Get-VMHardDiskDrive -VMName $VMName
        $needsMove = $false
        
        foreach ($vhd in $vmFiles) {
            if ($vhd.Path -notlike "$csvPath*") {
                $needsMove = $true
                break
            }
        }
        
        if ($needsMove) {
            Write-Host "    Moving VM files to CSV storage..." -ForegroundColor Yellow
            
            # Stop VM if running
            $wasRunning = $false
            if ($vm.State -eq "Running") {
                $wasRunning = $true
                Write-Host "    Stopping VM for file move..." -ForegroundColor Yellow
                Stop-VM -Name $VMName -Force -ErrorAction Stop
            }
            
            # Move VM to CSV
            Move-VM -Name $VMName -DestinationHost $env:COMPUTERNAME -DestinationStoragePath $vmCsvPath -ErrorAction Stop
            
            # Restart VM if it was running
            if ($wasRunning) {
                Write-Host "    Restarting VM..." -ForegroundColor Yellow
                Start-VM -Name $VMName -ErrorAction Stop
            }
            
            Write-Host "    ✓ VM files moved to CSV storage" -ForegroundColor Green
        } else {
            Write-Host "    ✓ VM files already on CSV storage" -ForegroundColor Green
        }
        
        return $vmCsvPath
        
    } catch {
        Write-Error "    Failed to move VM to CSV: $($_.Exception.Message)"
        throw
    }
}

# Function to add VM to cluster
function Add-VMToCluster {
    param(
        [string]$VMName,
        [string]$ClusterName,
        [switch]$WhatIf
    )
    
    Write-Host "  Adding VM to cluster..." -ForegroundColor Yellow
    
    try {
        # Check if VM is already clustered
        $clusteredVM = Get-ClusterResource | Where-Object { $_.ResourceType -eq "Virtual Machine" -and $_.Name -eq $VMName }
        
        if ($clusteredVM) {
            Write-Host "    ✓ VM is already in cluster" -ForegroundColor Green
            return $clusteredVM
        }
        
        if ($WhatIf) {
            Write-Host "    [WHATIF] Would add VM to cluster: $VMName" -ForegroundColor Magenta
            return $null
        }
        
        # Add VM to cluster
        $clusterVM = Add-ClusterVirtualMachineRole -VMName $VMName -ErrorAction Stop
        Write-Host "    ✓ VM added to cluster as resource: $($clusterVM.Name)" -ForegroundColor Green
        
        return $clusterVM
        
    } catch {
        Write-Error "    Failed to add VM to cluster: $($_.Exception.Message)"
        throw
    }
}

# Function to configure VM high availability settings
function Set-VMHAConfiguration {
    param(
        [string]$VMName,
        [object]$ClusterResource,
        [switch]$WhatIf
    )
    
    Write-Host "  Configuring HA settings..." -ForegroundColor Yellow
    
    try {
        if ($WhatIf) {
            Write-Host "    [WHATIF] Would configure failover policies" -ForegroundColor Magenta
            Write-Host "    [WHATIF] Would set VM monitoring" -ForegroundColor Magenta
            Write-Host "    [WHATIF] Would configure restart policies" -ForegroundColor Magenta
            return
        }
        
        # Configure failover policies
        $ClusterResource | Set-ClusterParameter -Name "FailoverThreshold" -Value 3
        $ClusterResource | Set-ClusterParameter -Name "FailoverPeriod" -Value 6
        Write-Host "    ✓ Set failover threshold: 3 failures in 6 hours" -ForegroundColor Green
        
        # Configure restart policies
        $ClusterResource | Set-ClusterParameter -Name "RestartDelay" -Value 0
        $ClusterResource | Set-ClusterParameter -Name "RestartPeriod" -Value 900000  # 15 minutes
        $ClusterResource | Set-ClusterParameter -Name "RestartThreshold" -Value 2
        Write-Host "    ✓ Set restart policies: 2 restarts in 15 minutes" -ForegroundColor Green
        
        # Enable VM monitoring
        $vmMonitoring = Get-ClusterResource -Name "Virtual Machine $VMName" | Get-ClusterParameter -Name "EnableVMMonitoring"
        if ($vmMonitoring.Value -ne 1) {
            $ClusterResource | Set-ClusterParameter -Name "EnableVMMonitoring" -Value 1
            Write-Host "    ✓ Enabled VM monitoring" -ForegroundColor Green
        }
        
        # Set preferred owners (optional - all nodes by default)
        $clusterNodes = Get-ClusterNode
        $ClusterResource | Set-ClusterOwnerNode -Owners $clusterNodes.Name
        Write-Host "    ✓ Set preferred owners: $($clusterNodes.Name -join ', ')" -ForegroundColor Green
        
    } catch {
        Write-Warning "    Warning: Some HA configuration may have failed: $($_.Exception.Message)"
    }
}

# Function to make a single VM highly available
function Make-VMHighlyAvailable {
    param(
        [string]$VMName,
        [string]$ClusterName,
        [object]$CSVVolume,
        [switch]$WhatIf
    )
    
    Write-Host "Processing VM: $VMName" -ForegroundColor Cyan
    
    try {
        # Verify VM exists
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        Write-Host "  ✓ Found VM: $VMName (State: $($vm.State))" -ForegroundColor Green
        
        # Step 1: Move VM to CSV storage
        $vmCsvPath = Move-VMToCSV -VMName $VMName -CSVVolume $CSVVolume -WhatIf:$WhatIf
        
        # Step 2: Add VM to cluster
        $clusterResource = Add-VMToCluster -VMName $VMName -ClusterName $ClusterName -WhatIf:$WhatIf
        
        # Step 3: Configure HA settings
        if ($clusterResource -or $WhatIf) {
            Set-VMHAConfiguration -VMName $VMName -ClusterResource $clusterResource -WhatIf:$WhatIf
        }
        
        Write-Host "  ✓ $VMName is now highly available!`n" -ForegroundColor Green
        
        return @{
            Success = $true
            VMName = $VMName
            ClusterResource = $clusterResource
            CSVPath = $vmCsvPath
        }
        
    } catch {
        Write-Error "  ✗ Failed to make $VMName highly available: $($_.Exception.Message)`n"
        return @{
            Success = $false
            VMName = $VMName
            Error = $_.Exception.Message
        }
    }
}

# Main script execution
Write-Host "=== Make VMs Highly Available ===" -ForegroundColor Yellow
Write-Host "This script will convert standalone VMs to clustered highly available VMs"
Write-Host "==========================================`n"

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent

# Extract settings from config
$vmPrefix = $config["vm_prefix"]
$vmCount = $config["vm_count"]

# Determine which VMs to process
if ($VMNames.Count -eq 0) {
    # Generate VM names based on config
    $VMNames = @()
    for ($i = 1; $i -le $vmCount; $i++) {
        $VMNames += "$vmPrefix-$i"
    }
    Write-Host "Auto-detected VMs based on config: $($VMNames -join ', ')"
} else {
    Write-Host "Processing specified VMs: $($VMNames -join ', ')"
}

# Validate cluster readiness
$clusterInfo = Test-ClusterReadiness -ClusterName $ClusterName
if (-not $clusterInfo.IsReady) {
    Write-Error "Cluster is not ready for HA VM configuration. Please ensure:"
    Write-Error "  - Failover Clustering is installed and running"
    Write-Error "  - Storage Spaces Direct is configured"
    Write-Error "  - Cluster Shared Volumes are available"
    exit 1
}

# Use first CSV volume (or implement logic to choose specific volume)
$csvVolume = $clusterInfo.CSVVolumes[0]
Write-Host "`nUsing CSV volume: $($csvVolume.Name)" -ForegroundColor Green
Write-Host "CSV path: $($csvVolume.SharedVolumeInfo.FriendlyVolumeName)`n"

# Safety confirmation unless -Force is specified
if (-not $Force -and -not $WhatIf) {
    Write-Warning "This will convert the following VMs to highly available clustered resources:"
    foreach ($vmName in $VMNames) {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm) {
            Write-Host "  - $vmName (State: $($vm.State))" -ForegroundColor Yellow
        } else {
            Write-Host "  - $vmName (Not found - will be skipped)" -ForegroundColor Red
        }
    }
    
    Write-Host "`nThis process will:"
    Write-Host "  1. Move VM files to Cluster Shared Volume storage"
    Write-Host "  2. Add VMs to the failover cluster"
    Write-Host "  3. Configure automatic failover and restart policies"
    Write-Host "  4. Enable VM monitoring and health checks"
    Write-Host "  5. VMs may be briefly stopped during file moves"
    
    $response = Read-Host "`nDo you want to proceed? (y/N)"
    if ($response -notmatch "^[Yy]") {
        Write-Host "Operation cancelled." -ForegroundColor Green
        exit 0
    }
}

# Process each VM
$results = @()
Write-Host "Starting HA conversion process...`n" -ForegroundColor Yellow

foreach ($vmName in $VMNames) {
    $result = Make-VMHighlyAvailable -VMName $vmName -ClusterName $clusterInfo.ClusterName -CSVVolume $csvVolume -WhatIf:$WhatIf
    $results += $result
}

# Summary
Write-Host "`n=== HA Conversion Summary ===" -ForegroundColor Yellow
if ($WhatIf) {
    Write-Host "WHAT-IF MODE - No changes were actually made" -ForegroundColor Magenta
    Write-Host "The following VMs would have been made highly available:"
}

$successCount = ($results | Where-Object { $_.Success }).Count
$failureCount = ($results | Where-Object { -not $_.Success }).Count

Write-Host "Successful conversions: $successCount" -ForegroundColor $(if($successCount -gt 0) { "Green" } else { "Yellow" })
Write-Host "Failed conversions: $failureCount" -ForegroundColor $(if($failureCount -gt 0) { "Red" } else { "Green" })

if ($successCount -gt 0) {
    Write-Host "`nSuccessfully converted VMs:" -ForegroundColor Green
    $results | Where-Object { $_.Success } | ForEach-Object {
        Write-Host "  ✓ $($_.VMName)" -ForegroundColor Green
    }
}

if ($failureCount -gt 0) {
    Write-Host "`nFailed VM conversions:" -ForegroundColor Red
    $results | Where-Object { -not $_.Success } | ForEach-Object {
        Write-Host "  ✗ $($_.VMName): $($_.Error)" -ForegroundColor Red
    }
}

if (-not $WhatIf -and $successCount -gt 0) {
    Write-Host "`n=== Next Steps ===" -ForegroundColor Yellow
    Write-Host "1. Verify cluster resources: Get-ClusterResource | Where-Object ResourceType -eq 'Virtual Machine'"
    Write-Host "2. Test failover: Move-ClusterVirtualMachineRole -Name <VM-Name> -Node <TargetNode>"
    Write-Host "3. Monitor cluster: Get-ClusterNode | Select Name,State"
    Write-Host "4. Check VM status: Get-VM | Select Name,State,ComputerName"
    
    Write-Host "`nYour VMs are now highly available and will automatically failover between cluster nodes!" -ForegroundColor Green
}

Write-Host "==============================="
