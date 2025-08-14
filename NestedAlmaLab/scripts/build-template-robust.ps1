# Enhanced Packer Build Script with Automatic Network Switch Management
# Addresses the "Error getting host adapter ip address: No ip address" issue

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("v1", "v2")]
    [string]$KickstartVersion = "v2",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Default Switch", "External", "Internal")]
    [string]$NetworkMode = "External",
    
    [Parameter(Mandatory=$false)]
    [string]$ExternalAdapterName,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipNetworkSetup
)

# Ensure we're running as Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator for Hyper-V operations."
    Write-Host "Please run PowerShell as Administrator and try again."
    exit 1
}

Write-Host "=== Enhanced Packer Build with Network Management ===" -ForegroundColor Cyan
Write-Host "Building AlmaLinux template with robust networking"
Write-Host "Network Mode: $NetworkMode"
Write-Host "====================================================="

# Set paths
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$templatePath = Join-Path $projectRoot "templates/almalinux-robust.pkr.hcl"
$kickstartPath = Join-Path $projectRoot "kickstart"
$outputPath = Join-Path $projectRoot "output-almalinux"

# Function to test network connectivity
function Test-NetworkConnectivity {
    param([string]$TestName, [string]$Target, [int]$Port = 80)
    
    Write-Host "  Testing $TestName..." -NoNewline
    try {
        $result = Test-NetConnection -ComputerName $Target -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($result) {
            Write-Host " ✅" -ForegroundColor Green
            return $true
        } else {
            Write-Host " ❌" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host " ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to get or create VM switch
function Get-OrCreateVMSwitch {
    param([string]$Mode, [string]$AdapterName)
    
    Write-Host "`nConfiguring VM Switch (Mode: $Mode)..." -ForegroundColor Yellow
    
    switch ($Mode) {
        "Default Switch" {
            $switch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
            if ($switch) {
                Write-Host "  ✅ Using existing Default Switch" -ForegroundColor Green
                
                # Check if Default Switch has network connectivity
                $adapters = Get-NetAdapter | Where-Object {$_.InterfaceDescription -match "Default" -or $_.Name -match "Default"}
                if ($adapters) {
                    $hasIP = $false
                    foreach ($adapter in $adapters) {
                        $ips = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                        if ($ips) {
                            Write-Host "  ✅ Default Switch adapter has IP: $($ips[0].IPAddress)" -ForegroundColor Green
                            $hasIP = $true
                            break
                        }
                    }
                    if (-not $hasIP) {
                        Write-Warning "  Default Switch exists but no IP found - this may cause Packer issues"
                        return $null
                    }
                } else {
                    Write-Warning "  Default Switch exists but no associated adapters found"
                    return $null
                }
                return $switch
            } else {
                Write-Host "  ❌ Default Switch not found" -ForegroundColor Red
                return $null
            }
        }
        
        "External" {
            $switchName = "PackerExternal"
            $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
            
            if ($existingSwitch) {
                Write-Host "  ✅ Using existing External switch: $switchName" -ForegroundColor Green
                return $existingSwitch
            }
            
            # Create new external switch
            Write-Host "  Creating new External switch: $switchName" -ForegroundColor Yellow
            
            # Find suitable physical adapter
            $physicalAdapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Virtual -eq $false}
            
            if (-not $physicalAdapters) {
                Write-Error "  No active physical network adapters found"
                return $null
            }
            
            $selectedAdapter = if ($AdapterName) {
                $physicalAdapters | Where-Object {$_.Name -eq $AdapterName}
            } else {
                $physicalAdapters[0]  # Use first available
            }
            
            if (-not $selectedAdapter) {
                Write-Error "  Specified adapter '$AdapterName' not found or not suitable"
                return $null
            }
            
            try {
                Write-Host "  Using adapter: $($selectedAdapter.Name)" -ForegroundColor Green
                $newSwitch = New-VMSwitch -Name $switchName -NetAdapterName $selectedAdapter.Name -AllowManagementOS $true
                Write-Host "  ✅ External switch created successfully" -ForegroundColor Green
                return $newSwitch
            } catch {
                Write-Error "  Failed to create External switch: $($_.Exception.Message)"
                return $null
            }
        }
        
        "Internal" {
            $switchName = "PackerInternal"
            $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
            
            if ($existingSwitch) {
                Write-Host "  ✅ Using existing Internal switch: $switchName" -ForegroundColor Green
                return $existingSwitch
            }
            
            # Create internal switch
            Write-Host "  Creating new Internal switch: $switchName" -ForegroundColor Yellow
            try {
                $newSwitch = New-VMSwitch -Name $switchName -SwitchType Internal
                Write-Host "  ✅ Internal switch created" -ForegroundColor Green
                
                # Configure IP on host adapter
                Start-Sleep -Seconds 2  # Wait for adapter creation
                $adapter = Get-NetAdapter | Where-Object {$_.Name -match $switchName}
                if ($adapter) {
                    try {
                        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress "192.168.99.1" -PrefixLength 24 -ErrorAction SilentlyContinue
                        Write-Host "  ✅ Host adapter configured with IP: 192.168.99.1" -ForegroundColor Green
                    } catch {
                        Write-Warning "  Could not configure host adapter IP: $($_.Exception.Message)"
                    }
                }
                
                return $newSwitch
            } catch {
                Write-Error "  Failed to create Internal switch: $($_.Exception.Message)"
                return $null
            }
        }
    }
}

# 1. Check prerequisites
Write-Host "`n1. Checking prerequisites..." -ForegroundColor Yellow

# Check Packer
try {
    $packerVersion = & packer version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Packer installed: $($packerVersion.Split("`n")[0])" -ForegroundColor Green
    } else {
        throw "Packer not found"
    }
} catch {
    Write-Error "  Packer not installed. Install with: winget install hashicorp.packer"
    exit 1
}

# Check Hyper-V
$hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
if ($hyperVFeature -and $hyperVFeature.State -eq "Enabled") {
    Write-Host "  ✅ Hyper-V is enabled" -ForegroundColor Green
} else {
    Write-Error "  Hyper-V is not enabled. Enable with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All"
    exit 1
}

# 2. Network connectivity tests
Write-Host "`n2. Testing network connectivity..." -ForegroundColor Yellow
$internetOK = Test-NetworkConnectivity "Internet" "8.8.8.8"
$dnsOK = Test-NetworkConnectivity "DNS" "google.com"
$repoOK = Test-NetworkConnectivity "AlmaLinux Repo" "repo.almalinux.org" 443

if (-not ($internetOK -and $dnsOK -and $repoOK)) {
    Write-Warning "Network connectivity issues detected. Build may fail."
}

# 3. Configure VM Switch
if (-not $SkipNetworkSetup) {
    $vmSwitch = Get-OrCreateVMSwitch -Mode $NetworkMode -AdapterName $ExternalAdapterName
    
    if (-not $vmSwitch) {
        Write-Error "Failed to configure VM switch. Cannot proceed with build."
        Write-Host "`nTry these alternatives:"
        Write-Host "1. Run with -NetworkMode 'External': .\$($MyInvocation.MyCommand.Name) -NetworkMode External"
        Write-Host "2. Run with -NetworkMode 'Internal': .\$($MyInvocation.MyCommand.Name) -NetworkMode Internal"
        Write-Host "3. Fix Default Switch manually and run with -SkipNetworkSetup"
        exit 1
    }
    
    $switchToUse = $vmSwitch.Name
} else {
    $switchToUse = "Default Switch"
    Write-Host "`nSkipping network setup - using Default Switch" -ForegroundColor Yellow
}

Write-Host "  Using VM Switch: $switchToUse" -ForegroundColor Green

# 4. Prepare directories
Write-Host "`n3. Preparing directories..." -ForegroundColor Yellow

if (Test-Path $outputPath) {
    if ($Force) {
        Write-Host "  Removing existing output directory..." -ForegroundColor Yellow
        Remove-Item $outputPath -Recurse -Force
    } else {
        Write-Error "  Output directory exists. Use -Force to overwrite."
        exit 1
    }
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
Write-Host "  ✅ Output directory ready: $outputPath" -ForegroundColor Green

# 5. Validate template and kickstart
Write-Host "`n4. Validating build files..." -ForegroundColor Yellow

if (-not (Test-Path $templatePath)) {
    Write-Error "  Packer template not found: $templatePath"
    exit 1
}

$kickstartFile = Join-Path $kickstartPath "kickstart-$KickstartVersion.cfg"
if (-not (Test-Path $kickstartFile)) {
    Write-Error "  Kickstart file not found: $kickstartFile"
    exit 1
}

Write-Host "  ✅ Template: $templatePath" -ForegroundColor Green
Write-Host "  ✅ Kickstart: $kickstartFile" -ForegroundColor Green

# 6. Create variables file
Write-Host "`n5. Creating variables file..." -ForegroundColor Yellow
$variablesFile = Join-Path $scriptPath "packer-vars.pkrvars.hcl"
$variablesContent = @"
kickstart_version = "$KickstartVersion"
switch_name = "$switchToUse"
output_directory = "$($outputPath.Replace('\', '/'))"
vm_name = "almalinux-9.4-template"
"@

Set-Content -Path $variablesFile -Value $variablesContent -Encoding UTF8
Write-Host "  ✅ Variables file created: $variablesFile" -ForegroundColor Green

# 7. Initialize Packer plugins
Write-Host "`n6. Initializing Packer plugins..." -ForegroundColor Yellow
try {
    Set-Location $projectRoot
    $initOutput = & packer init $templatePath 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Packer plugins initialized" -ForegroundColor Green
    } else {
        Write-Error "  Plugin initialization failed: $initOutput"
        exit 1
    }
} catch {
    Write-Error "  Exception during plugin init: $($_.Exception.Message)"
    exit 1
}

# 8. Validate template
Write-Host "`n7. Validating Packer template..." -ForegroundColor Yellow
try {
    $validateOutput = & packer validate -var-file="$variablesFile" $templatePath 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Template validation passed" -ForegroundColor Green
    } else {
        Write-Error "  Template validation failed: $validateOutput"
        exit 1
    }
} catch {
    Write-Error "  Exception during validation: $($_.Exception.Message)"
    exit 1
}

