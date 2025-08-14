# VM Boot Diagnostics Script
#
# This script diagnoses common VM boot issues and provides troubleshooting
# information for VMs that fail to boot properly.
#
# FEATURES:
# - Checks VM configuration and boot settings
# - Validates attached media (ISO, VHDs)
# - Analyzes UEFI/BIOS boot configuration
# - Provides specific troubleshooting recommendations
# - Can fix common boot configuration issues
#
# USAGE:
#   .\diagnose-vm-boot.ps1                     # Diagnose all VMs from config
#   .\diagnose-vm-boot.ps1 -VMNames "VM1"     # Diagnose specific VM
#   .\diagnose-vm-boot.ps1 -Fix               # Attempt to fix issues found
#

param(
    [Parameter(Mandatory=$false)]
    [string[]]$VMNames = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$Fix,
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed
)

# Load configuration from YAML file
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

# Function to diagnose a single VM
function Test-VMBootConfiguration {
    param(
        [string]$VMName,
        [switch]$Fix,
        [switch]$Detailed
    )
    
    Write-Host "`n=== Diagnosing VM: $VMName ===" -ForegroundColor Cyan
    $issues = @()
    $recommendations = @()
    
    try {
        # Check if VM exists
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        Write-Host "[OK] VM exists: $VMName" -ForegroundColor Green
        Write-Host "  State: $($vm.State)" -ForegroundColor Yellow
        Write-Host "  Generation: $($vm.Generation)" -ForegroundColor Yellow
        
        # Check VM state
        if ($vm.State -eq "Running") {
            Write-Host "  VM is currently running - some checks may be limited" -ForegroundColor Yellow
        }
        
        # Check attached storage
        Write-Host "`n--- Storage Analysis ---" -ForegroundColor Yellow
        
        # Check hard drives
        $hardDrives = Get-VMHardDiskDrive -VMName $VMName
        Write-Host "Hard Drives: $($hardDrives.Count)"
        
        foreach ($hdd in $hardDrives) {
            $exists = Test-Path $hdd.Path
            $status = if ($exists) { "[OK]" } else { "[FAIL]" }
            Write-Host "  $status $($hdd.Path)" -ForegroundColor $(if($exists) { "Green" } else { "Red" })
            
            if (-not $exists) {
                $issues += "Missing VHD file: $($hdd.Path)"
                $recommendations += "Recreate or restore the missing VHD file"
            }
            
            if ($Detailed -and $exists) {
                $vhdInfo = Get-VHD -Path $hdd.Path
                Write-Host "    Size: $([math]::Round($vhdInfo.Size / 1GB, 2)) GB"
                Write-Host "    Type: $($vhdInfo.VhdType)"
            }
        }
        
        # Check DVD drives
        $dvdDrives = Get-VMDvdDrive -VMName $VMName
        Write-Host "DVD Drives: $($dvdDrives.Count)"
        
        foreach ($dvd in $dvdDrives) {
            if ($dvd.Path) {
                $exists = Test-Path $dvd.Path
                $status = if ($exists) { "[OK]" } else { "[FAIL]" }
                Write-Host "  $status $($dvd.Path)" -ForegroundColor $(if($exists) { "Green" } else { "Red" })
                
                if (-not $exists) {
                    $issues += "Missing ISO file: $($dvd.Path)"
                    $recommendations += "Ensure the AlmaLinux ISO file exists and is accessible"
                }
            } else {
                Write-Host "  [FAIL] DVD drive present but no ISO attached" -ForegroundColor Red
                $issues += "No ISO attached to DVD drive"
                $recommendations += "Attach AlmaLinux ISO to the DVD drive"
            }
        }
        
        # Check floppy drives (Gen 1 only)
        if ($vm.Generation -eq 1) {
            $floppyDrives = Get-VMFloppyDiskDrive -VMName $VMName
            Write-Host "Floppy Drives: $($floppyDrives.Count)"
            
            foreach ($floppy in $floppyDrives) {
                if ($floppy.Path) {
                    $exists = Test-Path $floppy.Path
                    $status = if ($exists) { "[OK]" } else { "[FAIL]" }
                    Write-Host "  $status $($floppy.Path)" -ForegroundColor $(if($exists) { "Green" } else { "Red" })
                    
                    if (-not $exists) {
                        $issues += "Missing floppy VHD: $($floppy.Path)"
                    }
                } else {
                    Write-Host "  - Floppy drive present but no media attached" -ForegroundColor Yellow
                }
            }
        }
        
        # Check boot configuration
        Write-Host "`n--- Boot Configuration Analysis ---" -ForegroundColor Yellow
        
        if ($vm.Generation -eq 2) {
            # Generation 2 UEFI analysis
            $firmware = Get-VMFirmware -VMName $VMName
            
            Write-Host "UEFI Secure Boot: $($firmware.SecureBoot)"
            if ($firmware.SecureBoot -eq "On") {
                $issues += "Secure Boot is enabled (may prevent Linux boot)"
                $recommendations += "Disable Secure Boot for Linux compatibility"
            } else {
                Write-Host "  [OK] Secure Boot disabled (good for Linux)" -ForegroundColor Green
            }
            
            # Check boot order
            Write-Host "Boot Order:"
            $bootOrder = $firmware.BootOrder
            if ($bootOrder.Count -eq 0) {
                Write-Host "  [FAIL] No boot devices configured!" -ForegroundColor Red
                $issues += "No boot devices in UEFI boot order"
                $recommendations += "Configure boot order with DVD first, then hard drives"
            } else {
                for ($i = 0; $i -lt $bootOrder.Count; $i++) {
                    $device = $bootOrder[$i]
                    Write-Host "  $($i + 1). $($device.Device) ($($device.BootType))" -ForegroundColor Green
                }
                
                # Check if DVD is first
                $firstDevice = $bootOrder[0]
                if ($firstDevice.BootType -ne "Drive" -or $firstDevice.Device -notlike "*DVD*") {
                    $issues += "DVD drive is not the first boot device"
                    $recommendations += "Set DVD drive as the first boot device for installation"
                }
            }
            
            # Check first boot device
            if ($firmware.FirstBootDevice) {
                Write-Host "First Boot Device: $($firmware.FirstBootDevice.Name)" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] No first boot device set!" -ForegroundColor Red
                $issues += "No first boot device configured"
            }
            
        } else {
            # Generation 1 BIOS analysis
            $biosSettings = Get-VMBios -VMName $VMName
            
            Write-Host "BIOS Boot Order: $($biosSettings.StartupOrder -join ', ')"
            
            if ($biosSettings.StartupOrder[0] -ne "CD") {
                $issues += "CD/DVD is not the first boot device in BIOS"
                $recommendations += "Set boot order to CD, Floppy, IDE for installation"
            } else {
                Write-Host "  [OK] CD/DVD is first boot device" -ForegroundColor Green
            }
        }
        
        # Check network configuration
        Write-Host "`n--- Network Configuration ---" -ForegroundColor Yellow
        $networkAdapters = Get-VMNetworkAdapter -VMName $VMName
        
        foreach ($adapter in $networkAdapters) {
            Write-Host "Network Adapter: $($adapter.Name)"
            Write-Host "  Switch: $($adapter.SwitchName)"
            
            if (-not $adapter.SwitchName) {
                $issues += "Network adapter not connected to a virtual switch"
                $recommendations += "Connect network adapter to a virtual switch"
            }
        }
        
        # Attempt fixes if requested
        if ($Fix -and $issues.Count -gt 0) {
            Write-Host "`n--- Attempting Fixes ---" -ForegroundColor Yellow
            
            try {
                # Fix Secure Boot
                if ($vm.Generation -eq 2 -and (Get-VMFirmware -VMName $VMName).SecureBoot -eq "On") {
                    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
                    Write-Host "  [OK] Disabled Secure Boot" -ForegroundColor Green
                }
                
                # Fix boot order for Generation 2
                if ($vm.Generation -eq 2) {
                    $dvd = Get-VMDvdDrive -VMName $VMName | Select-Object -First 1
                    if ($dvd) {
                        Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd
                        Write-Host "  [OK] Set DVD as first boot device" -ForegroundColor Green
                        
                        # Set full boot order
                        $bootOrder = @($dvd)
                        $hdds = Get-VMHardDiskDrive -VMName $VMName
                        $bootOrder += $hdds
                        Set-VMFirmware -VMName $VMName -BootOrder $bootOrder
                        Write-Host "  [OK] Configured complete boot order" -ForegroundColor Green
                    }
                }
                
                # Fix boot order for Generation 1
                if ($vm.Generation -eq 1) {
                    Set-VMBios -VMName $VMName -StartupOrder @("CD", "Floppy", "IDE")
                    Write-Host "  [OK] Set BIOS boot order to CD, Floppy, IDE" -ForegroundColor Green
                }
                
            } catch {
                Write-Warning "  Some fixes failed: $($_.Exception.Message)"
            }
        }
        
    } catch {
        Write-Error "Failed to analyze VM $VMName : $($_.Exception.Message)"
        return @{
            VMName = $VMName
            Issues = @("VM analysis failed: $($_.Exception.Message)")
            Recommendations = @("Verify VM exists and you have proper permissions")
        }
    }
    
    # Summary
    Write-Host "`n--- Diagnosis Summary ---" -ForegroundColor Yellow
    
    if ($issues.Count -eq 0) {
        Write-Host "[OK] No issues found with VM $VMName" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Found $($issues.Count) issue(s) with VM $VMName :" -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host "  - $issue" -ForegroundColor Red
        }
        
        Write-Host "`nRecommendations:" -ForegroundColor Yellow
        foreach ($rec in $recommendations) {
            Write-Host "  • $rec" -ForegroundColor Cyan
        }
    }
    
    return @{
        VMName = $VMName
        Issues = $issues
        Recommendations = $recommendations
    }
}

