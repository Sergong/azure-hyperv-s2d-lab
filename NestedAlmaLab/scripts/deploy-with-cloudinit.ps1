# Deploy VMs from Packer-built AlmaLinux Template with cloud-init support
# Creates multiple VMs with custom network and user configuration via cloud-init

param(
    [Parameter(Mandatory=$false)]
    [string]$TemplatePath = "",
    
    [Parameter(Mandatory=$false)]
    [int]$VMCount = 2,
    
    [Parameter(Mandatory=$false)]
    [string]$VMPrefix = "AlmaLab",
    
    [Parameter(Mandatory=$false)]
    [string]$VMPath = "C:\HyperV\VMs",
    
    [Parameter(Mandatory=$false)]
    [string]$VHDPath = "C:\HyperV\VMs\VHDs",
    
    [Parameter(Mandatory=$false)]
    [string]$SwitchName = "PackerInternal",
    
    [Parameter(Mandatory=$false)]
    [int64]$Memory = 2GB,
    
    [Parameter(Mandatory=$false)]
    [switch]$StartVMs,
    
    # Cloud-init network configuration
    [Parameter(Mandatory=$false)]
    [string]$NetworkSubnet = "192.168.200",
    
    [Parameter(Mandatory=$false)]
    [int]$StartIP = 101,
    
    [Parameter(Mandatory=$false)]
    [string]$Gateway = "192.168.200.1",
    
    [Parameter(Mandatory=$false)]
    [string]$DNS = "8.8.8.8,8.8.4.4",
    
    # Cloud-init user configuration
    [Parameter(Mandatory=$false)]
    [string]$Username = "labuser",
    
    [Parameter(Mandatory=$false)]
    [string]$UserPassword = "labpass123!",
    
    [Parameter(Mandatory=$false)]
    [string]$RootPassword = "packer",
    
    [Parameter(Mandatory=$false)]
    [string]$SSHPublicKey = ""
)

Write-Host "=== Deploy VMs with cloud-init Configuration ====" -ForegroundColor Cyan
Write-Host "Template Path: $TemplatePath"
Write-Host "VM Count: $VMCount"
Write-Host "VM Prefix: $VMPrefix"
Write-Host "Memory per VM: $($Memory/1GB) GB"
Write-Host "Network Subnet: $NetworkSubnet.x/24"
Write-Host "Starting IP: $NetworkSubnet.$StartIP"
Write-Host "Username: $Username"
Write-Host "======================================="

# Auto-detect template path if not provided
if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = Split-Path -Parent $scriptPath
    
    if ($projectRoot -is [array]) {
        $projectRoot = $projectRoot[0]
    }
    
    $possiblePaths = @(
        (Join-Path $projectRoot "output-almalinux-simple"),
        (Join-Path $projectRoot "output-almalinux"),
        "C:\Packer\Output",
        (Join-Path $projectRoot "output")
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $vhdxSearchLocations = @(
                "$path\Virtual Hard Disks\*.vhdx",
                "$path\*.vhdx"
            )
            
            foreach ($searchLocation in $vhdxSearchLocations) {
                $vhdxFiles = Get-ChildItem $searchLocation -ErrorAction SilentlyContinue
                if ($vhdxFiles) {
                    $TemplatePath = $path
                    Write-Host "Auto-detected template path: $TemplatePath" -ForegroundColor Green
                    break
                }
            }
            
            if ($TemplatePath) { break }
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        Write-Error "Could not auto-detect template path. Please specify -TemplatePath parameter."
        exit 1
    }
}

# Find the template VHDX file
$vhdxSearchPaths = @(
    "$TemplatePath\Virtual Hard Disks\*.vhdx",
    "$TemplatePath\*.vhdx"
)

$templateFiles = @()
foreach ($searchPath in $vhdxSearchPaths) {
    $foundFiles = Get-ChildItem $searchPath -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($foundFiles) {
        $templateFiles = $foundFiles
        break
    }
}

if (-not $templateFiles) {
    Write-Error "No template VHDX files found in $TemplatePath"
    exit 1
}

$templateVHDX = $templateFiles[0].FullName
Write-Host "Using template: $templateVHDX" -ForegroundColor Green

# Validate VM switch
try {
    Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
    Write-Host "VM Switch validated: $SwitchName" -ForegroundColor Green
} catch {
    Write-Error "VM Switch '$SwitchName' not found. Please create it first."
    exit 1
}

# Create directories
New-Item -ItemType Directory -Path $VMPath, $VHDPath -Force | Out-Null

