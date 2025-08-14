# Simple AlmaLinux Hyper-V Template Build
# No checksum verification, focuses on getting the build working

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 2)]
    [int]$Generation = 1,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string]$SwitchName = "PackerExternal"
)

# Check if running as Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator for Hyper-V operations."
    exit 1
}

Write-Host "=== Simple AlmaLinux Template Build ===" -ForegroundColor Cyan
Write-Host "Generation: $Generation"
Write-Host "Switch: $SwitchName"
Write-Host "======================================="

# Set paths
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$templatePath = Join-Path $projectRoot "templates/almalinux-simple.pkr.hcl"
$kickstartPath = Join-Path $projectRoot "templates/AlmaLinux/hyperv/ks.cfg"
$outputPath = Join-Path $projectRoot "output-almalinux-simple"

# Check prerequisites
Write-Host "`n1. Checking prerequisites..." -ForegroundColor Yellow

# Check Packer
try {
    $packerVersion = & packer version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Packer found" -ForegroundColor Green
    } else {
        throw "Packer not found"
    }
} catch {
    Write-Error "Packer not installed. Install with: winget install hashicorp.packer"
    exit 1
}

# Check if we can list VM switches (basic Hyper-V check)
try {
    $switches = Get-VMSwitch -ErrorAction SilentlyContinue
    Write-Host "  [OK] Hyper-V is functional" -ForegroundColor Green
} catch {
    Write-Error "Hyper-V not functional. Check Hyper-V installation."
    exit 1
}

# Check template files
if (-not (Test-Path $templatePath)) {
    Write-Error "Template not found: $templatePath"
    exit 1
}

if (-not (Test-Path $kickstartPath)) {
    Write-Error "Kickstart file not found: $kickstartPath"
    exit 1
}

# Check ISO file
$isoPath = "C:\ISOs\AlmaLinux-9-latest-x86_64-dvd.iso"
if (-not (Test-Path $isoPath)) {
    Write-Error "ISO file not found: $isoPath"
    Write-Host "Please ensure the AlmaLinux ISO is available at: $isoPath"
    exit 1
}

$isoSize = (Get-Item $isoPath).Length / 1MB
Write-Host "  [OK] Template files found" -ForegroundColor Green
Write-Host "  [OK] ISO file found: $isoPath ($([math]::Round($isoSize, 1)) MB)" -ForegroundColor Green

# Check switch
$vmSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $vmSwitch) {
    Write-Error "VM Switch '$SwitchName' not found"
    Write-Host "Available switches:"
    Get-VMSwitch | ForEach-Object { Write-Host "  - $($_.Name) ($($_.SwitchType))" }
    exit 1
}

Write-Host "  [OK] Using switch: $($vmSwitch.Name)" -ForegroundColor Green

# Prepare output
Write-Host "`n2. Preparing output directory..." -ForegroundColor Yellow

if (Test-Path $outputPath) {
    if ($Force) {
        Remove-Item $outputPath -Recurse -Force
        Write-Host "  [OK] Removed existing output" -ForegroundColor Green
    } else {
        Write-Error "Output directory exists. Use -Force to overwrite."
        exit 1
    }
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
Write-Host "  [OK] Output directory ready" -ForegroundColor Green

# Create variables
Write-Host "`n3. Creating variables..." -ForegroundColor Yellow
$variablesFile = Join-Path $scriptPath "simple-vars.pkrvars.hcl"
$variablesContent = @"
iso_path = "C:/ISOs/AlmaLinux-9-latest-x86_64-dvd.iso"
generation = $Generation
switch_name = "$SwitchName"
output_directory = "$($outputPath.Replace('\', '/'))"
vm_name = "almalinux-simple-gen$Generation"
"@

Set-Content -Path $variablesFile -Value $variablesContent -Encoding UTF8
Write-Host "  [OK] Variables created" -ForegroundColor Green

# Initialize Packer
Write-Host "`n4. Initializing Packer..." -ForegroundColor Yellow
try {
    Set-Location $projectRoot
    & packer init $templatePath
    if ($LASTEXITCODE -ne 0) {
        throw "Packer init failed"
    }
    Write-Host "  [OK] Packer initialized" -ForegroundColor Green
} catch {
    Write-Error "Failed to initialize Packer: $($_.Exception.Message)"
    exit 1
}

# Validate template
Write-Host "`n5. Validating template..." -ForegroundColor Yellow
try {
    & packer validate -var-file="$variablesFile" $templatePath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Template valid" -ForegroundColor Green
    } else {
        throw "Template validation failed"
    }
} catch {
    Write-Error "Template validation failed: $($_.Exception.Message)"
    exit 1
}

# Configure Windows Firewall for Packer HTTP server
Write-Host "`n6. Configuring Windows Firewall..." -ForegroundColor Yellow

# Create firewall rule for Packer HTTP server (ports 8080-8090)
$firewallRuleName = "Packer HTTP Server"
try {
    # Remove existing rule if it exists
    $existingRule = Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $firewallRuleName
        Write-Host "  [OK] Removed existing firewall rule" -ForegroundColor Green
    }
    
    # Create new inbound rule
    New-NetFirewallRule -DisplayName $firewallRuleName `
                       -Direction Inbound `
                       -Protocol TCP `
                       -LocalPort 8080-8090 `
                       -Action Allow `
                       -Profile Any `
                       -Description "Allow Packer HTTP server for kickstart files" | Out-Null
    
    Write-Host "  [OK] Firewall rule created for ports 8080-8090" -ForegroundColor Green
} catch {
    Write-Warning "Failed to configure firewall rule: $($_.Exception.Message)"
    Write-Host "  [MANUAL] You may need to manually allow ports 8080-8090 in Windows Firewall" -ForegroundColor Yellow
}

# Start build
Write-Host "`n7. Starting build..." -ForegroundColor Green
Write-Host "This will take 15-30 minutes."
Write-Host "Watch the VM console for network detection."
Write-Host ""

try {
    & packer build -force -var-file="$variablesFile" $templatePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[SUCCESS] Template built successfully!" -ForegroundColor Green
        Write-Host "Location: $outputPath"
    } else {
        Write-Host "`n[FAILED] Build failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Error "Build failed: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $variablesFile) {
        Remove-Item $variablesFile -Force
    }
}
