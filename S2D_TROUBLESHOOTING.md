# Storage Spaces Direct (S2D) Troubleshooting Guide

## Issue Fixed: PowerShell Syntax Errors ✅

**Problem**: The original `setup-s2d-cluster.ps1` script had PowerShell syntax errors:
- Missing closing parenthesis in math calculations
- Incorrect string interpolation syntax
- Malformed try-catch blocks

**Solution**: Script has been corrected and updated in Azure Storage blob.

---

## Getting the Fixed Script

### Option 1: Use the Manual Download Script
Copy and paste this into PowerShell on hyperv-node-0:
```powershell
# Download the corrected script
Invoke-WebRequest -Uri "https://hypervscriptsjdlf6gwh.blob.core.windows.net/scripts/setup-s2d-cluster.ps1" -OutFile "C:\setup-s2d-cluster.ps1" -UseBasicParsing
```

### Option 2: Run the Download Helper
```powershell
PowerShell -ExecutionPolicy Bypass -File C:\download-s2d-script.ps1
```

### Option 3: Direct Browser Download
Navigate to: https://hypervscriptsjdlf6gwh.blob.core.windows.net/scripts/setup-s2d-cluster.ps1

---

## Common S2D Setup Issues and Solutions

### 1. Script Download Failures
**Symptoms**: "Could not download S2D script" or "File not found"

**Causes**:
- Network connectivity issues
- Windows Firewall blocking HTTP requests
- Storage account access restrictions

**Solutions**:
```powershell
# Check network connectivity
Test-NetConnection hypervscriptsjdlf6gwh.blob.core.windows.net -Port 443

# Disable Windows Firewall temporarily (if safe)
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Try alternative download method
(New-Object System.Net.WebClient).DownloadFile('https://hypervscriptsjdlf6gwh.blob.core.windows.net/scripts/setup-s2d-cluster.ps1', 'C:\setup-s2d-cluster.ps1')
```

### 2. Insufficient Storage for S2D
**Symptoms**: "No disks available for Storage Spaces Direct"

**Causes**:
- Azure managed disks not properly attached
- Disks already initialized or partitioned
- Insufficient disk count (need at least 2 disks)

**Solutions**:
```powershell
# Check attached disks
Get-PhysicalDisk | Where-Object {$_.CanPool -eq $true}

# Check disk management
Get-Disk | Where-Object {$_.PartitionStyle -eq 'RAW'}

# Reset disk if needed
Get-PhysicalDisk | Where-Object {$_.CanPool -eq $false} | Reset-PhysicalDisk
```

### 3. Cluster Creation Failures
**Symptoms**: "Failed to create cluster" or IP address conflicts

**Causes**:
- Cluster IP already in use
- DNS resolution issues
- Firewall blocking cluster ports
- Node connectivity problems

**Solutions**:
```powershell
# Test cluster connectivity
Test-Cluster -Node "hyperv-node-0", "hyperv-node-1"

# Check IP availability
Test-NetConnection -ComputerName "10.0.1.100" -Port 135

# Use different cluster IP
New-Cluster -Name "S2DCluster" -Node @("hyperv-node-0", "hyperv-node-1") -StaticAddress "10.0.1.101"
```

### 4. Windows Feature Prerequisites
**Symptoms**: "Required feature not installed"

**Solutions**:
```powershell
# Check feature status
Get-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-FileServer

# Install missing features
Install-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-FileServer -IncludeManagementTools -Restart
```

### 5. Node Connectivity Issues
**Symptoms**: "Cannot reach node" or ping failures

**Solutions**:
```powershell
# Check both nodes can communicate
Test-Connection hyperv-node-0, hyperv-node-1

# Verify Windows Firewall
Get-NetFirewallProfile | Select Name, Enabled

# Enable necessary firewall rules
Enable-NetFirewallRule -DisplayGroup "Failover Clusters"
```

---

## Step-by-Step Recovery Process

### 1. Verify Infrastructure
```powershell
# Check if both VMs are running
Get-VM

# Verify network connectivity
ping hyperv-node-0
ping hyperv-node-1
```

### 2. Download Fixed Script
```powershell
# Remove old broken script
Remove-Item C:\setup-s2d-cluster.ps1 -Force -ErrorAction SilentlyContinue

# Download corrected version
Invoke-WebRequest -Uri "https://hypervscriptsjdlf6gwh.blob.core.windows.net/scripts/setup-s2d-cluster.ps1" -OutFile "C:\setup-s2d-cluster.ps1" -UseBasicParsing
```

### 3. Verify Prerequisites
```powershell
# Check Windows features
Get-WindowsFeature | Where-Object {$_.Name -match "Hyper-V|Failover|FileServer"} | Select Name, InstallState

# Check available storage
Get-PhysicalDisk | Where-Object {$_.CanPool -eq $true} | Select FriendlyName, Size, MediaType
```

### 4. Run S2D Setup
```powershell
# Execute the fixed script
PowerShell -ExecutionPolicy Bypass -File C:\setup-s2d-cluster.ps1
```

---

## Manual S2D Setup (Alternative)

If the automated script continues to have issues, you can set up S2D manually:

```powershell
# 1. Create cluster (run on node-0)
New-Cluster -Name "S2DCluster" -Node @("hyperv-node-0", "hyperv-node-1") -StaticAddress "10.0.1.100" -NoStorage

# 2. Enable S2D
Enable-ClusterS2D -Confirm:$false

# 3. Create storage pool and volume
$pool = Get-StoragePool -FriendlyName "S2D*"
New-Volume -StoragePoolFriendlyName $pool.FriendlyName -FriendlyName "S2D-Volume01" -FileSystem NTFS -Size 100GB

# 4. Verify cluster status
Get-Cluster
Get-ClusterS2D
Get-ClusterNode
```

---

## Verification Commands

After successful setup, verify everything is working:

```powershell
# Cluster health
Get-Cluster
Get-ClusterNode
Get-ClusterResource

# S2D status
Get-ClusterS2D
Get-StoragePool
Get-Volume

# Physical disk status
Get-PhysicalDisk
Get-StorageJob
```

---

## Getting Help

If issues persist:

1. **Check logs**: 
   - `C:\S2D-Setup-Log.txt` (setup script log)
   - `C:\bootstrap-extension.txt` (bootstrap log)
   - Event Viewer → Windows Logs → System

2. **Run validation**: 
   ```powershell
   Test-Cluster -Node @("hyperv-node-0", "hyperv-node-1") -Include "Storage Spaces Direct"
   ```

3. **Contact support**: Include the log files and error messages when reporting issues.

The syntax errors in the original script have been resolved, and the corrected version is now available in Azure Storage.
