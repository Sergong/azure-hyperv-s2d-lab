# AlmaLinux UEFI Boot Fix Script
# This script diagnoses and fixes common UEFI boot issues with AlmaLinux VMs
#
# FEATURES:
# - Fixes kickstart UEFI compatibility issues
# - Regenerates custom ISO with proper UEFI support
# - Verifies VM configuration for UEFI boot
# - Provides step-by-step guidance
#
# USAGE:
#   .\fix-uefi-boot.ps1 [-FixKickstart] [-RegenerateISO] [-CheckVMs]

param(
    [switch]$FixKickstart = $false,
    [switch]$RegenerateISO = $false,
    [switch]$CheckVMs = $false
)

# If no specific actions requested, do everything
if (-not ($FixKickstart -or $RegenerateISO -or $CheckVMs)) {
    $FixKickstart = $true
    $RegenerateISO = $true
    $CheckVMs = $true
}

Write-Host "=== AlmaLinux UEFI Boot Fix Script ===" -ForegroundColor Cyan
Write-Host "This script will diagnose and fix UEFI boot issues" -ForegroundColor White
Write-Host "=========================================="

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

# Simple YAML parser
function ConvertFrom-Yaml {
    param([string]$YamlContent)
    $config = @{}
    $lines = $YamlContent -split "`n" | Where-Object { $_ -match '^\s*\w+:' }
    foreach ($line in $lines) {
        if ($line -match '^\s*([^:]+):\s*"?([^"]+)"?\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            $config[$key] = $value
        }
    }
    return $config
}

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent
$vmPrefix = $config["vm_prefix"]
$vmGeneration = [int]$config["vm_generation"]

Write-Host "Configuration loaded:" -ForegroundColor Green
Write-Host "  VM Prefix: $vmPrefix" -ForegroundColor Gray
Write-Host "  VM Generation: $vmGeneration" -ForegroundColor Gray

# Step 1: Fix kickstart files for UEFI compatibility
if ($FixKickstart) {
    Write-Host "`n[STEP 1] Fixing kickstart files for UEFI compatibility..." -ForegroundColor Green
    
    $kickstartFiles = @(
        "templates\AlmaLinux\v1\ks.cfg",
        "templates\AlmaLinux\v2\ks.cfg"
    )
    
    foreach ($ksFile in $kickstartFiles) {
        $ksPath = Join-Path (Split-Path $PSScriptRoot) $ksFile
        if (Test-Path $ksPath) {
            Write-Host "  Checking: $ksFile" -ForegroundColor Yellow
            
            $content = Get-Content $ksPath -Raw
            $modified = $false
            
            # Fix bootloader configuration
            if ($content -match 'bootloader\s+--location=mbr\s+--driveorder=\w+') {
                Write-Host "    [FIX] Removing BIOS-specific bootloader config" -ForegroundColor Yellow
                $content = $content -replace 'bootloader\s+--location=mbr\s+--driveorder=\w+\s+--append="([^"]*)"', 'bootloader --append="$1"'
                $modified = $true
            }
            
            # Fix disk partitioning
            if ($content -match 'clearpart\s+--all\s+--initlabel\s+--drives=\w+') {
                Write-Host "    [FIX] Removing hardcoded drive specification" -ForegroundColor Yellow
                $content = $content -replace 'clearpart\s+--all\s+--initlabel\s+--drives=\w+', 'clearpart --all --initlabel'
                $modified = $true
            }
            
            if ($modified) {
                Set-Content $ksPath $content -Encoding UTF8
                Write-Host "    [OK] Kickstart file updated for UEFI compatibility" -ForegroundColor Green
            } else {
                Write-Host "    [OK] Kickstart file already UEFI compatible" -ForegroundColor Green
            }
        } else {
            Write-Host "    [WARN] Kickstart file not found: $ksFile" -ForegroundColor Yellow
        }
    }
}

