# Hyper-V VM Provisioning Diagnostics Script
#
# This script helps diagnose common issues with VM creation
#

param(
    [string]$ConfigPath = "config.yaml"
)

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

Write-Host "=== Hyper-V VM Provisioning Diagnostics ===" -ForegroundColor Cyan

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Running as Administrator: " -NoNewline
if ($isAdmin) {
    Write-Host "YES" -ForegroundColor Green
} else {
    Write-Host "NO" -ForegroundColor Red
    Write-Host "  WARNING: Some operations may fail without administrator privileges"
}

# Check Hyper-V status
Write-Host "`nHyper-V Status:"
try {
    $hypervFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    Write-Host "  Hyper-V Feature State: $($hypervFeature.State)" -ForegroundColor $(if ($hypervFeature.State -eq 'Enabled') { 'Green' } else { 'Red' })
    
    if ($hypervFeature.State -eq 'Enabled') {
        $vmmsService = Get-Service -Name vmms
        Write-Host "  VMMS Service Status: $($vmmsService.Status)" -ForegroundColor $(if ($vmmsService.Status -eq 'Running') { 'Green' } else { 'Red' })
    }
} catch {
    Write-Host "  Could not check Hyper-V status: $($_.Exception.Message)" -ForegroundColor Red
}

# Load and validate configuration
$configPath = Join-Path $PSScriptRoot $ConfigPath
Write-Host "`nConfiguration File:"
Write-Host "  Path: $configPath"
if (Test-Path $configPath) {
    Write-Host "  Exists: YES" -ForegroundColor Green
    try {
        $yamlContent = Get-Content $configPath -Raw
        $config = ConvertFrom-Yaml -YamlContent $yamlContent
        Write-Host "  Parsed: YES" -ForegroundColor Green
        
        Write-Host "`nConfiguration Values:"
        foreach ($key in $config.Keys) {
            Write-Host "  $key : $($config[$key])"
        }
    } catch {
        Write-Host "  Parsed: NO - $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "  Exists: NO" -ForegroundColor Red
}

if ($config) {
    # Check paths
    Write-Host "`nPath Validation:"
    
    # ISO Path
    Write-Host "  ISO Path: $($config['iso_path'])"
    if (Test-Path $config['iso_path']) {
        $isoSize = (Get-Item $config['iso_path']).Length
        Write-Host "    Exists: YES ($([math]::Round($isoSize/1GB,2)) GB)" -ForegroundColor Green
    } else {
        Write-Host "    Exists: NO" -ForegroundColor Red
    }
    
    # VM Path
    Write-Host "  VM Path: $($config['vm_path'])"
    if (Test-Path $config['vm_path']) {
        Write-Host "    Exists: YES" -ForegroundColor Green
    } else {
        Write-Host "    Exists: NO (will be created)" -ForegroundColor Yellow
    }
    
    # VHD Path
    Write-Host "  VHD Path: $($config['vhd_path'])"
    if (Test-Path $config['vhd_path']) {
        Write-Host "    Exists: YES" -ForegroundColor Green
    } else {
        Write-Host "    Exists: NO (will be created)" -ForegroundColor Yellow
    }
    
    # Kickstart Path
    $ksPath = Join-Path $PSScriptRoot "..\templates\AlmaLinux\$($config['ks_version'])\ks.cfg"
    Write-Host "  Kickstart Path: $ksPath"
    if (Test-Path $ksPath) {
        Write-Host "    Exists: YES" -ForegroundColor Green
    } else {
        Write-Host "    Exists: NO" -ForegroundColor Red
    }
    
    # Check VM Switch
    Write-Host "`nVM Switch Validation:"
    Write-Host "  Switch Name: $($config['vm_switch'])"
    try {
        $switch = Get-VMSwitch -Name $config['vm_switch'] -ErrorAction Stop
        Write-Host "    Exists: YES" -ForegroundColor Green
        Write-Host "    Type: $($switch.SwitchType)"
        Write-Host "    Status: $($switch.Status)"
    } catch {
        Write-Host "    Exists: NO" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)"
        
        Write-Host "`n  Available VM Switches:"
        try {
            $switches = Get-VMSwitch
            foreach ($sw in $switches) {
                Write-Host "    - $($sw.Name) ($($sw.SwitchType))"
            }
        } catch {
            Write-Host "    Could not list VM switches: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Check for existing VMs with same names
    Write-Host "`nExisting VM Check:"
    for ($i = 1; $i -le $config['vm_count']; $i++) {
        $vmName = "$($config['vm_prefix'])-$i"
        try {
            $vm = Get-VM -Name $vmName -ErrorAction Stop
            Write-Host "  $vmName : EXISTS (State: $($vm.State))" -ForegroundColor Yellow
        } catch {
            Write-Host "  $vmName : Available" -ForegroundColor Green
        }
    }
    
    # Test VM creation capability
    Write-Host "`nVM Creation Test:"
    $testVMName = "DiagnosticTest-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "  Testing basic VM creation with name: $testVMName"
    
    try {
        $testVM = New-VM -Name $testVMName -MemoryStartupBytes 512MB -Generation $config['vm_generation'] -Path $env:TEMP -ErrorAction Stop
        Write-Host "    Basic VM Creation: SUCCESS" -ForegroundColor Green
        
        try {
            Remove-VM -Name $testVMName -Force -ErrorAction Stop
            Write-Host "    Test VM Cleanup: SUCCESS" -ForegroundColor Green
        } catch {
            Write-Host "    Test VM Cleanup: FAILED - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    Basic VM Creation: FAILED" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)"
        Write-Host "    HResult: $($_.Exception.HResult)"
        
        # Additional error analysis
        if ($_.Exception.HResult -eq -2147024894) {
            Write-Host "    This error typically indicates insufficient permissions or Hyper-V not properly enabled." -ForegroundColor Yellow
        } elseif ($_.Exception.HResult -eq -2147749896) {
            Write-Host "    This error (0x80041008) typically indicates configuration conflicts or unsupported settings." -ForegroundColor Yellow
        }
    }
    
    # Check disk space
    Write-Host "`nDisk Space Check:"
    $vmDrive = Split-Path $config['vm_path'] -Qualifier
    $vhdDrive = Split-Path $config['vhd_path'] -Qualifier
    
    try {
        $vmSpace = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$vmDrive'"
        $requiredSpace = ($config['vm_disk_size_gb'] * $config['vm_count'] + 5) * 1GB  # +5GB for overhead
        Write-Host "  VM Drive ($vmDrive): $([math]::Round($vmSpace.FreeSpace/1GB,1)) GB free"
        if ($vmSpace.FreeSpace -gt $requiredSpace) {
            Write-Host "    Sufficient space: YES" -ForegroundColor Green
        } else {
            Write-Host "    Sufficient space: NO (need ~$([math]::Round($requiredSpace/1GB,1)) GB)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  Could not check disk space: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Check system capabilities
Write-Host "`nSystem Capabilities:"
try {
    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    Write-Host "  CPU: $($cpu.Name)"
    Write-Host "  Cores: $($cpu.NumberOfCores)"
    Write-Host "  Logical Processors: $($cpu.NumberOfLogicalProcessors)"
    
    $ram = Get-WmiObject Win32_ComputerSystem
    Write-Host "  Total RAM: $([math]::Round($ram.TotalPhysicalMemory/1GB,1)) GB"
    
    # Check virtualization support
    $hypervCapable = (Get-ComputerInfo).HyperVRequirementVirtualizationFirmwareEnabled
    Write-Host "  Virtualization in Firmware: $hypervCapable" -ForegroundColor $(if ($hypervCapable) { 'Green' } else { 'Red' })
    
} catch {
    Write-Host "  Could not retrieve system information: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n=== Diagnostics Complete ===" -ForegroundColor Cyan

# Recommendations
Write-Host "`nRecommendations:" -ForegroundColor Yellow
Write-Host "1. Ensure you're running PowerShell as Administrator"
Write-Host "2. Verify Hyper-V is fully enabled and VMMS service is running"
Write-Host "3. Check that your system supports hardware virtualization"
Write-Host "4. Ensure all required paths exist and are accessible"
Write-Host "5. Verify the VM switch exists or create it first"
Write-Host "6. Check for sufficient disk space"
Write-Host "7. If using Gen 1 VMs, ensure the host system supports the configuration"

if ($config -and $config['vm_generation'] -eq 1) {
    Write-Host "`nGen 1 VM Specific Notes:" -ForegroundColor Cyan
    Write-Host "- Some newer systems may have limited Gen 1 VM support"
    Write-Host "- Consider trying vm_generation: 2 in config.yaml"
    Write-Host "- Floppy disk support may not be available on all systems"
}
