# Script to check bootstrap status and diagnose issues
# Run this on either VM to check the bootstrap status

Write-Host "=== Bootstrap Status Check ===" -ForegroundColor Green
Write-Host "Computer Name: $env:COMPUTERNAME"
Write-Host "Date/Time: $(Get-Date)"
Write-Host ""

# Check if NodeReady marker exists
Write-Host "1. Checking NodeReady marker..." -ForegroundColor Yellow
if (Test-Path "C:\NodeReady.txt") {
    Write-Host "✓ NodeReady.txt exists" -ForegroundColor Green
    Get-Content "C:\NodeReady.txt"
} else {
    Write-Host "✗ NodeReady.txt not found" -ForegroundColor Red
}
Write-Host ""

# Check if S2D script exists (should be on hyperv-node-0 only)
Write-Host "2. Checking S2D setup script..." -ForegroundColor Yellow
if (Test-Path "C:\setup-s2d-cluster.ps1") {
    $scriptInfo = Get-Item "C:\setup-s2d-cluster.ps1"
    Write-Host "✓ setup-s2d-cluster.ps1 exists" -ForegroundColor Green
    Write-Host "  Size: $($scriptInfo.Length) bytes"
    Write-Host "  Created: $($scriptInfo.CreationTime)"
    Write-Host "  Modified: $($scriptInfo.LastWriteTime)"
} else {
    Write-Host "✗ setup-s2d-cluster.ps1 not found" -ForegroundColor Red
    if ($env:COMPUTERNAME -eq "hyperv-node-0") {
        Write-Host "  This is hyperv-node-0 - the S2D script should be here!" -ForegroundColor Red
    } else {
        Write-Host "  This is not hyperv-node-0 - S2D script only downloads to hyperv-node-0" -ForegroundColor Gray
    }
}
Write-Host ""

# Check bootstrap logs
Write-Host "3. Checking bootstrap logs..." -ForegroundColor Yellow
if (Test-Path "C:\bootstrap-extension.txt") {
    Write-Host "✓ Bootstrap log exists" -ForegroundColor Green
    Write-Host "--- Last 20 lines of bootstrap log ---" -ForegroundColor Cyan
    Get-Content "C:\bootstrap-extension.txt" -Tail 20
} else {
    Write-Host "✗ Bootstrap log not found at C:\bootstrap-extension.txt" -ForegroundColor Red
}
Write-Host ""

# Check Windows features
Write-Host "4. Checking installed Windows features..." -ForegroundColor Yellow
$features = @('Hyper-V', 'Failover-Clustering', 'FS-FileServer')
foreach ($feature in $features) {
    $featureState = Get-WindowsFeature -Name $feature
    if ($featureState.InstallState -eq 'Installed') {
        Write-Host "✓ $feature is installed" -ForegroundColor Green
    } else {
        Write-Host "✗ $feature is NOT installed (State: $($featureState.InstallState))" -ForegroundColor Red
    }
}
Write-Host ""

# Check attached disks
Write-Host "5. Checking attached disks..." -ForegroundColor Yellow
$disks = Get-Disk | Where-Object { $_.BusType -ne "File Backed Virtual" }
Write-Host "Found $($disks.Count) physical/virtual disks:"
$disks | Format-Table Number, FriendlyName, Size, PartitionStyle -AutoSize
Write-Host ""

# Check network connectivity to blob storage
Write-Host "6. Testing network connectivity to blob storage..." -ForegroundColor Yellow
try {
    $testUrl = "https://hypervscripts1jwvkvf4.blob.core.windows.net/scripts/setup-s2d-cluster.ps1"
    $response = Invoke-WebRequest -Uri $testUrl -Method Head -UseBasicParsing -TimeoutSec 10
    Write-Host "✓ Can reach blob storage (HTTP $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "✗ Cannot reach blob storage: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "=== Status Check Complete ===" -ForegroundColor Green