# 9. Final pre-build checks
Write-Host "`n8. Final pre-build checks..." -ForegroundColor Yellow

# Check firewall rules for Packer HTTP server
try {
    $packerRules = Get-NetFirewallRule -DisplayName "*Packer*" -ErrorAction SilentlyContinue
    if (-not $packerRules) {
        Write-Host "  Creating firewall rule for Packer HTTP server..." -ForegroundColor Yellow
        New-NetFirewallRule -DisplayName "Packer HTTP Server" -Direction Inbound -Protocol TCP -LocalPort 8080-8090 -Action Allow | Out-Null
        Write-Host "  ✅ Firewall rule created" -ForegroundColor Green
    } else {
        Write-Host "  ✅ Packer firewall rules exist" -ForegroundColor Green
    }
} catch {
    Write-Warning "  Could not configure firewall rules: $($_.Exception.Message)"
}

# Display network configuration
Write-Host "`n9. Network Configuration Summary:" -ForegroundColor Cyan
$switch = Get-VMSwitch -Name $switchToUse -ErrorAction SilentlyContinue
if ($switch) {
    Write-Host "  Switch Name: $($switch.Name)"
    Write-Host "  Switch Type: $($switch.SwitchType)"
    
    if ($switch.SwitchType -ne "Private") {
        # Find associated host adapter
        $adapters = Get-NetAdapter | Where-Object {
            $_.Name -match $switch.Name -or 
            $_.InterfaceDescription -match $switch.Name -or
            ($switch.SwitchType -eq "External" -and $_.Name -eq $switch.NetAdapterInterfaceDescription)
        }
        
        foreach ($adapter in $adapters) {
            $ips = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ips) {
                Write-Host "  Host Adapter: $($adapter.Name) - IP: $($ips[0].IPAddress)" -ForegroundColor Green
            }
        }
    }
}

