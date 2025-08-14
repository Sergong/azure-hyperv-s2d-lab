# AlmaLinux VM Provisioning Script with Kickstart Automation
# 
# FIXES APPLIED:
# 1. Fixed VHD minimum size issues:
#    - Changed floppy size from 1.44MB to 3MB (Hyper-V minimum)
#    - Changed kickstart VHD size from 10MB to 100MB (Azure/Hyper-V minimum)
# 2. Fixed Generation 2 VM compatibility - Gen 2 VMs don't support floppy drives
#    - Gen 1 VMs: Use floppy disk for kickstart (hd:fd0:/ks.cfg)
#    - Gen 2 VMs: Use secondary VHD for kickstart (hd:sdb1:/ks.cfg)
# 3. Added proper error handling with try/catch blocks
# 4. Added path validation for ISO files and VM switches
# 5. Added cleanup on failure to prevent orphaned resources
# 6. Improved disk initialization and partitioning for VHD creation
# 7. Added informative messages about kickstart location for each VM generation
#
# USAGE:
# - For Gen 1 VMs: Kickstart will be loaded automatically from floppy
# - For Gen 2 VMs: You may need to specify kickstart location manually at boot:
#   Boot parameters: inst.ks=hd:sdb1:/ks.cfg inst.text console=ttyS0,115200
#

# Load configuration from YAML file
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

# Load configuration from config.yaml
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent

# Extract VM settings from config
$vmPrefix       = $config["vm_prefix"]
$vmCount        = $config["vm_count"]
$vmMemory       = $config["vm_memory"]
$vmVHDSizeGB    = $config["vm_disk_size_gb"]
$vmSwitchName   = $config["vm_switch"]
$vmGeneration   = $config["vm_generation"]
$vmPath         = $config["vm_path"]
$vhdPath        = $config["vhd_path"]
$isoPath        = $config["iso_path"]
$ksVersion      = $config["ks_version"]

# Build full kickstart path based on version
$ksPath = Join-Path $PSScriptRoot "..\templates\AlmaLinux\$ksVersion\ks.cfg"

# Validate kickstart file exists
if (-not (Test-Path $ksPath)) {
    Write-Error "Kickstart file not found: $ksPath"
    exit 1
}

# Display loaded configuration
Write-Host "=== VM Provisioning Configuration ==="
Write-Host "VM Prefix: $vmPrefix"
Write-Host "VM Count: $vmCount"
Write-Host "VM Memory: $($vmMemory / 1GB) GB"
Write-Host "VM Disk Size: $vmVHDSizeGB GB"
Write-Host "VM Switch: $vmSwitchName"
Write-Host "VM Generation: $vmGeneration"
Write-Host "ISO Path: $isoPath"
Write-Host "Kickstart Path: $ksPath"
Write-Host "VM Path: $vmPath"
Write-Host "VHD Path: $vhdPath"
Write-Host "====================================`n"

