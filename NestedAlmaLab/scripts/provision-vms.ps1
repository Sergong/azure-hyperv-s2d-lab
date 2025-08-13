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

# Function to create a virtual floppy disk with kickstart file
function New-KickstartFloppy {
    param(
        [string]$KickstartPath,
        [string]$FloppyPath
    )
    
    Write-Host "Creating kickstart floppy disk: $FloppyPath"
    
    # Create a 1.44MB floppy disk image
    $floppySize = 1440KB
    $floppy = New-VHD -Path $FloppyPath -SizeBytes $floppySize -Fixed
    
    # Mount the VHD to copy the kickstart file
    $mountResult = Mount-VHD -Path $FloppyPath -Passthru
    $driveLetter = ($mountResult | Get-Disk | Get-Partition | Get-Volume).DriveLetter
    
    if ($driveLetter) {
        # Format the floppy disk
        Format-Volume -DriveLetter $driveLetter -FileSystem FAT -Confirm:$false | Out-Null
        
        # Copy kickstart file to floppy
        Copy-Item $KickstartPath "${driveLetter}:\ks.cfg"
        
        Write-Host "Copied kickstart file to floppy disk"
    }
    
    # Unmount the VHD
    Dismount-VHD -Path $FloppyPath
    
    return $FloppyPath
}

# Create folders
New-Item -ItemType Directory -Path $vmPath, $vhdPath -Force | Out-Null

# Create a temporary directory for kickstart floppy disks
$ksFloppyPath = "$vhdPath\Kickstart"
New-Item -ItemType Directory -Path $ksFloppyPath -Force | Out-Null

# Provision VMs with AlmaLinux ISO and Kickstart
for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "$vmPrefix-$i"
    $vhdFile = "$vhdPath\$vmName.vhdx"
    $floppyFile = "$ksFloppyPath\$vmName-ks.vhd"
    
    Write-Host "Creating VM: $vmName"
    
    # Create kickstart floppy for this VM
    New-KickstartFloppy -KickstartPath $ksPath -FloppyPath $floppyFile

    # Create VM
    Write-Host "  Creating VHD: $vhdFile"
    New-VHD -Path $vhdFile -SizeBytes ($vmVHDSizeGB * 1GB) -Dynamic | Out-Null
    
    Write-Host "  Creating VM with $($vmMemory / 1GB) GB RAM"
    New-VM -Name $vmName -MemoryStartupBytes $vmMemory -Generation $vmGeneration `
           -SwitchName $vmSwitchName -Path $vmPath | Out-Null
    
    # Attach storage
    Add-VMHardDiskDrive -VMName $vmName -Path $vhdFile
    
    # Configure VM settings
    Set-VMFirmware -VMName $vmName -EnableSecureBoot Off
    Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true
    
    # Mount AlmaLinux ISO
    Write-Host "  Attaching AlmaLinux ISO"
    Add-VMDvdDrive -VMName $vmName -Path $isoPath
    
    # Attach kickstart floppy
    Write-Host "  Attaching kickstart floppy"
    Add-VMFloppyDiskDrive -VMName $vmName -Path $floppyFile
    
    # Configure boot order and parameters
    if ($vmGeneration -eq 2) {
        # For Generation 2 VMs, configure boot from DVD
        $dvdDrive = Get-VMDvdDrive -VMName $vmName
        Set-VMFirmware -VMName $vmName -FirstBootDevice $dvdDrive
        
        # Add automatic console configuration for headless installation
        Add-VMKeyValuePair -VMName $vmName -Name "KickstartParameters" -Value "inst.ks=hd:fd0:/ks.cfg inst.text inst.headless console=ttyS0,115200"
        
        Write-Host "  Configured Gen 2 VM with kickstart boot parameters"
        Write-Host "  Boot parameters: inst.ks=hd:fd0:/ks.cfg inst.text inst.headless console=ttyS0,115200"
        Write-Host "  Note: The installer will use these parameters automatically for kickstart"
    } else {
        # For Generation 1 VMs, set boot order
        Set-VMBios -VMName $vmName -StartupOrder @("CD", "Floppy", "IDE")
        Write-Host "  Configured Gen 1 VM boot order: CD, Floppy, IDE"
    }
    
    Write-Host "  Starting VM for automated installation"
    Start-VM -Name $vmName
    
    Write-Host "  VM $vmName created and started`n"
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

