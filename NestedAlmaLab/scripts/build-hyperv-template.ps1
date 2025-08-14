# Build Hyper-V Optimized AlmaLinux Template
# Addresses networking issues with Generation 1 fallback

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 2)]
    [int]$Generation = 1,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string]$SwitchName = "Default Switch",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateExternalSwitch,
    
    [Parameter(Mandatory=$false)]
    [string]$ExternalAdapterName,
    
    [Parameter(Mandatory=$false)]
    [switch]$DebugMode
)

# Ensure we're running as Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator for Hyper-V operations."
    Write-Host "Right-click PowerShell and select 'Run as Administrator'"
    exit 1
}

Write-Host "=== Hyper-V Optimized AlmaLinux Template Build ===" -ForegroundColor Cyan
Write-Host "Generation: $Generation (Gen 1 = BIOS, Gen 2 = UEFI)"
Write-Host "Switch: $SwitchName"
Write-Host "=================================================="

# Set paths
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$templatePath = Join-Path $projectRoot "templates/almalinux-hyperv.pkr.hcl"
$kickstartPath = Join-Path $projectRoot "templates/AlmaLinux/hyperv/ks.cfg"
$outputPath = Join-Path $projectRoot "output-almalinux-hyperv"

# 1. Prerequisites check
Write-Host "`n1. Checking prerequisites..." -ForegroundColor Yellow

# Check Packer
try {
    $packerVersion = & packer version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Packer: $($packerVersion.Split("`n")[0])" -ForegroundColor Green
    } else {
        throw "Packer not found"
    }
} catch {
    Write-Error "Packer not installed. Install with: winget install hashicorp.packer"
    exit 1
}

# Check Hyper-V - Multiple detection methods
$hypervEnabled = $false

# Method 1: Check Windows Feature
try {
    $hypervFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
    if ($hypervFeature -and $hypervFeature.State -eq "Enabled") {
        $hypervEnabled = $true
    }
} catch {
    # Ignore errors, try other methods
}

# Method 2: Check for Hyper-V service
if (-not $hypervEnabled) {
    try {
        $vmmsService = Get-Service -Name vmms -ErrorAction SilentlyContinue
        if ($vmmsService) {
            $hypervEnabled = $true
        }
    } catch {
        # Ignore errors, try other methods
    }
}

# Method 3: Check for Hyper-V PowerShell module
if (-not $hypervEnabled) {
    try {
        $hypervModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($hypervModule) {
            $hypervEnabled = $true
        }
    } catch {
        # Ignore errors
    }
}

# Method 4: Try to get VM switches (most reliable)
if (-not $hypervEnabled) {
    try {
        $switches = Get-VMSwitch -ErrorAction SilentlyContinue
        if ($switches) {
            $hypervEnabled = $true
        }
    } catch {
        # Final check failed
    }
}

if ($hypervEnabled) {
    Write-Host "  [OK] Hyper-V is enabled and functional" -ForegroundColor Green
} else {
    Write-Error "Hyper-V not enabled or not functional. Enable with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All"
    exit 1
}

# Check template files
if (-not (Test-Path $templatePath)) {
    Write-Error "Template not found: $templatePath"
    exit 1
}

if (-not (Test-Path $kickstartPath)) {
    Write-Error "Kickstart file not found: $kickstartPath"
    Write-Host "Expected: $kickstartPath"
    exit 1
}

Write-Host "  [OK] Template files found" -ForegroundColor Green

# 2. Network switch management
Write-Host "`n2. Configuring network switch..." -ForegroundColor Yellow

if ($CreateExternalSwitch) {
    # Create external switch for reliable networking
    $physicalAdapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Virtual -eq $false}
    
    if (-not $physicalAdapters) {
        Write-Error "No active physical network adapters found for External switch"
        exit 1
    }
    
    Write-Host "  Available network adapters:"
    $physicalAdapters | ForEach-Object { Write-Host "    - $($_.Name): $($_.InterfaceDescription)" }
    
    $selectedAdapter = if ($ExternalAdapterName) {
        $physicalAdapters | Where-Object {$_.Name -eq $ExternalAdapterName}
    } else {
        $physicalAdapters[0]
    }
    
    if (-not $selectedAdapter) {
        Write-Error "Adapter '$ExternalAdapterName' not found"
        exit 1
    }
    
    $externalSwitchName = "PackerExternal"
    $existingSwitch = Get-VMSwitch -Name $externalSwitchName -ErrorAction SilentlyContinue
    
    if (-not $existingSwitch) {
        try {
            Write-Host "  Creating External switch '$externalSwitchName' on adapter '$($selectedAdapter.Name)'..." -ForegroundColor Yellow
            New-VMSwitch -Name $externalSwitchName -NetAdapterName $selectedAdapter.Name -AllowManagementOS $true
            Write-Host "  [OK] External switch created" -ForegroundColor Green
        } catch {
            Write-Error "Failed to create External switch: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "  [OK] External switch already exists" -ForegroundColor Green
    }
    
    $SwitchName = $externalSwitchName
}

# Verify the switch exists and has connectivity
$vmSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $vmSwitch) {
    Write-Error "VM Switch '$SwitchName' not found"
    Write-Host "Available switches:"
    Get-VMSwitch | ForEach-Object { Write-Host "  - $($_.Name) ($($_.SwitchType))" }
    Write-Host "`nTo create an external switch, run:"
    Write-Host "  $PSCommandPath -CreateExternalSwitch"
    exit 1
}

Write-Host "  [OK] Using switch: $($vmSwitch.Name) ($($vmSwitch.SwitchType))" -ForegroundColor Green

