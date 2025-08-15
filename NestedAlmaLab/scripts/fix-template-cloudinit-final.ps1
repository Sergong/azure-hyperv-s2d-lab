# Fix cloud-init template configuration for CD-ROM NoCloud datasource
# This script provides the exact commands to run inside the template VM

Write-Host "=== Fix Cloud-init Template Configuration ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Run these commands INSIDE the template VM to fix cloud-init:" -ForegroundColor Yellow
Write-Host ""

$commands = @"
# 1. Remove the incorrect cloud-init configuration file
sudo rm -f /etc/cloud/cloud.cfg.d/99_force_nocloud.cfg

# 2. Create the correct cloud-init configuration for CD-ROM NoCloud
sudo tee /etc/cloud/cloud.cfg.d/90_dpkg.cfg << 'EOF'
# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

# 3. Create a proper NoCloud datasource configuration (Option 1: fs_label only)
sudo tee /etc/cloud/cloud.cfg.d/99_nocloud_cdrom.cfg << 'EOF'
# Force NoCloud datasource to check CD-ROM with cidata label
datasource:
  NoCloud:
    # Look for ISO with volume label 'cidata'
    fs_label: cidata
EOF

# Alternative Option 2: Use seedfrom with file:// URI (uncomment if Option 1 doesn't work)
# sudo tee /etc/cloud/cloud.cfg.d/99_nocloud_cdrom.cfg << 'EOF'
# # Force NoCloud datasource to check specific CD-ROM device
# datasource:
#   NoCloud:
#     # Read from CD-ROM device directly
#     seedfrom: file:///dev/sr0
# EOF

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

# 7. Verify our ISO has the correct volume label
echo ""
echo "=== Checking ISO volume label ==="
sudo blkid /dev/sr0

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
Write-Host "=== Important Notes ===" -ForegroundColor Yellow
Write-Host "- Option 1 (fs_label) is preferred as it's more reliable"
Write-Host "- Our deployment script creates ISOs with volume label 'cidata'"
Write-Host "- The blkid command will verify the ISO has the correct label"
Write-Host "- If fs_label doesn't work, try the seedfrom option commented above"
Write-Host ""
Write-Host "=== After Running These Commands ===" -ForegroundColor Green
Write-Host "1. Verify 'blkid /dev/sr0' shows LABEL=\"cidata\""
Write-Host "2. Verify cloud-init status shows 'done' or 'running'"
Write-Host "3. Shutdown the template VM: sudo shutdown -h now"
Write-Host "4. Deploy new VMs using the deployment script"
Write-Host ""
Write-Host "=== If fs_label Doesn't Work ===" -ForegroundColor Cyan
Write-Host "Replace step 3 above with the seedfrom version:"
Write-Host "sudo tee /etc/cloud/cloud.cfg.d/99_nocloud_cdrom.cfg << 'EOF'"
Write-Host "datasource:"
Write-Host "  NoCloud:"
Write-Host "    seedfrom: file:///dev/sr0"
Write-Host "EOF"
Write-Host ""