# Main script execution
Write-Host "=== VM Boot Diagnostics ===" -ForegroundColor Yellow
Write-Host "Analyzing VM boot configuration and identifying issues"
Write-Host "========================================`n"

# Load configuration if available
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (Test-Path $configPath) {
    $yamlContent = Get-Content $configPath -Raw
    $config = ConvertFrom-Yaml -YamlContent $yamlContent
    
    # Determine which VMs to analyze
    if ($VMNames.Count -eq 0) {
        # Generate VM names based on config
        $vmPrefix = $config["vm_prefix"]
        $vmCount = $config["vm_count"]
        
        $VMNames = @()
        for ($i = 1; $i -le $vmCount; $i++) {
            $VMNames += "$vmPrefix-$i"
        }
        Write-Host "Auto-detected VMs based on config: $($VMNames -join ', ')"
    }
} elseif ($VMNames.Count -eq 0) {
    Write-Warning "No config.yaml found and no VM names specified."
    Write-Host "Usage: .\diagnose-vm-boot.ps1 -VMNames 'VM1','VM2'"
    exit 1
}

# Analyze each VM
$results = @()
foreach ($vmName in $VMNames) {
    $result = Test-VMBootConfiguration -VMName $vmName -Fix:$Fix -Detailed:$Detailed
    $results += $result
}

