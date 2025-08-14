# Simplified AlmaLinux VM Provisioning Script
#
# This version creates VMs with minimal configuration to avoid the 0x80041008 error
#

# Load configuration function
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

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent

# Extract settings
$vmPrefix = $config["vm_prefix"]
$vmCount = $config["vm_count"]
$vmMemory = $config["vm_memory"]
$vmVHDSizeGB = $config["vm_disk_size_gb"]
$vmSwitchName = $config["vm_switch"]
$vmGeneration = $config["vm_generation"]
$vmPath = $config["vm_path"]
$vhdPath = $config["vhd_path"]
$isoPath = $config["iso_path"]

Write-Host "=== Simplified VM Provisioning ===" -ForegroundColor Cyan
Write-Host "Creating $vmCount VMs with Generation $vmGeneration"
Write-Host "Memory: $($vmMemory/1GB) GB, Disk: $vmVHDSizeGB GB"
Write-Host ""

# Create directories
New-Item -ItemType Directory -Path $vmPath, $vhdPath -Force | Out-Null

# Provision each VM
for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "$vmPrefix-$i"
    $vhdFile = "$vhdPath\$vmName.vhdx"
    
    Write-Host "Creating VM: $vmName" -ForegroundColor Green
    
    try {
        # Step 1: Create VHD first
        Write-Host "  1. Creating VHD..."
        if (Test-Path $vhdFile) {
            Remove-Item $vhdFile -Force
        }
        New-VHD -Path $vhdFile -SizeBytes ($vmVHDSizeGB * 1GB) -Dynamic | Out-Null
        
        # Step 2: Create VM with absolute minimum parameters
        Write-Host "  2. Creating VM..."
        $vm = New-VM -Name $vmName -MemoryStartupBytes $vmMemory -Generation $vmGeneration -NoVHD -Path $vmPath
        
        # Step 3: Add hard disk
        Write-Host "  3. Adding hard disk..."
        Add-VMHardDiskDrive -VMName $vmName -Path $vhdFile
        
        # Step 4: Configure DVD drive with ISO
        Write-Host "  4. Configuring DVD drive..."
        $dvdDrive = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue
        if ($dvdDrive) {
            # Use existing DVD drive
            Set-VMDvdDrive -VMName $vmName -ControllerNumber $dvdDrive.ControllerNumber -ControllerLocation $dvdDrive.ControllerLocation -Path $isoPath
            Write-Host "    Using existing DVD drive"
        } else {
            # Add new DVD drive
            Add-VMDvdDrive -VMName $vmName -Path $isoPath
            Write-Host "    Added new DVD drive"
        }
        
        # Step 5: Connect to network (if switch exists)
        Write-Host "  5. Configuring network..."
        try {
            Get-VMSwitch -Name $vmSwitchName -ErrorAction Stop | Out-Null
            Connect-VMNetworkAdapter -VMName $vmName -SwitchName $vmSwitchName
            Write-Host "    Connected to switch: $vmSwitchName"
        } catch {
            Write-Warning "    Switch '$vmSwitchName' not found, using default networking"
        }
        
        # Step 6: Configure generation-specific settings
        Write-Host "  6. Configuring VM settings..."
        if ($vmGeneration -eq 2) {
            # Gen 2 specific settings
            Set-VMFirmware -VMName $vmName -EnableSecureBoot Off
            
            # Set DVD as first boot device
            $dvdDrive = Get-VMDvdDrive -VMName $vmName
            Set-VMFirmware -VMName $vmName -FirstBootDevice $dvdDrive
            
            Write-Host "    Gen 2: Disabled Secure Boot, Set DVD boot"
        } else {
            # Gen 1 specific settings
            Set-VMBios -VMName $vmName -StartupOrder @("CD", "IDE")
            Write-Host "    Gen 1: Set boot order to CD, IDE"
        }
        
        # Step 7: Optional - Enable nested virtualization (don't fail if unsupported)
        Write-Host "  7. Configuring processor..."
        try {
            Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true
            Write-Host "    Enabled nested virtualization"
        } catch {
            Write-Host "    Nested virtualization not available (continuing)"
        }
        
        # Step 8: Start VM
        Write-Host "  8. Starting VM..."
        Start-VM -Name $vmName
        
        Write-Host "  VM $vmName created successfully!" -ForegroundColor Green
        Write-Host ""
        
    } catch {
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
        } catch {
            Write-Warning "Cleanup failed for $vmName"
        }
    }
}

Write-Host "=== VM Creation Complete ===" -ForegroundColor Cyan
Write-Host "Check VM status: Get-VM $vmPrefix-*"
Write-Host "View console: vmconnect localhost <vmname>"
Write-Host ""
Write-Host "IMPORTANT: VMs are booting from ISO"
if ($vmGeneration -eq 1) {
    Write-Host "Gen 1 VMs: Press TAB at boot menu and add kickstart parameters"
} else {
    Write-Host "Gen 2 VMs: Press TAB or 'e' at boot menu and add kickstart parameters"
}
Write-Host "Example: inst.ks=cdrom:/ks.cfg inst.text console=ttyS0,115200"
