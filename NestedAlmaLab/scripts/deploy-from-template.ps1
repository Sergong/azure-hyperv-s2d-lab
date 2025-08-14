# Deploy VMs from Packer-built AlmaLinux Template
# Creates multiple VMs from a pre-built template VHDX

param(
    [Parameter(Mandatory=$false)]
    [string]$TemplatePath = "",
    
    [Parameter(Mandatory=$false)]
    [int]$VMCount = 2,
    
    [Parameter(Mandatory=$false)]
    [string]$VMPrefix = "AlmaLab",
    
    [Parameter(Mandatory=$false)]
    [string]$VMPath = "C:\HyperV\VMs",
    
    [Parameter(Mandatory=$false)]
    [string]$VHDPath = "C:\HyperV\VMs\VHDs",
    
    [Parameter(Mandatory=$false)]
    [string]$SwitchName = "Default Switch",
    
    [Parameter(Mandatory=$false)]
    [int64]$Memory = 2GB,
    
    [Parameter(Mandatory=$false)]
    [switch]$StartVMs
)

# Auto-detect template path if not provided
if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = Split-Path -Parent $scriptPath
    
    # Ensure projectRoot is a single string
    if ($projectRoot -is [array]) {
        $projectRoot = $projectRoot[0]
    }
    
    Write-Host "Script path: $scriptPath" -ForegroundColor Gray
    Write-Host "Project root: $projectRoot" -ForegroundColor Gray
    
    # Look for common Packer output directories
    $possiblePaths = @(
        (Join-Path $projectRoot "output-almalinux-simple"),
        (Join-Path $projectRoot "output-almalinux"),
        "C:\Packer\Output",
        (Join-Path $projectRoot "output")
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            # Check both the main directory and Virtual Hard Disks subdirectory
            $vhdxSearchLocations = @(
                "$path\Virtual Hard Disks\*.vhdx",
                "$path\*.vhdx"
            )
            
            foreach ($searchLocation in $vhdxSearchLocations) {
                $vhdxFiles = Get-ChildItem $searchLocation -ErrorAction SilentlyContinue
                if ($vhdxFiles) {
                    $TemplatePath = $path
                    Write-Host "Auto-detected template path: $TemplatePath" -ForegroundColor Green
                    break
                }
            }
            
            if ($TemplatePath) { break }
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        Write-Error "Could not auto-detect template path. Please specify -TemplatePath parameter."
        Write-Host "Searched in:"
        foreach ($path in $possiblePaths) {
            Write-Host "  - $path"
        }
        exit 1
    }
}

Write-Host "=== Deploy VMs from Packer Template ===" -ForegroundColor Cyan
Write-Host "Template Path: $TemplatePath"
Write-Host "VM Count: $VMCount"
Write-Host "VM Prefix: $VMPrefix"
Write-Host "Memory per VM: $($Memory/1GB) GB"
Write-Host "=================================="

# Find the template VHDX file - Packer puts them in "Virtual Hard Disks" subdirectory
$vhdxSearchPaths = @(
    "$TemplatePath\Virtual Hard Disks\*.vhdx",
    "$TemplatePath\*.vhdx"
)

$templateFiles = @()
foreach ($searchPath in $vhdxSearchPaths) {
    $foundFiles = Get-ChildItem $searchPath -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($foundFiles) {
        $templateFiles = $foundFiles
        Write-Host "Found template files in: $(Split-Path $searchPath -Parent)" -ForegroundColor Gray
        break
    }
}

if (-not $templateFiles) {
    Write-Error "No template VHDX files found in $TemplatePath"
    Write-Host "Searched in:"
    foreach ($searchPath in $vhdxSearchPaths) {
        Write-Host "  - $(Split-Path $searchPath -Parent)"
    }
    Write-Host "Run build-static-ip.ps1 first to create a template."
    exit 1
}

$templateVHDX = $templateFiles[0].FullName
Write-Host "Using template: $templateVHDX" -ForegroundColor Green
Write-Host "Template size: $([math]::Round($templateFiles[0].Length/1GB,2)) GB"

# Validate VM switch
try {
    Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
    Write-Host "VM Switch validated: $SwitchName" -ForegroundColor Green
} catch {
    Write-Error "VM Switch '$SwitchName' not found. Please create it first."
    exit 1
}

# Create directories
New-Item -ItemType Directory -Path $VMPath, $VHDPath -Force | Out-Null

