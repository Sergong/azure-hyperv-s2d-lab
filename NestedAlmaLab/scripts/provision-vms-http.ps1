# Simplified AlmaLinux VM Provisioning
# Uses standard ISO + HTTP-served kickstart (no custom ISO needed)

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("v1", "v2")]
    [string]$KickstartVersion = "v1",
    
    [Parameter(Mandatory=$false)]
    [switch]$StartKickstartServer
)

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

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
            } elseif ($value -match '^(\d+)(GB|MB|KB)$') {
                $size = [int]$matches[1]
                $unit = $matches[2]
                switch ($unit) {
                    "KB" { $config[$key] = $size * 1KB }
                    "MB" { $config[$key] = $size * 1MB }
                    "GB" { $config[$key] = $size * 1GB }
                }
            } else {
                $config[$key] = $value
            }
        }
    }
    return $config
}

$yamlContent = Get-Content $configPath -Raw
$config = ConvertFrom-Yaml -YamlContent $yamlContent

# Configuration
$vmPrefix = $config["vm_prefix"]
$vmCount = $config["vm_count"]
$vmMemory = $config["vm_memory"]
$vmVHDSizeGB = $config["vm_disk_size_gb"]
$vmSwitchName = $config["vm_switch"]
$vmGeneration = $config["vm_generation"]
$vmPath = $config["vm_path"]
$vhdPath = $config["vhd_path"]
$isoPath = $config["iso_path"]

# Get local IP for kickstart server
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
$kickstartPort = 8080
$kickstartURL = "http://${localIP}:${kickstartPort}/ks.cfg"

Write-Host "=== Simplified AlmaLinux VM Provisioning ===" -ForegroundColor Cyan
Write-Host "Using standard ISO + HTTP kickstart approach"
Write-Host "VM Count: $vmCount"
Write-Host "VM Generation: $vmGeneration"
Write-Host "Kickstart Version: $KickstartVersion"
Write-Host "Kickstart URL: $kickstartURL"
Write-Host "=========================================="

# Validate inputs
if (-not (Test-Path $isoPath)) {
    Write-Error "AlmaLinux ISO not found: $isoPath"
    exit 1
}

# Check VM switch
try {
    Get-VMSwitch -Name $vmSwitchName -ErrorAction Stop | Out-Null
} catch {
    Write-Error "VM Switch '$vmSwitchName' not found. Please create it first."
    exit 1
}

# Start kickstart server if requested
if ($StartKickstartServer) {
    Write-Host "Starting kickstart HTTP server..." -ForegroundColor Yellow
    Write-Host "Run the following command in a separate PowerShell window:"
    Write-Host ".\serve-kickstart.ps1 -Port $kickstartPort -KickstartVersion $KickstartVersion" -ForegroundColor Green
    Write-Host ""
    Read-Host "Press Enter when the kickstart server is running"
}

# Create directories
New-Item -ItemType Directory -Path $vmPath, $vhdPath -Force | Out-Null

