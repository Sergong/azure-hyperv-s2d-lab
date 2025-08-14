# AlmaLinux Template Builder using Packer
# This script sets up and runs Packer to build AlmaLinux VM templates for Hyper-V

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("v1", "v2")]
    [string]$KickstartVersion = "v2",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 2)]
    [int]$Generation = 2,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\Packer\Output",
    
    [Parameter(Mandatory=$false)]
    [switch]$InstallPacker,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "=== AlmaLinux Packer Template Builder ===" -ForegroundColor Cyan
Write-Host "Building AlmaLinux template for Hyper-V"
Write-Host "Kickstart Version: $KickstartVersion"
Write-Host "VM Generation: $Generation"
Write-Host "Output Path: $OutputPath"
Write-Host "========================================"

# Function to check if Packer is installed
function Test-PackerInstalled {
    try {
        $packerVersion = & packer version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Packer is installed: $packerVersion" -ForegroundColor Green
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

# Function to install Packer
function Install-Packer {
    Write-Host "Installing Packer..." -ForegroundColor Yellow
    
    try {
        # Try winget first (Windows 10/11)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "  Using winget to install Packer..."
            winget install HashiCorp.Packer --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Packer installed successfully via winget" -ForegroundColor Green
                return $true
            }
        }
        
        # Fallback: Download and install manually
        Write-Host "  Downloading Packer manually..."
        $packerUrl = "https://releases.hashicorp.com/packer/1.10.0/packer_1.10.0_windows_amd64.zip"
        $packerZip = "${env:TEMP}\packer.zip"
        $packerDir = "${env:ProgramFiles}\Packer"
        
        Invoke-WebRequest -Uri $packerUrl -OutFile $packerZip -UseBasicParsing
        
        # Extract Packer
        New-Item -ItemType Directory -Path $packerDir -Force | Out-Null
        Expand-Archive -Path $packerZip -DestinationPath $packerDir -Force
        
        # Add to PATH
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$packerDir*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$packerDir", "Machine")
            $env:PATH += ";$packerDir"
        }
        
        # Cleanup
        Remove-Item $packerZip -Force -ErrorAction SilentlyContinue
        
        Write-Host "  Packer installed successfully to: $packerDir" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Error "Failed to install Packer: $($_.Exception.Message)"
        return $false
    }
}

# Check if Packer is installed
if (-not (Test-PackerInstalled)) {
    if ($InstallPacker) {
        if (-not (Install-Packer)) {
            Write-Error "Could not install Packer. Please install manually."
            exit 1
        }
    } else {
        Write-Error "Packer is not installed. Run with -InstallPacker to install automatically, or install manually:"
        Write-Host "Manual installation options:"
        Write-Host "1. winget install HashiCorp.Packer"
        Write-Host "2. Download from: https://www.packer.io/downloads"
        exit 1
    }
}

# Setup paths
$packerDir = Join-Path $PSScriptRoot "..\packer"
$templateFile = Join-Path $packerDir "almalinux.pkr.hcl"
$variablesFile = Join-Path $packerDir "variables.pkrvars.hcl"

# Validate template exists
if (-not (Test-Path $templateFile)) {
    Write-Error "Packer template not found: $templateFile"
    Write-Host "Please ensure the template file exists in the packer directory."
    exit 1
}

# Create output directories and clean up if needed
Write-Host "Setting up directories..."
if ($Force -and (Test-Path $OutputPath)) {
    Write-Host "  Force flag specified - cleaning up existing output directory..." -ForegroundColor Yellow
    Remove-Item $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $OutputPath, "C:\Packer\Temp" -Force | Out-Null

# Create variables file for this build
Write-Host "Creating Packer variables file..."
# Convert Windows paths to forward slashes for HCL
$outputPathHCL = $OutputPath -replace '\\', '/'
$tempPathHCL = "C:/Packer/Temp"

# Get host IP address for Hyper-V Default Switch
$hostIP = "192.168.1.1"  # Default for Hyper-V Default Switch
try {
    # Try to get the actual IP of the Default Switch
    $switchInfo = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
    if ($switchInfo) {
        # Get the host adapter IP for Default Switch
        $netAdapter = Get-NetAdapter | Where-Object {$_.InterfaceDescription -match "Hyper-V" -and $_.InterfaceDescription -match "Default"}
        if ($netAdapter) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $netAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ipConfig) {
                $hostIP = $ipConfig.IPAddress
                Write-Host "  Detected Hyper-V host IP: $hostIP" -ForegroundColor Green
            }
        }
    }
    
    # Fallback: try to get any local IP that's not loopback
    if ($hostIP -eq "192.168.1.1") {
        $localIPs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notmatch "^127\.|^169\.254\."}
        if ($localIPs) {
            $hostIP = $localIPs[0].IPAddress
            Write-Host "  Using fallback host IP: $hostIP" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Warning "Could not detect host IP, using default: $hostIP"
}

$variablesContent = @"
# Packer Variables for AlmaLinux Lab Template
vm_name = "almalinux-lab-${KickstartVersion}-gen${Generation}"
vm_memory = 2048
vm_disk_size = 30720
output_directory = "${outputPathHCL}"
temp_path = "${tempPathHCL}"
kickstart_version = "${KickstartVersion}"
host_ip = "${hostIP}"
iso_checksum = "file:https://repo.almalinux.org/almalinux/9/isos/x86_64/CHECKSUM"
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

