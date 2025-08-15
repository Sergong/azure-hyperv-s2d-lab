# Build AlmaLinux Packer Template with cloud-init support
# This creates a more flexible template that can be customized at deployment time

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet(1, 2)]
    [int]$Generation = 1,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string]$ISOPath = "C:\ISOs\AlmaLinux-9-latest-x86_64-dvd.iso"
)

Write-Host "=== Building Cloud-init Enabled AlmaLinux Template ===" -ForegroundColor Cyan
Write-Host "Generation: $Generation"
Write-Host "ISO Path: $ISOPath"
Write-Host "Force rebuild: $Force"
Write-Host "============================================="

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath

# Verify ISO exists
if (-not (Test-Path $ISOPath)) {
    Write-Error "ISO file not found: $ISOPath"
    Write-Host "Please download AlmaLinux 9 ISO and place it at the specified path."
    exit 1
}

# Verify kickstart file exists
$kickstartPath = Join-Path $projectRoot "templates\AlmaLinux\hyperv\ks-with-cloudinit.cfg"
if (-not (Test-Path $kickstartPath)) {
    Write-Error "Cloud-init kickstart file not found: $kickstartPath"
    Write-Host "Please ensure ks-with-cloudinit.cfg exists in the templates directory."
    exit 1
}

# Determine output path based on generation
if ($Generation -eq 1) {
    $outputPath = Join-Path $projectRoot "output-almalinux-cloudinit-gen1"
} elseif ($Generation -eq 2) {
    $outputPath = Join-Path $projectRoot "output-almalinux-cloudinit-gen2"
} else {
    Write-Error "Invalid generation specified: $Generation. Must be 1 or 2."
    exit 1
}

# Check if template already exists
if ((Test-Path $outputPath) -and -not $Force) {
    Write-Warning "Template already exists at: $outputPath"
    Write-Host "Use -Force to rebuild the template."
    
    $choice = Read-Host "Do you want to rebuild? (y/N)"
    if ($choice -notmatch '^[Yy]') {
        Write-Host "Build cancelled."
        exit 0
    }
}