# Function to create VMs with proper boot instructions
function New-LabVM {
    param(
        [string]$VMName,
        [string]$VHDFile,
        [string]$KickstartURL
    )
    
    Write-Host "Creating VM: $VMName" -ForegroundColor Yellow
    
    try {
        # Create VHD
        Write-Host "  Creating VHD: $VHDFile"
        New-VHD -Path $VHDFile -SizeBytes ($vmVHDSizeGB * 1GB) -Dynamic | Out-Null
        
        # Create VM
        Write-Host "  Creating VM with $($vmMemory / 1GB) GB RAM"
        $vm = New-VM -Name $VMName -MemoryStartupBytes $vmMemory -Generation $vmGeneration -Path $vmPath
        
        # Connect to switch
        if ($vmSwitchName -ne "Default Switch") {
            Connect-VMNetworkAdapter -VMName $VMName -SwitchName $vmSwitchName
        }
        
        # Attach storage
        Add-VMHardDiskDrive -VMName $VMName -Path $VHDFile
        Add-VMDvdDrive -VMName $VMName -Path $isoPath
        
        # Configure VM settings
        if ($vmGeneration -eq 2) {
            # Gen 2 configuration
            Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
            try {
                Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
                Write-Host "  Enabled nested virtualization"
            } catch {
                Write-Warning "  Could not enable nested virtualization"
            }
            
            # Set boot order
            $dvdDrive = Get-VMDvdDrive -VMName $VMName
            Set-VMFirmware -VMName $VMName -FirstBootDevice $dvdDrive
            
            Write-Host "  Gen 2 VM configured successfully"
            Write-Host "  Boot parameters to enter manually:" -ForegroundColor Yellow
            Write-Host "  inst.ks=$KickstartURL inst.text console=tty0 console=ttyS0,115200" -ForegroundColor Cyan
        } else {
            # Gen 1 configuration
            Set-VMBios -VMName $VMName -StartupOrder @("CD", "IDE")
            try {
                Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
                Write-Host "  Enabled nested virtualization"
            } catch {
                Write-Warning "  Could not enable nested virtualization"
            }
            
            Write-Host "  Gen 1 VM configured successfully"
            Write-Host "  Boot parameters to enter manually:" -ForegroundColor Yellow
            Write-Host "  inst.ks=$KickstartURL inst.text console=tty0 console=ttyS0,115200" -ForegroundColor Cyan
        }
        
        Write-Host "  VM $VMName created successfully`n" -ForegroundColor Green
        return $vm
        
    } catch {
        Write-Error "Failed to create VM ${VMName}: $($_.Exception.Message)"
        
        # Cleanup on failure
        try {
            if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
                Remove-VM -Name $VMName -Force
            }
            if (Test-Path $VHDFile) {
                Remove-Item $VHDFile -Force
            }
        } catch {
            Write-Warning "Failed to cleanup $VMName"
        }
        throw
    }
}

# Create VMs
$createdVMs = @()
for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "$vmPrefix-$i"
    $vhdFile = "$vhdPath\\$vmName.vhdx"
    
    try {
        $vm = New-LabVM -VMName $vmName -VHDFile $vhdFile -KickstartURL $kickstartURL
        $createdVMs += $vmName
    } catch {
        Write-Warning "Skipping VM $vmName due to error: $($_.Exception.Message)"
    }
}

Write-Host "`n=== VM Creation Summary ===" -ForegroundColor Green
Write-Host "Successfully created $($createdVMs.Count) out of $vmCount VMs:"
foreach ($vmName in $createdVMs) {
    $vmState = (Get-VM -Name $vmName).State
    Write-Host "  - $vmName : $vmState"
}

Write-Host "`n=== Installation Instructions ===" -ForegroundColor Yellow
Write-Host "1. Make sure the kickstart server is running:"
Write-Host "   .\serve-kickstart.ps1 -Port $kickstartPort -KickstartVersion $KickstartVersion"
Write-Host ""
Write-Host "2. Start each VM and when you see the AlmaLinux boot menu:"
Write-Host "   - Press TAB to edit boot parameters"
Write-Host "   - Add this to the end of the linux line:"
Write-Host "   inst.ks=$kickstartURL inst.text console=tty0 console=ttyS0,115200" -ForegroundColor Cyan
Write-Host "   - Press Enter to start installation"
Write-Host ""
Write-Host "3. Installation will proceed automatically (10-15 minutes)"
Write-Host "4. VMs will reboot and be ready for SSH access"

Write-Host "`n=== Alternative: Use Packer for Fully Automated Build ===" -ForegroundColor Magenta
Write-Host "For a completely automated approach, consider using Packer:"
Write-Host "1. Install Packer: winget install Packer"
Write-Host "2. Run: .\scripts\build-static-ip.ps1 -Generation 1 -Force"
Write-Host "3. Import the resulting VHDX as a template"

Write-Host "`nProvisioning completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
