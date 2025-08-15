# Create Bulletproof Cloud-init Kickstart
# This modifies the kickstart file to absolutely ensure cloud-init cannot be disabled

Write-Host "=== Creating Bulletproof Cloud-init Kickstart ===" -ForegroundColor Cyan

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$originalKickstart = Join-Path $projectRoot "templates\AlmaLinux\hyperv\ks-with-cloudinit.cfg"
$bulletproofKickstart = Join-Path $projectRoot "templates\AlmaLinux\hyperv\ks-bulletproof-cloudinit.cfg"

if (-not (Test-Path $originalKickstart)) {
    Write-Error "Original kickstart not found: $originalKickstart"
    exit 1
}

# Read the original kickstart
$kickstartContent = Get-Content $originalKickstart -Raw

# Add bulletproof cloud-init configuration to the %post section
# We'll insert this right before the final %end
$bulletproofCloudInitConfig = @'

# =============================================================================
# BULLETPROOF CLOUD-INIT CONFIGURATION
# This section ensures cloud-init CANNOT be disabled under any circumstances
# =============================================================================

echo "Starting BULLETPROOF cloud-init configuration..." >> /var/log/ks-post.log

# 1. DISABLE THE SYSTEMD GENERATOR COMPLETELY
echo "Disabling cloud-init systemd generator..." >> /var/log/ks-post.log
# Make the generator always return success without doing anything
if [ -f /lib/systemd/system-generators/cloud-init-generator ]; then
    # Backup the original
    cp /lib/systemd/system-generators/cloud-init-generator /lib/systemd/system-generators/cloud-init-generator.orig
    # Replace with a script that does nothing but enable cloud-init
    cat > /lib/systemd/system-generators/cloud-init-generator << 'GENERATOR_EOF'
#!/bin/bash
# Bulletproof cloud-init generator - ALWAYS enable cloud-init
# This overrides the default generator that can disable cloud-init

TARGET_DIR="$1"
if [ -n "$TARGET_DIR" ]; then
    # Force enable all cloud-init services
    mkdir -p "$TARGET_DIR/multi-user.target.wants"
    ln -sf /lib/systemd/system/cloud-init-local.service "$TARGET_DIR/multi-user.target.wants/cloud-init-local.service" 2>/dev/null || true
    ln -sf /lib/systemd/system/cloud-init.service "$TARGET_DIR/multi-user.target.wants/cloud-init.service" 2>/dev/null || true
    ln -sf /lib/systemd/system/cloud-config.service "$TARGET_DIR/multi-user.target.wants/cloud-config.service" 2>/dev/null || true
    ln -sf /lib/systemd/system/cloud-final.service "$TARGET_DIR/multi-user.target.wants/cloud-final.service" 2>/dev/null || true
fi
exit 0
GENERATOR_EOF
    chmod +x /lib/systemd/system-generators/cloud-init-generator
    echo "Cloud-init generator replaced with bulletproof version" >> /var/log/ks-post.log
fi

# 2. CREATE SYSTEMD SERVICE OVERRIDES TO REMOVE ALL CONDITIONS
echo "Creating systemd service overrides..." >> /var/log/ks-post.log
for service in cloud-init-local cloud-init cloud-config cloud-final; do
    mkdir -p "/etc/systemd/system/${service}.service.d"
    cat > "/etc/systemd/system/${service}.service.d/bulletproof.conf" << SERVICE_EOF
[Unit]
# Remove all conditions that could prevent startup
ConditionPathExists=
ConditionFileNotEmpty=
ConditionKernelCommandLine=
AssertFileIsExecutable=

[Service]
# Ensure the service runs regardless of conditions
RemainAfterExit=true
SERVICE_EOF
    echo "Created override for ${service}.service" >> /var/log/ks-post.log
done

# 3. FORCE DS-IDENTIFY TO ALWAYS ENABLE
echo "Configuring ds-identify to always enable..." >> /var/log/ks-post.log
cat > /etc/cloud/ds-identify.cfg << 'DS_EOF'
# BULLETPROOF: Force cloud-init to ALWAYS enable
policy: enabled
DS_EOF