# Clean existing output if force rebuild
if ($Force -and (Test-Path $outputPath)) {
    Write-Host "Cleaning existing template..." -ForegroundColor Yellow
    Remove-Item $outputPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Function to create Packer template
function New-PackerTemplate {
    param(
        [int]$Generation,
        [string]$ISOPath
    )
    
    $escapedISOPath = $ISOPath -replace '\\', '\\\\'
    
    $template = ""
    $template += "packer {`n"
    $template += "  required_plugins {`n"
    $template += "    hyperv = {`n"
    $template += "      version = `"~> 1`"`n"
    $template += "      source  = `"github.com/hashicorp/hyperv`"`n"
    $template += "    }`n"
    $template += "  }`n"
    $template += "}`n`n"
    
    $template += "variable `"iso_path`" {`n"
    $template += "  type        = string`n"
    $template += "  description = `"Path to AlmaLinux ISO file`"`n"
    $template += "  default     = `"$escapedISOPath`"`n"
    $template += "}`n`n"
    
    $sourceName = "almalinux-cloudinit-gen$Generation"
    $template += "source `"hyperv-iso`" `"$sourceName`" {`n"
    $template += "  # ISO configuration`n"
    $template += "  iso_url      = var.iso_path`n"
    $template += "  iso_checksum = `"none`"`n"
    $template += "  iso_target_path = `"C:/temp/packer-almalinux-gen$Generation.iso`"`n"
    $template += "  `n"
    $template += "  # VM configuration`n"
    $template += "  vm_name              = `"AlmaLinux-CloudInit-Gen$Generation-Template`"`n"
    $template += "  generation           = $Generation`n"
    $template += "  cpus                 = 2`n"
    $template += "  memory               = 2048`n"
    $template += "  disk_size            = 20480`n"
    
    if ($Generation -eq 2) {
        $template += "  enable_secure_boot   = false`n"
        $template += "  secure_boot_template = `"MicrosoftUEFICertificateAuthority`"`n"
    }
    
    $template += "  `n"
    $template += "  # Network configuration`n"
    $template += "  switch_name = `"PackerInternal`"`n"
    $template += "  `n"
    
    if ($Generation -eq 1) {
        # Generation 1 (BIOS) boot commands
        $template += "  # Boot configuration for Generation 1 (BIOS)`n"
        $template += "  boot_wait = `"10s`"`n"
        $template += "  boot_command = [`n"
        $template += "    `"<tab>`",              # Edit the default boot entry`n"
        $template += "    `" text`",              # Add text mode`n"
        $template += "    `" inst.ks=http://{{.HTTPIP}}:{{.HTTPPort}}/ks-with-cloudinit.cfg`",`n"
        $template += "    `" ip=192.168.200.100::192.168.200.1:255.255.255.0:almavm:eth0:none:8.8.8.8`",`n"
        $template += "    `" biosdevname=0`",`n"
        $template += "    `" net.ifnames=0`",`n"
        $template += "    `" rd.live.check=0`",`n"
        $template += "    `"<enter>`"             # Boot with modified parameters`n"
        $template += "  ]`n"
    } else {
        # Generation 2 (UEFI) boot commands
        $template += "  # Boot configuration for Generation 2 (UEFI)`n"
        $template += "  boot_wait = `"10s`"`n"
        $template += "  boot_command = [`n"
        $template += "    `"e`",                   # Type an e to edit the grub startup`n"
        $template += "    `"<down><down>`",        # Navigate to third line (linuxefi line)`n"
        $template += "    `"<end>`",               # Move to end of the linuxefi line`n"
        $template += "    `" text`",               # Add text mode`n"
        $template += "    `" inst.ks=http://{{.HTTPIP}}:{{.HTTPPort}}/ks-with-cloudinit.cfg`",`n"
        $template += "    `" ip=192.168.200.100::192.168.200.1:255.255.255.0:almavm:eth0:none:8.8.8.8`",`n"
        $template += "    `" biosdevname=0`",`n"
        $template += "    `" net.ifnames=0`",`n"
        $template += "    `" rd.live.check=0`",`n"
        $template += "    `"<enter>`"             # Boot with modified parameters`n"
        $template += "  ]`n"
    }
    
    $template += "  `n"
    $template += "  # HTTP server for kickstart`n"
    $template += "  http_directory = `"templates/AlmaLinux/hyperv`"`n"
    $template += "  http_port_min  = 8080`n"
    $template += "  http_port_max  = 8090`n"
    $template += "  `n"
    $template += "  # SSH configuration`n"
    $template += "  ssh_username = `"root`"`n"
    $template += "  ssh_password = `"packer`"`n"
    $template += "  ssh_timeout = `"60m`"`n"
    $template += "  ssh_handshake_attempts = 100`n"
    $template += "  `n"
    $template += "  # Shutdown configuration  `n"
    $template += "  shutdown_command = `"systemctl poweroff`"`n"
    $template += "  shutdown_timeout = `"30m`"`n"
    $template += "  `n"
    $template += "  # Output configuration`n"
    $template += "  output_directory = `"output-almalinux-cloudinit-gen$Generation`"`n"
    $template += "  `n"
    $template += "  # Keep registered for debugging if needed`n"
    $template += "  keep_registered = false`n"
    $template += "  `n"
    $template += "  # Additional settings for nested virtualization`n"
    $template += "  enable_virtualization_extensions = true`n"
    $template += "}`n"
    
    return $template
}

# Create both templates using the function
$packerTemplateGen1 = New-PackerTemplate -Generation 1 -ISOPath $ISOPath
$packerTemplateGen2 = New-PackerTemplate -Generation 2 -ISOPath $ISOPath

# Common build section for both templates
$buildSection = @"

build {
  sources = ["source.hyperv-iso.SOURCENAME"]
  
  provisioner "shell" {
    inline = [
      "echo 'Template build started' >> /var/log/packer-build.log",
      
      # Verify cloud-init installation
      "echo 'Verifying cloud-init installation...' >> /var/log/packer-build.log",
      "cloud-init --version >> /var/log/packer-build.log",
      "systemctl is-enabled cloud-init >> /var/log/packer-build.log",
      
      # Test cloud-init configuration
      "echo 'Testing cloud-init configuration...' >> /var/log/packer-build.log",
      "/usr/local/bin/test-cloud-init >> /var/log/packer-build.log 2>&1 || true",
      
      # Verify network configuration
      "echo 'Verifying NetworkManager configuration...' >> /var/log/packer-build.log",
      "nmcli connection show >> /var/log/packer-build.log",
      
      # Install additional packages that might be useful
      "echo 'Installing additional cloud-init utilities...' >> /var/log/packer-build.log",
      "dnf install -y python3-pip >> /var/log/packer-build.log 2>&1",
      
      # Clean up for template usage
      "echo 'Cleaning up for template usage...' >> /var/log/packer-build.log",
      
      # Clear cloud-init instance data (will be regenerated on first boot)
      "cloud-init clean --logs >> /var/log/packer-build.log 2>&1 || true",
      
      # Clear machine-id again (important for cloning)
      "echo -n > /etc/machine-id",
      
      # Remove Packer SSH marker and clear SSH host keys for template
      "rm -f /etc/ssh/.packer-ssh-marker",
      "rm -f /etc/ssh/ssh_host_*",
      
      # Clear bash history
      "history -c",
      "rm -f /root/.bash_history /home/labuser/.bash_history",
      
      # Clear network configuration that might conflict
      "rm -f /etc/NetworkManager/system-connections/Wired*",
      
      # CRITICAL: Ensure cloud-init will run on first boot
      "echo 'Creating bulletproof cloud-init configuration...' >> /var/log/packer-build.log",
      
      # Remove any disable files that might exist
      "rm -f /etc/cloud/cloud-init.disabled /run/cloud-init/disabled /var/lib/cloud/data/disabled",
      
      # Force enable all cloud-init services
      "systemctl enable cloud-init-local cloud-init cloud-config cloud-final",
      
      # CRITICAL: Create ds-identify.cfg to prevent systemd generator from disabling cloud-init
      "cat > /etc/cloud/ds-identify.cfg << 'DSEOF'",
      "# Force cloud-init to ALWAYS enable - prevents systemd generator from disabling",
      "policy: enabled",
      "DSEOF",
      
      # CRITICAL: Ensure NoCloud datasource configuration exists
      "cat > /etc/cloud/cloud.cfg.d/90_nocloud_forced.cfg << 'NOCLOUDEOF'",
      "# Force NoCloud datasource to be available",
      "datasource_list: [ NoCloud, None ]",
      "datasource:",
      "  NoCloud:",
      "    # Look for seed data on CD-ROM with correct label",
      "    fs_label: CD_ROM",
      "NOCLOUDEOF",
      
      # Verify the configuration was created properly
      "echo 'Verifying cloud-init configuration...' >> /var/log/packer-build.log",
      "ls -la /etc/cloud/ds-identify.cfg >> /var/log/packer-build.log",
      "cat /etc/cloud/ds-identify.cfg >> /var/log/packer-build.log",
      "ls -la /etc/cloud/cloud.cfg.d/90_nocloud_forced.cfg >> /var/log/packer-build.log",
      
      "echo 'Cloud-init template build completed' >> /var/log/packer-build.log"
    ]
  }
  
  # Final cleanup and optimization
  provisioner "shell" {
    inline = [
      "echo 'Final template optimization...' >> /var/log/packer-build.log",
      
      # Update package database
      "dnf makecache >> /var/log/packer-build.log 2>&1",
      
      # Install any missing cloud-init dependencies
      "dnf install -y cloud-init cloud-utils-growpart >> /var/log/packer-build.log 2>&1 || true",
      
      # Zero out free space (helps with compression)
      "echo 'Zeroing free space for compression...' >> /var/log/packer-build.log",
      "dd if=/dev/zero of=/tmp/zero bs=1M count=100 2>/dev/null || true",
      "rm -f /tmp/zero",
      
      # Final package cache cleanup
      "dnf clean all >> /var/log/packer-build.log 2>&1",
      
      "echo 'Template optimization completed' >> /var/log/packer-build.log"
    ]
  }
}
"@

# Complete the templates with build section
$gen1BuildSection = $buildSection -replace "SOURCENAME", "almalinux-cloudinit-gen1"
$gen2BuildSection = $buildSection -replace "SOURCENAME", "almalinux-cloudinit-gen2"

# Use intermediate variables to avoid concatenation issues
$fullTemplateGen1 = ""
$fullTemplateGen1 = $packerTemplateGen1
$fullTemplateGen1 = $fullTemplateGen1 + $gen1BuildSection

$fullTemplateGen2 = ""
$fullTemplateGen2 = $packerTemplateGen2
$fullTemplateGen2 = $fullTemplateGen2 + $gen2BuildSection

# Assign back to the original variables
$packerTemplateGen1 = $fullTemplateGen1
$packerTemplateGen2 = $fullTemplateGen2

# Debug - Write the contents to verify build section is appended
Write-Host "Verifying build section is present in templates..." -ForegroundColor Yellow
if ($packerTemplateGen1.Length -gt 50) {
    Write-Host "Template Gen1 ends with: $($packerTemplateGen1.Substring($packerTemplateGen1.Length - 50))" -ForegroundColor Gray
} else {
    Write-Host "Template Gen1 is too short: $($packerTemplateGen1.Length) characters" -ForegroundColor Red
}
if ($packerTemplateGen2.Length -gt 50) {
    Write-Host "Template Gen2 ends with: $($packerTemplateGen2.Substring($packerTemplateGen2.Length - 50))" -ForegroundColor Gray
} else {
    Write-Host "Template Gen2 is too short: $($packerTemplateGen2.Length) characters" -ForegroundColor Red
}

# Determine which template to create based on Generation parameter
if ($Generation -eq 1) {
    $templatePath = Join-Path $projectRoot "almalinux-cloudinit-gen1.pkr.hcl"
    $templateContent = $packerTemplateGen1
    Write-Host "Generation 1 template length: $($templateContent.Length) characters" -ForegroundColor Gray
    
    # Verify Gen1 template has build section
    if ($templateContent -notmatch "build \{") {
        Write-Host "Build section missing from Gen1 template, attempting to append..." -ForegroundColor Yellow
        $templateContent = $templateContent + $gen1BuildSection
    }
} elseif ($Generation -eq 2) {
    $templatePath = Join-Path $projectRoot "almalinux-cloudinit-gen2.pkr.hcl"
    $templateContent = $packerTemplateGen2
    Write-Host "Generation 2 template length: $($templateContent.Length) characters" -ForegroundColor Gray
    
    # Verify Gen2 template has build section
    if ($templateContent -notmatch "build \{") {
        Write-Host "Build section missing from Gen2 template, attempting to append..." -ForegroundColor Yellow
        $templateContent = $templateContent + $gen2BuildSection
    }
} else {
    Write-Error "Invalid generation specified: $Generation. Must be 1 or 2."
    exit 1
}

# Verify template content before writing
if ($templateContent.Length -lt 1000) {
    Write-Error "Generated template is suspiciously short ($($templateContent.Length) characters). Something went wrong."
    Write-Host "Template content preview:" -ForegroundColor Red
    Write-Host $templateContent
    
    # Emergency template generation - start from scratch
    Write-Host "Attempting emergency template generation..." -ForegroundColor Yellow
    
    # Determine which source to use
    if ($Generation -eq 1) {
        $sourceName = "almalinux-cloudinit-gen1"
        $freshTemplate = $packerTemplateGen1 # Original template section
        
        # Only add build section if it's missing
        if ($freshTemplate -notmatch "build \{") {
            $freshTemplate = $freshTemplate + ($buildSection -replace "SOURCENAME", $sourceName)
        }
    } else {
        $sourceName = "almalinux-cloudinit-gen2"
        $freshTemplate = $packerTemplateGen2 # Original template section
        
        # Only add build section if it's missing
        if ($freshTemplate -notmatch "build \{") {
            $freshTemplate = $freshTemplate + ($buildSection -replace "SOURCENAME", $sourceName)
        }
    }
    
    # Check if emergency generation worked
    if ($freshTemplate.Length -lt 1000) {
        Write-Error "Emergency template generation failed. Unable to create valid template."
        exit 1
    } else {
        Write-Host "Emergency template generation successful: $($freshTemplate.Length) characters" -ForegroundColor Green
        $templateContent = $freshTemplate
    }
}

# Write the template file using .NET methods to avoid any PowerShell string handling issues
if ($templateContent.Length -gt 0) {
    [System.IO.File]::WriteAllText($templatePath, $templateContent)
    Write-Host "Template written using .NET File.WriteAllText" -ForegroundColor Gray
} else {
    Write-Error "Cannot write empty template file. Template content is empty."
    exit 1
}
Write-Host "Packer template created: $templatePath" -ForegroundColor Green
Write-Host "Template size: $((Get-Item $templatePath).Length) bytes" -ForegroundColor Gray


# Verify Hyper-V and network setup
Write-Host "`nVerifying environment..." -ForegroundColor Yellow

# Check if Hyper-V is available
$hyperVFeature = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online -ErrorAction SilentlyContinue
if (-not $hyperVFeature -or $hyperVFeature.State -ne "Enabled") {
    Write-Warning "Hyper-V may not be properly enabled. Please ensure Hyper-V is installed and enabled."
}

# Check for PackerInternal switch
$packerSwitch = Get-VMSwitch -Name "PackerInternal" -ErrorAction SilentlyContinue
if (-not $packerSwitch) {
    Write-Host "Creating PackerInternal switch..." -ForegroundColor Yellow
    
    # Create internal switch
    New-VMSwitch -Name "PackerInternal" -SwitchType Internal | Out-Null
    
    # Configure NAT network
    $networkAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*PackerInternal*" }
    if ($networkAdapter) {
        # Set IP address on the host adapter
        New-NetIPAddress -IPAddress "192.168.200.1" -PrefixLength 24 -InterfaceIndex $networkAdapter.InterfaceIndex -ErrorAction SilentlyContinue
        
        # Create NAT network
        New-NetNat -Name "PackerInternalNAT" -InternalIPInterfaceAddressPrefix "192.168.200.0/24" -ErrorAction SilentlyContinue
        
        Write-Host "PackerInternal switch created and configured" -ForegroundColor Green
    }
} else {
    Write-Host "PackerInternal switch verified" -ForegroundColor Green
}

# Configure Windows Firewall
Write-Host "Configuring firewall for Packer HTTP server..." -ForegroundColor Yellow
$firewallRules = @(
    @{ Name = "PackerHTTP-Inbound"; Port = "8080-8090"; Direction = "Inbound" },
    @{ Name = "PackerHTTP-Outbound"; Port = "8080-8090"; Direction = "Outbound" }
)

foreach ($rule in $firewallRules) {
    $existingRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if (-not $existingRule) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction $rule.Direction -Protocol TCP -LocalPort $rule.Port -Action Allow | Out-Null
        Write-Host "  Created firewall rule: $($rule.Name)" -ForegroundColor Gray
    }
}

# Initialize Packer plugins
Write-Host "`nInitializing Packer plugins..." -ForegroundColor Yellow
try {
    # Verify template file exists and has content
    if (Test-Path $templatePath) {
        $templateContent = Get-Content -Path $templatePath -Raw
        $templateSize = (Get-Item $templatePath).Length
        Write-Host "Template file exists with size: $templateSize bytes" -ForegroundColor Gray
        
        # Verify template contains required sections
        if (-not $templateContent.Contains("build {")) {
            Write-Error "Template does not contain build section!"
            Write-Host "Attempting to fix template..." -ForegroundColor Yellow
            
            # Emergency fix - append build block if missing
            if ($Generation -eq 1) {
                $sourceName = "almalinux-cloudinit-gen1"
            } else {
                $sourceName = "almalinux-cloudinit-gen2"
            }
            $fixedBuildSection = ($buildSection -replace "SOURCENAME", $sourceName)
            Add-Content -Path $templatePath -Value $fixedBuildSection
            Write-Host "Build section added to template." -ForegroundColor Green
        }
    } else {
        Write-Error "Template file doesn't exist at: $templatePath"
        exit 1
    }
    
    # Initialize Packer with verbose output
    Write-Host "Running: packer init -machine-readable $templatePath" -ForegroundColor Gray
    & packer init -machine-readable $templatePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Packer plugins initialized successfully" -ForegroundColor Green
    } else {
        Write-Warning "Packer plugin initialization returned exit code: $LASTEXITCODE"
        
        # Try with explicit plugin source
        Write-Host "Attempting to install Hyper-V plugin explicitly..." -ForegroundColor Yellow
        & packer plugins install github.com/hashicorp/hyperv
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Hyper-V plugin installed manually" -ForegroundColor Green
        } else {
            Write-Error "Failed to install Hyper-V plugin manually. Please check Packer installation."
        }
    }
} catch {
    Write-Warning "Could not initialize Packer plugins: $($_.Exception.Message)"
    Write-Host "You may need to run 'packer plugins install github.com/hashicorp/hyperv' manually"
}

