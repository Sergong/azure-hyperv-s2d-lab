# Fix Cloud-init Issues in AlmaLinux Template
# This script provides manual steps to fix cloud-init in the template VM

param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "labuser",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "labpass123!"
)

Write-Host "=== Cloud-init Template Fix Guide for VM: $VMName ====" -ForegroundColor Cyan

# Check if VM exists and get its info
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Error "VM '$VMName' not found!"
    exit 1
}

# Start VM if not running
if ($vm.State -ne "Running") {
    Write-Host "Starting VM $VMName..." -ForegroundColor Yellow
    Start-VM -Name $VMName
    Write-Host "Waiting for VM to boot..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
}

# Try to get VM IP
$vmIP = $null
try {
    $networkAdapter = Get-VMNetworkAdapter -VMName $VMName
    $vmIP = $networkAdapter.IPAddresses | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+$" } | Select-Object -First 1
} catch {}

if (-not $vmIP) {
    $vmIP = "192.168.200.100"  # Default template IP
    Write-Warning "Could not detect VM IP, using default: $vmIP"
} else {
    Write-Host "Detected VM IP: $vmIP" -ForegroundColor Green
}

# Display manual steps
Write-Host "`n=== MANUAL STEPS TO FIX CLOUD-INIT ====" -ForegroundColor Yellow
Write-Host "Connect to your VM and run these commands:"

Write-Host "`n1. Connect to the VM:" -ForegroundColor Cyan
Write-Host "   ssh $Username@$vmIP" -ForegroundColor White
Write-Host "   Password: $Password" -ForegroundColor Gray

Write-Host "`n2. Check current cloud-init status:" -ForegroundColor Cyan
Write-Host "   cloud-init status --long" -ForegroundColor White

Write-Host "`n3. Check for disable files:" -ForegroundColor Cyan
Write-Host "   ls -la /etc/cloud/cloud-init.disabled /var/lib/cloud/data/disabled 2>/dev/null" -ForegroundColor White

Write-Host "`n4. Remove any disable files:" -ForegroundColor Cyan
Write-Host "   sudo rm -f /etc/cloud/cloud-init.disabled /var/lib/cloud/data/disabled" -ForegroundColor White

Write-Host "`n5. Enable cloud-init services:" -ForegroundColor Cyan
Write-Host "   sudo systemctl enable cloud-init-local cloud-init cloud-config cloud-final" -ForegroundColor White

Write-Host "`n6. Create NoCloud configuration:" -ForegroundColor Cyan
Write-Host "   sudo tee /etc/cloud/cloud.cfg.d/99_force_nocloud.cfg > /dev/null << 'EOF'" -ForegroundColor White
Write-Host "# Force cloud-init to use NoCloud data source" -ForegroundColor Gray
Write-Host "datasource_list: [ NoCloud ]" -ForegroundColor Gray
Write-Host "datasource:" -ForegroundColor Gray
Write-Host "  NoCloud:" -ForegroundColor Gray
Write-Host "    seedfrom: /var/lib/cloud/seed/nocloud/" -ForegroundColor Gray
Write-Host "EOF" -ForegroundColor White

Write-Host "`n7. Ensure NoCloud seed directory exists:" -ForegroundColor Cyan
Write-Host "   sudo mkdir -p /var/lib/cloud/seed/nocloud" -ForegroundColor White
Write-Host "   sudo chown -R root:root /var/lib/cloud/seed" -ForegroundColor White

Write-Host "`n8. Clean cloud-init state:" -ForegroundColor Cyan
Write-Host "   sudo cloud-init clean --logs" -ForegroundColor White

Write-Host "`n9. Test cloud-init configuration:" -ForegroundColor Cyan
Write-Host "   sudo cloud-init init --local" -ForegroundColor White
Write-Host "   cloud-init status --long" -ForegroundColor White

Write-Host "`n10. Shut down the VM to prepare template:" -ForegroundColor Cyan
Write-Host "    sudo shutdown -h now" -ForegroundColor White

Write-Host "`n=== VERIFICATION COMMANDS ====" -ForegroundColor Yellow
Write-Host "After restarting the VM, these should work:"
Write-Host "   cloud-init status --long      # Should show 'done'" -ForegroundColor White
Write-Host "   cloud-init query datasource   # Should show 'NoCloud'" -ForegroundColor White
Write-Host "   ls -la /var/lib/cloud/seed/nocloud/  # Should be accessible" -ForegroundColor White

Write-Host "`n=== POWERSHELL COMMANDS ====" -ForegroundColor Green
Write-Host "After fixing the template, stop the VM:"
Write-Host "   Stop-VM -Name $VMName" -ForegroundColor White
Write-Host "`nThen test deployment with:"
Write-Host "   .\NestedAlmaLab\scripts\deploy-with-cloudinit.ps1 -VMCount 1 -StartVMs" -ForegroundColor White
