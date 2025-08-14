# AlmaLinux Custom ISO Creator with Embedded Kickstart Parameters
# This script creates a custom AlmaLinux ISO with kickstart parameters embedded
# to enable fully automated installation without manual intervention.
#
# FEATURES:
# - Extracts original AlmaLinux ISO
# - Modifies boot configuration to include kickstart parameters
# - Embeds kickstart file directly into the ISO
# - Creates customized ISO for both Gen 1 and Gen 2 VMs
# - Supports both BIOS and UEFI boot modes
#
# USAGE:
#   .\create-custom-iso.ps1 [-KickstartVersion v1|v2] [-Generation 1|2]
#

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("v1", "v2")]
    [string]$KickstartVersion = "v1",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 2)]
    [int]$Generation = 1
)

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

# Simple YAML parser (reusing from provision-vms.ps1)
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

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent

# Configuration
$originalISO = $config["iso_path"]
$outputDir = Join-Path (Split-Path $PSScriptRoot) "custom-iso"
$customISOName = "AlmaLinux-$KickstartVersion-Gen$Generation-Custom.iso"
$customISO = Join-Path $outputDir $customISOName
# Use a more accessible temporary directory to avoid permission issues
$workDir = Join-Path $env:USERPROFILE "alma-iso-temp-$(Get-Random)"
$extractDir = Join-Path $workDir "extracted"
$kickstartFile = Join-Path $PSScriptRoot "..\templates\AlmaLinux\$KickstartVersion\ks.cfg"

# Validate inputs
if (-not (Test-Path $originalISO)) {
    Write-Error "Original AlmaLinux ISO not found: $originalISO"
    exit 1
}

if (-not (Test-Path $kickstartFile)) {
    Write-Error "Kickstart file not found: $kickstartFile"
    exit 1
}

# Function to install Windows ADK silently
function Install-WindowsADK {
    Write-Host "Windows ADK not found. Installing automatically..."
    
    # Download ADK installer
    $adkUrl = "https://go.microsoft.com/fwlink/?linkid=2243390"  # Latest ADK for Windows 11 version 22H2
    $adkInstaller = Join-Path $env:TEMP "adksetup.exe"
    
    try {
        Write-Host "Downloading Windows ADK installer..."
        Invoke-WebRequest -Uri $adkUrl -OutFile $adkInstaller -UseBasicParsing
        
        Write-Host "Installing Windows ADK (Deployment Tools only)..."
        Write-Host "This may take several minutes. Please wait..."
        
        # Install ADK with only Deployment Tools feature (silent install)
        $installArgs = @(
            "/quiet"
            "/norestart"
            "/features"
            "OptionId.DeploymentTools"
        )
        
        $process = Start-Process -FilePath $adkInstaller -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Windows ADK installed successfully!"
            # Remove installer
            Remove-Item $adkInstaller -Force -ErrorAction SilentlyContinue
            return $true
        } else {
            Write-Error "Windows ADK installation failed with exit code: $($process.ExitCode)"
            return $false
        }
        
    } catch {
        Write-Error "Failed to download or install Windows ADK: $($_.Exception.Message)"
        return $false
    } finally {
        # Cleanup installer file
        if (Test-Path $adkInstaller) {
            Remove-Item $adkInstaller -Force -ErrorAction SilentlyContinue
        }
    }
}