# Build the template
Write-Host "`nStarting Packer build..." -ForegroundColor Yellow
Write-Host "This will create a cloud-init enabled AlmaLinux template."
Write-Host "Build progress will be shown below:`n"

try {
    $env:PACKER_LOG = "1"
    $env:PACKER_LOG_PATH = Join-Path $projectRoot "packer-cloudinit-build.log"
    
    & packer build $templatePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n=== Build Completed Successfully ===" -ForegroundColor Green
        Write-Host "Cloud-init enabled template created in: $outputPath"
        Write-Host "VHDX files location: $outputPath\Virtual Hard Disks\"
        
        # List created files
        if (Test-Path $outputPath) {
            $vhdxFiles = Get-ChildItem -Path "$outputPath\Virtual Hard Disks" -Filter "*.vhdx" -ErrorAction SilentlyContinue
            if ($vhdxFiles) {
                Write-Host "`nCreated VHDX files:"
                foreach ($file in $vhdxFiles) {
                    Write-Host "  - $($file.Name) ($([math]::Round($file.Length/1GB,2)) GB)"
                }
            }
        }
        
        Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
        Write-Host "1. Test the template:"
        Write-Host "   .\deploy-with-cloudinit.ps1 -VMCount 1 -StartVMs"
        
        Write-Host "`n2. Deploy multiple VMs with custom configuration:"
        Write-Host "   .\deploy-with-cloudinit.ps1 -VMCount 5 -NetworkSubnet '192.168.100' -Username 'admin' -StartVMs"
        
        Write-Host "`n3. Check cloud-init status on deployed VMs:"
        Write-Host "   ssh labuser@<vm-ip> 'sudo cloud-init status --long'"
        
    } else {
        Write-Error "Packer build failed with exit code: $LASTEXITCODE"
        Write-Host "Check the log file for details: $env:PACKER_LOG_PATH"
    }
    
} catch {
    Write-Error "Build failed: $($_.Exception.Message)"
} finally {
    Remove-Item Env:PACKER_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:PACKER_LOG_PATH -ErrorAction SilentlyContinue
}

Write-Host "`nBuild completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
