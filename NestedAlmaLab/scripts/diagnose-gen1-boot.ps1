# Gen 1 VM ISO Boot Diagnostic Script
#
# This script helps diagnose why a custom ISO isn't booting properly on Gen 1 VMs
#

param(
    [Parameter(Mandatory=$false)]
    [string]$ISOPath = "",
    [Parameter(Mandatory=$false)]
    [string]$VMName = ""
)

Write-Host "=== Gen 1 VM Boot Diagnostics ===" -ForegroundColor Cyan

# Load configuration if no ISO path provided
if ([string]::IsNullOrEmpty($ISOPath)) {
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
        Write-Host "Using ISO from config: $ISOPath"
    }
}

if ([string]::IsNullOrEmpty($ISOPath)) {
    Write-Error "Please provide an ISO path or ensure config.yaml exists"
    exit 1
}

Write-Host "`nISO Analysis:"
Write-Host "Path: $ISOPath"

# Check if ISO exists
if (-not (Test-Path $ISOPath)) {
    Write-Host "  Exists: NO" -ForegroundColor Red
    exit 1
} else {
    $isoSize = (Get-Item $ISOPath).Length
    Write-Host "  Exists: YES ($([math]::Round($isoSize/1MB,2)) MB)" -ForegroundColor Green
}

# Mount and analyze ISO contents
try {
    Write-Host "`nMounting ISO for analysis..."
    $mountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    Write-Host "  Mounted at: ${driveLetter}:"
    
    Write-Host "`nBoot File Analysis:"
    
    # Check for BIOS boot files
    $isolinuxDir = "${driveLetter}:\isolinux"
    $isolinuxBin = "${driveLetter}:\isolinux\isolinux.bin"
    $isolinuxCfg = "${driveLetter}:\isolinux\isolinux.cfg"
    $bootCat = "${driveLetter}:\isolinux\boot.cat"
    
    Write-Host "  isolinux directory: $(if(Test-Path $isolinuxDir){'YES'}else{'NO'})" -ForegroundColor $(if(Test-Path $isolinuxDir){'Green'}else{'Red'})
    Write-Host "  isolinux.bin: $(if(Test-Path $isolinuxBin){'YES'}else{'NO'})" -ForegroundColor $(if(Test-Path $isolinuxBin){'Green'}else{'Red'})
    Write-Host "  isolinux.cfg: $(if(Test-Path $isolinuxCfg){'YES'}else{'NO'})" -ForegroundColor $(if(Test-Path $isolinuxCfg){'Green'}else{'Red'})
    Write-Host "  boot.cat: $(if(Test-Path $bootCat){'YES'}else{'NO'})" -ForegroundColor $(if(Test-Path $bootCat){'Green'}else{'Red'})
    
    if (Test-Path $isolinuxBin) {
        $binSize = (Get-Item $isolinuxBin).Length
        Write-Host "    isolinux.bin size: $binSize bytes" -ForegroundColor $(if($binSize -gt 0){'Green'}else{'Red'})
    }
    
    # Check boot configuration
    if (Test-Path $isolinuxCfg) {
        Write-Host "`nBoot Configuration Analysis:"
        $cfgContent = Get-Content $isolinuxCfg
        
        Write-Host "  isolinux.cfg contents:"
        $cfgContent | ForEach-Object { Write-Host "    $_" }
        
        # Look for kickstart parameters
        $hasKickstart = $false
        $cfgContent | ForEach-Object {
            if ($_ -match "inst\.ks") {
                $hasKickstart = $true
                Write-Host "  Kickstart parameters found: YES" -ForegroundColor Green
                Write-Host "    Line: $_" -ForegroundColor Green
            }
        }
        
        if (-not $hasKickstart) {
            Write-Host "  Kickstart parameters found: NO" -ForegroundColor Yellow
        }
        
        # Check for common boot problems
        $hasDefaultLabel = $cfgContent | Where-Object { $_ -match "^\s*default\s+" }
        $hasMenuTitle = $cfgContent | Where-Object { $_ -match "^\s*menu title" }
        $hasTimeOut = $cfgContent | Where-Object { $_ -match "^\s*timeout\s+" }
        
        Write-Host "`n  Boot Configuration Checks:"
        Write-Host "    Default label: $(if($hasDefaultLabel){'YES'}else{'NO'})" -ForegroundColor $(if($hasDefaultLabel){'Green'}else{'Yellow'})
        Write-Host "    Menu title: $(if($hasMenuTitle){'YES'}else{'NO'})" -ForegroundColor $(if($hasMenuTitle){'Green'}else{'Yellow'})
        Write-Host "    Timeout setting: $(if($hasTimeOut){'YES'}else{'NO'})" -ForegroundColor $(if($hasTimeOut){'Green'}else{'Yellow'})
    }
    
    # Check for kickstart file
    $kickstartFile = "${driveLetter}:\ks.cfg"
    Write-Host "`nKickstart File:"
    Write-Host "  ks.cfg: $(if(Test-Path $kickstartFile){'YES'}else{'NO'})" -ForegroundColor $(if(Test-Path $kickstartFile){'Green'}else{'Red'})
    
    if (Test-Path $kickstartFile) {
        $ksSize = (Get-Item $kickstartFile).Length
        Write-Host "    Size: $ksSize bytes"
        
        # Show first few lines
        Write-Host "    First 10 lines:"
        $ksContent = Get-Content $kickstartFile
        $ksContent[0..9] | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }
    
    # Check kernel and initrd files
    Write-Host "`nKernel Files:"
    $kernelLocations = @(
        "${driveLetter}:\images\pxeboot\vmlinuz",
        "${driveLetter}:\isolinux\vmlinuz",
        "${driveLetter}:\vmlinuz"
    )
    
    $initrdLocations = @(
        "${driveLetter}:\images\pxeboot\initrd.img",
        "${driveLetter}:\isolinux\initrd.img", 
        "${driveLetter}:\initrd.img"
    )
    
    $foundKernel = $false
    $foundInitrd = $false
    
    foreach ($kernelPath in $kernelLocations) {
        if (Test-Path $kernelPath) {
            Write-Host "  vmlinuz found: $kernelPath" -ForegroundColor Green
            $foundKernel = $true
            $kernelSize = (Get-Item $kernelPath).Length
            Write-Host "    Size: $([math]::Round($kernelSize/1MB,2)) MB"
            break
        }
    }
    
    foreach ($initrdPath in $initrdLocations) {
        if (Test-Path $initrdPath) {
            Write-Host "  initrd.img found: $initrdPath" -ForegroundColor Green
            $foundInitrd = $true
            $initrdSize = (Get-Item $initrdPath).Length
            Write-Host "    Size: $([math]::Round($initrdSize/1MB,2)) MB"
            break
        }
    }
    
    if (-not $foundKernel) {
        Write-Host "  vmlinuz: NOT FOUND" -ForegroundColor Red
    }
    
    if (-not $foundInitrd) {
        Write-Host "  initrd.img: NOT FOUND" -ForegroundColor Red
    }
    
    # Dismount ISO
    Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue

} catch {
    Write-Error "Failed to mount or analyze ISO: $($_.Exception.Message)"
    if ($mountResult) {
        Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
    }
}