# Function to create VM from template
function New-VMFromTemplate {
    param(
        [string]$VMName,
        [string]$TemplateVHDX,
        [string]$TargetVHDX
    )
    
    Write-Host "Creating VM: $VMName" -ForegroundColor Yellow
    
    try {
        # Copy template VHDX
        Write-Host "  Copying template VHDX..."
        Copy-Item $TemplateVHDX $TargetVHDX -Force
        
        # Detect template generation from VHDX metadata
        $vhdInfo = Get-VHD $TargetVHDX
        $generation = 2  # Default to Gen 2 for modern templates
        
        # Create VM
        Write-Host "  Creating Generation $generation VM..."
        $vm = New-VM -Name $VMName -MemoryStartupBytes $Memory -Generation $generation -Path $VMPath -VHDPath $TargetVHDX
        
        # Connect to network switch
        if ($SwitchName -ne "Default Switch") {
            Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName
        } else {
            # For Default Switch, explicitly connect
            Get-VMNetworkAdapter -VMName $VMName | Connect-VMNetworkAdapter -SwitchName $SwitchName
        }
        
        # Configure VM settings based on generation
        if ($generation -eq 2) {
            # Gen 2 specific settings
            Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
            
            # Enable nested virtualization if supported
            try {
                Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
                Write-Host "  Enabled nested virtualization"
            } catch {
                Write-Warning "  Could not enable nested virtualization: $($_.Exception.Message)"
            }
        } else {
            # Gen 1 specific settings
            try {
                Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
                Write-Host "  Enabled nested virtualization"
            } catch {
                Write-Warning "  Could not enable nested virtualization: $($_.Exception.Message)"
            }
        }
        
        # Configure additional VM settings for lab use
        Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false
        Set-VM -VMName $VMName -CheckpointType Disabled
        
        Write-Host "  VM $VMName created successfully" -ForegroundColor Green
        return $vm
        
    } catch {
        Write-Error "Failed to create VM ${VMName}: $($_.Exception.Message)"
        
        # Cleanup on failure
        try {
            if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
                Remove-VM -Name $VMName -Force
            }
            if (Test-Path $TargetVHDX) {
                Remove-Item $TargetVHDX -Force
            }
        } catch {
            Write-Warning "Failed to cleanup $VMName"
        }
        throw
    }
}

# Deploy VMs
$deployedVMs = @()
Write-Host "`nDeploying $VMCount VMs from template..." -ForegroundColor Yellow

for ($i = 1; $i -le $VMCount; $i++) {
    $vmName = "$VMPrefix-$i"
    $vhdFile = "$VHDPath\$vmName.vhdx"
    
    try {
        $vm = New-VMFromTemplate -VMName $vmName -TemplateVHDX $templateVHDX -TargetVHDX $vhdFile
        $deployedVMs += $vmName
        
        # Start VM if requested
        if ($StartVMs) {
            Write-Host "  Starting VM: $vmName"
            Start-VM -Name $vmName
        }
        
    } catch {
        Write-Warning "Skipping VM $vmName due to error: $($_.Exception.Message)"
    }
}

# Summary
Write-Host "`n=== Deployment Summary ===" -ForegroundColor Green
Write-Host "Successfully deployed $($deployedVMs.Count) out of $VMCount VMs:"

foreach ($vmName in $deployedVMs) {
    $vm = Get-VM -Name $vmName
    $vmIP = "Not available"
    
    # Try to get IP address if VM is running
    if ($vm.State -eq "Running") {
        try {
            $networkAdapter = Get-VMNetworkAdapter -VMName $vmName
            if ($networkAdapter.IPAddresses) {
                $vmIP = ($networkAdapter.IPAddresses | Where-Object {$_ -match "^\d+\.\d+\.\d+\.\d+$"})[0]
            }
        } catch {
            # IP not available yet
        }
    }
    
    Write-Host "  - $vmName : $($vm.State) (IP: $vmIP)"
}

Write-Host "`n=== Template Information ===" -ForegroundColor Cyan
Write-Host "Template includes:"
Write-Host "- AlmaLinux 9 with latest updates"
Write-Host "- Hyper-V integration services"
Write-Host "- Network utilities and development tools"
Write-Host "- SSH configured for immediate access"
Write-Host "- Static IP network configuration"
Write-Host "- Nested virtualization enabled (if supported)"

Write-Host "`n=== Access Information ===" -ForegroundColor Yellow
Write-Host "Default credentials for all VMs:"
Write-Host "- SSH: root / packer"
Write-Host "- SSH: labuser / labpass123!"
Write-Host "- Static IP: 192.168.200.100 (template default)"
Write-Host "- All VMs are ready for immediate SSH access"

Write-Host "`n=== Management Commands ===" -ForegroundColor White
Write-Host "Check VM status:     Get-VM $VMPrefix-*"
Write-Host "Get IP addresses:    Get-VM $VMPrefix-* | Get-VMNetworkAdapter | Select Name, IPAddresses"
Write-Host "Connect to console:  vmconnect localhost \u003cvmname\u003e"
Write-Host "Start all VMs:       Get-VM $VMPrefix-* | Start-VM"
Write-Host "Stop all VMs:        Get-VM $VMPrefix-* | Stop-VM"

if (-not $StartVMs) {
    Write-Host "`nTo start the VMs, run:" -ForegroundColor Yellow
    Write-Host "Get-VM $VMPrefix-* | Start-VM"
}

Write-Host "`nDeployment completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
