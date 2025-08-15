# Cloud-init Troubleshooting Guide

## Current Issue
The VM boots but cloud-init shows warnings about NoCloud data source and network configuration is not applied.

## Steps to Debug Inside the VM

1. **Connect to VM Console** (through Hyper-V Manager or PowerShell)
   ```powershell
   # On Windows Host
   vmconnect localhost "Test-1"
   ```

2. **Login as root** (password: `packer` from template)

3. **Check cloud-init status**
   ```bash
   # Check overall cloud-init status
   cloud-init status --long
   
   # Check if cloud-init detected data sources
   cloud-init query -n
   
   # Check available data sources
   cloud-init query datasource
   ```

4. **Check if ISO is mounted**
   ```bash
   # List block devices
   lsblk
   
   # Check if CD-ROM is detected
   ls -la /dev/sr*
   
   # Check current mounts
   mount | grep sr0
   ```

5. **Manually mount and check cloud-init data**
   ```bash
   # Create mount point
   sudo mkdir -p /mnt/cidata
   
   # Mount the CD-ROM
   sudo mount /dev/sr0 /mnt/cidata
   
   # Check contents
   ls -la /mnt/cidata/
   cat /mnt/cidata/user-data
   cat /mnt/cidata/meta-data
   cat /mnt/cidata/network-config
   ```

6. **Check cloud-init logs**
   ```bash
   # Real-time logs
   sudo journalctl -u cloud-init -f
   
   # Cloud-init log files
   sudo cat /var/log/cloud-init.log
   sudo cat /var/log/cloud-init-output.log
   
   # System log for cloud-init
   sudo grep cloud-init /var/log/messages
   ```

7. **Check network interface status**
   ```bash
   # Show all network interfaces
   ip addr show
   
   # Show routing table
   ip route show
   
   # Show NetworkManager connections
   nmcli con show
   ```

## Common Issues and Fixes

### Issue 1: Cloud-init can't read NoCloud data
**Symptoms**: "Getting data from NoCloud" warnings, no configuration applied

**Solution**: Force cloud-init to re-run
```bash
# Clean cloud-init state and logs
sudo cloud-init clean --logs

# Reboot to restart cloud-init
sudo reboot
```

### Issue 2: NoCloud datasource not configured
**Symptoms**: Cloud-init runs but doesn't find data

**Solution**: Check and fix datasource configuration
```bash
# Check current datasource config
sudo cat /etc/cloud/cloud.cfg.d/90_dpkg.cfg

# If missing, create it
sudo tee /etc/cloud/cloud.cfg.d/90_dpkg.cfg << 'EOF'
datasource_list: [NoCloud]
EOF
```

### Issue 3: Network configuration not applied
**Symptoms**: Interface up but no IP assigned

**Manual network configuration**:
```bash
# Configure static IP manually
sudo nmcli con mod 'System eth0' \
    ipv4.method manual \
    ipv4.addresses 192.168.200.100/24 \
    ipv4.gateway 192.168.200.1 \
    ipv4.dns 8.8.8.8

# Bring connection up
sudo nmcli con up 'System eth0'

# Verify configuration
ip addr show eth0
```

### Issue 4: User not created
**Symptoms**: Only root user exists, lab user missing

**Manual user creation**:
```bash
# Create lab user
sudo useradd -m -s /bin/bash labuser

# Set password
echo 'labuser:labpass123!' | sudo chpasswd

# Add to sudoers
sudo usermod -aG wheel labuser

# Enable SSH for the user
sudo systemctl enable sshd
sudo systemctl start sshd
```

## Alternative: Deploy without cloud-init

If cloud-init continues to fail, you can modify the deployment script to skip cloud-init and use a post-boot script instead:

1. **Create a simple deployment script**:
   ```powershell
   # Deploy VM without cloud-init
   .\deploy-simple.ps1 -VMName "Test-Simple" -IPAddress "192.168.200.101"
   ```

2. **Use VM console to manually configure**:
   - Network configuration
   - User creation  
   - SSH setup

## Next Steps

1. Run the diagnostic commands above inside the VM
2. Share the output of `cloud-init status --long` and `/var/log/cloud-init.log`
3. If cloud-init is fundamentally broken, we can create a simpler deployment approach
4. Consider using a different approach like injecting a startup script instead of cloud-init

## Quick Network Fix Command

If you just need to get network working quickly:
```bash
# One-liner to configure network
sudo nmcli con mod 'System eth0' ipv4.method manual ipv4.addresses 192.168.200.100/24 ipv4.gateway 192.168.200.1 ipv4.dns 8.8.8.8 && sudo nmcli con up 'System eth0'
```
