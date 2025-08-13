# VM Cleanup Script - Completely Remove VMs and Associated Files
#
# This script removes AlmaLinux VMs created by provision-vms.ps1 along with
# all associated files including VHDs, kickstart media, and VM configuration.
#
# FEATURES:
# - Safely stops and removes VMs
# - Deletes main VM VHD files
# - Removes kickstart media (floppy/VHD files)
# - Cleans up empty directories
# - Provides detailed progress information
# - Includes safety confirmations
# - Handles errors gracefully
#
# USAGE:
#   .\remove-vms.ps1                          # Remove all VMs based on config
#   .\remove-vms.ps1 -VMNames "VM1","VM2"     # Remove specific VMs
#   .\remove-vms.ps1 -Force                   # Skip confirmation prompts
#

param(
    [Parameter(Mandatory=$false)]
    [string[]]$VMNames = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Load configuration from YAML file (same as provision-vms.ps1)
function ConvertFrom-Yaml {
    param([string]$YamlContent)
    
    $config = @{}
    $lines = $YamlContent -split "`n" | Where-Object { $_ -match '^\s*\w+:' }
    
    foreach ($line in $lines) {
        if ($line -match '^\s*([^:]+):\s*"?([^"]+)"?\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            
            # Convert numeric values
            if ($value -match '^\d+$') {
                $config[$key] = [int]$value
            }
            # Convert memory values (e.g., "2GB")
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
$vmPath = $config["vm_path"]
$vhdPath = $config["vhd_path"]

# Create list of VMs to remove
if ($VMNames.Count -eq 0) {
    # Generate VM names based on config
    $VMNames = @()
    for ($i = 1; $i -le $vmCount; $i++) {
        $VMNames += "$vmPrefix-$i"
    }
    Write-Host "Auto-detected VMs based on config: $($VMNames -join ', ')"
} else {
    Write-Host "Removing specified VMs: $($VMNames -join ', ')"
}

# Kickstart media directory
$ksFloppyPath = "$vhdPath\Kickstart"

Write-Host "`n=== VM Cleanup Configuration ===" -ForegroundColor Yellow
Write-Host "VM Names: $($VMNames -join ', ')"
Write-Host "VM Path: $vmPath"
Write-Host "VHD Path: $vhdPath"
Write-Host "Kickstart Path: $ksFloppyPath"
Write-Host "====================================`n"

# Safety confirmation unless -Force is specified
if (-not $Force -and -not $WhatIf) {
    Write-Warning "This will PERMANENTLY DELETE the following VMs and ALL associated files:"
    foreach ($vmName in $VMNames) {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm) {
            Write-Host "  - $vmName (State: $($vm.State))" -ForegroundColor Red
        } else {
            Write-Host "  - $vmName (Not found - will clean up files if they exist)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nFiles that will be deleted:"
    Write-Host "  - VM configuration files"
    Write-Host "  - Main VHD files (*.vhdx)"
    Write-Host "  - Kickstart media files (*.vhd)"
    Write-Host "  - Empty directories"
    
    $response = Read-Host "`nAre you sure you want to proceed? (Type 'YES' to confirm)"
    if ($response -ne "YES") {
        Write-Host "Operation cancelled." -ForegroundColor Green
        exit 0
    }
}

# Function to safely remove a VM and its files
function Remove-VMCompletely {
    param(
        [string]$VMName,
        [string]$VMPath,
        [string]$VHDPath,
        [string]$KSPath,
        [switch]$WhatIf
    )
    
    $removed = @{
        VM = $false
        MainVHD = $false
        KickstartMedia = @()
        VMDirectory = $false
    }
    
    Write-Host "Processing VM: $VMName" -ForegroundColor Cyan
    
    try {
        # Check if VM exists
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        
        if ($vm) {
            Write-Host "  Found VM: $VMName (State: $($vm.State))"
            
            if ($WhatIf) {
                Write-Host "  [WHATIF] Would stop VM: $VMName" -ForegroundColor Magenta
                Write-Host "  [WHATIF] Would remove VM: $VMName" -ForegroundColor Magenta
            } else {
                # Stop VM if running
                if ($vm.State -eq "Running") {
                    Write-Host "  Stopping VM..." -ForegroundColor Yellow
                    Stop-VM -Name $VMName -Force -ErrorAction Stop
                    
                    # Wait a moment for VM to fully stop
                    Start-Sleep -Seconds 2
                }
                
                # Remove VM configuration
                Write-Host "  Removing VM configuration..."
                Remove-VM -Name $VMName -Force -ErrorAction Stop
                $removed.VM = $true
                Write-Host "  ✓ VM removed successfully" -ForegroundColor Green
            }
        } else {
            Write-Host "  VM not found in Hyper-V (may have been manually deleted)" -ForegroundColor Yellow
        }
        
        # Remove main VHD file
        $vhdFile = "$VHDPath\$VMName.vhdx"
        if (Test-Path $vhdFile) {
            Write-Host "  Found main VHD: $vhdFile"
            if ($WhatIf) {
                Write-Host "  [WHATIF] Would remove VHD: $vhdFile" -ForegroundColor Magenta
            } else {
                Remove-Item $vhdFile -Force -ErrorAction Stop
                $removed.MainVHD = $true
                Write-Host "  ✓ Main VHD removed: $vhdFile" -ForegroundColor Green
            }
        } else {
            Write-Host "  Main VHD not found: $vhdFile" -ForegroundColor Yellow
        }
        
        # Remove kickstart media files
        $kickstartFiles = @(
            "$KSPath\$VMName-ks.vhd",  # Gen 2 kickstart VHD
            "$KSPath\$VMName-ks.iso"   # Potential kickstart ISO
        )
        
        foreach ($ksFile in $kickstartFiles) {
            if (Test-Path $ksFile) {
                Write-Host "  Found kickstart media: $ksFile"
                if ($WhatIf) {
                    Write-Host "  [WHATIF] Would remove kickstart media: $ksFile" -ForegroundColor Magenta
                } else {
                    Remove-Item $ksFile -Force -ErrorAction Stop
                    $removed.KickstartMedia += $ksFile
                    Write-Host "  ✓ Kickstart media removed: $ksFile" -ForegroundColor Green
                }
            }
        }
        
        # Remove VM-specific directory if it exists and is empty
        $vmSpecificPath = "$VMPath\$VMName"
        if (Test-Path $vmSpecificPath) {
            $items = Get-ChildItem $vmSpecificPath -ErrorAction SilentlyContinue
            if ($items.Count -eq 0) {
                Write-Host "  Found empty VM directory: $vmSpecificPath"
                if ($WhatIf) {
                    Write-Host "  [WHATIF] Would remove empty directory: $vmSpecificPath" -ForegroundColor Magenta
                } else {
                    Remove-Item $vmSpecificPath -Force -ErrorAction Stop
                    $removed.VMDirectory = $true
                    Write-Host "  ✓ Empty VM directory removed: $vmSpecificPath" -ForegroundColor Green
                }
            } else {
                Write-Host "  VM directory not empty, keeping: $vmSpecificPath" -ForegroundColor Yellow
            }
        }
        
        Write-Host "  ✓ $VMName cleanup completed successfully`n" -ForegroundColor Green
        return $removed
        
    } catch {
        Write-Error "  ✗ Failed to remove VM $VMName : $($_.Exception.Message)"
        Write-Host ""
        return $removed
    }
}

# Process each VM
$totalRemoved = @{
    VMs = 0
    MainVHDs = 0
    KickstartMedia = 0
    Directories = 0
}

Write-Host "Starting VM removal process...`n" -ForegroundColor Yellow

foreach ($vmName in $VMNames) {
    $result = Remove-VMCompletely -VMName $vmName -VMPath $vmPath -VHDPath $vhdPath -KSPath $ksFloppyPath -WhatIf:$WhatIf
    
    if ($result.VM) { $totalRemoved.VMs++ }
    if ($result.MainVHD) { $totalRemoved.MainVHDs++ }
    $totalRemoved.KickstartMedia += $result.KickstartMedia.Count
    if ($result.VMDirectory) { $totalRemoved.Directories++ }
}

# Clean up empty parent directories
if (-not $WhatIf) {
    Write-Host "Checking for empty parent directories..." -ForegroundColor Yellow
    
    # Check kickstart directory
    if ((Test-Path $ksFloppyPath) -and ((Get-ChildItem $ksFloppyPath -ErrorAction SilentlyContinue).Count -eq 0)) {
        Write-Host "Removing empty kickstart directory: $ksFloppyPath"
        Remove-Item $ksFloppyPath -Force -ErrorAction SilentlyContinue
        $totalRemoved.Directories++
    }
    
    # Check main VHD directory if different from VM path
    if ($vhdPath -ne $vmPath -and (Test-Path $vhdPath)) {
        $vhdItems = Get-ChildItem $vhdPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "Kickstart" }
        if ($vhdItems.Count -eq 0 -and -not (Test-Path $ksFloppyPath)) {
            Write-Host "Removing empty VHD directory: $vhdPath"
            Remove-Item $vhdPath -Force -ErrorAction SilentlyContinue
            $totalRemoved.Directories++
        }
    }
}

# Summary
Write-Host "`n=== Cleanup Summary ===" -ForegroundColor Yellow
if ($WhatIf) {
    Write-Host "WHAT-IF MODE - No files were actually deleted" -ForegroundColor Magenta
    Write-Host "The following would have been removed:"
}
Write-Host "VMs removed: $($totalRemoved.VMs)" -ForegroundColor $(if($totalRemoved.VMs -gt 0) { "Green" } else { "Yellow" })
Write-Host "Main VHDs removed: $($totalRemoved.MainVHDs)" -ForegroundColor $(if($totalRemoved.MainVHDs -gt 0) { "Green" } else { "Yellow" })
Write-Host "Kickstart media removed: $($totalRemoved.KickstartMedia)" -ForegroundColor $(if($totalRemoved.KickstartMedia -gt 0) { "Green" } else { "Yellow" })
Write-Host "Directories cleaned: $($totalRemoved.Directories)" -ForegroundColor $(if($totalRemoved.Directories -gt 0) { "Green" } else { "Yellow" })

if ($totalRemoved.VMs -eq 0 -and $totalRemoved.MainVHDs -eq 0 -and $totalRemoved.KickstartMedia -eq 0) {
    Write-Host "`nNo VMs or files were found to remove." -ForegroundColor Yellow
} elseif (-not $WhatIf) {
    Write-Host "`nVM cleanup completed successfully!" -ForegroundColor Green
    Write-Host "All specified VMs and associated files have been permanently deleted." -ForegroundColor Green
}

Write-Host "=========================="