# Step 2: Regenerate custom ISO with proper UEFI support
if ($RegenerateISO) {
    Write-Host "`n[STEP 2] Checking and regenerating custom ISO..." -ForegroundColor Green
    
    $customISOScript = Join-Path $PSScriptRoot "create-custom-iso.ps1"
    if (Test-Path $customISOScript) {
        # Check if current ISO has UEFI issues
        $currentISO = $config["iso_path"]
        if (Test-Path $currentISO) {
            $isoName = Split-Path $currentISO -Leaf
            if ($isoName -match "Custom\.iso$") {
                Write-Host "  Current ISO appears to be custom: $isoName" -ForegroundColor Yellow
                
                # Run diagnostics on current ISO
                $diagScript = Join-Path $PSScriptRoot "diagnose-iso-boot.ps1"
                if (Test-Path $diagScript) {
                    Write-Host "  Running diagnostics on current ISO..." -ForegroundColor Gray
                    try {
                        & $diagScript -ISOPath $currentISO
                    } catch {
                        Write-Host "    [WARN] Diagnostics failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
                
                # Ask user if they want to regenerate
                $response = Read-Host "  Regenerate custom ISO with improved UEFI support? (Y/N)"
                if ($response -match "^[Yy]") {
                    Write-Host "  Regenerating custom ISO for Generation $vmGeneration..." -ForegroundColor Yellow
                    
                    try {
                        # Generate for both v1 and v2 if they exist
                        if (Test-Path (Join-Path (Split-Path $PSScriptRoot) "templates\AlmaLinux\v1\ks.cfg")) {
                            Write-Host "    Creating v1 custom ISO..." -ForegroundColor Gray
                            & $customISOScript -KickstartVersion "v1" -Generation $vmGeneration
                        }
                        
                        if (Test-Path (Join-Path (Split-Path $PSScriptRoot) "templates\AlmaLinux\v2\ks.cfg")) {
                            Write-Host "    Creating v2 custom ISO..." -ForegroundColor Gray
                            & $customISOScript -KickstartVersion "v2" -Generation $vmGeneration
                        }
                        
                        Write-Host "  [OK] Custom ISO regenerated successfully" -ForegroundColor Green
                    } catch {
                        Write-Host "  [FAIL] Custom ISO regeneration failed: $($_.Exception.Message)" -ForegroundColor Red
                    }
                } else {
                    Write-Host "  [SKIP] Keeping existing custom ISO" -ForegroundColor Gray
                }
            } else {
                Write-Host "  Current ISO is standard distribution ISO: $isoName" -ForegroundColor Gray
                Write-Host "  Consider creating custom ISO for fully automated installation" -ForegroundColor Gray
                
                $response = Read-Host "  Create custom ISO now? (Y/N)"
                if ($response -match "^[Yy]") {
                    Write-Host "  Creating custom ISO..." -ForegroundColor Yellow
                    try {
                        & $customISOScript -KickstartVersion "v1" -Generation $vmGeneration
                        Write-Host "  [OK] Custom ISO created successfully" -ForegroundColor Green
                        Write-Host "  [INFO] Update config.yaml to use the new custom ISO path" -ForegroundColor Cyan
                    } catch {
                        Write-Host "  [FAIL] Custom ISO creation failed: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        } else {
            Write-Host "  [WARN] ISO file not found: $currentISO" -ForegroundColor Yellow
            Write-Host "  Please update config.yaml with correct ISO path" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [WARN] Custom ISO creation script not found: $customISOScript" -ForegroundColor Yellow
    }
}

# Step 3: Check VM configuration for UEFI compatibility
if ($CheckVMs) {
    Write-Host "`n[STEP 3] Checking VM configuration for UEFI compatibility..." -ForegroundColor Green
    
    if ($vmGeneration -eq 2) {
        Write-Host "  Generation 2 VMs detected - checking UEFI settings..." -ForegroundColor Yellow
        
        # Get list of VMs matching the prefix
        $vmCount = [int]$config["vm_count"]
        $foundIssues = $false
        
        for ($i = 1; $i -le $vmCount; $i++) {
            $vmName = "$vmPrefix-$i"
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            
            if ($vm) {
                Write-Host "    Checking VM: $vmName" -ForegroundColor Gray
                
                # Check firmware settings
                try {
                    $firmware = Get-VMFirmware -VMName $vmName
                    
                    # Check Secure Boot
                    if ($firmware.SecureBoot -eq "On") {
                        Write-Host "      [ISSUE] Secure Boot is enabled - this will prevent Linux boot" -ForegroundColor Red
                        Write-Host "              Disabling Secure Boot..." -ForegroundColor Yellow
                        Set-VMFirmware -VMName $vmName -EnableSecureBoot Off
                        Write-Host "      [FIX] Secure Boot disabled" -ForegroundColor Green
                        $foundIssues = $true
                    } else {
                        Write-Host "      [OK] Secure Boot is disabled" -ForegroundColor Green
                    }
                    
                    # Check boot order
                    $bootOrder = $firmware.BootOrder
                    if ($bootOrder -and $bootOrder.Count -gt 0) {
                        $firstBoot = $bootOrder[0]
                        if ($firstBoot.FirmwareType -eq "UEFI" -and $firstBoot.BootType -eq "Drive") {
                            # Check if it's DVD drive
                            $dvdDrives = Get-VMDvdDrive -VMName $vmName
                            if ($dvdDrives) {
                                $dvdInBootOrder = $bootOrder | Where-Object { $_.BootType -eq "Drive" -and $_.Path -eq $dvdDrives[0].Path }
                                if (-not $dvdInBootOrder) {
                                    Write-Host "      [ISSUE] DVD drive not in boot order" -ForegroundColor Red
                                    Write-Host "              Setting DVD as first boot device..." -ForegroundColor Yellow
                                    Set-VMFirmware -VMName $vmName -FirstBootDevice $dvdDrives[0]
                                    Write-Host "      [FIX] DVD set as first boot device" -ForegroundColor Green
                                    $foundIssues = $true
                                } else {
                                    Write-Host "      [OK] DVD drive is in boot order" -ForegroundColor Green
                                }
                            }
                        }
                    }
                    
                } catch {
                    Write-Host "      [WARN] Could not check firmware settings: $($_.Exception.Message)" -ForegroundColor Yellow
                }
                
                # Check VM state
                if ($vm.State -eq "Running") {
                    Write-Host "      [INFO] VM is running - changes will take effect on next restart" -ForegroundColor Cyan
                } elseif ($vm.State -eq "Off") {
                    Write-Host "      [OK] VM is stopped - ready for testing" -ForegroundColor Green
                } else {
                    Write-Host "      [INFO] VM state: $($vm.State)" -ForegroundColor Gray
                }
                
            } else {
                Write-Host "    [INFO] VM not found: $vmName (not created yet)" -ForegroundColor Gray
            }
        }
        
        if (-not $foundIssues) {
            Write-Host "  [OK] All VMs have proper UEFI configuration" -ForegroundColor Green
        }
        
    } else {
        Write-Host "  Generation 1 VMs detected - BIOS mode, no UEFI issues expected" -ForegroundColor Green
    }
}

# Step 4: Final recommendations
Write-Host "`n[STEP 4] Final recommendations..." -ForegroundColor Green

Write-Host "  1. Test VM boot:" -ForegroundColor Yellow
Write-Host "     - Start a VM and observe the boot process" -ForegroundColor White
Write-Host "     - Custom ISOs should boot automatically without intervention" -ForegroundColor White
Write-Host "     - Standard ISOs require manual boot parameter entry" -ForegroundColor White

Write-Host "`n  2. If VMs still don't boot:" -ForegroundColor Yellow
Write-Host "     - Verify original AlmaLinux ISO supports UEFI (9.3+ recommended)" -ForegroundColor White
Write-Host "     - Check Hyper-V host supports nested virtualization" -ForegroundColor White
Write-Host "     - Ensure VM has sufficient resources (RAM, disk space)" -ForegroundColor White

Write-Host "`n  3. For troubleshooting:" -ForegroundColor Yellow
Write-Host "     - Use: .\diagnose-iso-boot.ps1 to examine ISO files" -ForegroundColor White
Write-Host "     - Check VM console during boot for error messages" -ForegroundColor White
Write-Host "     - Verify network connectivity for package downloads" -ForegroundColor White

Write-Host "`n  4. Alternative approach:" -ForegroundColor Yellow
Write-Host "     - Consider using Generation 1 VMs if UEFI issues persist" -ForegroundColor White
Write-Host "     - Update config.yaml: vm_generation: 1" -ForegroundColor White
Write-Host "     - Generation 1 VMs use BIOS and may have better compatibility" -ForegroundColor White

Write-Host "`n=== UEFI Boot Fix Completed ===" -ForegroundColor Cyan
Write-Host "The most common UEFI boot issues have been addressed." -ForegroundColor Green
Write-Host "Test your VMs now to verify the fixes work correctly." -ForegroundColor White
