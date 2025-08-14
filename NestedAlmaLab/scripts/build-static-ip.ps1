# AlmaLinux Hyper-V Template Build with Static IP
# For Azure nested VM environments - no DHCP server required

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 2)]
    [int]$Generation = 1,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string]$SwitchName = "PackerInternal"
)

# Check if running as Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator for Hyper-V operations."
    exit 1
}

Write-Host "=== AlmaLinux Template Build (Static IP) ===" -ForegroundColor Cyan
Write-Host "Generation: $Generation"
Write-Host "Switch: $SwitchName"
Write-Host "Network: 192.168.200.0/24 (Static IP)"
Write-Host "======================================="

# Set paths
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$templatePath = Join-Path $projectRoot "templates/almalinux-simple.pkr.hcl"
$kickstartPath = Join-Path $projectRoot "templates/AlmaLinux/hyperv/ks.cfg"
$outputPath = Join-Path $projectRoot "output-almalinux-simple"

# Network configuration
$natNetwork = "192.168.200.0/24"
$hostIP = "192.168.200.1"
$natName = "PackerNAT200"

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

# Check Hyper-V
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

# Configure network switch with static IP
Write-Host "`n2. Configuring network switch..." -ForegroundColor Yellow

# Clean up any existing NAT rules with our name
$existingNat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
if ($existingNat) {
    Write-Host "  Removing existing NAT rule '$natName'..." -ForegroundColor Yellow
    Remove-NetNat -Name $natName -Confirm:$false
}

# Create or get the VM switch
$vmSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $vmSwitch) {
    Write-Host "  Creating Internal switch '$SwitchName'..." -ForegroundColor Yellow
    try {
        New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
        Write-Host "  [OK] Internal switch created" -ForegroundColor Green
        Start-Sleep 5  # Wait for switch to be fully created
    } catch {
        Write-Error "Failed to create Internal switch: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "  [OK] Using existing switch: $($vmSwitch.Name)" -ForegroundColor Green
}

# Find the network adapter for this switch
Write-Host "  Configuring virtual network adapter..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object { 
    $_.Name -like "*$SwitchName*" -or 
    $_.InterfaceDescription -like "*$SwitchName*" -or
    ($_.Name -like "vEthernet*" -and $_.InterfaceDescription -like "*Hyper-V*")
} | Sort-Object Name | Select-Object -First 1

if (-not $adapter) {
    Write-Error "Could not find network adapter for switch '$SwitchName'"
    Write-Host "Available adapters:"
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status -AutoSize
    exit 1
}

Write-Host "  Using adapter: $($adapter.Name) (Index: $($adapter.InterfaceIndex))" -ForegroundColor Green

# Remove existing IP configurations from this adapter
Write-Host "  Cleaning existing IP configurations..." -ForegroundColor Yellow
$existingIPs = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
foreach ($ip in $existingIPs) {
    if ($ip.IPAddress -notlike "169.254.*" -and $ip.IPAddress -ne "127.0.0.1") {
        Remove-NetIPAddress -IPAddress $ip.IPAddress -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# Remove existing routes
Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue

# Configure the static IP
try {
    New-NetIPAddress -IPAddress $hostIP -PrefixLength 24 -InterfaceIndex $adapter.InterfaceIndex | Out-Null
    Write-Host "  [OK] Host adapter configured with IP: $hostIP" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*already exists*") {
        Write-Host "  [OK] IP address already configured: $hostIP" -ForegroundColor Green
    } else {
        Write-Error "Failed to configure IP address: $($_.Exception.Message)"
        exit 1
    }
}

# Create NAT rule
try {
    New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $natNetwork | Out-Null
    Write-Host "  [OK] NAT configured: $natNetwork" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*already exists*") {
        Write-Host "  [OK] NAT rule already exists: $natName" -ForegroundColor Green
    } else {
        Write-Error "Failed to configure NAT: $($_.Exception.Message)"
        exit 1
    }
}

# Verify network configuration
Write-Host "`n3. Verifying network configuration..." -ForegroundColor Yellow
Start-Sleep 3

$verifyIP = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $hostIP }
if ($verifyIP) {
    Write-Host "  [OK] Host IP verified: $($verifyIP.IPAddress)" -ForegroundColor Green
} else {
    Write-Warning "Could not verify host IP configuration"
    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 | Format-Table IPAddress, PrefixLength -AutoSize
}

$verifyNat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
if ($verifyNat) {
    Write-Host "  [OK] NAT rule verified: $($verifyNat.InternalIPInterfaceAddressPrefix)" -ForegroundColor Green
} else {
    Write-Warning "Could not verify NAT configuration"
}

# Display current network state
Write-Host "`n4. Current Network Configuration:" -ForegroundColor Cyan
Write-Host "  VM will use static IP: 192.168.200.100"
Write-Host "  Host IP (for HTTP server): $hostIP"
Write-Host "  Gateway: $hostIP"
Write-Host "  DNS: 8.8.8.8"

# Prepare output
Write-Host "`n5. Preparing output directory..." -ForegroundColor Yellow

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
Write-Host "`n6. Creating variables..." -ForegroundColor Yellow
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
Write-Host "`n7. Initializing Packer..." -ForegroundColor Yellow
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
Write-Host "`n8. Validating template..." -ForegroundColor Yellow
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

# Configure Windows Firewall
Write-Host "`n9. Configuring Windows Firewall..." -ForegroundColor Yellow
$firewallRuleName = "Packer HTTP Server"
try {
    $existingRule = Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $firewallRuleName
    }
    
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
}

# Start build
Write-Host "`n10. Starting build..." -ForegroundColor Green
Write-Host "Configuration:"
Write-Host "  - VM will use static IP: 192.168.200.100"
Write-Host "  - Host HTTP server will be accessible at: $hostIP:8080-8090"
Write-Host "  - No DHCP server required"
Write-Host ""
Write-Host "This will take 15-30 minutes."
Write-Host ""

try {
    & packer build -force -var-file="$variablesFile" $templatePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[SUCCESS] Template built successfully!" -ForegroundColor Green
        Write-Host "Location: $outputPath"
        Write-Host ""
        Write-Host "Network configuration used:"
        Write-Host "  VM IP: 192.168.200.100"
        Write-Host "  Host IP: $hostIP"
        Write-Host "  Gateway: $hostIP"
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
