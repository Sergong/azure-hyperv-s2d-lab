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
        (Join-Path $projectRoot "output-almalinux-cloudinit-gen2"),
        (Join-Path $projectRoot "output-almalinux-cloudinit-gen1"),
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

# Note: We'll rely on direct chpasswd commands in runcmd instead of the chpasswd section
# since Windows PowerShell cannot generate Unix password hashes

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
    # Write without BOM - this is critical for cloud-init to work properly
    [System.IO.File]::WriteAllText($metaDataPath, $metaData, [System.Text.UTF8Encoding]::new($false))
    
    # Create user-data file
    $userData = @"
#cloud-config

# CRITICAL: Must include all three module phases for proper execution
cloud_init_modules:
  - migrator
  - seed_random
  - bootcmd
  - write-files
  - growpart
  - resizefs
  - set_hostname
  - update_hostname
  - update_etc_hosts
  - users-groups
  - ssh

cloud_config_modules:
  - runcmd
  - ssh-import-id
  - locale
  - set-passwords
  - package-update-upgrade-install

cloud_final_modules:
  - scripts-user
  - ssh-authkey-fingerprints
  - keys-to-console
  - phone-home
  - final-message
  - power-state-change

# Set hostname
hostname: $VMName
fqdn: $VMName.lab.local

# Configure users - create new user (passwords will be set in runcmd)
users:
  - name: root
    lock_passwd: false
  - name: $Username
    groups: [wheel, adm, systemd-journal]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys: []

# SSH configuration - force enable password auth
ssh_pwauth: True
disable_root: False

# Write network configuration files and SSH config - force new IP configuration
write_files:
  - path: /etc/ssh/sshd_config.d/50-cloud-init.conf
    permissions: '0600'
    owner: root:root
    content: |
      # SSH configuration from cloud-init - ensure password auth works
      # These settings override the main sshd_config file
      PasswordAuthentication yes
      PermitRootLogin yes
      PubkeyAuthentication yes
      UsePAM yes
      ChallengeResponseAuthentication no
  - path: /etc/ssh/sshd_config.d/99-force-password-auth.conf
    permissions: '0600'
    owner: root:root
    content: |
      # Force password authentication - highest priority override
      # This file has the highest number so it loads last and overrides everything
      PasswordAuthentication yes
      PermitRootLogin yes
  - path: /etc/NetworkManager/system-connections/cloudinit-eth0.nmconnection
    permissions: '0600'
    owner: root:root
    content: |
      [connection]
      id=cloudinit-eth0
      type=ethernet
      interface-name=eth0
      autoconnect=true
      autoconnect-priority=999
      
      [ipv4]
      method=manual
      addresses=$IPAddress/24
      gateway=$Gateway
      dns=$($DNS -replace ',',';')
      may-fail=false
      
      [ipv6]
      method=ignore
  - path: /etc/sysconfig/network-scripts/ifcfg-eth0
    permissions: '0644'
    owner: root:root
    content: |
      DEVICE=eth0
      BOOTPROTO=static
      ONBOOT=yes
      IPADDR=$IPAddress
      NETMASK=255.255.255.0
      GATEWAY=$Gateway
      DNS1=8.8.8.8
      DNS2=8.8.4.4
      DEFROUTE=yes
      IPV4_FAILURE_FATAL=no
      IPV6INIT=no
      NAME=eth0
  - path: /usr/local/bin/cloud-init-debug
    permissions: '0755'
    owner: root:root
    content: |
      #!/bin/bash
      echo "=== Cloud-init Debug Info ==="
      echo "Status: `$(cloud-init status --long)"
      echo "Data source: `$(cloud-init query datasource)"
      echo "Instance ID: `$(cloud-init query instance_id)"
      echo "Local hostname: `$(cloud-init query local_hostname)"
      echo ""
      echo "=== Available data sources ==="
      ls -la /var/lib/cloud/seed/ 2>/dev/null || echo "No seed directory"
      ls -la /var/lib/cloud/seed/nocloud/ 2>/dev/null || echo "No nocloud seed"
      echo ""
      echo "=== Mount points ==="
      mount | grep -i cd
      echo ""
      echo "=== Cloud-init logs ==="
      tail -20 /var/log/cloud-init.log

