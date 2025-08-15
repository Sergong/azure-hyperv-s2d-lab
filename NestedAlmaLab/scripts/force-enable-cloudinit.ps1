# Force Enable Cloud-init Script
# This script creates a bash script to ensure cloud-init is enabled and will run on first boot
# Run this script on Windows host, then copy the generated bash script to your VM

param(
    [Parameter(Mandatory=$false)]
    [string]$VMName = "AlmaLinux-CloudInit-Template"
)

Write-Host "=== Force Enabling Cloud-init ===" -ForegroundColor Cyan
Write-Host "VM: $VMName"
Write-Host "==============================="

# Create the bash script content
$bashScript = @'
#!/bin/bash
set -e

echo "Starting cloud-init enablement process..."

# 1. Remove all possible disable files
echo "Removing cloud-init disable files..."
rm -f /etc/cloud/cloud-init.disabled
rm -f /run/cloud-init/disabled
rm -f /var/lib/cloud/data/disabled
rm -f /var/lib/cloud/instance/disabled

# 2. Force enable all cloud-init services
echo "Enabling cloud-init services..."
systemctl enable cloud-init-local.service
systemctl enable cloud-init.service  
systemctl enable cloud-config.service
systemctl enable cloud-final.service

# 3. Unmask services in case they were masked
echo "Unmasking cloud-init services..."
systemctl unmask cloud-init-local.service
systemctl unmask cloud-init.service
systemctl unmask cloud-config.service 
systemctl unmask cloud-final.service

# 4. Create ds-identify config to force enable
echo "Creating ds-identify configuration..."
cat > /etc/cloud/ds-identify.cfg << 'EOF'
# Force cloud-init to always enable - never disable
policy: enabled
EOF

# 5. Configure cloud-init to always look for NoCloud data
echo "Configuring NoCloud datasource..."
cat > /etc/cloud/cloud.cfg.d/90_nocloud_forced.cfg << 'EOF'
# Force NoCloud datasource to be available
datasource_list: [ NoCloud, None ]
datasource:
  NoCloud:
    # Look for seed data on CD-ROM
    fs_label: CD_ROM
    # Fallback locations
    seedfrom: file:///dev/sr0
EOF

# 6. Create systemd override to force cloud-init services to start
echo "Creating systemd overrides..."
mkdir -p /etc/systemd/system/cloud-init.service.d
cat > /etc/systemd/system/cloud-init.service.d/override.conf << 'EOF'
[Unit]
ConditionPathExists=
ConditionFileNotEmpty=

[Service]
ExecStart=
ExecStart=/usr/bin/cloud-init init
EOF

mkdir -p /etc/systemd/system/cloud-init-local.service.d
cat > /etc/systemd/system/cloud-init-local.service.d/override.conf << 'EOF'
[Unit]
ConditionPathExists=
ConditionFileNotEmpty=

[Service]
ExecStart=
ExecStart=/usr/bin/cloud-init init --local
EOF

# 7. Clean any existing cloud-init state
echo "Cleaning cloud-init state..."
cloud-init clean --logs || true
rm -rf /var/lib/cloud/instances/*
rm -f /var/lib/cloud/instance/datasource
rm -f /var/lib/cloud/data/result.json
rm -f /var/lib/cloud/data/status.json

# 8. Reload systemd and verify services
echo "Reloading systemd and verifying services..."
systemctl daemon-reload

# 9. Verify cloud-init is enabled
echo "Verifying cloud-init service status..."
for service in cloud-init-local cloud-init cloud-config cloud-final; do
    status=$(systemctl is-enabled $service.service 2>/dev/null || echo "unknown")
    echo "  $service.service: $status"
    if [ "$status" != "enabled" ]; then
        echo "  WARNING: $service is not enabled!"
        systemctl enable $service.service
    fi
done

# 10. Test cloud-init configuration
echo "Testing cloud-init configuration..."
cloud-init schema --system || echo "Schema validation failed - this may be normal"

echo "Cloud-init enablement completed successfully!"
echo "Services that will run on next boot:"
systemctl list-unit-files | grep cloud-init

echo "Cloud-init status:"
cloud-init status --long
'@

# Save the bash script
$outputPath = "force-enable-cloudinit.sh"
$bashScript | Set-Content -Path $outputPath -Encoding UTF8

Write-Host "Bash script created: $outputPath" -ForegroundColor Green

Write-Host "`n=== Instructions ===" -ForegroundColor Yellow
Write-Host "1. Copy this script to your template VM:"
Write-Host "   scp $outputPath labuser@<vm-ip>:/tmp/"
Write-Host ""
Write-Host "2. Run the script inside the VM:"
Write-Host "   ssh labuser@<vm-ip>"
Write-Host "   sudo chmod +x /tmp/$outputPath"
Write-Host "   sudo /tmp/$outputPath"
Write-Host ""
Write-Host "3. Verify cloud-init status (should show 'running' or 'done'):"
Write-Host "   sudo cloud-init status --long"
Write-Host ""
Write-Host "4. Clean up and shutdown:"
Write-Host "   sudo rm /tmp/$outputPath"
Write-Host "   sudo shutdown -h now"
Write-Host ""

Write-Host "=== What This Script Does ===" -ForegroundColor White
Write-Host "• Removes all cloud-init disable files"
Write-Host "• Enables and unmasks all cloud-init services"  
Write-Host "• Forces ds-identify to always enable cloud-init"
Write-Host "• Creates systemd service overrides to bypass conditions"
Write-Host "• Configures NoCloud datasource for CD-ROM"
Write-Host "• Cleans cloud-init state for fresh deployment"
Write-Host "• Verifies all services are enabled"

Write-Host "`nAfter running this script in your template VM, cloud-init should stay enabled permanently." -ForegroundColor Green
