#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy AlmaLinux VMs from template without cloud-init dependency

.DESCRIPTION
    Simple deployment script that creates VMs from the template and provides
    manual configuration instructions instead of relying on cloud-init.
    
    This is a fallback option when cloud-init is not working properly.

.PARAMETER VMName
    Name for the new VM

.PARAMETER IPAddress
    Static IP address to assign (will be provided as manual configuration instruction)

.PARAMETER MemoryGB
    Memory in GB (default: 2)

.PARAMETER CPUCount
    Number of CPU cores (default: 2)

.PARAMETER SwitchName
    Hyper-V switch name (default: PackerInternal)

.PARAMETER TemplateVHDX
    Path to the template VHDX file

.EXAMPLE
    .\deploy-simple.ps1 -VMName "Test-Simple" -IPAddress "192.168.200.101"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string]$IPAddress,
    
    [int]$MemoryGB = 2,
    [int]$CPUCount = 2,
    [string]$SwitchName = "PackerInternal",
    [string]$TemplateVHDX = $null
)

# Script directory and paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$OutputDir = Join-Path $ProjectDir "output"

Write-Host "=== Simple VM Deployment (No Cloud-init) ===" -ForegroundColor Green
Write-Host "VM Name: $VMName" -ForegroundColor Yellow
Write-Host "IP Address: $IPAddress" -ForegroundColor Yellow
Write-Host "Memory: ${MemoryGB}GB, CPUs: $CPUCount" -ForegroundColor Yellow
Write-Host "Switch: $SwitchName" -ForegroundColor Yellow
Write-Host

# Find template VHDX if not specified
if (-not $TemplateVHDX) {
    Write-Host "Looking for template VHDX files..." -ForegroundColor Cyan
    
    $vhdxFiles = @()
    
    # Look in output directory
    if (Test-Path $OutputDir) {
        $vhdxFiles += Get-ChildItem -Path $OutputDir -Filter "*.vhdx" -Recurse
    }
    
    if ($vhdxFiles.Count -eq 0) {
        Write-Host "ERROR: No VHDX template files found in output directory." -ForegroundColor Red
        Write-Host "Please build a template first using build-cloudinit-template.ps1" -ForegroundColor Yellow
        exit 1
    }
    
    if ($vhdxFiles.Count -gt 1) {
        Write-Host "Multiple VHDX files found:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $vhdxFiles.Count; $i++) {
            Write-Host "  [$i] $($vhdxFiles[$i].FullName)" -ForegroundColor Gray
        }
        
        $selection = Read-Host "Select VHDX file (0-$($vhdxFiles.Count-1))"
        try {
            $TemplateVHDX = $vhdxFiles[[int]$selection].FullName
        } catch {
            Write-Host "Invalid selection. Using first VHDX file." -ForegroundColor Yellow
            $TemplateVHDX = $vhdxFiles[0].FullName
        }
    } else {
        $TemplateVHDX = $vhdxFiles[0].FullName
    }
}

Write-Host "Using template: $TemplateVHDX" -ForegroundColor Green

# Verify template exists
if (-not (Test-Path $TemplateVHDX)) {
    Write-Host "ERROR: Template VHDX file not found: $TemplateVHDX" -ForegroundColor Red
    exit 1
}

# Create VM directory and copy VHDX
$VMDir = "C:\ClusterStorage\S2D-Volume01\VMs\$VMName"
$VMVHDX = "$VMDir\$VMName.vhdx"