Write-Host "Using kickstart template: $kickstartTemplate" -ForegroundColor Green

# Run Packer
Write-Host "`nStarting Packer build..." -ForegroundColor Yellow
Write-Host "This process will:"
Write-Host "1. Download the AlmaLinux ISO (if not cached)"
Write-Host "2. Create a new Hyper-V VM"
Write-Host "3. Boot from ISO and run automated installation"
Write-Host "4. Configure the VM with your kickstart settings"
Write-Host "5. Install additional software (Docker, dev tools, etc.)"
Write-Host "6. Export the VM as a reusable template"
Write-Host ""
Write-Host "Estimated time: 15-30 minutes depending on internet speed"
Write-Host "The VM will appear in Hyper-V Manager during the build process"
Write-Host ""

if (-not $Force) {
    $response = Read-Host "Continue with Packer build? (Y/N)"
    if ($response -notmatch "^[Yy]") {
        Write-Host "Build cancelled by user."
        exit 0
    }
}

try {
    # Change to packer directory
    Push-Location $packerDir
    
    # Initialize Packer (downloads required plugins)
    Write-Host "Initializing Packer plugins..." -ForegroundColor Yellow
    Write-Host "  Downloading Hyper-V plugin..."
    $initResult = & packer init . 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Packer init failed: $initResult"
        Write-Host "This might be due to:"
        Write-Host "1. Internet connectivity issues"
        Write-Host "2. Firewall blocking plugin downloads"
        Write-Host "3. Proxy configuration needed"
        throw "Packer plugin initialization failed"
    }
    Write-Host "  Plugins initialized successfully" -ForegroundColor Green
    
    # Validate template
    Write-Host "Validating Packer template..." -ForegroundColor Yellow
    & packer validate -var-file="$variablesFile" "$templateFile"
    if ($LASTEXITCODE -ne 0) {
        throw "Packer template validation failed"
    }
    Write-Host "  Template validation successful" -ForegroundColor Green
    
    # Clean up any previous build artifacts for this specific template
    $vmTemplateName = "almalinux-lab-${KickstartVersion}-gen${Generation}"
    $existingArtifacts = Get-ChildItem $OutputPath -Filter "*${vmTemplateName}*" -ErrorAction SilentlyContinue
    if ($existingArtifacts) {
        Write-Host "Cleaning up previous build artifacts for ${vmTemplateName}..." -ForegroundColor Yellow
        foreach ($artifact in $existingArtifacts) {
            Remove-Item $artifact.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Build template
    Write-Host "Starting Packer build..." -ForegroundColor Yellow
    Write-Host "  You can monitor progress in Hyper-V Manager"
    Write-Host "  Look for VM: almalinux-lab-${KickstartVersion}-gen${Generation}"
    Write-Host ""
    
    & packer build -force -var-file="$variablesFile" "$templateFile"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n=== Build Completed Successfully! ===" -ForegroundColor Green
        
        # List created files
        $outputFiles = Get-ChildItem $OutputPath -Filter "*almalinux-lab*" | Sort-Object LastWriteTime -Descending
        if ($outputFiles) {
            Write-Host "Created template files:"
            foreach ($file in $outputFiles) {
                Write-Host "  - $($file.FullName) ($([math]::Round($file.Length/1GB,2)) GB)"
            }
        }
        
        Write-Host "`n=== Usage Instructions ===" -ForegroundColor Yellow
        Write-Host "1. Import the VHDX as a template in Hyper-V:"
        Write-Host "   Import-VM -Path '${OutputPath}\Virtual Machines\*.vmcx'"
        Write-Host ""
        Write-Host "2. Or copy the VHDX file and create new VMs from it:"
        Write-Host "   Copy-Item '${OutputPath}\*.vhdx' 'C:\HyperV\Templates\'"
        Write-Host ""
        Write-Host "3. Create new VMs from template:"
        Write-Host "   New-VM -Name 'MyLabVM' -VHDPath 'C:\HyperV\Templates\template.vhdx'"
        Write-Host ""
        Write-Host "4. Template includes:"
        Write-Host "   - AlmaLinux 9 with all updates"
        Write-Host "   - Docker pre-installed and configured"
        Write-Host "   - Development tools (git, vim, python3, etc.)"
        Write-Host "   - SSH configured (root/alma123!, labuser/labpass123!)"
        Write-Host "   - Ready for nested virtualization"
        
    } else {
        throw "Packer build failed with exit code $LASTEXITCODE"
    }
    
} catch {
    Write-Error "Packer build failed: $($_.Exception.Message)"
    Write-Host "`n=== Troubleshooting Tips ===" -ForegroundColor Yellow
    Write-Host "1. Check Hyper-V is enabled and you have admin rights"
    Write-Host "2. Ensure sufficient disk space in $OutputPath"
    Write-Host "3. Check Windows Firewall isn't blocking Packer's HTTP server"
    Write-Host "4. Verify internet connectivity for ISO download"
    Write-Host "5. Check Packer logs in the console output above"
    
    exit 1
} finally {
    Pop-Location
}

Write-Host "`nPacker build process completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
