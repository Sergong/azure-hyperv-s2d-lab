# Fix cloud-init template configuration to use file:///dev/sr0 URI
# This script provides the exact commands to run inside the template VM

Write-Host "=== Fix Cloud-init Template Configuration with file:///dev/sr0 URI ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Run these commands INSIDE the template VM to fix cloud-init:" -ForegroundColor Yellow
Write-Host ""

$commands = @"
# 1. Remove the incorrect cloud-init configuration file
sudo rm -f /etc/cloud/cloud.cfg.d/99_force_nocloud.cfg
sudo rm -f /etc/cloud/cloud.cfg.d/99_nocloud_cdrom.cfg

# 2. Create the correct cloud-init configuration for CD-ROM NoCloud
sudo tee /etc/cloud/cloud.cfg.d/90_dpkg.cfg << 'EOF'
# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

# 3. Create a proper NoCloud datasource configuration with file:///dev/sr0 URI
sudo tee /etc/cloud/cloud.cfg.d/99_nocloud_cdrom.cfg << 'EOF'
# Force NoCloud datasource to check CD-ROM with file:///dev/sr0 URI
datasource:
  NoCloud:
    # Read directly from CD-ROM device using file:// URI
    seedfrom: file:///dev/sr0
EOF

# 4. Remove any disable files and clean cloud-init state
sudo rm -f /var/lib/cloud/instance/datasource
sudo rm -f /var/lib/cloud/data/set-hostname
sudo rm -f /var/lib/cloud/data/result.json
sudo rm -rf /var/lib/cloud/instances/*
sudo rm -f /run/cloud-init/disabled
sudo rm -f /etc/cloud/cloud-init.disabled

# 5. Enable cloud-init services
sudo systemctl enable cloud-init-local
sudo systemctl enable cloud-init
sudo systemctl enable cloud-config
sudo systemctl enable cloud-final

# 6. Clean cloud-init completely
sudo cloud-init clean --logs

# 7. Verify our ISO can be mounted
echo ""
echo "=== Checking ISO and mounting it ==="
sudo mkdir -p /mnt/cdrom
sudo mount /dev/sr0 /mnt/cdrom
ls -la /mnt/cdrom
sudo umount /mnt/cdrom

# 8. Test that cloud-init will look for NoCloud datasource
echo ""
echo "=== Testing cloud-init datasource detection ==="
sudo cloud-init init --local
sudo cloud-init status --long

echo ""
echo "If cloud-init status shows 'done' or 'running', the fix is working."
echo "Now shutdown the template VM and deploy new VMs."
"@

Write-Host $commands -ForegroundColor White

Write-Host ""
Write-Host "=== After Running These Commands ===" -ForegroundColor Green
Write-Host "1. Verify the ISO can be mounted and contains user-data, meta-data files"
Write-Host "2. Verify cloud-init status shows 'done' or 'running'"
Write-Host "3. Shutdown the template VM: sudo shutdown -h now"
Write-Host "4. Deploy new VMs using the deployment script"
Write-Host ""
Write-Host "=== If Issues Persist ===" -ForegroundColor Yellow
Write-Host "1. Examine the cloud-init logs in the VM: sudo cat /var/log/cloud-init.log"
Write-Host "2. Check if cloud-init can find the datasource: sudo cloud-init query datasource"
Write-Host "3. You may need to modify the deployment script's ISO creation method to set volume label correctly"
Write-Host ""
