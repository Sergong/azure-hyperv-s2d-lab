# Cloud-init Deployment Examples
# This script shows different ways to use the deploy-with-cloudinit.ps1 script

Write-Host "=== Cloud-init Deployment Examples ===" -ForegroundColor Cyan

Write-Host "`n1. Basic deployment (2 VMs, default settings):"
Write-Host "   .\deploy-with-cloudinit.ps1 -StartVMs" -ForegroundColor Yellow

Write-Host "`n2. Custom network range (10 VMs starting at .50):"
Write-Host "   .\deploy-with-cloudinit.ps1 -VMCount 10 -NetworkSubnet '192.168.100' -StartIP 50 -StartVMs" -ForegroundColor Yellow

Write-Host "`n3. Different user credentials:"
Write-Host "   .\deploy-with-cloudinit.ps1 -Username 'admin' -UserPassword 'SecurePass123!' -RootPassword 'RootPass456!' -StartVMs" -ForegroundColor Yellow

Write-Host "`n4. Custom VM naming and memory:"
Write-Host "   .\deploy-with-cloudinit.ps1 -VMPrefix 'TestLab' -VMCount 5 -Memory 4GB -StartVMs" -ForegroundColor Yellow

Write-Host "`n5. Different switch and DNS:"
Write-Host "   .\deploy-with-cloudinit.ps1 -SwitchName 'Internal' -DNS '1.1.1.1,1.0.0.1' -StartVMs" -ForegroundColor Yellow

Write-Host "`n6. With SSH public key authentication:"
Write-Host "   `$sshKey = Get-Content ~/.ssh/id_rsa.pub"
Write-Host "   .\deploy-with-cloudinit.ps1 -SSHPublicKey `$sshKey -StartVMs" -ForegroundColor Yellow

Write-Host "`n=== Key Benefits of Cloud-init Approach ===" -ForegroundColor Green
Write-Host "[OK] Each VM gets a unique IP address automatically"
Write-Host "[OK] No need to rebuild templates for different configurations"
Write-Host "[OK] Can customize users, passwords, and SSH keys per deployment"
Write-Host "[OK] Network configuration is applied at boot time"
Write-Host "[OK] Supports both password and key-based SSH authentication"
Write-Host "[OK] VMs are immediately accessible after boot"

Write-Host "`n=== Cloud-init vs. Kickstart Comparison ===" -ForegroundColor White
Write-Host "Kickstart (current approach):"
Write-Host "  - Configuration baked into template during build"
Write-Host "  - All VMs have identical configuration"
Write-Host "  - Need to rebuild template for changes"
Write-Host "  - Static IP conflicts when deploying multiple VMs"

Write-Host "`nCloud-init (new approach):"
Write-Host "  - Configuration applied at deployment time"
Write-Host "  - Each VM can have unique configuration"
Write-Host "  - No template rebuild needed for config changes"
Write-Host "  - Automatic unique IP assignment"
Write-Host "  - More flexible and reusable templates"

Write-Host "`n=== Usage Workflow ===" -ForegroundColor Cyan
Write-Host "1. Build template once with build-static-ip.ps1"
Write-Host "2. Deploy VMs with custom configs using deploy-with-cloudinit.ps1"
Write-Host "3. Each VM gets unique IP, hostname, and optionally custom users"
Write-Host "4. VMs are ready for SSH access immediately after boot"

Write-Host "`n=== Troubleshooting ===" -ForegroundColor Yellow
Write-Host "If cloud-init fails:"
Write-Host "  - Check logs: sudo tail -f /var/log/cloud-init.log"
Write-Host "  - Verify config: sudo cloud-init status"
Write-Host "  - Manual network: sudo nmcli connection up eth0"
Write-Host "  - Check files: ls -la /var/lib/cloud/seed/nocloud/"

Write-Host "`nFor detailed help:"
Write-Host "Get-Help .\deploy-with-cloudinit.ps1 -Full"
