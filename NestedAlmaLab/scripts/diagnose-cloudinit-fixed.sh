#!/bin/bash
echo "=== Cloud-init Disable Diagnostic ==="
echo "Running comprehensive diagnosis..."

echo
echo "1. CLOUD-INIT STATUS:"
cloud-init status
echo "Exit code: $?"

echo
echo "2. SYSTEMCTL STATUS:"
for service in cloud-init-local cloud-init cloud-config cloud-final; do
    echo "--- $service.service ---"
    systemctl status $service.service --no-pager -l
    echo "Is-enabled: $(systemctl is-enabled $service.service 2>/dev/null || echo 'UNKNOWN')"
    echo "Is-active: $(systemctl is-active $service.service 2>/dev/null || echo 'UNKNOWN')"
done

echo
echo "3. DISABLE FILES CHECK:"
echo "Checking for disable files:"
for file in /etc/cloud/cloud-init.disabled /run/cloud-init/disabled /var/lib/cloud/data/disabled; do
    if [ -f "$file" ]; then
        echo "FOUND: $file"
        ls -la "$file"
        echo "Content:"
        cat "$file"
    else
        echo "NOT FOUND: $file"
    fi
done

echo
echo "4. DS-IDENTIFY STATUS:"
echo "DS-identify configuration:"
if [ -f /etc/cloud/ds-identify.cfg ]; then
    echo "ds-identify.cfg exists:"
    cat /etc/cloud/ds-identify.cfg
else
    echo "ds-identify.cfg NOT FOUND"
fi

echo
echo "5. CLOUD-INIT GENERATOR:"
echo "Checking systemd generators:"
ls -la /lib/systemd/system-generators/cloud-init-generator 2>/dev/null || echo "Generator not found"
ls -la /etc/systemd/system-generators/ 2>/dev/null || echo "No custom generators"

echo
echo "6. DATASOURCE DETECTION:"
echo "Running ds-identify manually:"
/usr/lib/cloud-init/ds-identify check 2>&1 || echo "ds-identify failed"

echo
echo "7. CLOUD-INIT LOGS:"
echo "Recent cloud-init logs:"
journalctl -u cloud-init-local -n 10 --no-pager 2>/dev/null || echo "No cloud-init-local logs"
journalctl -u cloud-init -n 10 --no-pager 2>/dev/null || echo "No cloud-init logs"

echo
echo "8. BOOT COMMAND LINE:"
echo "Kernel command line:"
cat /proc/cmdline

echo
echo "9. CLOUD-INIT CONFIG:"
echo "Cloud-init configuration files:"
find /etc/cloud -name "*.cfg" -exec echo "=== {} ===" \; -exec cat {} \;

echo
echo "10. SYSTEMD UNIT FILES:"
echo "Cloud-init unit files:"
systemctl cat cloud-init-local.service 2>/dev/null || echo "cloud-init-local.service not found"
echo "---"
systemctl cat cloud-init.service 2>/dev/null || echo "cloud-init.service not found"

echo
echo "11. ENVIRONMENT CHECK:"
echo "Environment that might affect cloud-init:"
echo "DMI_PRODUCT_NAME: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo 'N/A')"
echo "CLOUD_INIT_GENERATOR: $(ls -la /lib/systemd/system-generators/cloud-init-generator 2>/dev/null || echo 'N/A')"

echo
echo "12. CD-ROM / DATASOURCE CHECK:"
echo "Checking for attached CD-ROM with cloud-init data:"
lsblk | grep rom
if [ -e /dev/sr0 ]; then
    echo "CD-ROM device found: /dev/sr0"
    mount | grep sr0 || echo "CD-ROM not mounted"
    # Try to mount and check
    mkdir -p /tmp/cdrom-check 2>/dev/null
    mount /dev/sr0 /tmp/cdrom-check 2>/dev/null && {
        echo "CD-ROM contents:"
        ls -la /tmp/cdrom-check/
        if [ -f /tmp/cdrom-check/user-data ]; then
            echo "Found user-data file"
        fi
        if [ -f /tmp/cdrom-check/meta-data ]; then
            echo "Found meta-data file"
        fi
        umount /tmp/cdrom-check 2>/dev/null
    } || echo "Could not mount CD-ROM"
else
    echo "No CD-ROM device found"
fi

echo
echo "=== DIAGNOSIS COMPLETE ==="
