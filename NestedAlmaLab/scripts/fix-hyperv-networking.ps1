# Fix Hyper-V Networking for Packer
# Diagnoses and resolves common Hyper-V networking issues that prevent Packer from working

param(
    [Parameter(Mandatory=$false)]
    [switch]$CreateExternalSwitch,
    
    [Parameter(Mandatory=$false)]
    [string]$ExternalAdapterName
)

Write-Host "=== Hyper-V Networking Diagnostics and Fix ===" -ForegroundColor Cyan
Write-Host "Checking Hyper-V network configuration for Packer compatibility"
Write-Host "=================================================="

# Check if running as admin
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator to modify Hyper-V settings."
    exit 1
}

# Function to test network connectivity
function Test-NetworkConnectivity {
    param([string]$TestName, [string]$Target)
    
    Write-Host "  Testing $TestName..."
    try {
        $result = Test-NetConnection -ComputerName $Target -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($result) {
            Write-Host "    [OK] ${TestName}: OK" -ForegroundColor Green
        } else {
            Write-Host "    [FAIL] ${TestName}: Failed" -ForegroundColor Red
        }
        return $result
    } catch {
        Write-Host "    [ERROR] ${TestName}: Error - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 1. Check Hyper-V service
Write-Host "`n1. Checking Hyper-V service..." -ForegroundColor Yellow
$vmmsService = Get-Service -Name vmms -ErrorAction SilentlyContinue
if ($vmmsService -and $vmmsService.Status -eq "Running") {
    Write-Host "  [OK] Hyper-V Virtual Machine Management service is running" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Hyper-V service issue" -ForegroundColor Red
    Write-Host "  Fix: Restart-Service vmms"
    try {
        Restart-Service vmms -Force
        Write-Host "  [OK] Hyper-V service restarted" -ForegroundColor Green
    } catch {
        Write-Error "  Failed to restart Hyper-V service: $($_.Exception.Message)"
    }
}

# 2. Check VM switches
Write-Host "`n2. Checking VM switches..." -ForegroundColor Yellow
$switches = Get-VMSwitch
Write-Host "  Found $($switches.Count) VM switches:"
foreach ($switch in $switches) {
    $status = if ($switch.SwitchType -eq "External") {"[EXT]"} elseif ($switch.SwitchType -eq "Internal") {"[INT]"} else {"[PVT]"}
    Write-Host "    $status $($switch.Name) ($($switch.SwitchType))"
}

# 3. Check Default Switch specifically
Write-Host "`n3. Checking Default Switch..." -ForegroundColor Yellow
$defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
if ($defaultSwitch) {
    Write-Host "  [OK] Default Switch exists" -ForegroundColor Green
    
    # Check associated network adapters
    $adapters = Get-NetAdapter | Where-Object {$_.InterfaceDescription -match "Default"}
    if ($adapters) {
        Write-Host "  [OK] Found Default Switch adapters:" -ForegroundColor Green
        foreach ($adapter in $adapters) {
            $ip = (Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            Write-Host "    - $($adapter.Name): $($adapter.Status) (IP: $ip)"
        }
    } else {
        Write-Host "  [FAIL] No Default Switch adapters found" -ForegroundColor Red
    }
} else {
    Write-Host "  [FAIL] Default Switch not found" -ForegroundColor Red
    Write-Host "  This will cause Packer networking issues."
}

# 4. Test internet connectivity
Write-Host "`n4. Testing network connectivity..." -ForegroundColor Yellow
Test-NetworkConnectivity "Internet" "8.8.8.8"
Test-NetworkConnectivity "DNS Resolution" "google.com"
Test-NetworkConnectivity "AlmaLinux Repository" "repo.almalinux.org"

# 5. Check Windows Firewall
Write-Host "`n5. Checking Windows Firewall..." -ForegroundColor Yellow
try {
    $firewallProfiles = Get-NetFirewallProfile
    $activeProfiles = $firewallProfiles | Where-Object {$_.Enabled -eq $true}
    if ($activeProfiles) {
        Write-Host "  Active firewall profiles: $($activeProfiles.Name -join ', ')" -ForegroundColor Yellow
        Write-Host "  Packer may need firewall exceptions for HTTP server (ports 8080-8090)"
    } else {
        Write-Host "  [OK] Windows Firewall is disabled" -ForegroundColor Green
    }
} catch {
    Write-Warning "  Could not check firewall status"
}

# Solutions
Write-Host "`n=== SOLUTIONS ===" -ForegroundColor Cyan

if (-not $defaultSwitch) {
    Write-Host "[CRITICAL] Missing Default Switch - Major Issue" -ForegroundColor Red
    Write-Host "Solutions:"
    Write-Host "1. Enable Windows features:"
    Write-Host "   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All"
    Write-Host "2. Restart computer after enabling Hyper-V"
    Write-Host "3. Or create External switch (see -CreateExternalSwitch option)"
}

if ($CreateExternalSwitch) {
    Write-Host "`nCreating External Switch for Packer..." -ForegroundColor Yellow
    
    # Get available network adapters
    $physicalAdapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Virtual -eq $false}
    
    if (-not $physicalAdapters) {
        Write-Error "No active physical network adapters found for External switch"
        exit 1
    }
    
    Write-Host "Available network adapters:"
    for ($i = 0; $i -lt $physicalAdapters.Count; $i++) {
        Write-Host "  $($i + 1). $($physicalAdapters[$i].Name) ($($physicalAdapters[$i].InterfaceDescription))"
    }
    
    if ($ExternalAdapterName) {
        $selectedAdapter = $physicalAdapters | Where-Object {$_.Name -eq $ExternalAdapterName}
    } else {
        # Use first adapter by default
        $selectedAdapter = $physicalAdapters[0]
        Write-Host "Using adapter: $($selectedAdapter.Name)" -ForegroundColor Green
    }
    
    if ($selectedAdapter) {
        try {
            Write-Host "Creating External switch 'PackerExternal'..." -ForegroundColor Yellow
            New-VMSwitch -Name "PackerExternal" -NetAdapterName $selectedAdapter.Name -AllowManagementOS $true
            Write-Host "  [OK] External switch created successfully" -ForegroundColor Green
            Write-Host "  Update your Packer template to use: switch_name = 'PackerExternal'"
        } catch {
            Write-Error "Failed to create External switch: $($_.Exception.Message)"
        }
    }
}

Write-Host "`n=== RECOMMENDATIONS ===" -ForegroundColor Green
Write-Host "For best Packer performance with Hyper-V:"
Write-Host ""
Write-Host "Option 1 (Recommended): Create External Switch"
Write-Host "  $PSCommandPath -CreateExternalSwitch"
Write-Host "  Then update template: switch_name = 'PackerExternal'"
Write-Host ""
Write-Host "Option 2: Fix Default Switch"
Write-Host "  1. Restart Hyper-V service: Restart-Service vmms"
Write-Host "  2. Disable/re-enable Default Switch in Hyper-V Manager"
Write-Host "  3. Reboot if necessary"
Write-Host ""
Write-Host "Option 3: Use Internal Switch"
Write-Host "  Create internal switch with manual IP configuration"
Write-Host ""
Write-Host "After fixing networking, retry Packer build:"
Write-Host "  .\\build-template-simple.ps1 -KickstartVersion v2 -Force"

Write-Host "`nDiagnostics completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
