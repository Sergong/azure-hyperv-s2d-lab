# Sample: copy SSH key, inject Ansible agent
$vmName = "AlmaVM-1"
$vmIp   = "192.168.100.101"

# Wait for SSH port
while (-not (Test-NetConnection $vmIp -Port 22).TcpTestSucceeded) {
    Start-Sleep -Seconds 10
}

# Copy postinstall.sh or run remote scripts
scp .\scripts\postinstall.sh root@${vmIp}:/root/
ssh root@$vmIp "bash /root/postinstall.sh"
