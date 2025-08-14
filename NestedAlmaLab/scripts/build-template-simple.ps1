# Simplified AlmaLinux Template Builder using Packer
# Fixed networking issues for Hyper-V

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("v1", "v2")]
    [string]$KickstartVersion = "v2",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\Packer\Output",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "=== AlmaLinux Packer Template Builder (Fixed) ===" -ForegroundColor Cyan
Write-Host "Kickstart Version: $KickstartVersion"
Write-Host "Output Path: $OutputPath"
Write-Host "============================================="

# Check if Packer is installed
try {
    $packerVersion = & packer version 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Packer not found"
    }
    Write-Host "Packer is installed: $packerVersion" -ForegroundColor Green
} catch {
    Write-Error "Packer is not installed. Please install it first:"
    Write-Host "winget install HashiCorp.Packer"
    exit 1
}

# Setup paths
$packerDir = Join-Path $PSScriptRoot "..\packer"
$templateFile = Join-Path $packerDir "almalinux-fixed.pkr.hcl"
$variablesFile = Join-Path $packerDir "build-vars.pkrvars.hcl"

# Validate template exists
if (-not (Test-Path $templateFile)) {
    Write-Error "Packer template not found: $templateFile"
    exit 1
}

# Create output directories
Write-Host "Setting up directories..."
if ($Force -and (Test-Path $OutputPath)) {
    Write-Host "  Cleaning up existing output directory..." -ForegroundColor Yellow
    Remove-Item $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Convert paths for HCL
$outputPathHCL = $OutputPath -replace '\\', '/'

# Create variables file
Write-Host "Creating build variables..."
$variablesContent = @"
# Build Variables
vm_name = "almalinux-lab-${KickstartVersion}"
vm_memory = 2048
vm_disk_size = 30720
output_directory = "${outputPathHCL}"
kickstart_version = "${KickstartVersion}"
ssh_username = "root"
ssh_password = "alma123!"
"@

Set-Content -Path $variablesFile -Value $variablesContent
Write-Host "  Variables file created: $variablesFile"

# Validate kickstart template exists
$kickstartTemplate = Join-Path $PSScriptRoot "..\templates\AlmaLinux\$KickstartVersion\ks.cfg"
if (-not (Test-Path $kickstartTemplate)) {
    Write-Error "Kickstart template not found: $kickstartTemplate"
    exit 1
}
Write-Host "Using kickstart: $kickstartTemplate" -ForegroundColor Green

# Check Hyper-V Default Switch
Write-Host "Checking Hyper-V networking..."
try {
    $defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction Stop
    Write-Host "  Default Switch found and active" -ForegroundColor Green
    
    # Check for host adapter
    $adapters = Get-NetAdapter | Where-Object {$_.InterfaceDescription -match "Hyper-V" -and $_.Status -eq "Up"}
    if ($adapters) {
        Write-Host "  Found active Hyper-V adapters: $($adapters.Count)" -ForegroundColor Green
    } else {
        Write-Warning "  No active Hyper-V adapters found - this may cause networking issues"
    }
} catch {
    Write-Error "Default Switch not found. Please ensure Hyper-V is properly configured."
    exit 1
}

Write-Host "`nStarting Packer build..." -ForegroundColor Yellow
Write-Host "Estimated time: 15-30 minutes"
Write-Host "Monitor progress in Hyper-V Manager"
Write-Host ""

if (-not $Force) {
    $response = Read-Host "Continue with build? (Y/N)"
    if ($response -notmatch "^[Yy]") {
        Write-Host "Build cancelled."
        exit 0
    }
}

try {
    Push-Location $packerDir
    
    # Initialize plugins
    Write-Host "Initializing Packer plugins..." -ForegroundColor Yellow
    & packer init .
    if ($LASTEXITCODE -ne 0) {
        throw "Plugin initialization failed"
    }
    Write-Host "  Plugins ready" -ForegroundColor Green
    
    # Validate template
    Write-Host "Validating template..." -ForegroundColor Yellow
    & packer validate -var-file="$variablesFile" "$templateFile"
    if ($LASTEXITCODE -ne 0) {
        throw "Template validation failed"
    }
    Write-Host "  Template valid" -ForegroundColor Green
    
    # Build
    Write-Host "Building template..." -ForegroundColor Yellow
    & packer build -force -var-file="$variablesFile" "$templateFile"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n=== SUCCESS! ===" -ForegroundColor Green
        
        # Show created files
        $outputFiles = Get-ChildItem $OutputPath -Recurse -File | Sort-Object LastWriteTime -Descending
        if ($outputFiles) {
            Write-Host "Template files created:"
            foreach ($file in $outputFiles | Select-Object -First 5) {
                $size = if ($file.Length -gt 1GB) { "$([math]::Round($file.Length/1GB,2)) GB" } else { "$([math]::Round($file.Length/1MB,2)) MB" }
                Write-Host "  - $($file.Name) ($size)"
            }
        }
        
        Write-Host "`nNext steps:"
        Write-Host "1. Use deploy-from-template.ps1 to create VMs from this template"
        Write-Host "2. VMs will boot in seconds with everything pre-configured!"
        
    } else {
        throw "Build failed with exit code $LASTEXITCODE"
    }
    
} catch {
    Write-Error "Build failed: $($_.Exception.Message)"
    
    Write-Host "`n=== Troubleshooting ===" -ForegroundColor Yellow
    Write-Host "Common networking fixes:"
    Write-Host "1. Restart Hyper-V service: Restart-Service vmms"
    Write-Host "2. Check Windows Firewall is allowing Packer"
    Write-Host "3. Try with a different switch (create External switch)"
    Write-Host "4. Run as Administrator"
    
    exit 1
} finally {
    Pop-Location
}

Write-Host "`nBuild completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