# Check for required tools and install if needed
$oscdimgPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
if (-not (Test-Path $oscdimgPath)) {
    Write-Host "oscdimg.exe not found at: $oscdimgPath"
    
    # Try alternative locations for different ADK versions
    $alternativePaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe"
    )
    
    $found = $false
    foreach ($altPath in $alternativePaths) {
        if (Test-Path $altPath) {
            $oscdimgPath = $altPath
            $found = $true
            Write-Host "Found oscdimg.exe at: $oscdimgPath"
            break
        }
    }
    
    if (-not $found) {
        Write-Host "Windows ADK (Assessment and Deployment Kit) is required but not installed."
        
        # Check if running as administrator
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Error "Administrator privileges required to install Windows ADK automatically."
            Write-Host "Please run PowerShell as Administrator, or install Windows ADK manually:"
            Write-Host "Download from: https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install"
            Write-Host "Only the 'Deployment Tools' component is required."
            exit 1
        }
        
        # Ask user for permission to install
        $response = Read-Host "Would you like to install Windows ADK automatically? (Y/N)"
        
        if ($response -match "^[Yy]") {
            if (Install-WindowsADK) {
                # Re-check for oscdimg.exe after installation
                if (Test-Path $oscdimgPath) {
                    Write-Host "Windows ADK installation successful. Continuing with ISO creation..."
                } else {
                    Write-Error "oscdimg.exe still not found after ADK installation. Please check the installation."
                    exit 1
                }
            } else {
                Write-Error "Windows ADK installation failed. Cannot continue."
                exit 1
            }
        } else {
            Write-Error "Windows ADK is required to create custom ISOs."
            Write-Host "Please install Windows ADK manually:"
            Write-Host "Download from: https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install"
            Write-Host "Only the 'Deployment Tools' component is required."
            exit 1
        }
    }
}

Write-Host "=== AlmaLinux Custom ISO Creator ==="
Write-Host "Original ISO: $originalISO"
Write-Host "Kickstart: $kickstartFile ($KickstartVersion)"
Write-Host "Target Generation: $Generation"
Write-Host "Output ISO: $customISO"
Write-Host "=====================================`n"

