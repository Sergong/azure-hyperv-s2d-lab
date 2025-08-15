# Fix Cloud-init Issues in AlmaLinux Template
# This script diagnoses and fixes common cloud-init problems in the template VM

param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "labuser",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "labpass123!"
)

Write-Host "=== Fixing Cloud-init in Template VM: $VMName ====" -ForegroundColor Cyan

# Function to run commands in the VM via SSH
function Invoke-VMCommand {
    param(
        [string]$Command,
        [string]$Description
    )
    
    Write-Host "  $Description..." -ForegroundColor Gray
    
    # Get VM IP address
    $vm = Get-VM -Name $VMName
    $vmIP = $null
    
    # Try to get IP from VM integration services
    $kvpData = Get-VMKeyValuePairItem -VMName $VMName | Where-Object { $_.Key -eq "NetworkAddressIPv4" }
    if ($kvpData) {
        $vmIP = $kvpData.Value
    }
    
    if (-not $vmIP) {
        # Try to get IP from network adapter
        $networkAdapter = Get-VMNetworkAdapter -VMName $VMName
        $vmIP = $networkAdapter.IPAddresses | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+$" } | Select-Object -First 1
    }
    
    if (-not $vmIP) {
        Write-Warning "Could not determine VM IP address. Using default template IP 192.168.200.100"
        $vmIP = "192.168.200.100"
    }
    
    Write-Host "    Using VM IP: $vmIP" -ForegroundColor Gray
    
    # Create SSH command using plink (if available) or warn about manual execution
    try {
        $sshCommand = "echo `"$Password`" | plink -ssh -l $Username -pw `"$Password`" $vmIP `"$Command`""
        $result = Invoke-Expression $sshCommand 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ Success" -ForegroundColor Green
            return $result
        } else {
            Write-Warning "    SSH command failed. Please run manually: ssh $Username@$vmIP '$Command'"
            return $null
        }
    } catch {
        Write-Host "    Manual execution required:" -ForegroundColor Yellow
        Write-Host "      ssh $Username@$vmIP" -ForegroundColor White
        Write-Host "      sudo $Command" -ForegroundColor White
        return $null
    }
}

# Check if VM is running
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Error "VM '$VMName' not found!"
    exit 1
}

if ($vm.State -ne "Running") {
    Write-Host "Starting VM $VMName..." -ForegroundColor Yellow
    Start-VM -Name $VMName
    Write-Host "Waiting for VM to boot..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
}

Write-Host "`nStep 1: Checking cloud-init status..."
Invoke-VMCommand "cloud-init status --long" "Checking current cloud-init status"

Write-Host "`nStep 2: Checking for cloud-init disable files..."
Invoke-VMCommand "ls -la /etc/cloud/cloud-init.disabled /var/lib/cloud/data/disabled 2>/dev/null || echo 'No disable files found'" "Looking for disable files"

Write-Host "`nStep 3: Enabling cloud-init services..."
Invoke-VMCommand "sudo systemctl enable cloud-init-local cloud-init cloud-config cloud-final" "Enabling cloud-init services"

Write-Host "`nStep 4: Removing any disable files..."
Invoke-VMCommand "sudo rm -f /etc/cloud/cloud-init.disabled /var/lib/cloud/data/disabled" "Removing disable files"

Write-Host "`nStep 5: Configuring cloud-init for NoCloud..."
$cloudInitConfig = @"
# Force cloud-init to use NoCloud data source
datasource_list: [ NoCloud ]
datasource:
  NoCloud:
    seedfrom: /var/lib/cloud/seed/nocloud/
"@

# Create a temporary file path
$tempConfigPath = "/tmp/99_force_nocloud.cfg"

Write-Host "  Creating cloud-init configuration..." -ForegroundColor Gray
Write-Host "    Manual steps required:" -ForegroundColor Yellow
Write-Host "      ssh $Username@<VM_IP>" -ForegroundColor White
Write-Host "      sudo tee /etc/cloud/cloud.cfg.d/99_force_nocloud.cfg << 'EOF'" -ForegroundColor White
Write-Host $cloudInitConfig -ForegroundColor White
Write-Host "      EOF" -ForegroundColor White

Write-Host "`nStep 6: Ensuring NoCloud seed directory exists..."
Invoke-VMCommand "sudo mkdir -p /var/lib/cloud/seed/nocloud && sudo chown -R root:root /var/lib/cloud/seed" "Creating NoCloud seed directory"

Write-Host "`nStep 7: Cleaning cloud-init state..."
Invoke-VMCommand "sudo cloud-init clean --logs" "Cleaning cloud-init state and logs"

Write-Host "`nStep 8: Verifying configuration..."
Invoke-VMCommand "sudo cloud-init init --local" "Testing cloud-init local initialization"

Write-Host "`n=== Manual Verification Steps ====" -ForegroundColor Cyan
Write-Host "Please connect to the VM and run these commands to verify:"
Write-Host "  1. Check status: cloud-init status --long" -ForegroundColor White
Write-Host "  2. Check config: cloud-init query --all" -ForegroundColor White
Write-Host "  3. Check logs: sudo tail -f /var/log/cloud-init.log" -ForegroundColor White
Write-Host "  4. Test NoCloud: sudo cloud-init init --local" -ForegroundColor White

Write-Host "`n=== Template Preparation Complete ====" -ForegroundColor Green
Write-Host "After making these changes, shut down the VM and use it as a template."
Write-Host "The next deployment should have working cloud-init!"

Write-Host "`nTo shut down the VM when ready:"
Write-Host "  Stop-VM -Name $VMName" -ForegroundColor White