# Overall summary
Write-Host "`n`n=== Overall Diagnosis Summary ===" -ForegroundColor Yellow

$totalIssues = 0
foreach ($result in $results) {
    $issueCount = $result.Issues.Count
    $totalIssues += $issueCount
    
    $status = if ($issueCount -eq 0) { "[OK]" } else { "[FAIL] ($issueCount issues)" }
    $color = if ($issueCount -eq 0) { "Green" } else { "Red" }
    
    Write-Host "$status $($result.VMName)" -ForegroundColor $color
}

Write-Host "`nTotal Issues Found: $totalIssues" -ForegroundColor $(if ($totalIssues -eq 0) { "Green" } else { "Red" })

if ($totalIssues -gt 0) {
    Write-Host "`n=== Common Troubleshooting Steps ===" -ForegroundColor Yellow
    Write-Host "1. Ensure AlmaLinux ISO file exists and is accessible"
    Write-Host "2. For Gen 2 VMs: Disable Secure Boot and set DVD as first boot device"
    Write-Host "3. For Gen 1 VMs: Set boot order to CD, Floppy, IDE"
    Write-Host "4. Verify VM has sufficient memory (minimum 1GB recommended)"
    Write-Host "5. Check that virtual switch exists and is properly configured"
    Write-Host "6. Try using a custom ISO with embedded kickstart parameters"
    
    if (-not $Fix) {
        Write-Host "`nTip: Run with -Fix parameter to attempt automatic fixes"
    }
} else {
    Write-Host "All VMs appear to be configured correctly for booting!" -ForegroundColor Green
}

Write-Host "======================================="