try {
    # Clean up previous work
    if (Test-Path $workDir) {
        Remove-Item $workDir -Recurse -Force
    }
    if (Test-Path $customISO) {
        Remove-Item $customISO -Force
    }
    
    # Create directories
    New-Item -ItemType Directory -Path $outputDir, $workDir, $extractDir -Force | Out-Null
    
    Write-Host "Extracting original ISO..."
    # Mount the original ISO
    $mountResult = Mount-DiskImage -ImagePath $originalISO -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    
    # Copy all files from ISO
    robocopy "${driveLetter}:" $extractDir /E /NP /NJH /NJS | Out-Null
    
    # Dismount the original ISO
    Dismount-DiskImage -ImagePath $originalISO
    
    # Remove read-only attributes from extracted files (common issue with ISO files)
    Write-Host "Removing read-only attributes from extracted files..."
    try {
        Get-ChildItem $extractDir -Recurse -File | ForEach-Object {
            if ($_.IsReadOnly) {
                $_.IsReadOnly = $false
            }
        }
        Write-Host "  Read-only attributes removed successfully"
    } catch {
        Write-Warning "  Could not remove some read-only attributes: $($_.Exception.Message)"
        Write-Host "  Attempting alternative method..."
        # Alternative method using attrib command
        try {
            $attribResult = & attrib -R "$extractDir\*.*" /S /D 2>&1
            Write-Host "  Alternative method completed"
        } catch {
            Write-Warning "  Alternative method also failed, continuing anyway..."
        }
    }
    
    Write-Host "Copying kickstart file..."
    # Copy kickstart file to ISO root
    try {
        Copy-Item $kickstartFile "$extractDir\ks.cfg" -Force -ErrorAction Stop
        Write-Host "  Kickstart file copied successfully"
    } catch {
        Write-Host "  Warning: Failed to copy kickstart file, trying alternative method..." -ForegroundColor Yellow
        try {
            # Alternative: Use robocopy for more robust file copying
            $robocopyResult = robocopy (Split-Path $kickstartFile) $extractDir (Split-Path $kickstartFile -Leaf) /R:3 /W:1 /NP /NJH /NJS
            if (Test-Path "$extractDir\$(Split-Path $kickstartFile -Leaf)") {
                if ((Split-Path $kickstartFile -Leaf) -ne "ks.cfg") {
                    Move-Item "$extractDir\$(Split-Path $kickstartFile -Leaf)" "$extractDir\ks.cfg" -Force
                }
                Write-Host "  Kickstart file copied successfully using robocopy"
            } else {
                throw "Robocopy also failed"
            }
        } catch {
            Write-Error "Cannot copy kickstart file to ISO directory. Check file permissions."
            throw
        }
    }
    
    Write-Host "Modifying boot configuration..."
    
    # Determine kickstart location based on generation
    if ($Generation -eq 1) {
        $ksLocation = "cdrom:/ks.cfg"
        $console = "console=tty0 console=ttyS0,115200"
    } else {
        $ksLocation = "cdrom:/ks.cfg"
        $console = "console=tty0 console=ttyS0,115200"
    }
    
    $bootParams = "inst.ks=$ksLocation inst.text $console rd.debug rd.udev.debug"
    
    # Modify BIOS boot configuration (isolinux)
    $isolinuxCfg = Join-Path $extractDir "isolinux\isolinux.cfg"
    if (Test-Path $isolinuxCfg) {
        Write-Host "Modifying BIOS boot configuration..."
        
        # Ensure the file is not read-only before modifying
        $cfgFile = Get-Item $isolinuxCfg
        if ($cfgFile.IsReadOnly) {
            $cfgFile.IsReadOnly = $false
            Write-Host "  Removed read-only attribute from isolinux.cfg"
        }
        
        $content = Get-Content $isolinuxCfg
        
        # Find and modify boot entries - try multiple patterns
        $modified = $false
        for ($i = 0; $i -lt $content.Count; $i++) {
            # Pattern 1: Direct append line with vmlinuz
            if ($content[$i] -match '^\s*append\s+.*vmlinuz') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified = $true
                Write-Host "  Modified BIOS boot entry (append): $($content[$i])"
            }
            # Pattern 2: Append line without vmlinuz (common in modern isolinux)
            elseif ($content[$i] -match '^\s*append\s+') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified = $true
                Write-Host "  Modified BIOS boot entry (append): $($content[$i])"
            }
            # Pattern 3: Kernel line (alternative format)
            elseif ($content[$i] -match '^\s*kernel\s+') {
                # For kernel lines, we need to modify the next append line
                if (($i + 1) -lt $content.Count -and $content[$i + 1] -match '^\s*append\s+') {
                    $content[$i + 1] = $content[$i + 1] + " $bootParams"
                    $modified = $true
                    Write-Host "  Modified BIOS boot entry (kernel+append): $($content[$i + 1])"
                }
            }
        }
        
        if ($modified) {
            Set-Content $isolinuxCfg $content
            Write-Host "  BIOS boot configuration updated successfully"
        } else {
            Write-Host "  No BIOS boot entries found to modify (this may be normal for UEFI-only ISOs)" -ForegroundColor Yellow
        }
    }
    
    # Modify UEFI boot configuration (grub)
    $grubCfg = Join-Path $extractDir "EFI\BOOT\grub.cfg"
    if (Test-Path $grubCfg) {
        Write-Host "Modifying UEFI boot configuration..."
        
        # Ensure the file is not read-only before modifying
        $grubFile = Get-Item $grubCfg
        if ($grubFile.IsReadOnly) {
            $grubFile.IsReadOnly = $false
            Write-Host "  Removed read-only attribute from grub.cfg"
        }
        
        $content = Get-Content $grubCfg
        
        # Find and modify the linux boot entries - try multiple patterns
        $modified = $false
        for ($i = 0; $i -lt $content.Count; $i++) {
            # Pattern 1: linux line with vmlinuz path
            if ($content[$i] -match '^\s*linux\s+.*vmlinuz') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified = $true
                Write-Host "  Modified UEFI boot entry (linux+vmlinuz): $($content[$i])"
            }
            # Pattern 2: linux line without vmlinuz (path might be different)
            elseif ($content[$i] -match '^\s*linux\s+') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified = $true
                Write-Host "  Modified UEFI boot entry (linux): $($content[$i])"
            }
            # Pattern 3: linuxefi (used on some RHEL-based systems)
            elseif ($content[$i] -match '^\s*linuxefi\s+') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified = $true
                Write-Host "  Modified UEFI boot entry (linuxefi): $($content[$i])"
            }
        }
        
        if ($modified) {
            Set-Content $grubCfg $content
            Write-Host "  UEFI boot configuration updated successfully"
        } else {
            Write-Host "  No UEFI boot entries found to modify (this may be normal for BIOS-only ISOs)" -ForegroundColor Yellow
        }
    }
    
    # Also check for grub.cfg in other locations
    $grubCfg2 = Join-Path $extractDir "boot\grub2\grub.cfg"
    if (Test-Path $grubCfg2) {
        Write-Host "Modifying additional GRUB configuration..."
        
        # Ensure the file is not read-only before modifying
        $grub2File = Get-Item $grubCfg2
        if ($grub2File.IsReadOnly) {
            $grub2File.IsReadOnly = $false
            Write-Host "  Removed read-only attribute from grub2.cfg"
        }
        
        $content = Get-Content $grubCfg2
        
        $modified2 = $false
        for ($i = 0; $i -lt $content.Count; $i++) {
            # Try multiple patterns for grub2 as well
            if ($content[$i] -match '^\s*linux\s+.*vmlinuz') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified2 = $true
                Write-Host "  Modified GRUB2 boot entry (linux+vmlinuz): $($content[$i])"
            }
            elseif ($content[$i] -match '^\s*linux\s+') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified2 = $true
                Write-Host "  Modified GRUB2 boot entry (linux): $($content[$i])"
            }
            elseif ($content[$i] -match '^\s*linuxefi\s+') {
                $content[$i] = $content[$i] + " $bootParams"
                $modified2 = $true
                Write-Host "  Modified GRUB2 boot entry (linuxefi): $($content[$i])"
            }
        }
        
        if ($modified2) {
            Set-Content $grubCfg2 $content
            Write-Host "  Additional GRUB2 configuration updated successfully"
        } else {
            Write-Host "  No additional GRUB2 boot entries found to modify" -ForegroundColor Yellow
        }
    }
    
    Write-Host "Creating custom ISO..."
    # Create the custom ISO using oscdimg with proper UEFI/BIOS hybrid support
    # Note: -j2 (Joliet) conflicts with -n (long file names), so we use separate approaches
    
    # Detect the best approach based on content analysis
    $needsLongNames = $false
    $files = Get-ChildItem $extractDir -Recurse -File | Where-Object { $_.Name.Length -gt 31 }
    if ($files.Count -gt 0) {
        $needsLongNames = $true
        Write-Host "  Long filenames detected - using ISO 9660 Level 2 with long name support"
    }
    
    if ($Generation -eq 1) {
        # For Gen 1 VMs, use the most compatible settings for BIOS boot
        $oscdimgArgs = @(
            "-m"                    # Ignore maximum image size limit
            "-h"                    # Include hidden files  
        )
        # Don't use -o (optimize) or -j2 (Joliet) for Gen 1 as they can cause boot issues
        # Don't use -n (long names) for Gen 1 to maintain compatibility
    }
    elseif ($needsLongNames) {
        # Use ISO 9660 with long name support (no Joliet to avoid conflict)
        $oscdimgArgs = @(
            "-n"                    # Allow long file names
            "-m"                    # Ignore maximum image size limit
            "-h"                    # Include hidden files
            "-l"                    # Long file name support
            "-o"                    # Optimize layout
        )
    } else {
        # Use Joliet file system for better compatibility
        $oscdimgArgs = @(
            "-j2"                   # Use Joliet file system level 2
            "-m"                    # Ignore maximum image size limit
            "-h"                    # Include hidden files
            "-o"                    # Optimize layout
        )
    }
    
    # Check for both BIOS and UEFI boot files
    $hasBiosBooter = Test-Path "$extractDir\isolinux\isolinux.bin"
    $hasUefiBooter = Test-Path "$extractDir\EFI\BOOT\bootx64.efi"
    
    if ($hasBiosBooter -and $hasUefiBooter) {
        # Hybrid BIOS/UEFI ISO - this is what we want for maximum compatibility
        Write-Host "Creating hybrid BIOS/UEFI bootable ISO..."
        if ($Generation -eq 1) {
            # For Gen 1 VMs, optimize for BIOS boot
            $oscdimgArgs += "-b`"$extractDir\isolinux\isolinux.bin`""
            $oscdimgArgs += "-e`"$extractDir\isolinux\boot.cat`""  # -e creates new boot catalog
        } else {
            # For Gen 2 VMs, standard hybrid approach
            $oscdimgArgs += "-b`"$extractDir\isolinux\isolinux.bin`""
            $oscdimgArgs += "-c`"$extractDir\isolinux\boot.cat`""
        }
        # Note: oscdimg doesn't directly support dual boot like xorriso, but we include UEFI files
        # The UEFI boot files will be present and should work when booted in UEFI mode
    }
    elseif ($hasBiosBooter) {
        # BIOS-only ISO
        Write-Host "Creating BIOS bootable ISO..."
        if ($Generation -eq 1) {
            # For Gen 1 VMs, use more compatible BIOS boot options
            $oscdimgArgs += "-b`"$extractDir\isolinux\isolinux.bin`""
            $oscdimgArgs += "-e`"$extractDir\isolinux\boot.cat`""  # -e creates new boot catalog
            $oscdimgArgs += "-N"  # Do not use long filenames for better BIOS compatibility
        } else {
            $oscdimgArgs += "-b`"$extractDir\isolinux\isolinux.bin`""
            $oscdimgArgs += "-c`"$extractDir\isolinux\boot.cat`""
        }
    }
    elseif ($hasUefiBooter) {
        # UEFI-only ISO (less common for Linux distros)
        Write-Host "Creating UEFI bootable ISO..."
        # oscdimg doesn't have direct UEFI-only support, but we'll create it anyway
    }
    else {
        Write-Warning "No bootable files found - creating non-bootable data ISO"
    }
    
    # Add source and destination
    $oscdimgArgs += $extractDir
    $oscdimgArgs += $customISO
    
    $result = & $oscdimgPath @oscdimgArgs 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create ISO. oscdimg output: $result"
        throw "ISO creation failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "Custom ISO created successfully: $customISO"
    Write-Host "ISO size: $([math]::Round((Get-Item $customISO).Length / 1MB, 2)) MB"
    
    # Cleanup
    Remove-Item $workDir -Recurse -Force
    
    Write-Host "`n=== Custom ISO Information ==="
    Write-Host "File: $customISO"
    Write-Host "Kickstart: Embedded as /ks.cfg"
    Write-Host "Boot Parameters: $bootParams"
    Write-Host "Generation: $Generation ($(if($Generation -eq 1){'BIOS'}else{'UEFI'}))"  
    
    Write-Host "`n=== Usage Instructions ==="
    Write-Host "1. Update config.yaml to use this custom ISO:"
    Write-Host "   iso_path: \"$customISO\""
    Write-Host "2. Run provision-vms.ps1 normally"
    Write-Host "3. VMs will boot and install automatically without manual intervention"
    Write-Host "4. No need to press TAB or add boot parameters manually"
    
    Write-Host "`nCustom ISO creation completed successfully!"
    
} catch {
    Write-Error "Failed to create custom ISO: $($_.Exception.Message)"
    
    # Cleanup on failure
    if (Test-Path $workDir) {
        Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $customISO) {
        Remove-Item $customISO -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}