# 3. Prepare build environment
Write-Host "`n3. Preparing build environment..." -ForegroundColor Yellow

if (Test-Path $outputPath) {
    if ($Force) {
        Write-Host "  Removing existing output..." -ForegroundColor Yellow
        Remove-Item $outputPath -Recurse -Force
    } else {
        Write-Error "Output directory exists. Use -Force to overwrite."
        exit 1
    }
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
Write-Host "  [OK] Output directory ready" -ForegroundColor Green

# 4. Create variables file
Write-Host "`n4. Creating build variables..." -ForegroundColor Yellow
$variablesFile = Join-Path $scriptPath "hyperv-vars.pkrvars.hcl"
$variablesContent = @"
kickstart_version = "hyperv"
generation = $Generation
switch_name = "$SwitchName"
output_directory = "$($outputPath.Replace('\', '/'))"
vm_name = "almalinux-9.4-hyperv-gen$Generation"
"@

Set-Content -Path $variablesFile -Value $variablesContent -Encoding UTF8
Write-Host "  [OK] Variables configured for Generation $Generation" -ForegroundColor Green

# 5. Test network connectivity
Write-Host "`n5. Testing network connectivity..." -ForegroundColor Yellow
try {
    $internetTest = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
    $repoTest = Test-NetConnection -ComputerName "repo.almalinux.org" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    
    if ($internetTest) {
        Write-Host "  [OK] Internet connectivity" -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] Internet connectivity issues" -ForegroundColor Yellow
    }
    
    if ($repoTest) {
        Write-Host "  [OK] AlmaLinux repository accessible" -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] AlmaLinux repository not accessible" -ForegroundColor Yellow
    }
} catch {
    Write-Warning "Could not test network connectivity"
}

# 6. Initialize and validate
Write-Host "`n6. Initializing Packer..." -ForegroundColor Yellow
try {
    Set-Location $projectRoot
    & packer init $templatePath
    if ($LASTEXITCODE -ne 0) {
        throw "Packer init failed"
    }
    Write-Host "  [OK] Packer plugins initialized" -ForegroundColor Green
} catch {
    Write-Error "Failed to initialize Packer: $($_.Exception.Message)"
    exit 1
}

Write-Host "`n7. Validating template..." -ForegroundColor Yellow
try {
    $validateOutput = & packer validate -var-file="$variablesFile" $templatePath 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Template validation passed" -ForegroundColor Green
    } else {
        Write-Error "Template validation failed: $validateOutput"
        exit 1
    }
} catch {
    Write-Error "Validation exception: $($_.Exception.Message)"
    exit 1
}

# 8. Final pre-build summary
Write-Host "`n8. Build Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Template: almalinux-hyperv.pkr.hcl"
Write-Host "  Kickstart: hyperv/ks.cfg (Hyper-V optimized)"
Write-Host "  Generation: $Generation $(if($Generation -eq 1){"(BIOS - more compatible)"} else {"(UEFI)"})"
Write-Host "  Switch: $SwitchName"
Write-Host "  Output: $outputPath"
Write-Host ""
Write-Host "Key Hyper-V optimizations:"
Write-Host "  - Network device detection using 'link' instead of 'eth0'"
Write-Host "  - Hyper-V integration services pre-installed"
Write-Host "  - DHCP timeout extended to 300 seconds"
Write-Host "  - NetworkManager configuration for synthetic adapters"
Write-Host "  - Generation $Generation boot configuration"

# 9. Start build
Write-Host "`n9. Starting Packer build..." -ForegroundColor Green
Write-Host "This will take 20-40 minutes. The VM console will be visible."
Write-Host "Watch for network interface detection during AlmaLinux boot."
Write-Host ""

try {
    $buildArgs = @(
        "build"
        "-force"
        "-var-file=$variablesFile"
    )
    
    if ($DebugMode) {
        $buildArgs += "-debug"
    }
    
    $buildArgs += $templatePath
    
    Write-Host "Command: packer $($buildArgs -join ' ')" -ForegroundColor Gray
    Write-Host ""
    
    & packer @buildArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[SUCCESS] AlmaLinux Hyper-V template built!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Template ready at: $outputPath"
        Write-Host ""
        Write-Host "To test the template:"
        Write-Host "1. Import into Hyper-V Manager"
        Write-Host "2. Create new VMs from this template"
        Write-Host "3. Network should work automatically with DHCP"
        Write-Host ""
        Write-Host "Network troubleshooting in VMs:"
        Write-Host "  - Run: hyperv-network-test.sh"
        Write-Host "  - Check: systemctl status NetworkManager"
        Write-Host "  - Restart network: systemctl restart NetworkManager"
        
    } else {
        Write-Host "`n[FAILED] BUILD FAILED" -ForegroundColor Red
        Write-Host ""
        Write-Host "Common issues and solutions:"
        Write-Host "1. Network adapter IP error:"
        Write-Host "   - Run: $PSCommandPath -CreateExternalSwitch"
        Write-Host "   - Or try Generation 1: $PSCommandPath -Generation 1"
        Write-Host ""
        Write-Host "2. Kickstart not found:"
        Write-Host "   - Check: $kickstartPath"
        Write-Host ""
        Write-Host "3. ISO download issues:"
        Write-Host "   - Check internet connectivity"
        Write-Host "   - Try manual ISO download"
        exit 1
    }
    
} catch {
    Write-Error "Build exception: $($_.Exception.Message)"
    exit 1
} finally {
    # Cleanup
    if (Test-Path $variablesFile) {
        Remove-Item $variablesFile -Force
    }
}

Write-Host "`nBuild completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