# Commands to run after boot
bootcmd:
  - echo "Starting cloud-init configuration for $VMName" >> /var/log/cloud-init-debug.log
  # Ensure CD-ROM devices are available and mount cloud-init data
  - modprobe sr_mod || true
  - mkdir -p /mnt/cidata
  - mount /dev/sr0 /mnt/cidata || mount /dev/sr1 /mnt/cidata || echo "Could not mount cloud-init CD-ROM" >> /var/log/cloud-init-debug.log
  - ls -la /mnt/cidata >> /var/log/cloud-init-debug.log 2>&1 || echo "No cloud-init data found" >> /var/log/cloud-init-debug.log
  # Force cloud-init to recognize NoCloud datasource
  - systemctl enable cloud-init-local cloud-init cloud-config cloud-final
  - systemctl daemon-reload
  # Clean up conflicting network connections early - keep System eth0 as it has correct IP
  - nmcli connection delete eth0 || true

runcmd:
  - |
    echo "Running cloud-init commands for $VMName" >> /var/log/cloud-init-debug.log
    # CRITICAL: Disable and remove conflicting Packer SSH enforcement service
    systemctl stop packer-ssh-enforce.service || true
    systemctl disable packer-ssh-enforce.service || true
    rm -f /etc/systemd/system/packer-ssh-enforce.service || true
    rm -f /etc/ssh/.packer-ssh-marker || true
    systemctl daemon-reload
    # Force password authentication to be enabled in all SSH configs
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    # Ensure user passwords are actually set correctly
    echo "root:$RootPassword" | chpasswd
    echo "${Username}:$UserPassword" | chpasswd
    # Force user account to be unlocked and enabled
    passwd -u root || true
    passwd -u $Username || true
    # Remove any existing eth0 connections that might conflict - keep System eth0 as it has correct config
    nmcli connection delete eth0 || true
    # Reload network configuration to pick up new connection file
    systemctl reload NetworkManager
    nmcli connection reload
    sleep 5
    # List connections to debug
    nmcli connection show >> /var/log/cloud-init-debug.log
    # Bring up the new cloudinit-eth0 connection
    nmcli connection up cloudinit-eth0 || true
    # If that fails, try direct IP configuration
    sleep 5
    ip addr show eth0 >> /var/log/cloud-init-debug.log
    # Check if we got the right IP, if not force it
    if ! ip addr show eth0 | grep -q '$IPAddress'; then 
      ip addr flush dev eth0 
      ip addr add $IPAddress/24 dev eth0 
      ip route add default via $Gateway
    fi
    # Restart SSH to apply new configuration
    systemctl restart sshd
    systemctl enable sshd
    echo "Network configured: `$(ip addr show eth0 | grep inet)" >> /var/log/cloud-init-debug.log
    echo "SSH config: `$(grep PasswordAuthentication /etc/ssh/sshd_config)" >> /var/log/cloud-init-debug.log
    echo "User accounts: `$(getent passwd | grep -E '^(root|$Username):')" >> /var/log/cloud-init-debug.log
    echo "Cloud-init configuration completed for $VMName at `$(date)" >> /var/log/cloud-init-debug.log
    /usr/local/bin/cloud-init-debug >> /var/log/cloud-init-debug.log

# Package updates
package_update: false
package_upgrade: false