# Create cloud-init directory for this deployment
$cloudInitPath = Join-Path $VMPath "cloud-init"
New-Item -ItemType Directory -Path $cloudInitPath -Force | Out-Null

# Function to generate password hash for cloud-init
function Get-PasswordHash {
    param([string]$Password)
    
    # For cloud-init, we can use plain text passwords in the chpasswd section
    # Cloud-init will handle the hashing internally when applying the configuration
    # This is actually the preferred method for cloud-init chpasswd
    return $Password
}

# Function to create cloud-init ISO
function New-CloudInitISO {
    param(
        [string]$VMName,
        [string]$IPAddress,
        [string]$OutputPath
    )
    
    $vmCloudInitPath = Join-Path $cloudInitPath $VMName
    New-Item -ItemType Directory -Path $vmCloudInitPath -Force | Out-Null
    
    # Create meta-data file
    $metaData = @"
instance-id: $VMName
local-hostname: $VMName
"@
    
    $metaDataPath = Join-Path $vmCloudInitPath "meta-data"
    $metaData | Set-Content -Path $metaDataPath -Encoding UTF8
    
    # Generate password hashes
    $userPasswordHash = Get-PasswordHash $UserPassword
    $rootPasswordHash = Get-PasswordHash $RootPassword
    
    # Create user-data file
    $userData = @"
#cloud-config

# Set hostname
hostname: $VMName
fqdn: $VMName.lab.local

# Configure users
users:
  - name: $Username
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    passwd: $userPasswordHash
    lock_passwd: false
    ssh_authorized_keys: []

# Set root password
chpasswd:
  list: |
    root:${RootPassword}
    ${Username}:${UserPassword}
  expire: False

# SSH configuration
ssh_pwauth: True
disable_root: False

# Network configuration
write_files:
  - path: /etc/NetworkManager/system-connections/eth0.nmconnection
    permissions: '0600'
    owner: root:root
    content: |
      [connection]
      id=eth0
      type=ethernet
      interface-name=eth0
      autoconnect=true
      
      [ipv4]
      method=manual
      addresses=$IPAddress/24
      gateway=$Gateway
      dns=$($DNS -replace ',',';')
      
      [ipv6]
      method=ignore

# Commands to run after boot
runcmd:
  - systemctl reload NetworkManager
  - nmcli connection reload
  - nmcli connection up eth0
  - systemctl enable sshd
  - systemctl start sshd
  - echo "Cloud-init configuration completed for $VMName" >> /var/log/cloud-init-custom.log

# Package updates
package_update: false
package_upgrade: false

# Final message
final_message: "The system is finally up, after `$UPTIME seconds"
"@

    if ($SSHPublicKey) {
        $userData = $userData -replace "ssh_authorized_keys: \[\]", "ssh_authorized_keys:`n      - `"$SSHPublicKey`""
    }
    
    $userDataPath = Join-Path $vmCloudInitPath "user-data"
    $userData | Set-Content -Path $userDataPath -Encoding UTF8
    
    # Create network-config file (alternative network configuration method)
    $networkConfig = @"
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - $IPAddress/24
    gateway4: $Gateway
    nameservers:
      addresses: [$($DNS -replace ',', ', ')]
"@
    
    $networkConfigPath = Join-Path $vmCloudInitPath "network-config"
    $networkConfig | Set-Content -Path $networkConfigPath -Encoding UTF8
    
    # Create NoCloud ISO using available tools
    $isoPath = $OutputPath
    
    # Try to create ISO using different methods
    $isoCreated = $false
    
    # Method 1: Use mkisofs if available
    try {
        $result = mkisofs -output $isoPath -volid cidata -joliet -rock $vmCloudInitPath 2>$null
        if ($LASTEXITCODE -eq 0) {
            $isoCreated = $true
            Write-Host "  Created cloud-init ISO using mkisofs" -ForegroundColor Gray
        }
    } catch {}
    
    # Method 2: Use genisoimage if available
    if (-not $isoCreated) {
        try {
            $result = genisoimage -output $isoPath -volid cidata -joliet -rock $vmCloudInitPath 2>$null
            if ($LASTEXITCODE -eq 0) {
                $isoCreated = $true
                Write-Host "  Created cloud-init ISO using genisoimage" -ForegroundColor Gray
            }
        } catch {}
    }
    
    # Method 3: Use PowerShell to create a simple ISO
    if (-not $isoCreated) {
        Write-Host "  Creating cloud-init ISO using PowerShell..." -ForegroundColor Gray
        try {
            # Use PowerShell's built-in New-IsoFile cmdlet if available (Windows 11/Server 2022+)
            if (Get-Command New-IsoFile -ErrorAction SilentlyContinue) {
                New-IsoFile -Source $vmCloudInitPath -DestinationPath $isoPath -VolumeName "cidata" | Out-Null
                $isoCreated = $true
                Write-Host "  Created cloud-init ISO using New-IsoFile" -ForegroundColor Gray
            }
            # Alternative: Use DISM to create ISO (available on most Windows versions)
            elseif (Get-Command oscdimg.exe -ErrorAction SilentlyContinue) {
                $result = oscdimg.exe -n -m -o -h "$vmCloudInitPath" "$isoPath" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $isoCreated = $true
                    Write-Host "  Created cloud-init ISO using oscdimg" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Warning "  PowerShell ISO creation failed: $($_.Exception.Message)"
        }
        
        if (-not $isoCreated) {
            Write-Warning "  No ISO creation tools available. Cloud-init files will be available in directory only."
            Write-Host "  Cloud-init files created in: $vmCloudInitPath" -ForegroundColor Yellow
            Write-Host "  Note: VM will still work if cloud-init can find files via other methods" -ForegroundColor Yellow
            return $false
        }
    }
    
    return $isoCreated
}

# Function to inject cloud-init files directly into VHDX
function Add-CloudInitToVHDX {
    param(
        [string]$VHDXPath,
        [string]$VMName,
        [string]$IPAddress
    )
    
    try {
        Write-Host "  Injecting cloud-init configuration into VHDX..." -ForegroundColor Gray
        
        # Mount the VHDX
        $mountResult = Mount-VHD -Path $VHDXPath -Passthru
        $disk = Get-Disk | Where-Object { $_.Location -eq $mountResult.Path }
        
        # Get all partitions and find the largest one (likely root filesystem)
        $partitions = Get-Partition -DiskNumber $disk.Number | Sort-Object Size -Descending
        
        Write-Host "    Found $($partitions.Count) partitions:" -ForegroundColor Gray
        foreach ($p in $partitions) {
            Write-Host "    - Partition $($p.PartitionNumber): $($p.Type), Size: $([math]::Round($p.Size/1GB, 2)) GB" -ForegroundColor Gray
        }
        
        # Try to find the root partition - usually the largest non-system partition
        $rootPartition = $null
        
        # First try: Find largest partition that's not System or Reserved
        $rootPartition = $partitions | Where-Object { 
            $_.Type -notin @('System', 'Reserved') -and $_.Size -gt 500MB 
        } | Select-Object -First 1
        
        # Second try: If no suitable partition found, use the largest partition
        if (-not $rootPartition) {
            $rootPartition = $partitions | Select-Object -First 1
        }
        
        if (-not $rootPartition) {
            throw "Could not find any suitable partition in VHDX"
        }
        
        Write-Host "    Using partition $($rootPartition.PartitionNumber) ($($rootPartition.Type), $([math]::Round($rootPartition.Size/1GB, 2)) GB)" -ForegroundColor Gray
        
        # Assign drive letter if needed
        $driveLetter = $rootPartition.DriveLetter
        if (-not $driveLetter) {
            # Find an available drive letter
            $availableLetters = 67..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) }
            if ($availableLetters.Count -gt 0) {
                $driveLetter = $availableLetters[0]
                $rootPartition | Set-Partition -NewDriveLetter $driveLetter
                Write-Host "    Assigned drive letter: $driveLetter" -ForegroundColor Gray
            } else {
                throw "No available drive letters to assign"
            }
        }
        
        # Create cloud-init directory structure
        $cloudInitDir = "${driveLetter}:\var\lib\cloud\seed\nocloud"
        Write-Host "    Creating cloud-init directory: $cloudInitDir" -ForegroundColor Gray
        
        # Create directory structure with proper error handling
        try {
            New-Item -ItemType Directory -Path "${driveLetter}:\var" -Force -ErrorAction SilentlyContinue | Out-Null
            New-Item -ItemType Directory -Path "${driveLetter}:\var\lib" -Force -ErrorAction SilentlyContinue | Out-Null
            New-Item -ItemType Directory -Path "${driveLetter}:\var\lib\cloud" -Force -ErrorAction SilentlyContinue | Out-Null
            New-Item -ItemType Directory -Path "${driveLetter}:\var\lib\cloud\seed" -Force -ErrorAction SilentlyContinue | Out-Null
            New-Item -ItemType Directory -Path $cloudInitDir -Force | Out-Null
        } catch {
            Write-Warning "    Could not create cloud-init directories: $($_.Exception.Message)"
            # Try alternative method - create files in root and let cloud-init find them
            $cloudInitDir = "${driveLetter}:\"
            Write-Host "    Using root directory instead: $cloudInitDir" -ForegroundColor Yellow
        }
        
        # Generate and write cloud-init files
        $vmCloudInitPath = Join-Path $cloudInitPath $VMName
        if (Test-Path $vmCloudInitPath) {
            $cloudInitFiles = Get-ChildItem $vmCloudInitPath -File
            foreach ($file in $cloudInitFiles) {
                $targetPath = Join-Path $cloudInitDir $file.Name
                Copy-Item $file.FullName $targetPath -Force
                Write-Host "    Copied $($file.Name) to $targetPath" -ForegroundColor Gray
            }
        }
        
        # Unmount the VHDX
        Dismount-VHD -Path $VHDXPath
        Write-Host "    Cloud-init files successfully injected" -ForegroundColor Green
        
        return $true
        
    } catch {
        Write-Warning "  Failed to inject cloud-init files: $($_.Exception.Message)"
        try { Dismount-VHD -Path $VHDXPath -ErrorAction SilentlyContinue } catch {}
        return $false
    }
}

# Function to create VM from template with cloud-init
function New-VMFromTemplateWithCloudInit {
    param(
        [string]$VMName,
        [string]$TemplateVHDX,
        [string]$TargetVHDX,
        [string]$IPAddress
    )
    
    Write-Host "Creating VM: $VMName (IP: $IPAddress)" -ForegroundColor Yellow
    
    try {
        # Copy template VHDX
        Write-Host "  Copying template VHDX..."
        Copy-Item $TemplateVHDX $TargetVHDX -Force
        
        # Generate cloud-init configuration
        Write-Host "  Generating cloud-init configuration..."
        $vmCloudInitPath = Join-Path $cloudInitPath $VMName
        New-Item -ItemType Directory -Path $vmCloudInitPath -Force | Out-Null
        
        # Create cloud-init files and ISO
        $isoCreated = New-CloudInitISO -VMName $VMName -IPAddress $IPAddress -OutputPath (Join-Path $vmCloudInitPath "cloud-init.iso")
        
        # Try to inject cloud-init into the VHDX (optional - ISO method is primary)
        if (-not $isoCreated) {
            Write-Host "  ISO creation failed, trying VHDX injection as fallback..." -ForegroundColor Yellow
            $cloudInitInjected = Add-CloudInitToVHDX -VHDXPath $TargetVHDX -VMName $VMName -IPAddress $IPAddress
            if (-not $cloudInitInjected) {
                Write-Warning "  Both ISO creation and VHDX injection failed. VM may not have cloud-init configuration."
            }
        } else {
            Write-Host "  Cloud-init ISO created successfully - will use ISO method" -ForegroundColor Green
        }
        
        # Detect VM generation
        $generation = 1
        try {
            $mountResult = Mount-VHD -Path $TargetVHDX -ReadOnly -Passthru
            $disk = Get-Disk | Where-Object { $_.Location -eq $mountResult.Path }
            $partitions = Get-Partition -DiskNumber $disk.Number
            $efiPartition = $partitions | Where-Object { $_.Type -eq 'System' -and $_.Size -lt 1GB }
            
            if ($efiPartition) {
                $generation = 2
                Write-Host "  Detected Generation 2 template (UEFI boot)" -ForegroundColor Gray
            } else {
                Write-Host "  Detected Generation 1 template (BIOS boot)" -ForegroundColor Gray
            }
            
            Dismount-VHD -Path $TargetVHDX
        } catch {
            Write-Host "  Could not detect generation, defaulting to Generation 1" -ForegroundColor Yellow
        }
        
        # Create VM
        Write-Host "  Creating Generation $generation VM..."
        $vm = New-VM -Name $VMName -MemoryStartupBytes $Memory -Generation $generation -Path $VMPath -VHDPath $TargetVHDX
        
        # Connect to network switch
        Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName
        
        # Configure VM settings
        if ($generation -eq 2) {
            Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
        }
        
        try {
            Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
            Write-Host "  Enabled nested virtualization"
        } catch {
            Write-Warning "  Could not enable nested virtualization: $($_.Exception.Message)"
        }
        
        Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false
        Set-VM -VMName $VMName -CheckpointType Disabled
        
        # Add cloud-init ISO as DVD drive if ISO was created
        $cloudInitIsoPath = Join-Path $vmCloudInitPath "cloud-init.iso"
        if (Test-Path $cloudInitIsoPath) {
            try {
                Add-VMDvdDrive -VMName $VMName -Path $cloudInitIsoPath
                Write-Host "  Attached cloud-init ISO" -ForegroundColor Gray
            } catch {
                Write-Warning "  Could not attach cloud-init ISO: $($_.Exception.Message)"
            }
        }
        
        Write-Host "  VM $VMName created successfully with cloud-init" -ForegroundColor Green
        return $vm
        
    } catch {
        Write-Error "Failed to create VM ${VMName}: $($_.Exception.Message)"
        
        # Cleanup on failure
        try {
            if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
                Remove-VM -Name $VMName -Force
            }
            if (Test-Path $TargetVHDX) {
                Remove-Item $TargetVHDX -Force
            }
        } catch {
            Write-Warning "Failed to cleanup $VMName"
        }
        throw
    }
}

# Deploy VMs with cloud-init
$deployedVMs = @()
Write-Host "`nDeploying $VMCount VMs with cloud-init configuration..." -ForegroundColor Yellow

for ($i = 1; $i -le $VMCount; $i++) {
    $vmName = "$VMPrefix-$i"
    $vhdFile = "$VHDPath\$vmName.vhdx"
    $vmIP = "$NetworkSubnet.$($StartIP + $i - 1)"
    
    try {
        $vm = New-VMFromTemplateWithCloudInit -VMName $vmName -TemplateVHDX $templateVHDX -TargetVHDX $vhdFile -IPAddress $vmIP
        $deployedVMs += @{ Name = $vmName; IP = $vmIP }
        
        # Start VM if requested
        if ($StartVMs) {
            Write-Host "  Starting VM: $vmName"
            Start-VM -Name $vmName
            
            # Wait a moment for cloud-init to start configuring
            Write-Host "  Waiting for cloud-init to configure the VM..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        }
        
    } catch {
        Write-Warning "Skipping VM $vmName due to error: $($_.Exception.Message)"
    }
}

# Summary
Write-Host "`n=== Deployment Summary ====" -ForegroundColor Green
Write-Host "Successfully deployed $($deployedVMs.Count) out of $VMCount VMs with cloud-init:"

foreach ($vmInfo in $deployedVMs) {
    $vm = Get-VM -Name $vmInfo.Name
    Write-Host "  - $($vmInfo.Name) : $($vm.State) (IP: $($vmInfo.IP))"
}

Write-Host "`n=== Cloud-init Configuration ====" -ForegroundColor Cyan
Write-Host "Each VM is configured with:"
Write-Host "- Custom static IP address"
Write-Host "- Custom user: $Username / $UserPassword"
Write-Host "- Root password: $RootPassword"
Write-Host "- SSH enabled with password authentication"
Write-Host "- Hostname set to VM name"
Write-Host "- Network configured via NetworkManager"

Write-Host "`n=== Access Information ====" -ForegroundColor Yellow
Write-Host "SSH access for each VM:"
foreach ($vmInfo in $deployedVMs) {
    Write-Host "  ssh $Username@$($vmInfo.IP)  # Password: $UserPassword"
    Write-Host "  ssh root@$($vmInfo.IP)       # Password: $RootPassword"
}

Write-Host "`n=== Management Commands ====" -ForegroundColor White
Write-Host "Check VM status:       Get-VM $VMPrefix-*"
Write-Host "Get IP addresses:      Get-VM $VMPrefix-* | Get-VMNetworkAdapter | Select Name, IPAddresses"
Write-Host "View cloud-init logs:  ssh user@ip 'sudo tail -f /var/log/cloud-init.log'"
Write-Host "Check network config:  ssh user@ip 'ip addr show'"

if (-not $StartVMs) {
    Write-Host "`nTo start the VMs and apply cloud-init configuration:" -ForegroundColor Yellow
    Write-Host "Get-VM $VMPrefix-* | Start-VM"
}

Write-Host "`n=== Cloud-init Files ====" -ForegroundColor Gray
Write-Host "Cloud-init configuration stored in: $cloudInitPath"
Write-Host "Each VM has its own subdirectory with user-data, meta-data, and network-config files"

Write-Host "`nDeployment completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