# If VM name provided, check VM configuration
if (-not [string]::IsNullOrEmpty($VMName)) {
    Write-Host "`n=== VM Configuration Analysis ===" -ForegroundColor Cyan
    
    try {
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        Write-Host "VM Name: $($vm.Name)"
        Write-Host "Generation: $($vm.Generation)"
        Write-Host "State: $($vm.State)"
        Write-Host "Memory: $($vm.MemoryStartup/1GB) GB"
        
        if ($vm.Generation -eq 1) {
            # Check BIOS settings
            $vmBios = Get-VMBios -VMName $VMName
            Write-Host "`nBIOS Configuration:"
            Write-Host "  Startup Order: $($vmBios.StartupOrder -join ', ')"
            Write-Host "  Num Lock: $($vmBios.NumLockEnabled)"
            
            # Check for floppy disk
            $floppyDrive = Get-VMFloppyDiskDrive -VMName $VMName -ErrorAction SilentlyContinue
            if ($floppyDrive) {
                Write-Host "`nFloppy Drive:"
                Write-Host "  Path: $($floppyDrive.Path)"
                Write-Host "  Connected: $($floppyDrive.Path -ne $null)"
            }
        }
        
        # Check DVD drives
        $dvdDrives = Get-VMDvdDrive -VMName $VMName
        Write-Host "`nDVD Drives:"
        foreach ($dvd in $dvdDrives) {
            Write-Host "  Controller: $($dvd.ControllerType) $($dvd.ControllerNumber):$($dvd.ControllerLocation)"
            Write-Host "    Path: $($dvd.Path)"
            Write-Host "    Connected: $($dvd.Path -ne $null)"
        }
        
        # Check hard drives
        $hardDrives = Get-VMHardDiskDrive -VMName $VMName
        Write-Host "`nHard Drives:"
        foreach ($hdd in $hardDrives) {
            Write-Host "  Controller: $($hdd.ControllerType) $($hdd.ControllerNumber):$($hdd.ControllerLocation)"
            Write-Host "    Path: $($hdd.Path)"
            Write-Host "    Size: $([math]::Round((Get-VHD $hdd.Path).Size/1GB,2)) GB"
        }
        
    } catch {
        Write-Warning "Could not analyze VM '$VMName': $($_.Exception.Message)"
    }
}

Write-Host "`n=== Recommendations ===" -ForegroundColor Cyan

Write-Host "For Gen 1 boot issues:"
Write-Host "1. Ensure isolinux.bin exists and is not corrupted"
Write-Host "2. Check that isolinux.cfg has proper boot configuration"
Write-Host "3. Verify vmlinuz and initrd.img are present"
Write-Host "4. Make sure boot.cat file exists"
Write-Host "5. Check VM BIOS boot order includes CD/DVD first"
Write-Host "6. Try recreating the ISO with Gen 1 specific parameters"

if (Test-Path $ISOPath) {
    $isoName = Split-Path $ISOPath -Leaf
    if ($isoName -match "Custom\.iso$") {
        Write-Host "`nFor custom ISOs:"
        Write-Host "7. Try recreating with: .\create-custom-iso.ps1 -Generation 1"
        Write-Host "8. Ensure the original ISO boots correctly first"
        Write-Host "9. Check if the custom ISO creation corrupted boot files"
    }
}

Write-Host "`nIf the ISO still won't boot:"
Write-Host "- Test with the original (unmodified) AlmaLinux ISO first"
Write-Host "- Check Hyper-V event logs for boot errors"
Write-Host "- Try using a different AlmaLinux ISO version"
Write-Host "- Consider using Generation 2 VMs instead"