# 10. Start the build
Write-Host "`n10. Starting Packer build..." -ForegroundColor Green
Write-Host "This may take 15-30 minutes depending on your internet connection."
Write-Host "The VM console will be visible for monitoring progress."
Write-Host ""

try {
    $buildArgs = @(
        "build"
        "-force"
        "-var-file=$variablesFile"
        $templatePath
    )
    
    Write-Host "Running: packer $($buildArgs -join ' ')" -ForegroundColor Gray
    Write-Host ""
    
    & packer @buildArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n🎉 SUCCESS: AlmaLinux template built successfully!" -ForegroundColor Green
        Write-Host "Template location: $outputPath"
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "1. Test the template: .\deploy-from-template.ps1"
        Write-Host "2. Create VMs from template using Hyper-V Manager or PowerShell"
    } else {
        Write-Host "`n❌ BUILD FAILED" -ForegroundColor Red
        Write-Host ""
        Write-Host "If you still get 'Error getting host adapter ip address':"
        Write-Host "1. Try External switch: .\$($MyInvocation.MyCommand.Name) -NetworkMode External"
        Write-Host "2. Try Internal switch: .\$($MyInvocation.MyCommand.Name) -NetworkMode Internal"
        Write-Host "3. Check Windows Firewall settings"
        Write-Host "4. Restart Hyper-V service: Restart-Service vmms"
        exit 1
    }
    
} catch {
    Write-Error "`nBuild failed with exception: $($_.Exception.Message)"
    exit 1
} finally {
    # Cleanup
    if (Test-Path $variablesFile) {
        Remove-Item $variablesFile -Force
    }
}

Write-Host "`nBuild completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