Write-Host "Creating VM directory and copying VHDX..." -ForegroundColor Cyan
try {
    if (Test-Path $VMDir) {
        Write-Host "WARNING: VM directory already exists. Removing..." -ForegroundColor Yellow
        Remove-Item $VMDir -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $VMDir -Force | Out-Null
    Copy-Item $TemplateVHDX $VMVHDX -Force
    
    Write-Host "VHDX copied successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to copy VHDX: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Detect VM generation from VHDX
Write-Host "Detecting VM generation from VHDX..." -ForegroundColor Cyan
try {
    $vhdxInfo = Get-VHD $VMVHDX
    
    # Mount VHDX temporarily to check partitions
    $mountResult = Mount-VHD $VMVHDX -Passthru
    $disk = $mountResult | Get-Disk
    $partitions = $disk | Get-Partition
    
    # Check for EFI system partition (indicates Generation 2)
    $hasEFI = $partitions | Where-Object { $_.Type -eq "System" -and $_.Size -lt 1GB }
    
    if ($hasEFI) {
        $Generation = 2
        Write-Host "Detected Generation 2 (UEFI)" -ForegroundColor Green
    } else {
        $Generation = 1
        Write-Host "Detected Generation 1 (BIOS)" -ForegroundColor Green
    }
    
    # Dismount VHDX
    Dismount-VHD $VMVHDX
} catch {
    Write-Host "WARNING: Could not detect generation, defaulting to Generation 1" -ForegroundColor Yellow
    $Generation = 1
    
    # Try to dismount if it was mounted
    try { Dismount-VHD $VMVHDX -ErrorAction SilentlyContinue } catch {}
}

# Create the VM
Write-Host "Creating VM..." -ForegroundColor Cyan
try {
    $VM = New-VM -Name $VMName -MemoryStartupBytes ($MemoryGB * 1GB) -VHDPath $VMVHDX -Generation $Generation -SwitchName $SwitchName
    
    # Configure VM
    Set-VM -VMName $VMName -ProcessorCount $CPUCount
    Set-VM -VMName $VMName -DynamicMemory:$false
    
    # Enable guest services integration
    Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"
    
    Write-Host "VM created successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create VM: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Start the VM
Write-Host "Starting VM..." -ForegroundColor Cyan
try {
    Start-VM -Name $VMName
    Write-Host "VM started successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to start VM: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host
Write-Host "=== VM Deployment Complete ===" -ForegroundColor Green
Write-Host
Write-Host "VM Details:" -ForegroundColor Cyan
Write-Host "  Name: $VMName" -ForegroundColor White
Write-Host "  Generation: $Generation" -ForegroundColor White
Write-Host "  Memory: ${MemoryGB}GB" -ForegroundColor White
Write-Host "  CPUs: $CPUCount" -ForegroundColor White
Write-Host "  Switch: $SwitchName" -ForegroundColor White
Write-Host "  VHDX: $VMVHDX" -ForegroundColor White
Write-Host

Write-Host "=== Manual Configuration Required ===" -ForegroundColor Yellow
Write-Host "Since this deployment doesn't use cloud-init, you need to manually configure the VM:" -ForegroundColor White
Write-Host
Write-Host "1. Connect to VM console:" -ForegroundColor Cyan
Write-Host "   vmconnect localhost '$VMName'" -ForegroundColor Gray
Write-Host
Write-Host "2. Login as root (password: packer)" -ForegroundColor Cyan
Write-Host
Write-Host "3. Configure network with static IP:" -ForegroundColor Cyan
Write-Host "   nmcli con mod 'System eth0' ipv4.method manual ipv4.addresses $IPAddress/24 ipv4.gateway 192.168.200.1 ipv4.dns 8.8.8.8" -ForegroundColor Gray
Write-Host "   nmcli con up 'System eth0'" -ForegroundColor Gray
Write-Host
Write-Host "4. Create lab user:" -ForegroundColor Cyan
Write-Host "   useradd -m -s /bin/bash labuser" -ForegroundColor Gray
Write-Host "   echo 'labuser:labpass123!' | chpasswd" -ForegroundColor Gray
Write-Host "   usermod -aG wheel labuser" -ForegroundColor Gray
Write-Host
Write-Host "5. Enable SSH:" -ForegroundColor Cyan
Write-Host "   systemctl enable sshd" -ForegroundColor Gray
Write-Host "   systemctl start sshd" -ForegroundColor Gray
Write-Host
Write-Host "6. Verify network connectivity:" -ForegroundColor Cyan
Write-Host "   ping 192.168.200.1  # Gateway" -ForegroundColor Gray
Write-Host "   ping 8.8.8.8        # Internet" -ForegroundColor Gray
Write-Host

Write-Host "After manual configuration, you can SSH to the VM:" -ForegroundColor Green
Write-Host "ssh labuser@$IPAddress" -ForegroundColor Gray
Write-Host