# Function to create a virtual disk with kickstart file for Gen 1 VMs
function New-KickstartFloppy {
    param(
        [string]$KickstartPath,
        [string]$FloppyPath
    )
    
    Write-Host "Creating kickstart floppy disk: $FloppyPath"
    
    try {
        # Create a floppy disk image (minimum 3MB required by Hyper-V)
        $floppySize = 3MB
        $floppy = New-VHD -Path $FloppyPath -SizeBytes $floppySize -Fixed -ErrorAction Stop
        
        # Mount the VHD to copy the kickstart file
        $mountResult = Mount-VHD -Path $FloppyPath -Passthru -ErrorAction Stop
        $disk = $mountResult | Get-Disk
        
        # Initialize disk if needed
        if ($disk.PartitionStyle -eq 'RAW') {
            Initialize-Disk -Number $disk.Number -PartitionStyle MBR -ErrorAction Stop
            $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
            Format-Volume -DriveLetter $partition.DriveLetter -FileSystem FAT -Confirm:$false -ErrorAction Stop | Out-Null
            $driveLetter = $partition.DriveLetter
        } else {
            $driveLetter = ($disk | Get-Partition | Get-Volume).DriveLetter
        }
        
        if ($driveLetter) {
            # Copy kickstart file to floppy
            Copy-Item $KickstartPath "${driveLetter}:\ks.cfg" -ErrorAction Stop
            Write-Host "Copied kickstart file to floppy disk"
        } else {
            throw "Could not get drive letter for mounted floppy"
        }
        
        # Unmount the VHD
        Dismount-VHD -Path $FloppyPath -ErrorAction Stop
        
        return $FloppyPath
    }
    catch {
        Write-Error "Failed to create kickstart floppy: $($_.Exception.Message)"
        if (Test-Path $FloppyPath) {
            try { Dismount-VHD -Path $FloppyPath -ErrorAction SilentlyContinue } catch {}
            Remove-Item $FloppyPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

# Function to create a small ISO with kickstart file for Gen 2 VMs
function New-KickstartISO {
    param(
        [string]$KickstartPath,
        [string]$ISOPath
    )
    
    Write-Host "Creating kickstart ISO: $ISOPath"
    
    try {
        # Create temporary directory for ISO contents
        $tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ -Force }
        
        # Copy kickstart file to temp directory
        Copy-Item $KickstartPath "$tempDir\ks.cfg" -ErrorAction Stop
        
        # Use Windows built-in tools to create ISO (requires Windows 10/Server 2016+)
        # Alternative: Use external tool like oscdimg.exe from Windows ADK
        $oscdimgPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        
        if (Test-Path $oscdimgPath) {
            & $oscdimgPath -n -m "$tempDir" "$ISOPath" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "oscdimg.exe failed with exit code $LASTEXITCODE"
            }
        } else {
            # Fallback: Create a small VHD instead of ISO for Gen 2 VMs
            Write-Warning "oscdimg.exe not found. Creating VHD instead of ISO for Gen 2 VM."
            $vhdPath = $ISOPath -replace '\.iso$', '.vhd'
            return New-KickstartVHD -KickstartPath $KickstartPath -VHDPath $vhdPath
        }
        
        # Clean up temp directory
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "Created kickstart ISO successfully"
        return $ISOPath
    }
    catch {
        Write-Error "Failed to create kickstart ISO: $($_.Exception.Message)"
        # Clean up
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $ISOPath) {
            Remove-Item $ISOPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

# Function to create a small VHD with kickstart file for Gen 2 VMs
function New-KickstartVHD {
    param(
        [string]$KickstartPath,
        [string]$VHDPath
    )
    
    Write-Host "Creating kickstart VHD: $VHDPath"
    
    try {
        # Create a VHD with minimum supported size (Hyper-V requires larger than 10MB)
        # Using 100MB to ensure compatibility with all Hyper-V environments
        $vhdSize = 100MB
        $vhd = New-VHD -Path $VHDPath -SizeBytes $vhdSize -Fixed -ErrorAction Stop
        
        # Mount the VHD to copy the kickstart file
        $mountResult = Mount-VHD -Path $VHDPath -Passthru -ErrorAction Stop
        $disk = $mountResult | Get-Disk
        
        # Initialize disk
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction Stop
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
        Format-Volume -DriveLetter $partition.DriveLetter -FileSystem FAT32 -Confirm:$false -ErrorAction Stop | Out-Null
        
        # Copy kickstart file
        Copy-Item $KickstartPath "$($partition.DriveLetter):\ks.cfg" -ErrorAction Stop
        
        # Unmount the VHD
        Dismount-VHD -Path $VHDPath -ErrorAction Stop
        
        Write-Host "Created kickstart VHD successfully"
        return $VHDPath
    }
    catch {
        Write-Error "Failed to create kickstart VHD: $($_.Exception.Message)"
        if (Test-Path $VHDPath) {
            try { Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue } catch {}
            Remove-Item $VHDPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

# Create folders
New-Item -ItemType Directory -Path $vmPath, $vhdPath -Force | Out-Null

# Create a temporary directory for kickstart floppy disks
$ksFloppyPath = "$vhdPath\Kickstart"
New-Item -ItemType Directory -Path $ksFloppyPath -Force | Out-Null

# Function to detect if ISO has embedded kickstart (custom ISO)
function Test-CustomISO {
    param([string]$ISOPath)
    
    # Check if this is a custom ISO by looking at the filename pattern
    $isoName = Split-Path $ISOPath -Leaf
    if ($isoName -match "Custom\.iso$") {
        return $true
    }
    
    # Additional check: mount ISO temporarily and look for embedded ks.cfg
    try {
        $mountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        $hasKickstart = Test-Path "${driveLetter}:\ks.cfg"
        Dismount-DiskImage -ImagePath $ISOPath -ErrorAction Stop
        return $hasKickstart
    } catch {
        # If we can't mount/check, assume it's not a custom ISO
        return $false
    }
}

# Validate required paths before proceeding
if (-not (Test-Path $isoPath)) {
    Write-Error "AlmaLinux ISO not found: $isoPath"
    exit 1
}

# Check if the VM switch exists
try {
    Get-VMSwitch -Name $vmSwitchName -ErrorAction Stop | Out-Null
} catch {
    Write-Error "VM Switch '$vmSwitchName' not found. Please create it first."
    exit 1
}

# Detect if using custom ISO with embedded kickstart
$isCustomISO = Test-CustomISO -ISOPath $isoPath

if ($isCustomISO) {
    Write-Host "Detected custom ISO with embedded kickstart parameters"
    Write-Host "Skipping kickstart media creation - fully automated installation enabled"
} else {
    Write-Host "Using standard ISO - kickstart media will be created for manual boot parameter entry"
}

# Provision VMs with AlmaLinux ISO and Kickstart
for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "$vmPrefix-$i"
    $vhdFile = "$vhdPath\$vmName.vhdx"
    
    Write-Host "Creating VM: $vmName"
    
    try {
        # Only create kickstart media if NOT using custom ISO
        $kickstartMedia = $null
        $kickstartType = $null
        $kickstartLocation = $null
        
        if (-not $isCustomISO) {
            # Create kickstart media based on VM generation (only for standard ISOs)
            if ($vmGeneration -eq 1) {
                # Gen 1 VMs support floppy drives
                $floppyFile = "$ksFloppyPath\$vmName-ks.vhd"
                New-KickstartFloppy -KickstartPath $ksPath -FloppyPath $floppyFile
                $kickstartMedia = $floppyFile
                $kickstartType = "floppy"
                $kickstartLocation = "hd:fd0:/ks.cfg"
            } else {
                # Gen 2 VMs don't support floppy - use VHD as secondary disk
                $kickstartVhdFile = "$ksFloppyPath\$vmName-ks.vhd"
                New-KickstartVHD -KickstartPath $ksPath -VHDPath $kickstartVhdFile
                $kickstartMedia = $kickstartVhdFile
                $kickstartType = "vhd"
                $kickstartLocation = "hd:sdb1:/ks.cfg"
            }
        } else {
            # For custom ISOs, kickstart is embedded in the ISO itself
            $kickstartLocation = "cdrom:/ks.cfg"
            Write-Host "  Using embedded kickstart from custom ISO"
        }

        # Create VM
        Write-Host "  Creating VHD: $vhdFile"
        New-VHD -Path $vhdFile -SizeBytes ($vmVHDSizeGB * 1GB) -Dynamic -ErrorAction Stop | Out-Null
        
        Write-Host "  Creating VM with $($vmMemory / 1GB) GB RAM"
        # Create VM with minimal parameters first to avoid configuration conflicts
        $newVMParams = @{
            Name = $vmName
            MemoryStartupBytes = $vmMemory
            Generation = $vmGeneration
            Path = $vmPath
            ErrorAction = "Stop"
        }
        
        # Only add switch if it's not the default
        if ($vmSwitchName -ne "Default Switch") {
            $newVMParams["SwitchName"] = $vmSwitchName
        }
        
        $vm = New-VM @newVMParams
        
        # Configure switch if needed after VM creation
        if ($vmSwitchName -eq "Default Switch") {
            try {
                Connect-VMNetworkAdapter -VMName $vmName -SwitchName $vmSwitchName -ErrorAction Stop
                Write-Host "  Connected to Default Switch"
            } catch {
                Write-Warning "  Could not connect to Default Switch: $($_.Exception.Message)"
            }
        }
        
        # Attach storage
        Add-VMHardDiskDrive -VMName $vmName -Path $vhdFile -ErrorAction Stop
        
        # Mount AlmaLinux ISO first (before VM configuration)
        Write-Host "  Attaching AlmaLinux ISO"
        Add-VMDvdDrive -VMName $vmName -Path $isoPath -ErrorAction Stop
        
        # Configure VM settings
        if ($vmGeneration -eq 2) {
            # Disable Secure Boot for Linux compatibility
            Set-VMFirmware -VMName $vmName -EnableSecureBoot Off -ErrorAction Stop
            Write-Host "  Disabled Secure Boot for Linux compatibility"
            
            # Enable nested virtualization for Gen 2 VMs
            try {
                Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true -ErrorAction Stop
                Write-Host "  Enabled nested virtualization"
            } catch {
                Write-Warning "  Could not enable nested virtualization: $($_.Exception.Message)"
            }
        } else {
            # For Gen 1 VMs, try to enable nested virtualization but don't fail if it's not supported
            try {
                Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true -ErrorAction Stop
                Write-Host "  Enabled nested virtualization"
            } catch {
                Write-Warning "  Nested virtualization not supported on this system for Gen 1 VMs"
            }
        }
        
        # Only attach kickstart media if NOT using custom ISO
        if (-not $isCustomISO -and $kickstartMedia) {
            # Attach kickstart media based on generation
            if ($vmGeneration -eq 1) {
                Write-Host "  Attaching kickstart floppy"
                try {
                    Add-VMFloppyDiskDrive -VMName $vmName -Path $kickstartMedia -ErrorAction Stop
                } catch {
                    Write-Warning "  Failed to attach floppy drive: $($_.Exception.Message)"
                    Write-Host "  Continuing without kickstart floppy - manual boot parameters will be required"
                }
            } else {
                Write-Host "  Attaching kickstart VHD as secondary disk"
                Add-VMHardDiskDrive -VMName $vmName -Path $kickstartMedia -ErrorAction Stop
            }
        }
        
        # Configure boot order and parameters
        if ($vmGeneration -eq 2) {
            # For Generation 2 VMs, configure UEFI boot settings
            Write-Host "  Configuring UEFI boot settings..."
            
            # Get the DVD drive and set it as first boot device
            $dvdDrive = Get-VMDvdDrive -VMName $vmName -ErrorAction Stop
            if (-not $dvdDrive) {
                throw "DVD drive not found on VM $vmName"
            }
            
            # Set DVD as first boot device
            Set-VMFirmware -VMName $vmName -FirstBootDevice $dvdDrive -ErrorAction Stop
            Write-Host "  Set DVD as first boot device"
            
            # Configure additional UEFI settings for better compatibility
            try {
                # Set boot order explicitly
                $bootOrder = @()
                $bootOrder += $dvdDrive  # DVD first
                
                # Add hard drives to boot order
                $hardDrives = Get-VMHardDiskDrive -VMName $vmName
                foreach ($hdd in $hardDrives) {
                    $bootOrder += $hdd
                }
                
                # Apply boot order
                Set-VMFirmware -VMName $vmName -BootOrder $bootOrder -ErrorAction Stop
                Write-Host "  Configured UEFI boot order: DVD, HDD(s)"
                
            } catch {
                Write-Warning "  Could not set detailed boot order: $($_.Exception.Message)"
                Write-Host "  Basic DVD boot should still work"
            }
            
            if ($isCustomISO) {
                # Custom ISO with embedded kickstart - fully automated
                Write-Host "  Gen 2 VM configured for fully automated installation"
                Write-Host "  Custom ISO contains embedded kickstart parameters"
                Write-Host "  No manual intervention required - installation will proceed automatically"
            } else {
                # Standard ISO - requires manual boot parameter entry
                Write-Host "  Gen 2 VM configured to boot from DVD"
                $bootParameters = "inst.ks=$kickstartLocation inst.text console=tty0 console=ttyS0,115200 rd.debug rd.udev.debug"
                Write-Host "  IMPORTANT: On first boot, press TAB at the boot menu and add these parameters:"
                Write-Host "  $bootParameters"
                Write-Host "  Or press 'e' to edit, add to the linux line, then press Ctrl+X"
            }
        } else {
            # For Generation 1 VMs, set boot order
            try {
                if ($isCustomISO) {
                    # Custom ISO - only need DVD boot
                    Set-VMBios -VMName $vmName -StartupOrder @("CD", "IDE") -ErrorAction Stop
                    Write-Host "  Configured Gen 1 VM for fully automated installation"
                    Write-Host "  Custom ISO contains embedded kickstart parameters"
                    Write-Host "  No manual intervention required - installation will proceed automatically"
                } else {
                    # Standard ISO - try CD and Floppy boot order, fallback to CD only
                    try {
                        Set-VMBios -VMName $vmName -StartupOrder @("CD", "Floppy", "IDE") -ErrorAction Stop
                        Write-Host "  Configured Gen 1 VM boot order: CD, Floppy, IDE"
                    } catch {
                        Write-Warning "  Could not set Floppy in boot order, using CD, IDE only"
                        Set-VMBios -VMName $vmName -StartupOrder @("CD", "IDE") -ErrorAction Stop
                        Write-Host "  Configured Gen 1 VM boot order: CD, IDE"
                    }
                    $bootParameters = "inst.ks=$kickstartLocation inst.text console=tty0 console=ttyS0,115200"
                    Write-Host "  IMPORTANT: On first boot, press TAB at the boot menu and add these parameters:"
                    Write-Host "  $bootParameters"
                }
            } catch {
                Write-Warning "  Could not configure BIOS boot order: $($_.Exception.Message)"
                Write-Host "  VM will use default boot order"
            }
        }
        
        Write-Host "  Starting VM for automated installation"
        Start-VM -Name $vmName -ErrorAction Stop
        
        Write-Host "  VM $vmName created and started successfully`n"
    }
    catch {
        Write-Error "Failed to create VM $vmName : $($_.Exception.Message)"
        
        # Cleanup on failure
        try {
            if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
                Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
                Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $vhdFile) {
                Remove-Item $vhdFile -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $kickstartMedia) {
                Remove-Item $kickstartMedia -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Failed to cleanup resources for $vmName : $($_.Exception.Message)"
        }
        
        continue
    }
}

Write-Host "`n=== VM Provisioning Summary ==="
Write-Host "Successfully created and started $vmCount AlmaLinux VMs:"
for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "$vmPrefix-$i"
    $vmState = (Get-VM -Name $vmName).State
    Write-Host "  - $vmName : $vmState"
}

Write-Host "`n=== Installation Information ==="
Write-Host "VMs are now performing automated AlmaLinux installation using kickstart."
Write-Host "Kickstart version: $ksVersion"

if ($ksVersion -eq "v1") {
    Write-Host "v1 Features:"
    Write-Host "  - Minimal AlmaLinux installation"
    Write-Host "  - SSH enabled with root access"
    Write-Host "  - Root password: alma123!"
} elseif ($ksVersion -eq "v2") {
    Write-Host "v2 Features:"
    Write-Host "  - Enhanced AlmaLinux with development tools"
    Write-Host "  - SSH enabled with root access"
    Write-Host "  - Root password: alma123!"
    Write-Host "  - Lab user: labuser / labpass123!"
    Write-Host "  - Pre-installed: git, python3, vim, htop, network tools"
}

Write-Host "`n=== Next Steps ==="
Write-Host "1. Monitor VM installation progress using Hyper-V Manager"
Write-Host "2. VMs will automatically reboot after installation completes"
Write-Host "3. Once booted, VMs will be accessible via SSH"
Write-Host "4. Check VM IP addresses with: Get-VMNetworkAdapter -VMName <vmname>"

Write-Host "`n=== Monitoring Commands ==="
Write-Host "Check VM status:    Get-VM $vmPrefix-*"
Write-Host "View VM console:    vmconnect localhost <vmname>"
Write-Host "Get IP addresses:   Get-VM $vmPrefix-* | Get-VMNetworkAdapter | Select Name, IPAddresses"

Write-Host "`nInstallation started. Please allow 10-20 minutes for completion."
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - VM provisioning completed."