# Final message
final_message: "Cloud-init completed successfully for $VMName at \$UPTIME seconds"
"@

    if ($SSHPublicKey) {
        $userData = $userData -replace "ssh_authorized_keys: \[\]", "ssh_authorized_keys:`n      - `"$SSHPublicKey`""
    }
    
    $userDataPath = Join-Path $vmCloudInitPath "user-data"
    # Write without BOM - this is critical for cloud-init to work properly
    [System.IO.File]::WriteAllText($userDataPath, $userData, [System.Text.UTF8Encoding]::new($false))
    
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
    # Write without BOM - this is critical for cloud-init to work properly
    [System.IO.File]::WriteAllText($networkConfigPath, $networkConfig, [System.Text.UTF8Encoding]::new($false))
    
    # Create NoCloud ISO using available tools
    $isoPath = $OutputPath
    
    # Try to create ISO using different methods
    $isoCreated = $false
    
    # Method 1: Use mkisofs if available
    try {
        $result = mkisofs -output $isoPath -volid CD_ROM -joliet -rock $vmCloudInitPath 2>$null
        if ($LASTEXITCODE -eq 0) {
            $isoCreated = $true
            Write-Host "  Created cloud-init ISO using mkisofs" -ForegroundColor Gray
        }
    } catch {}
    
    # Method 2: Use genisoimage if available
    if (-not $isoCreated) {
        try {
            $result = genisoimage -output $isoPath -volid CD_ROM -joliet -rock $vmCloudInitPath 2>$null
            if ($LASTEXITCODE -eq 0) {
                $isoCreated = $true
                Write-Host "  Created cloud-init ISO using genisoimage" -ForegroundColor Gray
            }
        } catch {}
    }
    
    # Method 3: Try to find oscdimg.exe in Windows SDK or ADK locations
    if (-not $isoCreated) {
        Write-Host "  Searching for Windows ISO creation tools..." -ForegroundColor Gray
        
        # Common locations for oscdimg.exe
        $oscdimgPaths = @(
            "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
            "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
            "C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\oscdimg.exe",
            "C:\Program Files (x86)\Microsoft SDKs\Windows\v7.1A\Bin\oscdimg.exe"
        )
        
        $oscdimgPath = $null
        foreach ($path in $oscdimgPaths) {
            if (Test-Path $path) {
                $oscdimgPath = $path
                break
            }
        }
        
        if ($oscdimgPath) {
            try {
                Write-Host "  Found oscdimg at: $oscdimgPath" -ForegroundColor Gray
                $result = & "$oscdimgPath" -n -m -o -h "$vmCloudInitPath" "$isoPath" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $isoCreated = $true
                    Write-Host "  Created cloud-init ISO using oscdimg from Windows SDK" -ForegroundColor Gray
                }
            } catch {
                Write-Warning "  oscdimg failed: $($_.Exception.Message)"
            }
        }
    }
    
    # Method 4: Create a simple ISO using PowerShell COM objects (last resort)
    if (-not $isoCreated) {
        Write-Host "  Attempting to create ISO using PowerShell COM..." -ForegroundColor Gray
        try {
            # Use IMAPI2 COM interface to create ISO
            $mediaType = 1  # IMAPI_MEDIA_TYPE_DISK
            $image = New-Object -ComObject IMAPI2.MsftFileSystemImage
            $image.VolumeName = "CD_ROM"
            $image.FileSystemsToCreate = 3  # ISO9660 + Joliet
            
            $dir = $image.Root
            
            # Add files to the image
            $files = Get-ChildItem $vmCloudInitPath -File
            foreach ($file in $files) {
                $fileStream = $image.CreateFileItem($file.FullName)
                $dir.AddFile($file.Name, $fileStream)
            }
            
            # Create the ISO
            $result = $image.CreateResultImage()
            $stream = $result.ImageStream
            
            # Write to file
            $buffer = New-Object byte[] 2048
            $fileStream = [System.IO.File]::Create($isoPath)
            
            do {
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -gt 0) {
                    $fileStream.Write($buffer, 0, $bytesRead)
                }
            } while ($bytesRead -gt 0)
            
            $fileStream.Close()
            $stream.Close()
            
            if (Test-Path $isoPath) {
                $isoCreated = $true
                Write-Host "  Created cloud-init ISO using COM interface" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "  COM ISO creation failed: $($_.Exception.Message)"
        }
    }
    
    if (-not $isoCreated) {
        Write-Error "  Unable to create cloud-init ISO. Please install Windows ADK or ensure mkisofs/genisoimage is available."
        Write-Host "  Cloud-init files created in: $vmCloudInitPath" -ForegroundColor Yellow
        Write-Host "  You can manually create an ISO using: oscdimg -n -m -o -h `"$vmCloudInitPath`" `"$isoPath`"" -ForegroundColor Yellow
        return $false
    }
    
    return $isoCreated
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
        
        if (-not $isoCreated) {
            Write-Error "Failed to create cloud-init ISO for $VMName. Cannot proceed without cloud-init configuration."
            throw "Cloud-init configuration failed"
        }
        
        Write-Host "  Cloud-init ISO created successfully" -ForegroundColor Green
        
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
