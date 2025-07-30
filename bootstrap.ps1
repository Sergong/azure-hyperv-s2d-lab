# Ensure Hyper-V and Failover Clustering are enabled
Install-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-FileServer -IncludeManagementTools -Restart

# Optional: Create internal switch
New-VMSwitch -SwitchName "InternalLabSwitch" -SwitchType Internal

# Prepare virtual disks for S2D simulation
Get-PhysicalDisk | Where-Object CanPool -eq $True | New-StoragePool -FriendlyName LabPool -StorageSubsystemFriendlyName "Storage Spaces*" |
New-Volume -FriendlyName S2DVolume -FileSystem NTFS -Size 100GB

# Validate cluster
Test-Cluster -Node "hyperv-node-0","hyperv-node-1"

# Create cluster
New-Cluster -Name "S2DCluster" -Node "hyperv-node-0","hyperv-node-1" -StaticAddress "10.0.1.100"

# Enable S2D
Enable-ClusterS2D

# Done – now you can create test VMs inside nested Hyper-V

