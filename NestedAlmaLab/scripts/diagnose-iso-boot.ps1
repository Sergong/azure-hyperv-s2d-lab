# AlmaLinux ISO Boot Diagnostics
# This script examines an ISO file to diagnose potential UEFI/BIOS boot issues
#
# USAGE:
#   .\diagnose-iso-boot.ps1 [-ISOPath "path\to\iso"]

param(
    [Parameter(Mandatory=$false)]
    [string]$ISOPath = ""
)

# Load configuration if ISO path not provided
if ([string]::IsNullOrWhiteSpace($ISOPath)) {
    $configPath = Join-Path $PSScriptRoot "config.yaml"
    if (Test-Path $configPath) {
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
        $ISOPath = $config["iso_path"]
    }
}

if ([string]::IsNullOrWhiteSpace($ISOPath) -or -not (Test-Path $ISOPath)) {
    Write-Error "ISO file not found. Please specify -ISOPath or ensure config.yaml has valid iso_path"
    exit 1
}

Write-Host "=== AlmaLinux ISO Boot Diagnostics ===" -ForegroundColor Cyan
Write-Host "Examining: $ISOPath" -ForegroundColor Yellow
Write-Host "==========================================="

# Check if ISO is mountable
try {
    Write-Host "`n[STEP 1] Mounting ISO for examination..." -ForegroundColor Green
    $mountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    Write-Host "  [OK] ISO mounted successfully as ${driveLetter}:" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Cannot mount ISO: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    # Check basic ISO structure
    Write-Host "`n[STEP 2] Checking ISO structure..." -ForegroundColor Green
    $rootFiles = Get-ChildItem "${driveLetter}:" -ErrorAction SilentlyContinue
    Write-Host "  Root directory contains $($rootFiles.Count) items:"
    foreach ($file in ($rootFiles | Sort-Object Name | Select-Object -First 10)) {
        $type = if ($file.PSIsContainer) { "[DIR] " } else { "[FILE]" }
        Write-Host "    $type $($file.Name)" -ForegroundColor Gray
    }
    if ($rootFiles.Count -gt 10) {
        Write-Host "    ... and $($rootFiles.Count - 10) more items" -ForegroundColor Gray
    }

    # Check for BIOS boot files
    Write-Host "`n[STEP 3] Checking BIOS boot support..." -ForegroundColor Green
    $isolinuxDir = "${driveLetter}:\isolinux"
    $isolinuxBin = "${driveLetter}:\isolinux\isolinux.bin"
    $bootCat = "${driveLetter}:\isolinux\boot.cat"
    $isolinuxCfg = "${driveLetter}:\isolinux\isolinux.cfg"
    
    if (Test-Path $isolinuxDir) {
        Write-Host "  [OK] BIOS boot directory found: isolinux\" -ForegroundColor Green
        
        if (Test-Path $isolinuxBin) {
            $binSize = [math]::Round((Get-Item $isolinuxBin).Length / 1KB, 1)
            Write-Host "  [OK] BIOS boot loader found: isolinux.bin ($binSize KB)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] BIOS boot loader missing: isolinux.bin" -ForegroundColor Red
        }
        
        if (Test-Path $bootCat) {
            Write-Host "  [OK] Boot catalog found: boot.cat" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Boot catalog missing: boot.cat" -ForegroundColor Yellow
        }
        
        if (Test-Path $isolinuxCfg) {
            Write-Host "  [OK] BIOS boot config found: isolinux.cfg" -ForegroundColor Green
            # Check isolinux.cfg content for kickstart
            $isolinuxContent = Get-Content $isolinuxCfg -Raw
            if ($isolinuxContent -match "inst\.ks=") {
                Write-Host "  [OK] Kickstart parameters found in BIOS config" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] No kickstart parameters in BIOS config" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [FAIL] BIOS boot config missing: isolinux.cfg" -ForegroundColor Red
        }
    } else {
        Write-Host "  [FAIL] BIOS boot directory not found: isolinux\" -ForegroundColor Red
    }

    # Check for UEFI boot files
    Write-Host "`n[STEP 4] Checking UEFI boot support..." -ForegroundColor Green
    $efiDir = "${driveLetter}:\EFI"
    $efiBootDir = "${driveLetter}:\EFI\BOOT"
    $bootx64Efi = "${driveLetter}:\EFI\BOOT\bootx64.efi"
    $grubEfi = "${driveLetter}:\EFI\BOOT\grubx64.efi"
    $grubCfg = "${driveLetter}:\EFI\BOOT\grub.cfg"
    $grub2Cfg = "${driveLetter}:\boot\grub2\grub.cfg"
    
    if (Test-Path $efiDir) {
        Write-Host "  [OK] UEFI directory found: EFI\" -ForegroundColor Green
        
        if (Test-Path $efiBootDir) {
            Write-Host "  [OK] UEFI boot directory found: EFI\BOOT\" -ForegroundColor Green
            
            if (Test-Path $bootx64Efi) {
                $efiSize = [math]::Round((Get-Item $bootx64Efi).Length / 1KB, 1)
                Write-Host "  [OK] UEFI boot loader found: bootx64.efi ($efiSize KB)" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] UEFI boot loader missing: bootx64.efi" -ForegroundColor Red
            }
            
            if (Test-Path $grubEfi) {
                $grubSize = [math]::Round((Get-Item $grubEfi).Length / 1KB, 1)
                Write-Host "  [OK] GRUB UEFI loader found: grubx64.efi ($grubSize KB)" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] GRUB UEFI loader not found: grubx64.efi" -ForegroundColor Yellow
            }
            
            if (Test-Path $grubCfg) {
                Write-Host "  [OK] UEFI GRUB config found: EFI\BOOT\grub.cfg" -ForegroundColor Green
                # Check grub.cfg content for kickstart
                $grubContent = Get-Content $grubCfg -Raw
                if ($grubContent -match "inst\.ks=") {
                    Write-Host "  [OK] Kickstart parameters found in UEFI config" -ForegroundColor Green
                } else {
                    Write-Host "  [WARN] No kickstart parameters in UEFI config" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  [WARN] UEFI GRUB config missing: EFI\BOOT\grub.cfg" -ForegroundColor Yellow
            }
            
            if (Test-Path $grub2Cfg) {
                Write-Host "  [OK] Additional GRUB config found: boot\grub2\grub.cfg" -ForegroundColor Green
            }
        } else {
            Write-Host "  [FAIL] UEFI boot directory not found: EFI\BOOT\" -ForegroundColor Red
        }
    } else {
        Write-Host "  [FAIL] UEFI directory not found: EFI\" -ForegroundColor Red
    }

    # Check for kickstart file
    Write-Host "`n[STEP 5] Checking kickstart configuration..." -ForegroundColor Green
    $ksCfg = "${driveLetter}:\ks.cfg"
    if (Test-Path $ksCfg) {
        $ksSize = [math]::Round((Get-Item $ksCfg).Length / 1KB, 1)
        Write-Host "  [OK] Kickstart file found: ks.cfg ($ksSize KB)" -ForegroundColor Green
        
        # Check kickstart content
        $ksContent = Get-Content $ksCfg -Raw
        if ($ksContent -match "bootloader") {
            Write-Host "  [OK] Bootloader configuration found in kickstart" -ForegroundColor Green
            if ($ksContent -match "bootloader.*--location=mbr") {
                Write-Host "  [WARN] Kickstart uses BIOS-specific bootloader config (--location=mbr)" -ForegroundColor Yellow
                Write-Host "         This may cause issues with UEFI boot. Consider using auto-detection." -ForegroundColor Yellow
            } else {
                Write-Host "  [OK] Kickstart uses flexible bootloader configuration" -ForegroundColor Green
            }
        } else {
            Write-Host "  [WARN] No bootloader configuration in kickstart" -ForegroundColor Yellow
        }
        
        if ($ksContent -match "clearpart.*--drives=sda") {
            Write-Host "  [WARN] Kickstart hardcodes disk as 'sda'" -ForegroundColor Yellow
            Write-Host "         Consider using auto-detection for better UEFI compatibility" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [FAIL] Kickstart file not found: ks.cfg" -ForegroundColor Red
    }

    # Check for kernel and initrd
    Write-Host "`n[STEP 6] Checking boot files..." -ForegroundColor Green
    $imagesDir = "${driveLetter}:\images"
    $bootDir = "${driveLetter}:\boot"
    
    if (Test-Path $imagesDir) {
        $pxebootDir = "${driveLetter}:\images\pxeboot"
        if (Test-Path $pxebootDir) {
            $vmlinuz = "${driveLetter}:\images\pxeboot\vmlinuz"
            $initrd = "${driveLetter}:\images\pxeboot\initrd.img"
            
            if (Test-Path $vmlinuz) {
                $kernelSize = [math]::Round((Get-Item $vmlinuz).Length / 1MB, 1)
                Write-Host "  [OK] Kernel found: images\pxeboot\vmlinuz ($kernelSize MB)" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] Kernel missing: images\pxeboot\vmlinuz" -ForegroundColor Red
            }
            
            if (Test-Path $initrd) {
                $initrdSize = [math]::Round((Get-Item $initrd).Length / 1MB, 1)
                Write-Host "  [OK] Initial ramdisk found: images\pxeboot\initrd.img ($initrdSize MB)" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] Initial ramdisk missing: images\pxeboot\initrd.img" -ForegroundColor Red
            }
        }
    }

    # Summary and recommendations
    Write-Host "`n[STEP 7] Boot compatibility summary..." -ForegroundColor Green
    $biosBootOK = (Test-Path $isolinuxBin) -and (Test-Path $isolinuxCfg)
    $uefiBootOK = (Test-Path $bootx64Efi) -and (Test-Path $grubCfg)
    
    if ($biosBootOK -and $uefiBootOK) {
        Write-Host "  [OK] ISO supports both BIOS and UEFI boot modes" -ForegroundColor Green
        Write-Host "       This ISO should work with both Gen 1 and Gen 2 VMs" -ForegroundColor Green
    } elseif ($biosBootOK) {
        Write-Host "  [WARN] ISO only supports BIOS boot mode" -ForegroundColor Yellow
        Write-Host "        This will work with Gen 1 VMs but may fail with Gen 2 VMs" -ForegroundColor Yellow
    } elseif ($uefiBootOK) {
        Write-Host "  [OK] ISO supports UEFI boot mode" -ForegroundColor Green
        Write-Host "       This should work with Gen 2 VMs" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] ISO does not appear to be bootable" -ForegroundColor Red
        Write-Host "        Boot files are missing or corrupted" -ForegroundColor Red
    }

    # Custom ISO detection
    $isoName = Split-Path $ISOPath -Leaf
    if ($isoName -match "Custom\.iso$") {
        Write-Host "`n[INFO] This appears to be a custom ISO" -ForegroundColor Cyan
        if (Test-Path $ksCfg) {
            Write-Host "       Custom ISOs should provide fully automated installation" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`n[INFO] This appears to be a standard distribution ISO" -ForegroundColor Cyan
        Write-Host "       Standard ISOs require manual boot parameter entry" -ForegroundColor Cyan
    }

} finally {
    # Always unmount the ISO
    try {
        Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
        Write-Host "`n[INFO] ISO unmounted successfully" -ForegroundColor Gray
    } catch {
        Write-Host "`n[WARN] Failed to unmount ISO: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Diagnostics completed ===" -ForegroundColor Cyan

# Provide recommendations
Write-Host "`n=== Recommendations ===" -ForegroundColor Yellow

if (-not $uefiBootOK) {
    Write-Host "1. For UEFI boot issues:" -ForegroundColor Yellow
    Write-Host "   - Ensure you're using a recent AlmaLinux ISO (9.3+)" -ForegroundColor White
    Write-Host "   - Verify the original ISO supports UEFI boot" -ForegroundColor White
    Write-Host "   - Re-create custom ISO with proper UEFI support" -ForegroundColor White
}

if (Test-Path $ksCfg) {
    $ksContent = Get-Content $ksCfg -Raw
    if ($ksContent -match "--location=mbr") {
        Write-Host "2. For kickstart UEFI compatibility:" -ForegroundColor Yellow
        Write-Host "   - Update kickstart to use: bootloader --append=\"...\"" -ForegroundColor White
        Write-Host "   - Remove --location=mbr and --driveorder=sda" -ForegroundColor White
        Write-Host "   - Let the installer auto-detect UEFI vs BIOS" -ForegroundColor White
    }
}

Write-Host "`n3. For VM configuration:" -ForegroundColor Yellow
Write-Host "   - Ensure Secure Boot is disabled for Linux VMs" -ForegroundColor White
Write-Host "   - Verify DVD drive is set as first boot device" -ForegroundColor White
Write-Host "   - Check VM firmware settings in Hyper-V Manager" -ForegroundColor White

Write-Host "`nDiagnostics completed. Check the output above for any [FAIL] or [WARN] messages." -ForegroundColor Cyan
