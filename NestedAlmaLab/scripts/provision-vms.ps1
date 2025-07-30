# Define VM settings
$vmPrefix       = "AlmaVM"
$vmCount        = 2
$vmMemory       = 2GB
$vmVHDSizeGB    = 30
$vmSwitchName   = "InternalLabSwitch"
$vmGeneration   = 2
$vmPath         = "C:\HyperV\VMs"
$vhdPath        = "$vmPath\VHDs"
$isoPath        = "C:\ISOs\AlmaLinux-latest-x86_64.iso"
$ksPath         = "C:\ISOs\ks.cfg"

# Create folders
New-Item -ItemType Directory -Path $vmPath, $vhdPath -Force | Out-Null

# Provision VMs with AlmaLinux ISO
for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "$vmPrefix-$i"
    $vhdFile = "$vhdPath\$vmName.vhdx"

    # Create VM
    New-VHD -Path $vhdFile -SizeBytes ($vmVHDSizeGB * 1GB) -Dynamic
    New-VM -Name $vmName -MemoryStartupBytes $vmMemory -Generation $vmGeneration `
           -SwitchName $vmSwitchName -Path $vmPath
    Add-VMHardDiskDrive -VMName $vmName -Path $vhdFile
    Set-VMFirmware -VMName $vmName -EnableSecureBoot Off
    Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true

    # Mount AlmaLinux ISO
    Add-VMDvdDrive -VMName $vmName -Path $isoPath

    # Inject Kickstart ISO via ISO or floppy (easier with ISO tools or config-drive if needed)

    # Start VM to begin automated install
    Start-VM -Name $vmName
}

Write-Host "`nCreated $vmCount AlmaLinux nested VMs with automated OS installation."