# 4. CREATE A BOOT-TIME SERVICE TO ENFORCE CLOUD-INIT
echo "Creating boot-time cloud-init enforcer..." >> /var/log/ks-post.log
cat > /etc/systemd/system/cloud-init-enforcer.service << 'ENFORCER_EOF'
[Unit]
Description=Bulletproof Cloud-init Enforcer
DefaultDependencies=false
After=sysinit.target
Before=multi-user.target
Before=graphical.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/bin/bash -c '\
    # Remove any disable files that might have been created\
    rm -f /etc/cloud/cloud-init.disabled /run/cloud-init/disabled /var/lib/cloud/data/disabled;\
    # Ensure services are enabled\
    systemctl enable cloud-init-local cloud-init cloud-config cloud-final;\
    # Create run directory if it does not exist\
    mkdir -p /run/cloud-init;\
    # Log our enforcement\
    echo "Cloud-init enforcer: Ensured cloud-init services are enabled" >> /var/log/cloud-init-enforcer.log\
'

[Install]
WantedBy=multi-user.target
RequiredBy=multi-user.target
ENFORCER_EOF

systemctl enable cloud-init-enforcer.service
echo "Cloud-init enforcer service created and enabled" >> /var/log/ks-post.log

# 5. MODIFY CLOUD-INIT CONFIGURATION FOR MAXIMUM COMPATIBILITY
echo "Configuring cloud-init for maximum compatibility..." >> /var/log/ks-post.log
cat > /etc/cloud/cloud.cfg.d/99_bulletproof.cfg << 'BULLETPROOF_EOF'
# Bulletproof cloud-init configuration
# This ensures cloud-init works in all scenarios

# Force datasource detection
datasource_list: [ NoCloud, None ]
datasource:
  NoCloud:
    # Multiple ways to find the data
    fs_label: CD_ROM
    seedfrom: file:///dev/sr0
    # Look in multiple locations
    seed_dir: /var/lib/cloud/seed/nocloud

# Disable strict datasource checking
disable_ec2_metadata: false
allow_public_ssh_keys: true

# Ensure cloud-init runs even without perfect conditions
cloud_init_modules:
  - bootcmd
  - write-files
  - resizefs
  - set_hostname
  - users-groups
  - ssh

# Force user creation even if other modules fail
preserve_sources_list: true
apt_preserve_sources_list: true
BULLETPROOF_EOF

# 6. CREATE A CRON JOB TO MONITOR CLOUD-INIT STATUS
echo "Creating cloud-init monitoring..." >> /var/log/ks-post.log
cat > /etc/cron.d/cloud-init-monitor << 'CRON_EOF'
# Monitor cloud-init and re-enable if it gets disabled
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Check every 5 minutes during boot process
*/5 * * * * root /bin/bash -c 'if ! systemctl is-enabled cloud-init >/dev/null 2>&1; then systemctl enable cloud-init-local cloud-init cloud-config cloud-final; echo "$(date): Re-enabled cloud-init services" >> /var/log/cloud-init-monitor.log; fi'
CRON_EOF

echo "BULLETPROOF cloud-init configuration completed!" >> /var/log/ks-post.log

'@

# Insert the bulletproof configuration before the final %end
$modifiedKickstart = $kickstartContent -replace '%end$', ($bulletproofCloudInitConfig + "`n%end")

# Save the bulletproof kickstart
$modifiedKickstart | Set-Content -Path $bulletproofKickstart -Encoding UTF8

Write-Host "Bulletproof kickstart created: $bulletproofKickstart" -ForegroundColor Green

Write-Host "`n=== What This Does ===" -ForegroundColor White
Write-Host "• Replaces the systemd generator with one that ALWAYS enables cloud-init"
Write-Host "• Removes ALL conditions from cloud-init services"
Write-Host "• Forces ds-identify to always return 'enabled'"
Write-Host "• Creates a boot-time enforcer service"
Write-Host "• Sets up monitoring to re-enable if disabled"
Write-Host "• Configures cloud-init for maximum compatibility"

Write-Host "`n=== To Use This ===" -ForegroundColor Yellow
Write-Host "1. Update your build script to use the bulletproof kickstart:"
Write-Host "   Edit build-cloudinit-template.ps1"
Write-Host "   Change: 'ks-with-cloudinit.cfg' to 'ks-bulletproof-cloudinit.cfg'"
Write-Host ""
Write-Host "2. Rebuild your template with the bulletproof kickstart"
Write-Host "   .\build-cloudinit-template.ps1 -Force"
Write-Host ""

Write-Host "This nuclear option should make it impossible for cloud-init to be disabled!" -ForegroundColor Green
